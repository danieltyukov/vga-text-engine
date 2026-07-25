// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Formal harness for vte_timing_gen.
//
// The frame comparison tests prove the renderer is right for the frames they capture. This
// proves properties of the sync generator for every reachable state and every legal
// configuration, including the twelve mode indices that fall outside the table and the
// grid sizes that have to be clamped. Those are the cases a captured frame will never
// reach.
//
// The configuration is latched at reset and then held, which is exactly the contract the
// design states: vte_frame_sync snapshots the configuration once per frame and it does not
// change while a frame is being drawn. The solver is free to pick any value for that
// snapshot, so one proof covers all of them at once.
//
// The snapshot is expressed with anyconst, which is exactly the right primitive: a value
// the solver chooses freely and which then never changes. An earlier version latched free
// inputs in the reset branch of a flop instead, which async2sync rejects with "async reset
// value is not constant" and which produced a model yosys-smtbmc could not make progress
// on at all.
//
// Only the four fields the sync generator actually reads are given to the solver: the mode
// index, the column and row counts and the glyph height. The other 274 bits of the bundle
// are the palette, the buffer base address and the cursor and blink settings, none of which
// reach this module, as the lint tie off in vte_timing_gen spells out. Tying them to zero
// keeps 274 irrelevant bits out of the problem.
//
// Properties, all of them things a monitor would actually care about:
//
//   P1  the horizontal counter never leaves its own total
//   P2  the vertical counter never leaves its own total
//   P3  data enable is never asserted while the horizontal sync pulse is active
//   P4  data enable is never asserted while the vertical sync pulse is active
//   P5  the text grid is never painted outside active video
//   P6  the character prefetch window lies entirely inside the line, so the eight pixel
//       lead can never reach back past the start of the line or forward into active video
//   P7  the glyph row index never exceeds the height of the selected font
//
// P1 and P2 are the ones that justify a specific design decision: the counter wrap tests
// use >= rather than == so that a geometry change latched mid blanking can never leave a
// counter stranded above its new total. P6 is the one that justifies walking a line
// SYNC, BACK PORCH, ACTIVE, FRONT PORCH.

