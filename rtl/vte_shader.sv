// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Character shader, pixel clock domain. Turns cells into colour.
//
// Three register stages spread across the eight pixel budget of one cell group, so
// the glyph ROM gets a full clock of read latency and can map to a block RAM:
//
//   pre_phase 5  pop the FIFO, capture the cell           -> cell_q
//   pre_phase 6  drive the ROM address                    -> rom_addr_q
//   pre_phase 7  capture the attribute half of the cell   -> attr_q
//   next group   rom_data_q and attr_q are both valid for all 8 display pixels
//
// rom_addr_q is only rewritten once per group, so the ROM output holds its value for
// the whole display window without an extra holding register.
//
// Attribute resolution order, which the Python reference model in scripts/model.py
// reimplements independently:
//
//   1. pixel = glyph bitmap bit, MSB is the leftmost pixel
//   2. ULINE  forces the pixel on when row_in_glyph equals CURSHAPE.ULINE_ROW
//   3. BLINK  forces the pixel off during the off phase of the TXT_DIV divider
//   4. REV    swaps the foreground and background indices
//   5. cursor inverts the pixel inside the programmed scanline span
//   6. palette index = pixel ? foreground : background
//   7. outside the text grid but inside active video: CTRL.BORDER
//   8. RGB444 entry expanded to the per channel DAC width by bit replication
//
// Steps 2 and 3 are ordered so a blinking underlined cell goes fully dark, matching
// what a text console expects.

