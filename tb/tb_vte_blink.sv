// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Cursor and attribute blink testbench.
//
// Watches two pixels for a run of consecutive frames and writes one line per frame
// recording whether each is lit:
//
//   sample A sits inside the cursor cell, which is a space, so it is lit exactly when
//            the cursor overlay is in its visible phase
//   sample B sits inside a glyph of a cell with the BLINK attribute set, so it is lit
//            exactly when the text blink divider is in its visible phase
//
// scripts/check_blink.py turns the two columns into on and off run lengths and asserts
// the period and duty against the programmed dividers.
//
// Plusargs:
//   +regs=FILE   register script
//   +mem=FILE    cell buffer image
//   +width=N     active pixels per line
//   +height=N    active lines per frame
//   +frames=N    frames to record
//   +ax=N +ay=N  cursor sample coordinate
//   +bx=N +by=N  blinking attribute sample coordinate
//   +out=FILE    output path

`timescale 1ps / 1ps

module tb_vte_blink;

  localparam int unsigned AxiAddrW = 12;
  localparam int unsigned ClkHalf = 10000;
  localparam int unsigned PixHalf = 19861;

  logic clk, rst_n, clk_pix, rst_pix_n;

  logic [AxiAddrW-1:0] awaddr;
  logic [2:0] awprot;
  logic awvalid, awready;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic wvalid, wready;
  logic [1:0] bresp;
  logic bvalid, bready;
  logic [AxiAddrW-1:0] araddr;
  logic [2:0] arprot;
  logic arvalid, arready;
  logic [31:0] rdata;
  logic [1:0] rresp;
  logic rvalid, rready;

  logic fetch_req, fetch_gnt, fetch_rvalid;
  logic [31:0] fetch_addr, fetch_rdata;

  logic hsync, vsync, de;
  logic [7:0] red, green, blue;
  logic frame_evt, underrun_evt;

  assign awprot = 3'b000;
  assign arprot = 3'b000;

  vga_text_engine #(
      .RedW      (8),
      .GreenW    (8),
      .BlueW     (8),
      .FifoDepth (32),
      .AxiAddrW  (AxiAddrW),
      .FetchAddrW(32)
  ) dut (
      .clk_i           (clk),
      .rst_ni          (rst_n),
      .clk_pix_i       (clk_pix),
      .rst_pix_ni      (rst_pix_n),
      .s_axil_awaddr_i (awaddr),
      .s_axil_awprot_i (awprot),
      .s_axil_awvalid_i(awvalid),
      .s_axil_awready_o(awready),
      .s_axil_wdata_i  (wdata),
      .s_axil_wstrb_i  (wstrb),
      .s_axil_wvalid_i (wvalid),
      .s_axil_wready_o (wready),
      .s_axil_bresp_o  (bresp),
      .s_axil_bvalid_o (bvalid),
      .s_axil_bready_i (bready),
      .s_axil_araddr_i (araddr),
      .s_axil_arprot_i (arprot),
      .s_axil_arvalid_i(arvalid),
      .s_axil_arready_o(arready),
      .s_axil_rdata_o  (rdata),
      .s_axil_rresp_o  (rresp),
      .s_axil_rvalid_o (rvalid),
      .s_axil_rready_i (rready),
      .fetch_req_o     (fetch_req),
      .fetch_addr_o    (fetch_addr),
      .fetch_gnt_i     (fetch_gnt),
      .fetch_rvalid_i  (fetch_rvalid),
      .fetch_rdata_i   (fetch_rdata),
      .hsync_o         (hsync),
      .vsync_o         (vsync),
      .de_o            (de),
      .red_o           (red),
      .green_o         (green),
      .blue_o          (blue),
      .frame_o         (frame_evt),
      .underrun_o      (underrun_evt)
  );

  vte_cell_mem #(
      .AddrW(32),
      .Words(16384)
  ) i_mem (
      .clk_i   (clk),
      .rst_ni  (rst_n),
      .stall_i (1'b0),
      .req_i   (fetch_req),
      .addr_i  (fetch_addr),
      .gnt_o   (fetch_gnt),
      .rvalid_o(fetch_rvalid),
      .rdata_o (fetch_rdata)
  );

  initial begin
    clk = 1'b0;
    forever #ClkHalf clk = ~clk;
  end

  initial begin
    clk_pix = 1'b0;
    forever #PixHalf clk_pix = ~clk_pix;
  end

`include "vte_tb_axil.svh"

  int width, height, frames, ax, ay, bx, by;
  string out_file;

  int px, ln, frame_idx, recorded;
  bit a_lit, b_lit;
  logic de_q;
  int fd;
  bit errors;

  always @(posedge clk_pix) begin
    if (rst_pix_n) begin
      if (de && !de_q) px = 0;
      if (de) begin
        if (ln == ay && px == ax) a_lit = ((red | green | blue) != 0);
        if (ln == by && px == bx) b_lit = ((red | green | blue) != 0);
        px = px + 1;
      end
      if (!de && de_q) begin
        if (px != width) begin
          $display("FAIL line %0d has %0d pixels, expected %0d", ln, px, width);
          errors = 1;
        end
        ln = ln + 1;
        if (ln == height) begin
          if (recorded < frames) begin
            $fwrite(fd, "%0d %0d %0d\n", frame_idx, a_lit, b_lit);
            recorded = recorded + 1;
          end
          ln        = 0;
          frame_idx = frame_idx + 1;
          a_lit     = 0;
          b_lit     = 0;
        end
      end
      de_q = de;
    end
  end

  initial begin
    string regs_file;

    px        = 0;
    ln        = 0;
    frame_idx = 0;
    recorded  = 0;
    a_lit     = 0;
    b_lit     = 0;
    de_q      = 0;
    errors    = 0;

    if (!$value$plusargs("width=%d", width)) width = 640;
    if (!$value$plusargs("height=%d", height)) height = 480;
    if (!$value$plusargs("frames=%d", frames)) frames = 24;
    if (!$value$plusargs("ax=%d", ax)) ax = 0;
    if (!$value$plusargs("ay=%d", ay)) ay = 0;
    if (!$value$plusargs("bx=%d", bx)) bx = 0;
    if (!$value$plusargs("by=%d", by)) by = 0;
    if (!$value$plusargs("out=%s", out_file)) out_file = "results/sim/blink.txt";

    fd = $fopen(out_file, "w");
    if (fd == 0) begin
      $display("TEST_RESULT: FAIL cannot open %s", out_file);
      $finish;
    end

    rst_n     = 0;
    rst_pix_n = 0;
    axil_idle();
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk_pix);
    rst_pix_n = 1;
    repeat (5) @(posedge clk);

    if ($value$plusargs("regs=%s", regs_file)) axil_replay(regs_file);
    else begin
      $display("TEST_RESULT: FAIL no +regs= script given");
      $finish;
    end

    while (recorded < frames) @(posedge clk_pix);
    $fclose(fd);

    if (errors) $display("TEST_RESULT: FAIL");
    else $display("TEST_RESULT: PASS  %0d frames recorded to %s", recorded, out_file);
    $finish;
  end

  initial begin
    #900_000_000_000;
    $display("TEST_RESULT: FAIL watchdog timeout");
    $finish;
  end

endmodule
