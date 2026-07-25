// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// vga_text_engine: colour VGA text mode display controller.
//
// Two clock domains:
//
//   clk_i      register and fetch domain. Drives the AXI4-Lite subordinate and the
//              cell fetch port. Any convenient system frequency.
//   clk_pix_i  pixel domain. One pixel per clock, so it must be the exact pixel
//              clock of the selected mode (25.175, 40.000, 65.000 or 28.322 MHz).
//
// Everything that crosses between them goes through vte_frame_sync, which runs a
// four phase level handshake once per frame inside vertical blanking. That single
// mechanism delivers an atomic configuration snapshot to the pixel domain, samples
// the pixel domain counters back, and realigns the elastic buffer.
//
//   AXI4-Lite ---> vte_axil_regs ---> cfg ---> vte_frame_sync ===> cfg_pix
//                                               |                    |
//   fetch port <-- vte_fetch_engine <-----------+                    v
//                        |                                    vte_timing_gen
//                        v                                           |
//                  vte_cdc_fifo  =============================> vte_shader --> RGB
//                                                                    ^
//                                                              vte_glyph_rom
//
// Constraints for a real implementation:
//   - clk_i and clk_pix_i are asynchronous; the only paths between them are the
//     gray coded FIFO pointers and the single bit handshake lines, all through
//     vte_sync2. Declare them as separate clock groups.
//   - clk_i must be at least clk_pix_i / 1000 so the handshake fits in vertical
//     blanking. Any realistic system clock satisfies this by a wide margin.

