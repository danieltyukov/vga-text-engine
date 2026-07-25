// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Register file testbench.
//
// Walks the whole map: identification, every read/write register at all ones and all
// zeros to pin down the implemented bit mask, read only registers proof against
// writes, reserved and unmapped addresses reading zero, byte strobes, and the write
// one to clear behaviour of the sticky status flags.
//
// Self checking. Prints one line per failure and a TEST_RESULT verdict.

`timescale 1ps / 1ps

module tb_vte_regs;

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

  int errors;
  int checks;

  task automatic expect_eq(input string what, input logic [31:0] got, input logic [31:0] want);
    checks = checks + 1;
    if (got !== want) begin
      errors = errors + 1;
      $display("FAIL %s: read %08h, expected %08h", what, got, want);
    end
  endtask

  // Writes all ones then all zeros and confirms the register only keeps the bits in
  // mask. This pins down both the field widths and that reserved bits read as zero.
  task automatic check_rw(input string name, input logic [31:0] off, input logic [31:0] mask);
    logic [31:0] v;
    axil_write(off, 32'hFFFF_FFFF);
    axil_read(off, v);
    expect_eq({name, " all ones"}, v, mask);
    axil_write(off, 32'h0000_0000);
    axil_read(off, v);
    expect_eq({name, " all zeros"}, v, 32'h0);
    // A walking pattern catches bits wired to the wrong position.
    axil_write(off, 32'hA5A5_A5A5);
    axil_read(off, v);
    expect_eq({name, " pattern A5"}, v, 32'hA5A5_A5A5 & mask);
    axil_write(off, 32'h5A5A_5A5A);
    axil_read(off, v);
    expect_eq({name, " pattern 5A"}, v, 32'h5A5A_5A5A & mask);
    axil_write(off, 32'h0000_0000);
  endtask

  task automatic check_ro(input string name, input logic [31:0] off, input logic [31:0] expect_v);
    logic [31:0] v;
    axil_read(off, v);
    expect_eq({name, " initial"}, v, expect_v);
    axil_write(off, 32'hFFFF_FFFF);
    axil_read(off, v);
    expect_eq({name, " after write"}, v, expect_v);
  endtask

  initial begin
    logic [31:0] v;
    errors = 0;
    checks = 0;

    rst_n     = 0;
    rst_pix_n = 0;
    axil_idle();
    repeat (5) @(posedge clk);
    rst_n = 1;
    repeat (5) @(posedge clk_pix);
    rst_pix_n = 1;
    repeat (5) @(posedge clk);

    // ---- identification and reset values --------------------------------
    check_ro("ID", 32'h00, 32'h5654_4501);

    axil_read(32'h04, v);
    expect_eq("CTRL reset value", v, 32'h0000_0002);  // 8x16 glyphs, disabled
    axil_read(32'h0C, v);
    expect_eq("GEOM reset value", v, 32'h001E_0050);  // 80 by 30
    axil_read(32'h18, v);
    expect_eq("CURSHAPE reset value", v, 32'h000F_0F0E);
    axil_read(32'h1C, v);
    expect_eq("BLINK reset value", v, 32'h000F_000F);
    axil_read(32'h40, v);
    expect_eq("PAL0 reset value", v, 32'h0000_0000);
    axil_read(32'h5C, v);
    expect_eq("PAL7 reset value", v, 32'h0000_0AAA);
    axil_read(32'h7C, v);
    expect_eq("PAL15 reset value", v, 32'h0000_0FFF);

    // ---- read/write registers -------------------------------------------
    check_rw("CTRL", 32'h04, 32'h0000_0FF7);
    check_rw("GEOM", 32'h0C, 32'h00FF_00FF);
    check_rw("BASE", 32'h10, 32'hFFFF_FFFF);
    check_rw("CURSOR", 32'h14, 32'h80FF_00FF);
    check_rw("CURSHAPE", 32'h18, 32'h000F_0F0F);
    check_rw("BLINK", 32'h1C, 32'h00FF_00FF);
    check_rw("SCRATCH", 32'h2C, 32'hFFFF_FFFF);
    for (int i = 0; i < 16; i++) begin
      check_rw($sformatf("PAL%0d", i), 32'h40 + 4 * i, 32'h0000_0FFF);
    end

    // ---- read only registers --------------------------------------------
    // The engine is disabled, so the frame and underrun counters read zero and
    // MODEDIM reports the geometry of mode 0.
    check_ro("FRAME", 32'h20, 32'h0000_0000);
    check_ro("UNDERRUN", 32'h28, 32'h0000_0000);
    check_ro("MODEDIM", 32'h24, 32'h01E0_0280);  // 480 by 640

    // ---- reserved and unmapped addresses --------------------------------
    axil_read(32'h30, v);
    expect_eq("unmapped 0x30 reads zero", v, 32'h0);
    axil_write(32'h30, 32'hFFFF_FFFF);
    axil_read(32'h30, v);
    expect_eq("unmapped 0x30 stays zero", v, 32'h0);
    axil_read(32'h3C, v);
    expect_eq("unmapped 0x3C reads zero", v, 32'h0);
    axil_read(32'h80, v);
    expect_eq("above the palette reads zero", v, 32'h0);
    axil_read(32'hFC, v);
    expect_eq("top of the window reads zero", v, 32'h0);
    axil_read(32'h100, v);
    expect_eq("outside the window reads zero", v, 32'h0);
    axil_write(32'h100, 32'hDEAD_BEEF);
    axil_read(32'h2C, v);
    expect_eq("out of window write is dropped", v, 32'h0);

    // ---- byte strobes ----------------------------------------------------
    axil_write(32'h2C, 32'hAABB_CCDD);
    axil_write_be(32'h2C, 32'h1122_3344, 4'b0010);
    axil_read(32'h2C, v);
    expect_eq("SCRATCH byte 1 only", v, 32'hAABB_33DD);
    axil_write_be(32'h2C, 32'h1122_3344, 4'b1001);
    axil_read(32'h2C, v);
    expect_eq("SCRATCH bytes 0 and 3", v, 32'h11BB_3344);
    axil_write_be(32'h2C, 32'h0000_0000, 4'b0000);
    axil_read(32'h2C, v);
    expect_eq("SCRATCH no strobes is a no-op", v, 32'h11BB_3344);
    axil_write(32'h2C, 32'h0);

    // ---- sticky status flags --------------------------------------------
    // A disabled engine is not displaying, so VBLANK reads one. RUNNING and both
    // sticky flags must be clear.
    axil_read(32'h08, v);
    expect_eq("STATUS while disabled", v & 32'h0000_000F, 32'h0000_0002);

    // Run a few frames so the frame flag latches, then clear it.
    axil_write(32'h0C, 32'h0008_0028);  // 40 by 8 cells keeps the frame cheap
    axil_write(32'h04, 32'h0000_0003);
    repeat (3) @(posedge frame_evt);
    axil_read(32'h08, v);
    if ((v & 32'h0000_0008) == 0) begin
      errors = errors + 1;
      $display("FAIL STATUS.FRAME did not latch, read %08h", v);
    end
    checks = checks + 1;
    if ((v & 32'h0000_0001) == 0) begin
      errors = errors + 1;
      $display("FAIL STATUS.RUNNING low while enabled, read %08h", v);
    end
    checks = checks + 1;

    axil_read(32'h20, v);
    if (v == 0) begin
      errors = errors + 1;
      $display("FAIL FRAME counter still zero after three frames");
    end
    checks = checks + 1;

    // Writing zero to a write one to clear bit must leave it alone.
    axil_write(32'h08, 32'h0000_0000);
    axil_read(32'h08, v);
    if ((v & 32'h0000_0008) == 0) begin
      errors = errors + 1;
      $display("FAIL STATUS.FRAME cleared by a zero write");
    end
    checks = checks + 1;

    axil_write(32'h08, 32'h0000_0008);
    axil_read(32'h08, v);
    if ((v & 32'h0000_0008) != 0) begin
      errors = errors + 1;
      $display("FAIL STATUS.FRAME did not clear on a one write, read %08h", v);
    end
    checks = checks + 1;

    // MODEDIM follows the mode that the pixel domain latched, not the last write.
    axil_write(32'h04, 32'h0000_0000);
    repeat (20) @(posedge clk);
    axil_write(32'h04, 32'h0000_0023);  // mode 2, enabled
    repeat (2) @(posedge frame_evt);
    axil_read(32'h24, v);
    expect_eq("MODEDIM after switching to mode 2", v, 32'h0300_0400);  // 768 by 1024
    axil_write(32'h04, 32'h0000_0000);

    if (errors == 0) $display("TEST_RESULT: PASS  %0d register checks", checks);
    else $display("TEST_RESULT: FAIL  %0d of %0d register checks failed", errors, checks);
    $finish;
  end

  initial begin
    #400_000_000_000;
    $display("TEST_RESULT: FAIL watchdog timeout");
    $finish;
  end

endmodule
