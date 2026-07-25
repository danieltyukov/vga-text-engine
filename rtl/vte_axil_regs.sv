// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// AXI4-Lite subordinate register file.
//
// 32 bit data, byte strobes honoured, one outstanding transaction in each direction.
// Every response is OKAY: an access outside the 256 byte window reads as zero and a
// write to it is dropped, which keeps a stray probe from wedging the bus. Reserved
// bits inside implemented registers read as zero and ignore writes.
//
// One address decode function serves both the read mux and the read-modify-write
// path for byte strobes, so a register can never answer reads and writes from
// different field layouts.
//
// The full map, bit fields and reset values are tabulated in the README.

module vte_axil_regs #(
    parameter int unsigned AxiAddrW = 12
) (
    input logic clk_i,
    input logic rst_ni,

    // Write address channel
    input  logic [AxiAddrW-1:0] awaddr_i,
    input  logic [         2:0] awprot_i,
    input  logic                awvalid_i,
    output logic                awready_o,
    // Write data channel
    input  logic [        31:0] wdata_i,
    input  logic [         3:0] wstrb_i,
    input  logic                wvalid_i,
    output logic                wready_o,
    // Write response channel
    output logic [         1:0] bresp_o,
    output logic                bvalid_o,
    input  logic                bready_i,
    // Read address channel
    input  logic [AxiAddrW-1:0] araddr_i,
    input  logic [         2:0] arprot_i,
    input  logic                arvalid_i,
    output logic                arready_o,
    // Read data channel
    output logic [        31:0] rdata_o,
    output logic [         1:0] rresp_o,
    output logic                rvalid_o,
    input  logic                rready_i,

    // Assembled configuration for the rest of the engine.
    output vte_pkg::cfg_t cfg_o,
    output logic          en_o,

    // Status inputs, already in this clock domain.
    input vte_pkg::sts_t sts_i,
    input logic          frame_evt_i,
    input logic          underrun_evt_i,
    input logic          running_i,
    input logic          vblank_i,
    input logic [   7:0] fifo_level_i,
    input logic [  11:0] h_active_i,
    input logic [  11:0] v_active_i
);

  // ---------------------------------------------------------------------------
  // Register storage
  // ---------------------------------------------------------------------------
  logic en_q, font_h16_q, blank_q;
  logic [3:0] mode_q, border_q;
  logic [7:0] cols_q, rows_q;
  logic [31:0] base_q;
  logic [7:0] cur_col_q, cur_row_q;
  logic cur_en_q;
  logic [3:0] cur_start_q, cur_end_q, uline_row_q;
  logic [7:0] cur_div_q, txt_div_q;
  logic [31:0] scratch_q;
  logic [vte_pkg::PalEntryW-1:0] pal_q[0:vte_pkg::PalEntries-1];
  logic [vte_pkg::PalW-1:0] pal_flat;
  logic underrun_sticky_q, frame_sticky_q;

  // ---------------------------------------------------------------------------
  // Channel state
  // ---------------------------------------------------------------------------
  logic aw_pend_q, w_pend_q;
  logic [AxiAddrW-1:0] awaddr_q;
  logic [31:0] wdata_q;
  logic [3:0] wstrb_q;
  logic bvalid_q, rvalid_q;
  logic [31:0] rdata_q;

  logic do_write;
  logic [7:0] wr_off, rd_off;
  logic wr_in_range, rd_in_range;
  logic wr_is_pal, rd_is_pal;
  logic [3:0] wr_pal_idx, rd_pal_idx;
  logic [31:0] wr_cur, wr_val, rd_mux;

  assign awready_o   = !aw_pend_q && !bvalid_q;
  assign wready_o    = !w_pend_q && !bvalid_q;
  assign arready_o   = !rvalid_q;
  assign bresp_o     = 2'b00;
  assign rresp_o     = 2'b00;
  assign bvalid_o    = bvalid_q;
  assign rvalid_o    = rvalid_q;
  assign rdata_o     = rdata_q;

  assign do_write    = aw_pend_q && w_pend_q && !bvalid_q;

  // The palette occupies the upper 64 bytes of the window, PAL0 at RegPalBase.
  assign wr_off      = awaddr_q[7:0];
  assign wr_in_range = (awaddr_q[AxiAddrW-1:8] == '0);
  assign wr_is_pal   = wr_in_range && (wr_off >= vte_pkg::RegPalBase)
                       && (wr_off < vte_pkg::RegPalBase + 8'd64);
  assign wr_pal_idx  = wr_off[5:2];

  assign rd_off      = araddr_i[7:0];
  assign rd_in_range = (araddr_i[AxiAddrW-1:8] == '0);
  assign rd_is_pal   = rd_in_range && (rd_off >= vte_pkg::RegPalBase)
                       && (rd_off < vte_pkg::RegPalBase + 8'd64);
  assign rd_pal_idx  = rd_off[5:2];

  // ---------------------------------------------------------------------------
  // Address decode. Also used to seed the byte strobe merge, so reads and writes
  // are guaranteed to share one field layout per register.
  // ---------------------------------------------------------------------------
  // Flattened view of the palette for the configuration bundle. A generate loop is
  // used because the slice base has to be an elaboration time constant.
  for (genvar gi = 0; gi < int'(vte_pkg::PalEntries); gi++) begin : g_pal_flat
    assign pal_flat[vte_pkg::PalEntryW*gi+:vte_pkg::PalEntryW] = pal_q[gi];
  end

  function automatic logic [31:0] reg_value(input logic [7:0] off, input logic in_range,
                                            input logic is_pal, input logic [3:0] pidx);
    logic [31:0] v;
    v = 32'h0;
    if (is_pal) begin
      v = {20'h0, pal_q[pidx]};
    end else if (in_range) begin
      case (off)
        vte_pkg::RegId: v = vte_pkg::IdValue;
        vte_pkg::RegCtrl: begin
          v[vte_pkg::CtrlEnBit]        = en_q;
          v[vte_pkg::CtrlFontH16Bit]   = font_h16_q;
          v[vte_pkg::CtrlBlankBit]     = blank_q;
          v[vte_pkg::CtrlModeLsb+:4]   = mode_q;
          v[vte_pkg::CtrlBorderLsb+:4] = border_q;
        end
        vte_pkg::RegStatus: begin
          v[vte_pkg::StRunningBit]    = running_i;
          v[vte_pkg::StVblankBit]     = vblank_i;
          v[vte_pkg::StUnderrunBit]   = underrun_sticky_q;
          v[vte_pkg::StFrameBit]      = frame_sticky_q;
          v[vte_pkg::StFifoLvlLsb+:8] = fifo_level_i;
        end
        vte_pkg::RegGeom: begin
          v[vte_pkg::GeomColsLsb+:8] = cols_q;
          v[vte_pkg::GeomRowsLsb+:8] = rows_q;
        end
        vte_pkg::RegBase: v = base_q;
        vte_pkg::RegCursor: begin
          v[vte_pkg::CurColLsb+:8] = cur_col_q;
          v[vte_pkg::CurRowLsb+:8] = cur_row_q;
          v[vte_pkg::CurEnBit]     = cur_en_q;
        end
        vte_pkg::RegCurShape: begin
          v[vte_pkg::ShpStartLsb+:4] = cur_start_q;
          v[vte_pkg::ShpEndLsb+:4]   = cur_end_q;
          v[vte_pkg::ShpUlineLsb+:4] = uline_row_q;
        end
        vte_pkg::RegBlink: begin
          v[vte_pkg::BlkCurDivLsb+:8] = cur_div_q;
          v[vte_pkg::BlkTxtDivLsb+:8] = txt_div_q;
        end
        vte_pkg::RegFrame: v = sts_i.frame_cnt;
        vte_pkg::RegModeDim: v = {4'h0, v_active_i, 4'h0, h_active_i};
        vte_pkg::RegUnderrun: v = {16'h0, sts_i.underrun_cnt};
        vte_pkg::RegScratch: v = scratch_q;
        default: v = 32'h0;
      endcase
    end
    reg_value = v;
  endfunction

  // Unrolled on purpose: a loop with a variable part select base is not portable
  // across the simulators in this flow.
  function automatic logic [31:0] be_merge(input logic [31:0] cur, input logic [31:0] nw,
                                           input logic [3:0] be);
    logic [31:0] r;
    r[7:0]   = be[0] ? nw[7:0] : cur[7:0];
    r[15:8]  = be[1] ? nw[15:8] : cur[15:8];
    r[23:16] = be[2] ? nw[23:16] : cur[23:16];
    r[31:24] = be[3] ? nw[31:24] : cur[31:24];
    be_merge = r;
  endfunction

  // always_comb rather than assign: a continuous assignment whose right hand side is
  // a function call is not guaranteed to be re-evaluated when a signal the function
  // reads internally changes, and reg_value reads the whole register file.
  always_comb rd_mux = reg_value(rd_off, rd_in_range, rd_is_pal, rd_pal_idx);
  always_comb wr_cur = reg_value(wr_off, wr_in_range, wr_is_pal, wr_pal_idx);
  always_comb wr_val = be_merge(wr_cur, wdata_q, wstrb_q);

  // ---------------------------------------------------------------------------
  // Sequential
  // ---------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_pend_q         <= 1'b0;
      w_pend_q          <= 1'b0;
      awaddr_q          <= '0;
      wdata_q           <= '0;
      wstrb_q           <= '0;
      bvalid_q          <= 1'b0;
      rvalid_q          <= 1'b0;
      rdata_q           <= '0;
      en_q              <= 1'b0;
      font_h16_q        <= 1'b1;
      blank_q           <= 1'b0;
      mode_q            <= 4'd0;
      border_q          <= 4'd0;
      cols_q            <= 8'd80;
      rows_q            <= 8'd30;
      base_q            <= '0;
      cur_col_q         <= '0;
      cur_row_q         <= '0;
      cur_en_q          <= 1'b0;
      cur_start_q       <= 4'd14;
      cur_end_q         <= 4'd15;
      uline_row_q       <= 4'd15;
      cur_div_q         <= 8'd15;
      txt_div_q         <= 8'd15;
      scratch_q         <= '0;
      for (int unsigned i = 0; i < vte_pkg::PalEntries; i++) begin
        pal_q[i] <= vte_pkg::PalEntryW'(vte_pkg::PalDefault >> (vte_pkg::PalEntryW * i));
      end
      underrun_sticky_q <= 1'b0;
      frame_sticky_q    <= 1'b0;
    end else begin
      if (awvalid_i && awready_o) begin
        aw_pend_q <= 1'b1;
        awaddr_q  <= awaddr_i;
      end
      if (wvalid_i && wready_o) begin
        w_pend_q <= 1'b1;
        wdata_q  <= wdata_i;
        wstrb_q  <= wstrb_i;
      end

      if (do_write) begin
        aw_pend_q <= 1'b0;
        w_pend_q  <= 1'b0;
        bvalid_q  <= 1'b1;
      end
      if (bvalid_q && bready_i) bvalid_q <= 1'b0;

      if (arvalid_i && arready_o) begin
        rvalid_q <= 1'b1;
        rdata_q  <= rd_mux;
      end
      if (rvalid_q && rready_i) rvalid_q <= 1'b0;

      // Sticky status flags, set by the once per frame status sample.
      if (frame_evt_i) frame_sticky_q <= 1'b1;
      if (underrun_evt_i) underrun_sticky_q <= 1'b1;

      if (do_write && wr_is_pal) begin
        pal_q[wr_pal_idx] <= wr_val[vte_pkg::PalEntryW-1:0];
      end else if (do_write && wr_in_range) begin
        case (wr_off)
          vte_pkg::RegCtrl: begin
            en_q       <= wr_val[vte_pkg::CtrlEnBit];
            font_h16_q <= wr_val[vte_pkg::CtrlFontH16Bit];
            blank_q    <= wr_val[vte_pkg::CtrlBlankBit];
            mode_q     <= wr_val[vte_pkg::CtrlModeLsb+:4];
            border_q   <= wr_val[vte_pkg::CtrlBorderLsb+:4];
          end
          vte_pkg::RegStatus: begin
            // Write one to clear.
            if (wr_val[vte_pkg::StUnderrunBit]) underrun_sticky_q <= 1'b0;
            if (wr_val[vte_pkg::StFrameBit]) frame_sticky_q <= 1'b0;
          end
          vte_pkg::RegGeom: begin
            cols_q <= wr_val[vte_pkg::GeomColsLsb+:8];
            rows_q <= wr_val[vte_pkg::GeomRowsLsb+:8];
          end
          vte_pkg::RegBase: base_q <= wr_val;
          vte_pkg::RegCursor: begin
            cur_col_q <= wr_val[vte_pkg::CurColLsb+:8];
            cur_row_q <= wr_val[vte_pkg::CurRowLsb+:8];
            cur_en_q  <= wr_val[vte_pkg::CurEnBit];
          end
          vte_pkg::RegCurShape: begin
            cur_start_q <= wr_val[vte_pkg::ShpStartLsb+:4];
            cur_end_q   <= wr_val[vte_pkg::ShpEndLsb+:4];
            uline_row_q <= wr_val[vte_pkg::ShpUlineLsb+:4];
          end
          vte_pkg::RegBlink: begin
            cur_div_q <= wr_val[vte_pkg::BlkCurDivLsb+:8];
            txt_div_q <= wr_val[vte_pkg::BlkTxtDivLsb+:8];
          end
          vte_pkg::RegScratch: scratch_q <= wr_val;
          default: ;
        endcase
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Configuration bundle
  // ---------------------------------------------------------------------------
  always_comb begin
    cfg_o.pal       = pal_flat;
    cfg_o.base      = base_q;
    cfg_o.cols      = cols_q;
    cfg_o.rows      = rows_q;
    cfg_o.cur_col   = cur_col_q;
    cfg_o.cur_row   = cur_row_q;
    cfg_o.cur_div   = cur_div_q;
    cfg_o.txt_div   = txt_div_q;
    cfg_o.cur_start = cur_start_q;
    cfg_o.cur_end   = cur_end_q;
    cfg_o.uline_row = uline_row_q;
    cfg_o.border    = border_q;
    cfg_o.mode      = mode_q;
    cfg_o.cur_en    = cur_en_q;
    cfg_o.font_h16  = font_h16_q;
    cfg_o.blank     = blank_q;
  end

  assign en_o = en_q;

  logic unused;
  assign unused = ^{awprot_i, arprot_i};

`ifndef SYNTHESIS
  initial begin : p_param_check
    assert (AxiAddrW >= 8 && AxiAddrW <= 32)
    else $fatal(1, "vte_axil_regs: AxiAddrW must be 8..32, got %0d", AxiAddrW);
  end
`endif

endmodule