module vga_text_engine #(
    // Per channel DAC widths. An RGB444 palette entry is expanded by bit
    // replication, so 4, 8 and 12 are exact and anything in between is monotonic.
    parameter int unsigned RedW = 8,
    parameter int unsigned GreenW = 8,
    parameter int unsigned BlueW = 8,
    // Elastic buffer depth in character cells. Power of two, at least 8.
    parameter int unsigned FifoDepth = 32,
    // AXI4-Lite address width. Only the low 8 bits are decoded.
    parameter int unsigned AxiAddrW = 12,
    // Fetch port address width.
    parameter int unsigned FetchAddrW = 32
) (
    // Register and fetch domain
    input logic clk_i,
    input logic rst_ni,
    // Pixel domain
    input logic clk_pix_i,
    input logic rst_pix_ni,

    // AXI4-Lite subordinate for the register file
    input  logic [AxiAddrW-1:0] s_axil_awaddr_i,
    input  logic [         2:0] s_axil_awprot_i,
    input  logic                s_axil_awvalid_i,
    output logic                s_axil_awready_o,
    input  logic [        31:0] s_axil_wdata_i,
    input  logic [         3:0] s_axil_wstrb_i,
    input  logic                s_axil_wvalid_i,
    output logic                s_axil_wready_o,
    output logic [         1:0] s_axil_bresp_o,
    output logic                s_axil_bvalid_o,
    input  logic                s_axil_bready_i,
    input  logic [AxiAddrW-1:0] s_axil_araddr_i,
    input  logic [         2:0] s_axil_arprot_i,
    input  logic                s_axil_arvalid_i,
    output logic                s_axil_arready_o,
    output logic [        31:0] s_axil_rdata_o,
    output logic [         1:0] s_axil_rresp_o,
    output logic                s_axil_rvalid_o,
    input  logic                s_axil_rready_i,

    // Read only cell fetch port, at most one outstanding read
    output logic                  fetch_req_o,
    output logic [FetchAddrW-1:0] fetch_addr_o,
    input  logic                  fetch_gnt_i,
    input  logic                  fetch_rvalid_i,
    input  logic [          31:0] fetch_rdata_i,

    // Video output, pixel domain
    output logic              hsync_o,
    output logic              vsync_o,
    output logic              de_o,
    output logic [  RedW-1:0] red_o,
    output logic [GreenW-1:0] green_o,
    output logic [ BlueW-1:0] blue_o,

    // Event pulses in the register domain, one clock wide
    output logic frame_o,
    output logic underrun_o
);

  vte_pkg::cfg_t cfg_live, cfg_frame, cfg_pix;
  vte_pkg::sts_t sts_reg, sts_pix;
  logic en_reg, en_pix, cfg_pix_valid, pix_run;
  logic fetch_run;
  logic frame_evt, underrun_evt, running, vblank_reg;

  logic fifo_wr, fifo_full, fifo_pop, fifo_empty, fifo_drain;
  logic [vte_pkg::CellW-1:0] fifo_wdata, fifo_rdata;
  logic [$clog2(FifoDepth):0] fifo_level;

  logic hsync_raw, vsync_raw, de_raw, vblank_pix, frame_edge;
  logic pre_run, disp_text;
  logic [2:0] pre_phase, pix_phase;
  logic [7:0] disp_col, text_row;
  logic [3:0] row_in_glyph;
  logic [31:0] frame_cnt_pix;
  logic [15:0] underrun_cnt_pix;
  logic [vte_modes_pkg::HCntW-1:0] hcnt, vcnt;

  // ---------------------------------------------------------------------------
  // Register file
  // ---------------------------------------------------------------------------
  vte_modes_pkg::mode_t dim_mode;
  logic [vte_modes_pkg::HCntW-1:0] dim_h0, dim_h1, dim_h2, dim_h3;
  logic [vte_modes_pkg::VCntW-1:0] dim_v0, dim_v1, dim_v2, dim_v3;

  // Reports the geometry of the mode the pixel domain is actually displaying, which
  // is the frozen snapshot rather than whatever software wrote most recently.
  vte_mode_lut i_dim_lut (
      .mode_i       (cfg_frame.mode),
      .mode_o       (dim_mode),
      .h_sync_end_o (dim_h0),
      .h_act_start_o(dim_h1),
      .h_act_end_o  (dim_h2),
      .h_total_o    (dim_h3),
      .v_sync_end_o (dim_v0),
      .v_act_start_o(dim_v1),
      .v_act_end_o  (dim_v2),
      .v_total_o    (dim_v3)
  );

  vte_axil_regs #(
      .AxiAddrW(AxiAddrW)
  ) i_regs (
      .clk_i         (clk_i),
      .rst_ni        (rst_ni),
      .awaddr_i      (s_axil_awaddr_i),
      .awprot_i      (s_axil_awprot_i),
      .awvalid_i     (s_axil_awvalid_i),
      .awready_o     (s_axil_awready_o),
      .wdata_i       (s_axil_wdata_i),
      .wstrb_i       (s_axil_wstrb_i),
      .wvalid_i      (s_axil_wvalid_i),
      .wready_o      (s_axil_wready_o),
      .bresp_o       (s_axil_bresp_o),
      .bvalid_o      (s_axil_bvalid_o),
      .bready_i      (s_axil_bready_i),
      .araddr_i      (s_axil_araddr_i),
      .arprot_i      (s_axil_arprot_i),
      .arvalid_i     (s_axil_arvalid_i),
      .arready_o     (s_axil_arready_o),
      .rdata_o       (s_axil_rdata_o),
      .rresp_o       (s_axil_rresp_o),
      .rvalid_o      (s_axil_rvalid_o),
      .rready_i      (s_axil_rready_i),
      .cfg_o         (cfg_live),
      .en_o          (en_reg),
      .sts_i         (sts_reg),
      .frame_evt_i   (frame_evt),
      .underrun_evt_i(underrun_evt),
      .running_i     (running),
      .vblank_i      (vblank_reg),
      .fifo_level_i  (8'(fifo_level)),
      .h_active_i    (dim_mode.h_active),
      .v_active_i    (dim_mode.v_active)
  );

  assign frame_o    = frame_evt;
  assign underrun_o = underrun_evt;

  // ---------------------------------------------------------------------------
  // Clock domain crossing and per frame snapshot
  // ---------------------------------------------------------------------------
  assign sts_pix.frame_cnt    = frame_cnt_pix;
  assign sts_pix.underrun_cnt = underrun_cnt_pix;

  vte_frame_sync i_frame_sync (
      .clk_i          (clk_i),
      .rst_ni         (rst_ni),
      .en_i           (en_reg),
      .cfg_live_i     (cfg_live),
      .cfg_frame_o    (cfg_frame),
      .fetch_run_o    (fetch_run),
      .sts_o          (sts_reg),
      .frame_evt_o    (frame_evt),
      .underrun_evt_o (underrun_evt),
      .running_o      (running),
      .vblank_o       (vblank_reg),
      .clk_pix_i      (clk_pix_i),
      .rst_pix_ni     (rst_pix_ni),
      .en_pix_o       (en_pix),
      .cfg_pix_o      (cfg_pix),
      .cfg_pix_valid_o(cfg_pix_valid),
      .frame_edge_i   (frame_edge),
      .vblank_pix_i   (vblank_pix),
      .fifo_empty_i   (fifo_empty),
      .fifo_drain_o   (fifo_drain),
      .sts_pix_i      (sts_pix)
  );

  assign pix_run = en_pix && cfg_pix_valid;

  // ---------------------------------------------------------------------------
  // Fetch side
  // ---------------------------------------------------------------------------
  vte_fetch_engine #(
      .FetchAddrW(FetchAddrW)
  ) i_fetch (
      .clk_i      (clk_i),
      .rst_ni     (rst_ni),
      .run_i      (fetch_run),
      .cfg_i      (cfg_frame),
      .req_o      (fetch_req_o),
      .addr_o     (fetch_addr_o),
      .gnt_i      (fetch_gnt_i),
      .rvalid_i   (fetch_rvalid_i),
      .rdata_i    (fetch_rdata_i),
      .fifo_wr_o  (fifo_wr),
      .fifo_data_o(fifo_wdata),
      .fifo_full_i(fifo_full)
  );

  vte_cdc_fifo #(
      .Width(vte_pkg::CellW),
      .Depth(FifoDepth)
  ) i_fifo (
      .clk_wr_i  (clk_i),
      .rst_wr_ni (rst_ni),
      .wr_en_i   (fifo_wr),
      .wr_data_i (fifo_wdata),
      .wr_full_o (fifo_full),
      .wr_level_o(fifo_level),
      .clk_rd_i  (clk_pix_i),
      .rst_rd_ni (rst_pix_ni),
      .rd_en_i   (fifo_pop),
      .rd_data_o (fifo_rdata),
      .rd_empty_o(fifo_empty)
  );

  // ---------------------------------------------------------------------------
  // Pixel side
  // ---------------------------------------------------------------------------
  vte_timing_gen i_timing (
      .clk_pix_i     (clk_pix_i),
      .rst_pix_ni    (rst_pix_ni),
      .en_i          (pix_run),
      .cfg_i         (cfg_pix),
      .hsync_o       (hsync_raw),
      .vsync_o       (vsync_raw),
      .de_o          (de_raw),
      .vblank_o      (vblank_pix),
      .frame_edge_o  (frame_edge),
      .frame_cnt_o   (frame_cnt_pix),
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

  vte_shader #(
      .RedW  (RedW),
      .GreenW(GreenW),
      .BlueW (BlueW)
  ) i_shader (
      .clk_pix_i     (clk_pix_i),
      .rst_pix_ni    (rst_pix_ni),
      .en_i          (pix_run),
      .cfg_i         (cfg_pix),
      .hsync_i       (hsync_raw),
      .vsync_i       (vsync_raw),
      .de_i          (de_raw),
      .frame_edge_i  (frame_edge),
      .pre_run_i     (pre_run),
      .pre_phase_i   (pre_phase),
      .disp_text_i   (disp_text),
      .pix_phase_i   (pix_phase),
      .disp_col_i    (disp_col),
      .row_in_glyph_i(row_in_glyph),
      .text_row_i    (text_row),
      .fifo_empty_i  (fifo_empty),
      .fifo_data_i   (fifo_rdata),
      .fifo_drain_i  (fifo_drain),
      .fifo_pop_o    (fifo_pop),
      .underrun_cnt_o(underrun_cnt_pix),
      .hsync_o       (hsync_o),
      .vsync_o       (vsync_o),
      .de_o          (de_o),
      .red_o         (red_o),
      .green_o       (green_o),
      .blue_o        (blue_o)
  );

  logic unused;
  assign unused = ^{hcnt, vcnt, dim_h0, dim_h1, dim_h2, dim_h3, dim_v0, dim_v1, dim_v2, dim_v3,
                    dim_mode.h_front, dim_mode.h_sync, dim_mode.h_back, dim_mode.v_front,
                    dim_mode.v_sync, dim_mode.v_back, dim_mode.h_pos, dim_mode.v_pos};

