// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// AXI4-Lite manager tasks, textually included by each testbench.
//
// The including module must declare clk, rst_n and the AXI-Lite signal set with the
// names used below. Inclusion rather than a separate module keeps the tasks callable
// without hierarchical references, which not every simulator in the flow supports.

task automatic axil_write_be(input logic [31:0] addr, input logic [31:0] data,
                             input logic [3:0] strb);
  @(posedge clk);
  awaddr  <= addr[AxiAddrW-1:0];
  awvalid <= 1'b1;
  wdata   <= data;
  wstrb   <= strb;
  wvalid  <= 1'b1;
  bready  <= 1'b1;
  // Both address and data are offered until each is accepted.
  fork
    begin
      while (!(awvalid && awready)) @(posedge clk);
      @(posedge clk);
      awvalid <= 1'b0;
    end
    begin
      while (!(wvalid && wready)) @(posedge clk);
      @(posedge clk);
      wvalid <= 1'b0;
    end
  join
  while (!bvalid) @(posedge clk);
  @(posedge clk);
  bready <= 1'b0;
endtask

task automatic axil_write(input logic [31:0] addr, input logic [31:0] data);
  axil_write_be(addr, data, 4'hF);
endtask

task automatic axil_read(input logic [31:0] addr, output logic [31:0] data);
  @(posedge clk);
  araddr  <= addr[AxiAddrW-1:0];
  arvalid <= 1'b1;
  rready  <= 1'b1;
  while (!(arvalid && arready)) @(posedge clk);
  @(posedge clk);
  arvalid <= 1'b0;
  while (!rvalid) @(posedge clk);
  data = rdata;
  @(posedge clk);
  rready <= 1'b0;
endtask

// Replays a register script: one "offset value" pair of hex numbers per line.
task automatic axil_replay(input string fname);
  int fd;
  int r;
  logic [31:0] a;
  logic [31:0] d;
  fd = $fopen(fname, "r");
  if (fd == 0) begin
    $display("FATAL cannot open register script %s", fname);
    $finish;
  end
  r = 2;
  while (r == 2) begin
    r = $fscanf(fd, "%h %h", a, d);
    if (r == 2) axil_write(a, d);
  end
  $fclose(fd);
endtask

task automatic axil_idle();
  awaddr  <= '0;
  awvalid <= 1'b0;
  wdata   <= '0;
  wstrb   <= '0;
  wvalid  <= 1'b0;
  bready  <= 1'b0;
  araddr  <= '0;
  arvalid <= 1'b0;
  rready  <= 1'b0;
endtask
