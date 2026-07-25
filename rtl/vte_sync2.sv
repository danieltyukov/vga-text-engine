// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Two stage flop synchroniser.
//
// Only ever instantiated on signals that are either single bit or gray coded, so
// that a partially settled sample is always a legal value.

module vte_sync2 #(
    parameter int unsigned Width = 1
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [Width-1:0] d_i,
    output logic [Width-1:0] q_o
);

  logic [Width-1:0] stage0_q;
  logic [Width-1:0] stage1_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stage0_q <= '0;
      stage1_q <= '0;
    end else begin
      stage0_q <= d_i;
      stage1_q <= stage0_q;
    end
  end

  assign q_o = stage1_q;

endmodule
