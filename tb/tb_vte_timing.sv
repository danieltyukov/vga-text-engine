// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// VGA timing conformance testbench.
//
// Measures the real geometry of the pins rather than peeking at internal counters. It
// times the runs of each hsync and vsync level and the position of the data enable
// window relative to the end of the sync pulse. Every horizontal quantity is recorded
// as a minimum and a maximum over a whole frame, so one irregular line out of hundreds
// shows up as min != max.
//
// A line runs SYNC, BACK PORCH, ACTIVE, FRONT PORCH. With a position counter that
// restarts on the cycle the sync pulse ends:
//   data enable rises at   back porch
//   data enable falls at   back porch + active
//   next sync rises at     back porch + active + front porch
//
// Both raw sync level run lengths are reported, so scripts/check_timing.py can confirm
// the polarity numerically: for a positive sync the high run must equal the sync width
// and the low run the rest of the line, and the other way round for a negative sync.
//
// Plusargs:
//   +mode=N    video mode index
//   +cols=N    text columns
//   +rows=N    text rows
//   +hspol=N   expected hsync polarity, used to locate the pulse
//   +vspol=N   expected vsync polarity
//   +out=FILE  measurement output path

`timescale 1ps / 1ps

module tb_vte_timing;

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

  int mode_sel, cols, rows, hspol, vspol;
  string out_file;

  logic hs_q, de_q;
  bit measuring;
  bit hs_active, hs_active_q;
  bit vs_active;

  int hs_run;
  int hi_min, hi_max, lo_min, lo_max;
  int pos, de_start, de_end;
  int back_min, back_max, act_min, act_max, front_min, front_max;

  typedef enum int {
    V_SYNC,
    V_BACK,
    V_ACT,
    V_FRONT
  } vstate_e;
  vstate_e vstate;
  int vs_cnt, vb_cnt, va_cnt, vf_cnt;
  int vs_res, vb_res, va_res, vf_res;
  int frames_done;
  bit de_seen, vs_seen;

  function automatic int imin(int a, int b);
    imin = (a < b) ? a : b;
  endfunction

  function automatic int imax(int a, int b);
    imax = (a > b) ? a : b;
  endfunction

  assign hs_active = (hsync == hspol[0]);
  assign vs_active = (vsync == vspol[0]);

  // Classifies the line that just finished and folds it into the vertical counts.
  task automatic close_line();
    if (measuring) begin
      if (vs_seen) begin
        if (vstate != V_SYNC) begin
          // A fresh vertical sync run means the previous frame is complete.
          if (frames_done > 0) begin
            vs_res = vs_cnt;
            vb_res = vb_cnt;
            va_res = va_cnt;
            vf_res = vf_cnt;
          end
          frames_done = frames_done + 1;
          vs_cnt      = 1;
          vb_cnt      = 0;
          va_cnt      = 0;
          vf_cnt      = 0;
          vstate      = V_SYNC;
        end else begin
          vs_cnt = vs_cnt + 1;
        end
      end else if (de_seen) begin
        vstate = V_ACT;
        va_cnt = va_cnt + 1;
      end else if (vstate == V_SYNC || vstate == V_BACK) begin
        vstate = V_BACK;
        vb_cnt = vb_cnt + 1;
      end else begin
        vstate = V_FRONT;
        vf_cnt = vf_cnt + 1;
      end
    end
    de_seen = 0;
    vs_seen = 0;
  endtask

  always @(posedge clk_pix) begin
    if (rst_pix_n) begin
      // Position counter restarts on the cycle the sync pulse releases.
      if (!hs_active && hs_active_q) pos = 0;
      else pos = pos + 1;

      // Sync level run lengths.
      if (hsync != hs_q) begin
        if (hs_q) begin
          hi_min = (hi_min == 0) ? hs_run : imin(hi_min, hs_run);
          hi_max = imax(hi_max, hs_run);
        end else begin
          lo_min = (lo_min == 0) ? hs_run : imin(lo_min, hs_run);
          lo_max = imax(lo_max, hs_run);
        end
        hs_run = 1;
      end else begin
        hs_run = hs_run + 1;
      end

      // Start of a sync pulse closes out the previous line.
      if (hs_active && !hs_active_q) begin
        if (measuring && de_end > 0) begin
          front_min = (front_min == 0) ? (pos - de_end) : imin(front_min, pos - de_end);
          front_max = imax(front_max, pos - de_end);
        end
        close_line();
      end

      if (de && !de_q) de_start = pos;
      if (!de && de_q) begin
        de_end = pos;
        if (measuring) begin
          back_min = (back_min == 0) ? de_start : imin(back_min, de_start);
          back_max = imax(back_max, de_start);
          act_min  = (act_min == 0) ? (de_end - de_start) : imin(act_min, de_end - de_start);
          act_max  = imax(act_max, de_end - de_start);
        end
      end

      // Accumulate for the line now in progress.
      if (de) de_seen = 1;
      if (vs_active) vs_seen = 1;

      hs_q        = hsync;
      hs_active_q = hs_active;
      de_q        = de;
    end
  end

  task automatic reset_counters();
    hi_min      = 0;
    hi_max      = 0;
    lo_min      = 0;
    lo_max      = 0;
    back_min    = 0;
    back_max    = 0;
    act_min     = 0;
    act_max     = 0;
    front_min   = 0;
    front_max   = 0;
    frames_done = 0;
    vs_cnt      = 0;
    vb_cnt      = 0;
    va_cnt      = 0;
    vf_cnt      = 0;
    vstate      = V_FRONT;
  endtask

  task automatic wait_frame();
    while (!vs_active) @(posedge clk_pix);
    while (vs_active) @(posedge clk_pix);
  endtask

  int fd;

  initial begin
    hs_q        = 0;
    hs_active_q = 0;
    de_q        = 0;
    measuring   = 0;
    hs_run      = 0;
    pos         = 0;
    de_start    = 0;
    de_end      = 0;
    de_seen     = 0;
    vs_seen     = 0;
    vs_res      = 0;
    vb_res      = 0;
    va_res      = 0;
    vf_res      = 0;
    reset_counters();

    if (!$value$plusargs("mode=%d", mode_sel)) mode_sel = 0;
    if (!$value$plusargs("cols=%d", cols)) cols = 80;
    if (!$value$plusargs("rows=%d", rows)) rows = 30;
    if (!$value$plusargs("hspol=%d", hspol)) hspol = 0;
    if (!$value$plusargs("vspol=%d", vspol)) vspol = 0;
    if (!$value$plusargs("out=%s", out_file)) out_file = "results/sim/timing.txt";

    rst_n     = 0;
    rst_pix_n = 0;
    axil_idle();
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk_pix);
    rst_pix_n = 1;
    repeat (5) @(posedge clk);

    axil_write(32'h0C, (rows << 16) | cols);
    axil_write(32'h10, 32'h0);
    axil_write(32'h04, 32'h0000_0003 | (mode_sel << 4));

    // Discard the first frame so the measurement starts from a settled pipeline.
    wait_frame();
    reset_counters();
    measuring = 1;
    // Two vertical sync runs bracket one complete frame.
    while (frames_done < 2) @(posedge clk_pix);
    measuring = 0;

    fd = $fopen(out_file, "w");
    if (fd == 0) begin
      $display("TEST_RESULT: FAIL cannot open %s", out_file);
      $finish;
    end
    $fwrite(fd, "mode %0d\n", mode_sel);
    $fwrite(fd, "h_hi_min %0d\nh_hi_max %0d\n", hi_min, hi_max);
    $fwrite(fd, "h_lo_min %0d\nh_lo_max %0d\n", lo_min, lo_max);
    $fwrite(fd, "h_back_min %0d\nh_back_max %0d\n", back_min, back_max);
    $fwrite(fd, "h_active_min %0d\nh_active_max %0d\n", act_min, act_max);
    $fwrite(fd, "h_front_min %0d\nh_front_max %0d\n", front_min, front_max);
    $fwrite(fd, "v_sync %0d\n", vs_res);
    $fwrite(fd, "v_back %0d\n", vb_res);
    $fwrite(fd, "v_active %0d\n", va_res);
    $fwrite(fd, "v_front %0d\n", vf_res);
    $fclose(fd);

    $display("mode %0d  hsync hi=%0d lo=%0d  back=%0d active=%0d front=%0d", mode_sel, hi_min,
             lo_min, back_min, act_min, front_min);
    $display("mode %0d  vsync=%0d back=%0d active=%0d front=%0d", mode_sel, vs_res, vb_res,
             va_res, vf_res);
    $display("TEST_RESULT: PASS  measurements written to %s", out_file);
    $finish;
  end

  initial begin
    #900_000_000_000;
    $display("TEST_RESULT: FAIL watchdog timeout");
    $finish;
  end

endmodule
