// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Frame capture testbench. Renders whole frames out of the RTL and writes them as
// binary PPM files for scripts/check_frames.py to compare against the independent
// Python reference renderer, pixel for pixel.
//
// The register programming comes from a replay script and the cell buffer from a
// $readmemh image, so the RTL and the reference model are driven by byte identical
// stimulus and nothing about a scene is duplicated in Verilog.
//
// Plusargs:
//   +regs=FILE     register script, "offset value" hex pairs, applied before enable
//   +mem=FILE      cell buffer image, consumed by vte_cell_mem
//   +ppm=PREFIX    output path prefix; frame k lands in PREFIX_k.ppm
//   +width=N       expected active pixels per line
//   +height=N      expected active lines per frame
//   +skip=N        frames to discard before capturing (default 1)
//   +frames=N      frames to capture (default 1)
//   +ascii         also print the first captured frame as coarse ASCII art
//
// Compile with -DGATE_LEVEL against the synthesised netlist to run the same comparison on
// the mapped design instead of the RTL.

`timescale 1ps / 1ps

module tb_vte_frame;

  localparam int unsigned AxiAddrW = 12;
  localparam int unsigned RedW = 8;
  localparam int unsigned GreenW = 8;
  localparam int unsigned BlueW = 8;

  // 50 MHz register clock and a 25.175 MHz pixel clock. The ratio is deliberately
  // not an integer so the domain crossing is exercised at every phase relationship.
  localparam int unsigned ClkHalf = 10000;
  localparam int unsigned PixHalf = 19861;

  logic clk, rst_n;
  logic clk_pix, rst_pix_n;

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
  logic [RedW-1:0] red;
  logic [GreenW-1:0] green;
  logic [BlueW-1:0] blue;
  logic frame_evt, underrun_evt;

  assign awprot = 3'b000;
  assign arprot = 3'b000;

  // The gate level netlist has no parameters: synthesis resolved them, so the
  // instantiation has to drop the override list. Everything else is identical, which is
  // the point: the same testbench drives the RTL and the mapped netlist.
`ifdef GATE_LEVEL
  vga_text_engine dut (
`else
  vga_text_engine #(
      .RedW      (RedW),
      .GreenW    (GreenW),
      .BlueW     (BlueW),
      .FifoDepth (32),
      .AxiAddrW  (AxiAddrW),
      .FetchAddrW(32)
  ) dut (
`endif
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

  // ---------------------------------------------------------------------------
  // Frame capture
  // ---------------------------------------------------------------------------
  int width, height, skip, frames;
  string ppm_prefix;
  bit ascii_dump;

  int fd;
  int px, ln;
  int frame_idx;
  int captured;
  bit capturing;
  bit errors;
  logic de_q;

  // One coarse ASCII line per glyph row of the first captured frame.
  string ascii_line;

  task automatic open_frame();
    string fname;
    fname = $sformatf("%s_%0d.ppm", ppm_prefix, frame_idx);
    fd = $fopen(fname, "wb");
    if (fd == 0) begin
      $display("FATAL cannot open %s for writing", fname);
      errors = 1;
      $finish;
    end
    $fwrite(fd, "P6\n%0d %0d\n255\n", width, height);
  endtask

  always @(posedge clk_pix) begin
    if (rst_pix_n) begin
      if (de && !de_q) begin
        // Start of an active line.
        px = 0;
        if (ln == 0 && capturing) open_frame();
        ascii_line = "";
      end
      if (de) begin
        if (capturing) $fwrite(fd, "%c%c%c", red, green, blue);
        if (ascii_dump && capturing && captured == 0 && px < 120) begin
          ascii_line = {ascii_line, ((red | green | blue) != 0) ? "#" : "."};
        end
        px = px + 1;
      end
      if (!de && de_q) begin
        // End of an active line.
        if (px != width) begin
          $display("FAIL active line %0d has %0d pixels, expected %0d", ln, px, width);
          errors = 1;
        end
        if (ascii_dump && capturing && captured == 0 && ln < 32) $display("| %s", ascii_line);
        ln = ln + 1;
        if (ln == height) begin
          if (capturing) begin
            $fclose(fd);
            captured  = captured + 1;
            capturing = 0;
          end
          ln        = 0;
          frame_idx = frame_idx + 1;
          if (frame_idx >= skip && captured < frames) capturing = 1;
        end
      end
      de_q = de;
    end
  end

  // ---------------------------------------------------------------------------
  // Stimulus
  // ---------------------------------------------------------------------------
  initial begin
    string regs_file;

    errors    = 0;
    px        = 0;
    ln        = 0;
    frame_idx = 0;
    captured  = 0;
    capturing = 0;
    de_q      = 0;
    ascii_line = "";

    if (!$value$plusargs("width=%d", width)) width = 640;
    if (!$value$plusargs("height=%d", height)) height = 480;
    if (!$value$plusargs("skip=%d", skip)) skip = 1;
    if (!$value$plusargs("frames=%d", frames)) frames = 1;
    if (!$value$plusargs("ppm=%s", ppm_prefix)) ppm_prefix = "results/frame";
    ascii_dump = $test$plusargs("ascii");

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
      $display("FATAL no +regs= script given");
      $finish;
    end

    // Wait for the requested frames to be captured.
    while (captured < frames) @(posedge clk_pix);
    repeat (100) @(posedge clk_pix);

    if (errors) $display("TEST_RESULT: FAIL");
    else $display("TEST_RESULT: PASS  captured %0d frame(s) of %0dx%0d", captured, width, height);
    $finish;
  end

  // Watchdog. Ten 1024x768 frames at 25 MHz is about 400 ms of model time.
  initial begin
    #600_000_000_000;
    $display("TEST_RESULT: FAIL watchdog timeout");
    $finish;
  end

endmodule
