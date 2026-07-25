// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Elastic buffer underrun and recovery testbench.
//
// Deliberately starves the fetch port for longer than a frame and checks three things:
//
//   1. the sync generator does not care. The hsync period is measured across the whole
//      starvation window and must stay at exactly one value, so a display fed by this
//      controller keeps its lock even while the memory system is unavailable.
//   2. STATUS.UNDERRUN latches and the UNDERRUN counter advances.
//   3. once the memory responds again the picture heals by itself. The sticky flag is
//      cleared, three frames are allowed to pass and the flag must stay clear, and a
//      frame captured after recovery is written out for the reference model to check
//      pixel for pixel. That is what proves the frame boundary resynchronisation
//      actually repairs the cell alignment rather than merely reporting the fault.
//
// Plusargs:
//   +regs=FILE   register script
//   +mem=FILE    cell buffer image
//   +width=N     active pixels per line
//   +height=N    active lines per frame
//   +ppm=PREFIX  recovery frame output prefix
//   +stall=N     starvation length in pixel clocks

`timescale 1ps / 1ps

module tb_vte_underrun;

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
  logic mem_stall;

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
      .stall_i (mem_stall),
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

  // ---------------------------------------------------------------------------
  // hsync period monitor, always running
  // ---------------------------------------------------------------------------
  int hs_period, hs_cnt;
  int hs_min, hs_max;
  bit hs_armed;
  logic hs_q;

  always @(posedge clk_pix) begin
    if (rst_pix_n) begin
      hs_cnt = hs_cnt + 1;
      if (hsync && !hs_q) begin
        hs_period = hs_cnt;
        hs_cnt    = 0;
        // The first interval after arming starts from an arbitrary point in the line.
        if (!hs_armed) begin
          hs_armed = 1;
        end else begin
          if (hs_min == 0 || hs_period < hs_min) hs_min = hs_period;
          if (hs_period > hs_max) hs_max = hs_period;
        end
      end
      hs_q = hsync;
    end
  end

  task automatic arm_period_monitor();
    hs_min   = 0;
    hs_max   = 0;
    hs_armed = 0;
  endtask

  // ---------------------------------------------------------------------------
  // Recovery frame capture
  // ---------------------------------------------------------------------------
  int width, height, stall_len;
  string ppm_prefix;
  int px, ln, frame_idx, fd;
  bit capturing, captured;
  logic de_q;
  int errors;

  always @(posedge clk_pix) begin
    if (rst_pix_n) begin
      if (de && !de_q) begin
        px = 0;
        if (ln == 0 && capturing) begin
          fd = $fopen($sformatf("%s_%0d.ppm", ppm_prefix, frame_idx), "wb");
          if (fd == 0) begin
            $display("FAIL cannot open the recovery frame for writing");
            errors = errors + 1;
          end else begin
            $fwrite(fd, "P6\n%0d %0d\n255\n", width, height);
          end
        end
      end
      if (de) begin
        if (capturing && fd != 0) $fwrite(fd, "%c%c%c", red, green, blue);
        px = px + 1;
      end
      if (!de && de_q) begin
        if (px != width) begin
          $display("FAIL active line %0d has %0d pixels, expected %0d", ln, px, width);
          errors = errors + 1;
        end
        ln = ln + 1;
        if (ln == height) begin
          if (capturing) begin
            if (fd != 0) $fclose(fd);
            capturing = 0;
            captured  = 1;
          end
          ln        = 0;
          frame_idx = frame_idx + 1;
        end
      end
      de_q = de;
    end
  end

  task automatic wait_frames(input int n);
    repeat (n) @(posedge frame_evt);
  endtask

  initial begin
    logic [31:0] v;
    string regs_file;
    int recovery_frame;

    errors    = 0;
    hs_cnt    = 0;
    hs_min    = 0;
    hs_max    = 0;
    hs_armed  = 0;
    hs_q      = 0;
    px        = 0;
    ln        = 0;
    frame_idx = 0;
    capturing = 0;
    captured  = 0;
    de_q      = 0;
    fd        = 0;
    mem_stall = 0;

    if (!$value$plusargs("width=%d", width)) width = 640;
    if (!$value$plusargs("height=%d", height)) height = 480;
    if (!$value$plusargs("stall=%d", stall_len)) stall_len = 500000;
    if (!$value$plusargs("ppm=%s", ppm_prefix)) ppm_prefix = "results/sim/recover";

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

    // ---- healthy operation ------------------------------------------------
    wait_frames(1);
    arm_period_monitor();
    wait_frames(1);
    axil_read(32'h08, v);
    if (v[2]) begin
      $display("FAIL STATUS.UNDERRUN set with a responsive memory: %08h", v);
      errors = errors + 1;
    end
    axil_read(32'h28, v);
    if (v != 0) begin
      $display("FAIL UNDERRUN counter is %0d with a responsive memory", v);
      errors = errors + 1;
    end
    $display("healthy: hsync period %0d..%0d pixels", hs_min, hs_max);
    if (hs_min != hs_max) begin
      $display("FAIL hsync period varied before the starvation");
      errors = errors + 1;
    end

    // ---- starve the fetch port -------------------------------------------
    arm_period_monitor();
    mem_stall = 1;
    repeat (stall_len) @(posedge clk_pix);
    $display("starved for %0d pixel clocks: hsync period %0d..%0d pixels", stall_len, hs_min,
             hs_max);
    if (hs_min != hs_max) begin
      $display("FAIL hsync period varied during the starvation: %0d..%0d", hs_min, hs_max);
      errors = errors + 1;
    end
    if (hs_min == 0) begin
      $display("FAIL hsync stopped during the starvation");
      errors = errors + 1;
    end
    mem_stall = 0;

    axil_read(32'h08, v);
    if (!v[2]) begin
      $display("FAIL STATUS.UNDERRUN did not latch after the starvation: %08h", v);
      errors = errors + 1;
    end
    axil_read(32'h28, v);
    $display("underrun events counted: %0d", v);
    if (v == 0) begin
      $display("FAIL UNDERRUN counter did not advance");
      errors = errors + 1;
    end

    // ---- recovery ---------------------------------------------------------
    // The frame that was in progress when the memory came back keeps underrunning
    // until the frame boundary handshake realigns the buffer, so let two frames pass
    // before clearing the sticky flag.
    wait_frames(2);
    axil_write(32'h08, 32'h0000_0004);  // write one to clear
    axil_read(32'h08, v);
    if (v[2]) begin
      $display("FAIL STATUS.UNDERRUN did not clear on a one write: %08h", v);
      errors = errors + 1;
    end

    wait_frames(3);
    axil_read(32'h08, v);
    if (v[2]) begin
      $display("FAIL STATUS.UNDERRUN latched again after recovery: %08h", v);
      errors = errors + 1;
    end

    // Capture the next whole frame for the reference model to check.
    arm_period_monitor();
    recovery_frame = frame_idx + 1;
    while (frame_idx < recovery_frame) @(posedge clk_pix);
    capturing = 1;
    while (!captured) @(posedge clk_pix);
    $display("recovery frame %0d captured, hsync period %0d..%0d pixels", recovery_frame, hs_min,
             hs_max);
    if (hs_min != hs_max) begin
      $display("FAIL hsync period varied after recovery");
      errors = errors + 1;
    end

    // Record the index so the reference model check knows which frame to render.
    fd = $fopen($sformatf("%s_index.txt", ppm_prefix), "w");
    if (fd != 0) begin
      $fwrite(fd, "%0d\n", recovery_frame);
      $fclose(fd);
    end

    if (errors == 0) $display("TEST_RESULT: PASS  recovery frame index %0d", recovery_frame);
    else $display("TEST_RESULT: FAIL  %0d problem(s)", errors);
    $finish;
  end

  initial begin
    #900_000_000_000;
    $display("TEST_RESULT: FAIL watchdog timeout");
    $finish;
  end

endmodule
