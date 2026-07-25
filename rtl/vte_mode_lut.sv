// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Mode table lookup. Purely combinational, no state.
//
// Selecting an out of range mode index falls back to mode 0 rather than producing
// an undriven geometry, so a bad register write degrades to 640x480 instead of
// stopping the sync generator.
//
// The derived region boundaries are computed here so that vte_timing_gen only ever
// compares its counters against precomputed edges. Boundaries are expressed as
// cumulative positions in a line/frame that runs SYNC, BACK, ACTIVE, FRONT.

module vte_mode_lut (
    input  logic [ vte_modes_pkg::ModeSelW-1:0] mode_i,
    output vte_modes_pkg::mode_t                mode_o,
    // Cumulative horizontal boundaries.
    output logic [   vte_modes_pkg::HCntW-1:0]  h_sync_end_o,   // first pixel of back porch
    output logic [   vte_modes_pkg::HCntW-1:0]  h_act_start_o,  // first active pixel
    output logic [   vte_modes_pkg::HCntW-1:0]  h_act_end_o,    // first pixel of front porch
    output logic [   vte_modes_pkg::HCntW-1:0]  h_total_o,
    // Cumulative vertical boundaries.
    output logic [   vte_modes_pkg::VCntW-1:0]  v_sync_end_o,
    output logic [   vte_modes_pkg::VCntW-1:0]  v_act_start_o,
    output logic [   vte_modes_pkg::VCntW-1:0]  v_act_end_o,
    output logic [   vte_modes_pkg::VCntW-1:0]  v_total_o
);

  logic [vte_modes_pkg::ModeW-1:0] row;

  always_comb begin
    case (mode_i)
      vte_modes_pkg::ModeSelW'(0): row = vte_modes_pkg::Mode640x480x60;
      vte_modes_pkg::ModeSelW'(1): row = vte_modes_pkg::Mode800x600x60;
      vte_modes_pkg::ModeSelW'(2): row = vte_modes_pkg::Mode1024x768x60;
      vte_modes_pkg::ModeSelW'(3): row = vte_modes_pkg::Mode720x400x70;
      default:                     row = vte_modes_pkg::Mode640x480x60;
    endcase
  end

  always_comb mode_o = row;

  assign h_sync_end_o  = mode_o.h_sync;
  assign h_act_start_o = mode_o.h_sync + mode_o.h_back;
  assign h_act_end_o   = mode_o.h_sync + mode_o.h_back + mode_o.h_active;
  assign h_total_o     = mode_o.h_sync + mode_o.h_back + mode_o.h_active + mode_o.h_front;

  assign v_sync_end_o  = mode_o.v_sync;
  assign v_act_start_o = mode_o.v_sync + mode_o.v_back;
  assign v_act_end_o   = mode_o.v_sync + mode_o.v_back + mode_o.v_active;
  assign v_total_o     = mode_o.v_sync + mode_o.v_back + mode_o.v_active + mode_o.v_front;

`ifndef SYNTHESIS
  // Keeps the hand written summary constants in vte_modes_pkg honest.
  initial begin : p_table_check
    int unsigned max_h, max_v, min_vb;
    int unsigned ht, vt, vb;
    logic [3:0] exp_hpos, exp_vpos;
    vte_modes_pkg::mode_t m;
    // VESA DMT sync polarities, one bit per mode index, low index first.
    exp_hpos = 4'b0010;  // only 800x600 has a positive hsync
    exp_vpos = 4'b1010;  // 800x600 and 720x400 have a positive vsync
    max_h    = 0;
    max_v    = 0;
    min_vb   = 32'hFFFF_FFFF;
    for (int unsigned i = 0; i < vte_modes_pkg::NumModes; i++) begin
      case (i)
        0: m = vte_modes_pkg::Mode640x480x60;
        1: m = vte_modes_pkg::Mode800x600x60;
        2: m = vte_modes_pkg::Mode1024x768x60;
        default: m = vte_modes_pkg::Mode720x400x70;
      endcase
      ht = 32'(m.h_active) + 32'(m.h_front) + 32'(m.h_sync) + 32'(m.h_back);
      vt = 32'(m.v_active) + 32'(m.v_front) + 32'(m.v_sync) + 32'(m.v_back);
      vb = ht * (32'(m.v_front) + 32'(m.v_sync) + 32'(m.v_back));
      if (ht > max_h) max_h = ht;
      if (vt > max_v) max_v = vt;
      if (vb < min_vb) min_vb = vb;
      assert (m.h_pos == exp_hpos[i[1:0]])
      else $fatal(1, "vte_mode_lut: mode %0d hsync polarity is %0b", i, m.h_pos);
      assert (m.v_pos == exp_vpos[i[1:0]])
      else $fatal(1, "vte_mode_lut: mode %0d vsync polarity is %0b", i, m.v_pos);
    end
    assert (max_h == vte_modes_pkg::MaxHTotal)
    else $fatal(1, "vte_modes_pkg::MaxHTotal is %0d, table says %0d", vte_modes_pkg::MaxHTotal,
                max_h);
    assert (max_v == vte_modes_pkg::MaxVTotal)
    else $fatal(1, "vte_modes_pkg::MaxVTotal is %0d, table says %0d", vte_modes_pkg::MaxVTotal,
                max_v);
    assert (min_vb == vte_modes_pkg::MinVBlankPixels)
    else $fatal(1, "vte_modes_pkg::MinVBlankPixels is %0d, table says %0d",
                vte_modes_pkg::MinVBlankPixels, min_vb);
  end
`endif

endmodule
