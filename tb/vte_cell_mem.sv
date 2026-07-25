// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Cell buffer model for the read only fetch port. Simulation only.
//
// Grants in the same cycle as the request and returns data one cycle later, which is
// the fastest legal behaviour for the port. Driving stall_i high withholds grants so
// a testbench can starve the engine and provoke an elastic buffer underrun while the
// sync generator keeps running.
//
// Contents are loaded from the file named by the +mem= plusarg in $readmemh format,
// one 32 bit cell word per line.

module vte_cell_mem #(
    parameter int unsigned AddrW = 32,
    parameter int unsigned Words = 16384
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic             stall_i,
    input  logic             req_i,
    input  logic [AddrW-1:0] addr_i,
    output logic             gnt_o,
    output logic             rvalid_o,
    output logic [     31:0] rdata_o
);

  localparam int unsigned IdxW = $clog2(Words);

  logic [31:0] mem[0:Words-1];
  logic [IdxW-1:0] idx;
  logic rvalid_q;
  logic [31:0] rdata_q;

  initial begin
    string f;
    for (int unsigned i = 0; i < Words; i++) mem[i] = 32'h0000_0020;  // blank cell
    if ($value$plusargs("mem=%s", f)) $readmemh(f, mem);
  end

  assign gnt_o = req_i && !stall_i;
  assign idx   = addr_i[IdxW+1:2];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rvalid_q <= 1'b0;
      rdata_q  <= '0;
    end else begin
      rvalid_q <= req_i && !stall_i;
      if (req_i && !stall_i) rdata_q <= mem[idx];
    end
  end

  assign rvalid_o = rvalid_q;
  assign rdata_o  = rdata_q;

endmodule