`ifndef SYNTHESIS
  initial begin : p_param_check
    assert (FifoDepth >= 8)
    else $fatal(1, "vga_text_engine: FifoDepth must be at least 8, got %0d", FifoDepth);
    assert ((FifoDepth & (FifoDepth - 1)) == 0)
    else $fatal(1, "vga_text_engine: FifoDepth must be a power of two, got %0d", FifoDepth);
    // The drain phase of the frame handshake costs at most FifoDepth pixel clocks and
    // has to fit inside the shortest vertical blanking interval in the mode table.
    assert (FifoDepth < vte_modes_pkg::MinVBlankPixels / 4)
    else
      $fatal(1, "vga_text_engine: FifoDepth %0d does not fit in %0d pixels of blanking",
             FifoDepth, vte_modes_pkg::MinVBlankPixels);
    assert (RedW >= 1 && RedW <= 12)
    else $fatal(1, "vga_text_engine: RedW must be 1..12, got %0d", RedW);
    assert (GreenW >= 1 && GreenW <= 12)
    else $fatal(1, "vga_text_engine: GreenW must be 1..12, got %0d", GreenW);
    assert (BlueW >= 1 && BlueW <= 12)
    else $fatal(1, "vga_text_engine: BlueW must be 1..12, got %0d", BlueW);
    assert (AxiAddrW >= 8)
    else $fatal(1, "vga_text_engine: AxiAddrW must be at least 8, got %0d", AxiAddrW);
  end
`endif

endmodule