module vte_shader #(
    parameter int unsigned RedW   = 8,
    parameter int unsigned GreenW = 8,
    parameter int unsigned BlueW  = 8
) (
    input logic clk_pix_i,
    input logic rst_pix_ni,
    input logic en_i,

    input vte_pkg::cfg_t cfg_i,

    // Timing stream from vte_timing_gen, all valid in the same cycle.
    input logic       hsync_i,
    input logic       vsync_i,
    input logic       de_i,
    input logic       frame_edge_i,
    input logic       pre_run_i,
    input logic [2:0] pre_phase_i,
    input logic       disp_text_i,
    input logic [2:0] pix_phase_i,
    input logic [7:0] disp_col_i,
    input logic [3:0] row_in_glyph_i,
    input logic [7:0] text_row_i,

    // Elastic buffer read side, show ahead.
    input  logic                       fifo_empty_i,
    input  logic [vte_pkg::CellW-1:0]  fifo_data_i,
    input  logic                       fifo_drain_i,
    output logic                       fifo_pop_o,

    // Status back to the register domain.
    output logic [15:0] underrun_cnt_o,

    // Registered pixel outputs.
    output logic                hsync_o,
    output logic                vsync_o,
    output logic                de_o,
    output logic [  RedW-1:0]   red_o,
    output logic [GreenW-1:0]   green_o,
    output logic [ BlueW-1:0]   blue_o
);

  vte_pkg::cell_t head;
  vte_pkg::cell_t cell_q;

  logic take_cell;  // pop for display purposes
  logic underrun;

  logic [vte_pkg::RomAddrW-1:0] rom_addr_q, rom_addr_d;
  logic [7:0] rom_data;

  logic [3:0] attr_fg_q, attr_bg_q;
  logic attr_blink_q, attr_rev_q, attr_uline_q, attr_void_q;

  logic [15:0] underrun_cnt_q;

  logic cur_phase_q, txt_phase_q;
  logic [7:0] cur_div_q, txt_div_q;

  logic glyph_bit, pixel_on, cursor_hit;
  logic [3:0] fg_idx, bg_idx, pal_idx;
  logic [11:0] pal_entry;
  logic [vte_pkg::PalEntryW-1:0] pal_arr[0:vte_pkg::PalEntries-1];

  logic [15:0] rep_r, rep_g, rep_b;
  logic [RedW-1:0] red_d;
  logic [GreenW-1:0] green_d;
  logic [BlueW-1:0] blue_d;

  logic unused_cfg;

  always_comb head = fifo_data_i;

  // ---------------------------------------------------------------------------
  // Stage 1: pull a cell out of the elastic buffer
  // ---------------------------------------------------------------------------
  assign take_cell  = pre_run_i && (pre_phase_i == 3'd5);
  assign underrun   = take_cell && fifo_empty_i;
  assign fifo_pop_o = (take_cell && !fifo_empty_i) || fifo_drain_i;

  // ---------------------------------------------------------------------------
  // Stage 2: glyph ROM address
  //
  // Bank 8x16 lives at ch*16+row, bank 8x8 at 2048+ch*8+row. Codes at or above
  // GlyphCount have bit 7 set and render as an empty cell.
  // ---------------------------------------------------------------------------
  assign rom_addr_d = cfg_i.font_h16
                    ? {1'b0, cell_q.ch[6:0], row_in_glyph_i}
                    : (vte_pkg::RomAddrW'(vte_pkg::Bank8Base) +
                       {2'b00, cell_q.ch[6:0], row_in_glyph_i[2:0]});

  vte_glyph_rom i_glyph_rom (
      .clk_i (clk_pix_i),
      .addr_i(rom_addr_q),
      .data_o(rom_data)
  );

  // ---------------------------------------------------------------------------
  // Pipeline registers
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_pix_i or negedge rst_pix_ni) begin
    if (!rst_pix_ni) begin
      cell_q         <= '0;
      rom_addr_q     <= '0;
      attr_fg_q      <= '0;
      attr_bg_q      <= '0;
      attr_blink_q   <= 1'b0;
      attr_rev_q     <= 1'b0;
      attr_uline_q   <= 1'b0;
      attr_void_q    <= 1'b0;
      underrun_cnt_q <= '0;
    end else if (!en_i) begin
      cell_q         <= '0;
      rom_addr_q     <= '0;
      attr_fg_q      <= '0;
      attr_bg_q      <= '0;
      attr_blink_q   <= 1'b0;
      attr_rev_q     <= 1'b0;
      attr_uline_q   <= 1'b0;
      attr_void_q    <= 1'b0;
      underrun_cnt_q <= '0;
    end else begin
      if (take_cell) cell_q <= fifo_empty_i ? '0 : head;
      if (pre_run_i && (pre_phase_i == 3'd6)) rom_addr_q <= rom_addr_d;
      if (pre_run_i && (pre_phase_i == 3'd7)) begin
        attr_fg_q    <= cell_q.fg;
        attr_bg_q    <= cell_q.bg;
        attr_blink_q <= cell_q.blink;
        attr_rev_q   <= cell_q.rev;
        attr_uline_q <= cell_q.uline;
        attr_void_q  <= cell_q.ch[7];
      end
      if (underrun && (underrun_cnt_q != 16'hFFFF)) underrun_cnt_q <= underrun_cnt_q + 16'd1;
    end
  end

  assign underrun_cnt_o = underrun_cnt_q;

  // ---------------------------------------------------------------------------
  // Blink phase generators. Each phase toggles every DIV+1 frames, so the period
  // is 2*(DIV+1) frames at 50 percent duty. Both start in the visible phase.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_pix_i or negedge rst_pix_ni) begin
    if (!rst_pix_ni) begin
      cur_phase_q <= 1'b1;
      txt_phase_q <= 1'b1;
      cur_div_q   <= '0;
      txt_div_q   <= '0;
    end else if (!en_i) begin
      cur_phase_q <= 1'b1;
      txt_phase_q <= 1'b1;
      cur_div_q   <= '0;
      txt_div_q   <= '0;
    end else if (frame_edge_i) begin
      if (cur_div_q >= cfg_i.cur_div) begin
        cur_div_q   <= '0;
        cur_phase_q <= ~cur_phase_q;
      end else begin
        cur_div_q <= cur_div_q + 8'd1;
      end
      if (txt_div_q >= cfg_i.txt_div) begin
        txt_div_q   <= '0;
        txt_phase_q <= ~txt_phase_q;
      end else begin
        txt_div_q <= txt_div_q + 8'd1;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Per pixel resolution
  // ---------------------------------------------------------------------------
  assign glyph_bit  = attr_void_q ? 1'b0 : rom_data[3'd7-pix_phase_i];

  assign cursor_hit = cfg_i.cur_en
                   && (disp_col_i == cfg_i.cur_col)
                   && (text_row_i == cfg_i.cur_row)
                   && (row_in_glyph_i >= cfg_i.cur_start)
                   && (row_in_glyph_i <= cfg_i.cur_end);

  always_comb begin
    pixel_on = glyph_bit;
    if (attr_uline_q && (row_in_glyph_i == cfg_i.uline_row)) pixel_on = 1'b1;
    if (attr_blink_q && !txt_phase_q) pixel_on = 1'b0;

    fg_idx = attr_rev_q ? attr_bg_q : attr_fg_q;
    bg_idx = attr_rev_q ? attr_fg_q : attr_bg_q;

    if (cursor_hit && cur_phase_q) pixel_on = ~pixel_on;

    pal_idx = pixel_on ? fg_idx : bg_idx;
    if (!disp_text_i) pal_idx = cfg_i.border;
  end

  // 16 way palette mux. The generate loop gives each entry a literal slice base and
  // the array index collapses to a single mux.
  for (genvar gi = 0; gi < vte_pkg::PalEntries; gi++) begin : g_pal_split
    assign pal_arr[gi] = cfg_i.pal[vte_pkg::PalEntryW*gi+:vte_pkg::PalEntryW];
  end
  assign pal_entry = pal_arr[pal_idx];

  // RGB444 to DAC width by bit replication: the output is the top RedW bits of the
  // nibble repeated four times. Exact for widths 4, 8 and 12 and monotonic for the
  // widths in between.
  assign rep_r = {4{pal_entry[11:8]}};
  assign rep_g = {4{pal_entry[7:4]}};
  assign rep_b = {4{pal_entry[3:0]}};

  assign red_d = (de_i && !cfg_i.blank) ? rep_r[15-:RedW] : {RedW{1'b0}};
  assign green_d = (de_i && !cfg_i.blank) ? rep_g[15-:GreenW] : {GreenW{1'b0}};
  assign blue_d = (de_i && !cfg_i.blank) ? rep_b[15-:BlueW] : {BlueW{1'b0}};

  // ---------------------------------------------------------------------------
  // Output stage. Sync, data enable and colour are registered together so the
  // module boundary carries one aligned set of signals.
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_pix_i or negedge rst_pix_ni) begin
    if (!rst_pix_ni) begin
      hsync_o <= 1'b1;
      vsync_o <= 1'b1;
      de_o    <= 1'b0;
      red_o   <= '0;
      green_o <= '0;
      blue_o  <= '0;
    end else begin
      hsync_o <= hsync_i;
      vsync_o <= vsync_i;
      de_o    <= de_i;
      red_o   <= red_d;
      green_o <= green_d;
      blue_o  <= blue_d;
    end
  end

  // Lint tie off: the shader receives the whole configuration bundle but the grid
  // size and buffer address only matter to the fetch side, and the replication
  // vectors are wider than any single DAC width.
  assign unused_cfg = ^{cfg_i.base, cfg_i.cols, cfg_i.rows, cfg_i.mode, rep_r, rep_g, rep_b};

`ifndef SYNTHESIS
  initial begin : p_param_check
    // Bit 7 of the character code is the out of range test, which only works while
    // the ROM holds exactly 128 glyphs per bank.
    assert (vte_pkg::GlyphCount == 128)
    else $fatal(1, "vte_shader: GlyphCount must be 128, got %0d", vte_pkg::GlyphCount);
    assert (RedW >= 1 && RedW <= 12)
    else $fatal(1, "vte_shader: RedW must be 1..12, got %0d", RedW);
    assert (GreenW >= 1 && GreenW <= 12)
    else $fatal(1, "vte_shader: GreenW must be 1..12, got %0d", GreenW);
    assert (BlueW >= 1 && BlueW <= 12)
    else $fatal(1, "vte_shader: BlueW must be 1..12, got %0d", BlueW);
  end
`endif

endmodule
