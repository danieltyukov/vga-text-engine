// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Dual clock elastic buffer: the character FIFO between the fetch engine and the
// pixel pipeline.
//
// Gray coded pointers with two flop synchronisers in both directions. The read side
// is show ahead: rd_data_o is always the head of the queue and is valid whenever
// rd_empty_o is low, so the pixel pipeline can consume a cell in the same cycle it
// decides to. That matters because the pipeline has a fixed 8 pixel budget per cell
// and cannot afford a read latency cycle.
//
// wr_level_o is an occupancy estimate in the write domain. It is conservative: the
// read pointer it compares against is up to two write clocks stale, so the reported
// level is never lower than the true level. That is the safe direction for a
// software watermark.

module vte_cdc_fifo #(
    parameter int unsigned Width = 19,
    parameter int unsigned Depth = 32,  // must be a power of two, at least 4
    localparam int unsigned PtrW = $clog2(Depth)
) (
    // Write domain
    input  logic             clk_wr_i,
    input  logic             rst_wr_ni,
    input  logic             wr_en_i,
    input  logic [Width-1:0] wr_data_i,
    output logic             wr_full_o,
    output logic [    PtrW:0] wr_level_o,
    // Read domain
    input  logic             clk_rd_i,
    input  logic             rst_rd_ni,
    input  logic             rd_en_i,
    output logic [Width-1:0] rd_data_o,
    output logic             rd_empty_o
);

  logic [Width-1:0] mem[0:Depth-1];

  logic [PtrW:0] wbin_q, wbin_d;
  logic [PtrW:0] wgray_q, wgray_d;
  logic [PtrW:0] rbin_q, rbin_d;
  logic [PtrW:0] rgray_q, rgray_d;

  logic [PtrW:0] wgray_in_rd;  // write pointer observed by the read domain
  logic [PtrW:0] rgray_in_wr;  // read pointer observed by the write domain
  logic [PtrW:0] rbin_in_wr;

  logic do_write;
  logic do_read;

  function automatic logic [PtrW:0] bin2gray(input logic [PtrW:0] b);
    bin2gray = b ^ (b >> 1);
  endfunction

  function automatic logic [PtrW:0] gray2bin(input logic [PtrW:0] g);
    logic [PtrW:0] b;
    b[PtrW] = g[PtrW];
    for (int i = PtrW - 1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
    gray2bin = b;
  endfunction

  // ---------------------------------------------------------------------------
  // Write side
  // ---------------------------------------------------------------------------
  assign do_write = wr_en_i && !wr_full_o;
  assign wbin_d   = wbin_q + {{PtrW{1'b0}}, do_write};
  assign wgray_d  = bin2gray(wbin_d);

  always_ff @(posedge clk_wr_i or negedge rst_wr_ni) begin
    if (!rst_wr_ni) begin
      wbin_q  <= '0;
      wgray_q <= '0;
    end else begin
      wbin_q  <= wbin_d;
      wgray_q <= wgray_d;
    end
  end

  always_ff @(posedge clk_wr_i) begin
    if (do_write) mem[wbin_q[PtrW-1:0]] <= wr_data_i;
  end

  vte_sync2 #(
      .Width(PtrW + 1)
  ) i_sync_rptr (
      .clk_i (clk_wr_i),
      .rst_ni(rst_wr_ni),
      .d_i   (rgray_q),
      .q_o   (rgray_in_wr)
  );

  assign rbin_in_wr = gray2bin(rgray_in_wr);

  // Full when the pointers differ only in the top two bits, the standard gray
  // wrap test.
  assign wr_full_o = (wgray_q == {~rgray_in_wr[PtrW:PtrW-1], rgray_in_wr[PtrW-2:0]});
  assign wr_level_o = wbin_q - rbin_in_wr;

  // ---------------------------------------------------------------------------
  // Read side
  // ---------------------------------------------------------------------------
  assign do_read   = rd_en_i && !rd_empty_o;
  assign rbin_d    = rbin_q + {{PtrW{1'b0}}, do_read};
  assign rgray_d   = bin2gray(rbin_d);

  always_ff @(posedge clk_rd_i or negedge rst_rd_ni) begin
    if (!rst_rd_ni) begin
      rbin_q  <= '0;
      rgray_q <= '0;
    end else begin
      rbin_q  <= rbin_d;
      rgray_q <= rgray_d;
    end
  end

  vte_sync2 #(
      .Width(PtrW + 1)
  ) i_sync_wptr (
      .clk_i (clk_rd_i),
      .rst_ni(rst_rd_ni),
      .d_i   (wgray_q),
      .q_o   (wgray_in_rd)
  );

  assign rd_empty_o = (rgray_q == wgray_in_rd);
  assign rd_data_o  = mem[rbin_q[PtrW-1:0]];

`ifndef SYNTHESIS
  initial begin : p_param_check
    assert (Depth >= 4)
    else $fatal(1, "vte_cdc_fifo: Depth must be at least 4, got %0d", Depth);
    assert ((Depth & (Depth - 1)) == 0)
    else $fatal(1, "vte_cdc_fifo: Depth must be a power of two, got %0d", Depth);
    assert (Width >= 1)
    else $fatal(1, "vte_cdc_fifo: Width must be at least 1");
  end
`endif

endmodule
