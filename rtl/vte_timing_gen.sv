// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Sync generator and character grid address generator, pixel clock domain.
//
// A line runs SYNC, BACK PORCH, ACTIVE, FRONT PORCH so that the blanking gap that
// precedes active video is one contiguous run at the low end of hcnt. The eight
// pixel character prefetch window therefore lands inside the back porch and never
// has to wrap. h_act_start is at least 144 in every table entry, so subtracting the
// eight pixel lead can never underflow.
//
// Two independent position streams come out of here:
//
//   prefetch stream: pre_run_o / pre_phase_o, active over the 8*cols pixels that
//     start 8 pixels before the first active pixel. The pipeline uses it to pull a
//     cell out of the FIFO and turn it into a glyph row.
//
//   display stream: disp_text_o / pix_phase_o / disp_col_o, active over the
//     8*cols pixels of the text grid. The shader uses it to place pixels.
//
// The two streams are exactly one cell group apart, which is the pipeline latency.
//
// All outputs are combinational functions of registered counters, so they are all
// valid in the same cycle. vte_shader registers them together with the colour so
// the module boundary carries one aligned set of signals.

module vte_timing_gen (
    input logic clk_pix_i,
    input logic rst_pix_ni,
    // Runs only once the pixel domain holds a valid configuration snapshot, which
    // guarantees the very first frame after enable already uses the right geometry.
    input logic en_i,

    input vte_pkg::cfg_t cfg_i,

    // Raw sync outputs, combinational from the counters.
    output logic hsync_o,
    output logic vsync_o,
    output logic de_o,
    output logic vblank_o,

    // Pulse on the last active pixel of the frame. Starts the resynchronisation
    // handshake and advances the frame counter.
    output logic        frame_edge_o,
    output logic [31:0] frame_cnt_o,

    // Prefetch stream.
    output logic       pre_run_o,
    output logic [2:0] pre_phase_o,

    // Display stream.
    output logic       disp_text_o,
    output logic [2:0] pix_phase_o,
    output logic [7:0] disp_col_o,
    output logic [3:0] row_in_glyph_o,
    output logic [7:0] text_row_o,

    // Position, exported for waveform debug and for the testbenches.
    output logic [vte_modes_pkg::HCntW-1:0] hcnt_o,
    output logic [vte_modes_pkg::VCntW-1:0] vcnt_o
);

  localparam int unsigned HW = vte_modes_pkg::HCntW;
  localparam int unsigned VW = vte_modes_pkg::VCntW;

  vte_modes_pkg::mode_t mode;
  logic [HW-1:0] h_sync_end, h_act_start, h_act_end, h_total;
  logic [VW-1:0] v_sync_end, v_act_start, v_act_end, v_total;

  vte_mode_lut i_mode_lut (
      .mode_i       (cfg_i.mode),
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

  logic [HW-1:0] hcnt_q, hcnt_d;
  logic [VW-1:0] vcnt_q, vcnt_d;
  logic line_end, frame_end;
  logic in_hsync, in_vsync, h_de, v_de;

  logic [3:0] row_q, row_d;
  logic [7:0] trow_q, trow_d;
  logic [31:0] frame_cnt_q, frame_cnt_d;

  logic [8:0] cols_lim, rows_lim, cols_eff, rows_eff;
  logic [3:0] row_last;
  logic [HW-1:0] pre_span, h_pre_start, pre_off, disp_off;
  logic pre_in_win, v_text;

  // ---------------------------------------------------------------------------
  // Effective grid size. A grid larger than the active area is clamped rather
  // than allowed to run the prefetch window past the end of the line.
  // ---------------------------------------------------------------------------
  assign cols_lim = mode.h_active[HW-1:3];
  assign rows_lim = cfg_i.font_h16 ? {1'b0, mode.v_active[VW-1:4]} : mode.v_active[VW-1:3];
  assign cols_eff = ({1'b0, cfg_i.cols} < cols_lim) ? {1'b0, cfg_i.cols} : cols_lim;
  assign rows_eff = ({1'b0, cfg_i.rows} < rows_lim) ? {1'b0, cfg_i.rows} : rows_lim;
  assign row_last = cfg_i.font_h16 ? 4'd15 : 4'd7;

  // ---------------------------------------------------------------------------
  // Free running position counters. The wrap tests use >= so that a geometry
  // change latched mid blanking can never leave a counter above its new total.
  // ---------------------------------------------------------------------------
  assign line_end  = (hcnt_q >= h_total - {{(HW - 1) {1'b0}}, 1'b1});
  assign frame_end = line_end && (vcnt_q >= v_total - {{(VW - 1) {1'b0}}, 1'b1});

  assign hcnt_d    = line_end ? {HW{1'b0}} : hcnt_q + {{(HW - 1) {1'b0}}, 1'b1};
  always_comb begin
    vcnt_d = vcnt_q;
    if (line_end) vcnt_d = frame_end ? {VW{1'b0}} : vcnt_q + {{(VW - 1) {1'b0}}, 1'b1};
  end

  assign in_hsync = (hcnt_q < h_sync_end);
  assign in_vsync = (vcnt_q < v_sync_end);
  assign h_de     = (hcnt_q >= h_act_start) && (hcnt_q < h_act_end);
  assign v_de     = (vcnt_q >= v_act_start) && (vcnt_q < v_act_end);

  // Outside the sync region the pin sits at the inactive level, which is the
  // complement of the programmed polarity. A disabled engine parks there too.
  assign hsync_o  = (en_i && in_hsync) ? mode.h_pos : ~mode.h_pos;
  assign vsync_o  = (en_i && in_vsync) ? mode.v_pos : ~mode.v_pos;
  assign de_o     = en_i && h_de && v_de;
  assign vblank_o = !v_de;

  assign hcnt_o   = hcnt_q;
  assign vcnt_o   = vcnt_q;

  // ---------------------------------------------------------------------------
  // Character row tracking
  // ---------------------------------------------------------------------------
  always_comb begin
    row_d  = row_q;
    trow_d = trow_q;
    if (line_end) begin
      if (vcnt_q + {{(VW - 1) {1'b0}}, 1'b1} == v_act_start) begin
        // Last blanking line before active video: rearm at the top of the grid.
        row_d  = 4'd0;
        trow_d = 8'd0;
      end else if (v_de) begin
        if (row_q == row_last) begin
          row_d  = 4'd0;
          trow_d = trow_q + 8'd1;
        end else begin
          row_d = row_q + 4'd1;
        end
      end
    end
  end

  assign v_text         = v_de && ({1'b0, trow_q} < rows_eff);
  assign row_in_glyph_o = row_q;
  assign text_row_o     = trow_q;

  // ---------------------------------------------------------------------------
  // Prefetch and display windows
  // ---------------------------------------------------------------------------
  assign pre_span       = {cols_eff, 3'b000};
  assign h_pre_start    = h_act_start - HW'(vte_pkg::GlyphW);
  assign pre_off        = hcnt_q - h_pre_start;
  assign disp_off       = hcnt_q - h_act_start;

  assign pre_in_win     = (hcnt_q >= h_pre_start) && (pre_off < pre_span);
  assign pre_run_o      = en_i && v_text && pre_in_win;
  assign pre_phase_o    = pre_off[2:0];

  assign disp_text_o    = en_i && v_text && h_de && (disp_off < pre_span);
  assign pix_phase_o    = disp_off[2:0];
  assign disp_col_o     = disp_off[10:3];

  // ---------------------------------------------------------------------------
  // Frame boundary
  // ---------------------------------------------------------------------------
  assign frame_edge_o   = en_i && line_end && (vcnt_q == v_act_end - {{(VW - 1) {1'b0}}, 1'b1});
  assign frame_cnt_d    = frame_edge_o ? frame_cnt_q + 32'd1 : frame_cnt_q;
  assign frame_cnt_o    = frame_cnt_q;

  always_ff @(posedge clk_pix_i or negedge rst_pix_ni) begin
    if (!rst_pix_ni) begin
      hcnt_q      <= '0;
      vcnt_q      <= '0;
      row_q       <= '0;
      trow_q      <= '0;
      frame_cnt_q <= '0;
    end else if (!en_i) begin
      hcnt_q      <= '0;
      vcnt_q      <= '0;
      row_q       <= '0;
      trow_q      <= '0;
      frame_cnt_q <= '0;
    end else begin
      hcnt_q      <= hcnt_d;
      vcnt_q      <= vcnt_d;
      row_q       <= row_d;
      trow_q      <= trow_d;
      frame_cnt_q <= frame_cnt_d;
    end
  end

  // Lint tie off: the sync generator receives the whole configuration bundle but
  // only needs the geometry fields, and it uses the active sizes of the mode row
  // rather than the individual porch counts, which the boundary outputs already fold in.
  logic unused;
  assign unused = ^{cfg_i.pal, cfg_i.base, cfg_i.cur_col, cfg_i.cur_row, cfg_i.cur_div,
                    cfg_i.txt_div, cfg_i.cur_start, cfg_i.cur_end, cfg_i.uline_row,
                    cfg_i.border, cfg_i.cur_en, cfg_i.blank, mode.h_front, mode.h_sync,
                    mode.h_back, mode.v_front, mode.v_sync, mode.v_back};

`ifndef SYNTHESIS
  // The eight pixel prefetch lead has to fit inside the back porch of every mode.
  always @(posedge clk_pix_i) begin
    if (rst_pix_ni && en_i) begin
      assert (h_act_start >= HW'(vte_pkg::GlyphW))
      else $fatal(1, "vte_timing_gen: back porch shorter than the prefetch lead");
    end
  end
`endif

endmodule