module fv_timing_gen (
    input logic clk_pix_i,
    input logic en_i
);

  localparam int unsigned HW = vte_modes_pkg::HCntW;
  localparam int unsigned VW = vte_modes_pkg::VCntW;

  // ---------------------------------------------------------------------------
  // Reset generated here rather than left as a free input.
  //
  // The design uses asynchronous resets. Leaving rst_pix_ni free lets the solver assert
  // reset at any point in any trace, which both multiplies the base case paths and gives
  // k-induction a much larger space to cover; the proof did not finish in ten minutes that
  // way. Driving it from a counter with a declared initial value gives the model one
  // defined starting state and matches how the block is actually used: reset once, then
  // never again.
  // ---------------------------------------------------------------------------
  logic [1:0] rst_cnt_q = 2'd0;
  logic rst_pix_ni;

  always_ff @(posedge clk_pix_i) begin
    if (rst_cnt_q != 2'd3) rst_cnt_q <= rst_cnt_q + 2'd1;
  end

  assign rst_pix_ni = (rst_cnt_q >= 2'd2);

  // ---------------------------------------------------------------------------
  // Configuration snapshot: chosen freely by the solver, then constant.
  // ---------------------------------------------------------------------------
  // Arbitrary but constant: every value is legal, including the twelve mode indices outside
  // the table and grid sizes far larger than any mode can display.
  (* anyconst *) logic [vte_modes_pkg::ModeSelW-1:0] mode_q;
  (* anyconst *) logic [7:0] cols_q;
  (* anyconst *) logic [7:0] rows_q;
  (* anyconst *) logic font_h16_q;

  vte_pkg::cfg_t cfg_q;

  always_comb begin
    cfg_q          = '0;
    cfg_q.mode     = mode_q;
    cfg_q.cols     = cols_q;
    cfg_q.rows     = rows_q;
    cfg_q.font_h16 = font_h16_q;
  end

  // ---------------------------------------------------------------------------
  // Design under proof
  // ---------------------------------------------------------------------------
  logic hsync, vsync, de, vblank, frame_edge;
  logic [31:0] frame_cnt;
  logic pre_run, disp_text;
  logic [2:0] pre_phase, pix_phase;
  logic [7:0] disp_col, text_row;
  logic [3:0] row_in_glyph;
  logic [HW-1:0] hcnt;
  logic [VW-1:0] vcnt;

  vte_timing_gen i_dut (
      .clk_pix_i     (clk_pix_i),
      .rst_pix_ni    (rst_pix_ni),
      .en_i          (en_i),
      .cfg_i         (cfg_q),
      .hsync_o       (hsync),
      .vsync_o       (vsync),
      .de_o          (de),
      .vblank_o      (vblank),
      .frame_edge_o  (frame_edge),
      .frame_cnt_o   (frame_cnt),
      .pre_run_o     (pre_run),
      .pre_phase_o   (pre_phase),
      .disp_text_o   (disp_text),
      .pix_phase_o   (pix_phase),
      .disp_col_o    (disp_col),
      .row_in_glyph_o(row_in_glyph),
      .text_row_o    (text_row),
      .hcnt_o        (hcnt),
      .vcnt_o        (vcnt)
  );

  // ---------------------------------------------------------------------------
  // The same geometry the design derives, recomputed here from the same table so the
  // properties are written against the specification rather than against internal nets.
  // ---------------------------------------------------------------------------
  vte_modes_pkg::mode_t mode;
  logic [HW-1:0] h_sync_end, h_act_start, h_act_end, h_total;
  logic [VW-1:0] v_sync_end, v_act_start, v_act_end, v_total;

  vte_mode_lut i_ref_lut (
      .mode_i       (mode_q),
      .mode_o       (mode),
      .h_sync_end_o (h_sync_end),
      .h_act_start_o(h_act_start),
      .h_act_end_o  (h_act_end),
      .h_total_o    (h_total),
      .v_sync_end_o (v_sync_end),
      .v_act_start_o(v_act_start),
      .v_act_end_o  (v_act_end),
      .v_total_o    (v_total)
  );

  logic hsync_active, vsync_active;
  assign hsync_active = (hsync == mode.h_pos);
  assign vsync_active = (vsync == mode.v_pos);

  logic [3:0] glyph_h_last;
  assign glyph_h_last = font_h16_q ? 4'd15 : 4'd7;

  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------
  always @(posedge clk_pix_i) begin
    if (rst_pix_ni) begin
      // P1, P2: neither counter ever leaves its own total, for any mode and any moment.
      assert (hcnt < h_total);
      assert (vcnt < v_total);

      // P3, P4: a monitor loses lock if data is driven during a sync pulse.
      assert (!(de && hsync_active));
      assert (!(de && vsync_active));

      // P5: the text grid is a subset of active video.
      assert (!disp_text || de);

      // P6: the prefetch window lives inside the line, never before its start and never
      // past the last cell of active video.
      if (pre_run) begin
        assert (hcnt + HW'(vte_pkg::GlyphW) >= h_act_start);
        assert (hcnt + HW'(vte_pkg::GlyphW) <= h_act_end);
      end

      // P7: the glyph row index stays inside the selected font height.
      assert (row_in_glyph <= glyph_h_last);
    end
  end

  // ---------------------------------------------------------------------------
  // Reachability
  //
  // The harness contains no assume statements at all, so it cannot over constrain the
  // design and a vacuous proof is not possible by construction. This is the belt to that
  // braces: with one of the FV_REACH_* defines set, that state becomes an assertion of its
  // own negation, so ABC finding a counterexample is a proof that the state is reachable.
  // A "property proved" result here would mean the state can never occur, which for data
  // enable would make the whole proof meaningless.
  // ---------------------------------------------------------------------------
  // One define per state, checked in its own run. A single run asserting all four negations
  // is not enough: the engine stops at the first counterexample it finds, so it would report
  // one reachable state and say nothing about the other three.
  always @(posedge clk_pix_i) begin
    if (rst_pix_ni) begin
`ifdef FV_REACH_DE
      assert (!de);
`elsif FV_REACH_PRE
      assert (!pre_run);
`elsif FV_REACH_HSYNC
      assert (!hsync_active);
`elsif FV_REACH_TEXT
      assert (!disp_text);
`else
      cover (de);
      cover (pre_run);
      cover (hsync_active);
      cover (disp_text);
`endif
    end
  end

endmodule
