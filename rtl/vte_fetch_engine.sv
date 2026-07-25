// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Cell fetch engine, register clock domain.
//
// Walks the cell buffer once per frame in exactly the order the pixel pipeline
// consumes it: for every text row, for every glyph scanline of that row, all cols
// cells of the row. Re-reading a text row once per scanline rather than caching it
// keeps the engine to two address registers and lets the elastic buffer absorb every
// bit of the burstiness, which is the whole point of having one.
//
// Cell count per frame is rows*glyph_h*cols on both sides of the FIFO, and both
// sides derive rows and cols by clamping the same frozen configuration snapshot
// against the same mode table. That is what keeps the FIFO index mapping aligned
// without any per-scanline synchronisation.
//
// Fetch port contract, read only, at most one outstanding read:
//
//   req_o     asserted while a read is offered; address is valid in the same cycle
//   gnt_i     the target accepted the address this cycle
//   rvalid_i  read data returned; may be the cycle after gnt_i or later
//
// Back to back issue is allowed: a new req_o may go out in the same cycle rvalid_i
// returns the previous one, so a zero wait state target sustains one cell per clock.
// Issuing is gated on the elastic buffer having room for the in flight response plus
// the new one, so no fetched cell is ever dropped.

module vte_fetch_engine #(
    parameter int unsigned FetchAddrW = 32
) (
    input logic clk_i,
    input logic rst_ni,

    // High for the whole frame. Low during the resynchronisation handshake and
    // whenever the engine is disabled, which also rearms the address sequence.
    input logic          run_i,
    input vte_pkg::cfg_t cfg_i,

    // Read only fetch port.
    output logic                  req_o,
    output logic [FetchAddrW-1:0] addr_o,
    input  logic                  gnt_i,
    input  logic                  rvalid_i,
    input  logic [          31:0] rdata_i,

    // Elastic buffer write side.
    output logic                      fifo_wr_o,
    output logic [vte_pkg::CellW-1:0] fifo_data_o,
    // High when the buffer has fewer than two free slots, which is the point at
    // which a new request could no longer be guaranteed a home.
    input  logic                      fifo_afull_i
);

  vte_modes_pkg::mode_t mode;
  logic [vte_modes_pkg::HCntW-1:0] h_unused0, h_unused1, h_unused2, h_unused3;
  logic [vte_modes_pkg::VCntW-1:0] v_unused0, v_unused1, v_unused2, v_unused3;

  vte_mode_lut i_mode_lut (
      .mode_i       (cfg_i.mode),
      .mode_o       (mode),
      .h_sync_end_o (h_unused0),
      .h_act_start_o(h_unused1),
      .h_act_end_o  (h_unused2),
      .h_total_o    (h_unused3),
      .v_sync_end_o (v_unused0),
      .v_act_start_o(v_unused1),
      .v_act_end_o  (v_unused2),
      .v_total_o    (v_unused3)
  );

  logic [8:0] cols_lim, rows_lim, cols_eff, rows_eff;
  logic [3:0] line_last;
  logic grid_empty;

  // Identical clamping to vte_timing_gen, driven from the identical snapshot.
  assign cols_lim   = mode.h_active[vte_modes_pkg::HCntW-1:3];
  assign rows_lim   = cfg_i.font_h16 ? {1'b0, mode.v_active[vte_modes_pkg::VCntW-1:4]}
                                     : mode.v_active[vte_modes_pkg::VCntW-1:3];
  assign cols_eff   = ({1'b0, cfg_i.cols} < cols_lim) ? {1'b0, cfg_i.cols} : cols_lim;
  assign rows_eff   = ({1'b0, cfg_i.rows} < rows_lim) ? {1'b0, cfg_i.rows} : rows_lim;
  assign line_last  = cfg_i.font_h16 ? 4'd15 : 4'd7;
  assign grid_empty = (cols_eff == 9'd0) || (rows_eff == 9'd0);

  logic [FetchAddrW-1:0] row_base_q, row_base_d;
  logic [FetchAddrW-1:0] addr_q, addr_d;
  logic [8:0] col_q, col_d;
  logic [3:0] line_q, line_d;
  logic [8:0] trow_q, trow_d;
  logic done_q, done_d;
  logic outstanding_q, outstanding_d;

  logic [FetchAddrW-1:0] row_bytes;
  logic accept, last_col, last_line, last_row;

  // Row stride is the programmed column count, not the clamped one, so the buffer
  // layout stays fixed even when the grid is wider than the active area.
  assign row_bytes = {{(FetchAddrW - 10) {1'b0}}, cfg_i.cols, 2'b00};

  // A request is only offered when the buffer can hold both the response already in
  // flight and the response this request will produce. Checking plain "not full" here
  // would let a response arrive at a full buffer and be dropped.
  assign req_o     = run_i && !done_q && !fifo_afull_i && (!outstanding_q || rvalid_i);
  assign addr_o    = addr_q;
  assign accept    = req_o && gnt_i;

  assign last_col  = (col_q + 9'd1 >= cols_eff);
  assign last_line = (line_q == line_last);
  assign last_row  = (trow_q + 9'd1 >= rows_eff);

  // ---------------------------------------------------------------------------
  // Address sequencer. Advances only on an accepted request.
  // ---------------------------------------------------------------------------
  always_comb begin
    col_d      = col_q;
    line_d     = line_q;
    trow_d     = trow_q;
    addr_d     = addr_q;
    row_base_d = row_base_q;
    done_d     = done_q;

    if (accept) begin
      if (!last_col) begin
        col_d  = col_q + 9'd1;
        addr_d = addr_q + FetchAddrW'(4);
      end else begin
        col_d = 9'd0;
        if (!last_line) begin
          // Same text row, next glyph scanline: rewind to the row start.
          line_d = line_q + 4'd1;
          addr_d = row_base_q;
        end else begin
          line_d = 4'd0;
          if (!last_row) begin
            trow_d     = trow_q + 9'd1;
            row_base_d = row_base_q + row_bytes;
            addr_d     = row_base_q + row_bytes;
          end else begin
            // Whole frame issued. Park until the next resynchronisation.
            done_d = 1'b1;
          end
        end
      end
    end
  end

  assign outstanding_d = accept ? 1'b1 : (rvalid_i ? 1'b0 : outstanding_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      col_q         <= '0;
      line_q        <= '0;
      trow_q        <= '0;
      addr_q        <= '0;
      row_base_q    <= '0;
      done_q        <= 1'b0;
      outstanding_q <= 1'b0;
    end else if (!run_i) begin
      col_q         <= '0;
      line_q        <= '0;
      trow_q        <= '0;
      addr_q        <= cfg_i.base[FetchAddrW-1:0];
      row_base_q    <= cfg_i.base[FetchAddrW-1:0];
      done_q        <= grid_empty;
      outstanding_q <= 1'b0;
    end else begin
      col_q         <= col_d;
      line_q        <= line_d;
      trow_q        <= trow_d;
      addr_q        <= addr_d;
      row_base_q    <= row_base_d;
      done_q        <= done_d;
      outstanding_q <= outstanding_d;
    end
  end

  // ---------------------------------------------------------------------------
  // Cell word decode. Only the 19 meaningful bits enter the elastic buffer.
  // ---------------------------------------------------------------------------
  vte_pkg::cell_t cell_w;

  // Field order must match vte_pkg::cell_t: uline, rev, blink, bg, fg, ch.
  assign cell_w = {rdata_i[vte_pkg::CellUlineBit],
                   rdata_i[vte_pkg::CellRevBit],
                   rdata_i[vte_pkg::CellBlinkBit],
                   rdata_i[vte_pkg::CellBgLsb+:4],
                   rdata_i[vte_pkg::CellFgLsb+:4],
                   rdata_i[vte_pkg::CellChLsb+:8]};

  assign fifo_data_o = cell_w;
  assign fifo_wr_o   = outstanding_q && rvalid_i;

  // Lint tie off: the engine only needs the grid size and buffer address out of the
  // configuration bundle, and only the active sizes out of the mode row.
  logic unused;
  assign unused = ^{rdata_i[31:19], mode.h_front, mode.h_sync, mode.h_back, mode.v_front,
                    mode.v_sync, mode.v_back, mode.h_pos, mode.v_pos, h_unused0, h_unused1,
                    h_unused2, h_unused3, v_unused0, v_unused1, v_unused2, v_unused3,
                    cfg_i.base, cfg_i.pal, cfg_i.cur_col, cfg_i.cur_row, cfg_i.cur_div,
                    cfg_i.txt_div, cfg_i.cur_start, cfg_i.cur_end, cfg_i.uline_row,
                    cfg_i.border, cfg_i.cur_en, cfg_i.blank};

`ifndef SYNTHESIS
  initial begin : p_param_check
    assert (FetchAddrW >= 16 && FetchAddrW <= 32)
    else $fatal(1, "vte_fetch_engine: FetchAddrW must be 16..32, got %0d", FetchAddrW);
  end
`endif

endmodule
