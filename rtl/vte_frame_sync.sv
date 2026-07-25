// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Frame boundary resynchronisation and configuration snapshot.
//
// This is the only module that deliberately spans both clock domains, so every
// crossing in the design is visible in one place. It solves three problems at once
// with a single four phase level handshake that runs inside vertical blanking:
//
//   1. Alignment. The pixel pipeline consumes exactly cols*rows*glyph_h cells per
//      frame and the fetch engine produces exactly that many, so under normal
//      operation the FIFO index mapping never drifts. An underrun breaks that
//      invariant. Draining the FIFO once per frame while the producer is parked
//      makes any drift heal within one frame instead of persisting forever.
//
//   2. Atomic configuration. A multi bit bundle cannot be sampled across clocks
//      without a handshake. While the producer is parked its shadow copy of the
//      register file is frozen and provably stable, so the pixel domain can sample
//      all 295 bits at once. Software therefore never sees a torn configuration:
//      a palette rewrite or a geometry change lands as one atomic frame update.
//
//   3. Status readback. The frame and underrun counters live in the pixel domain.
//      They only change outside the handshake window, so the register domain can
//      sample them at the same quiescent point.
//
// Handshake, with the pixel domain as initiator:
//
//   pixel  P_REQ    hold=1 ..................... wait for held
//   fetch           see hold, refresh shadow, freeze it, sample status, held=1
//   pixel  P_LATCH  sample the frozen shadow into cfg_pix
//   pixel  P_DRAIN  pop the FIFO until empty
//   pixel  P_REL    hold=0 ..................... wait for !held
//   fetch           see !hold, restart the address sequence, resume fetching
//   pixel  P_RUN    run until the next vertical front porch
//
// Timing budget: the whole sequence costs a handful of clocks in each domain plus
// at most Depth pixel clocks for the drain. vte_modes_pkg::MinVBlankPixels is
// 29568, so the margin is more than three orders of magnitude.

module vte_frame_sync (
    // -------------------------------------------------------------------------
    // Register / fetch domain
    // -------------------------------------------------------------------------
    input  logic          clk_i,
    input  logic          rst_ni,
    input  logic          en_i,            // CTRL.EN as written by software
    input  vte_pkg::cfg_t cfg_live_i,      // live register file contents
    output vte_pkg::cfg_t cfg_frame_o,     // frozen snapshot for the fetch engine
    output logic          fetch_run_o,     // fetch engine may issue requests
    output vte_pkg::sts_t sts_o,           // last sampled pixel domain counters
    output logic          frame_evt_o,     // pulse: frame counter advanced
    output logic          underrun_evt_o,  // pulse: underrun counter advanced
    output logic          running_o,       // pixel pipeline holds a valid config
    output logic          vblank_o,        // pixel pipeline is in vertical blanking
    // -------------------------------------------------------------------------
    // Pixel domain
    // -------------------------------------------------------------------------
    input  logic          clk_pix_i,
    input  logic          rst_pix_ni,
    output logic          en_pix_o,
    output vte_pkg::cfg_t cfg_pix_o,
    output logic          cfg_pix_valid_o,  // gates the sync generator
    input  logic          frame_edge_i,     // pulse at the vertical front porch start
    input  logic          vblank_pix_i,
    input  logic          fifo_empty_i,
    output logic          fifo_drain_o,
    input  vte_pkg::sts_t sts_pix_i
);

  // ---------------------------------------------------------------------------
  // Pixel domain: handshake initiator
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    P_IDLE,
    P_REQ,
    P_LATCH,
    P_DRAIN,
    P_REL,
    P_RUN
  } pstate_e;

  pstate_e pstate_q, pstate_d;

  logic hold_q, hold_d;
  logic held_in_pix;
  logic cfg_valid_q, cfg_valid_d;
  vte_pkg::cfg_t cfg_pix_q, cfg_pix_d;
  vte_pkg::cfg_t cfg_shadow_q;
  logic drain_q, drain_d;

  vte_sync2 i_sync_en_pix (
      .clk_i (clk_pix_i),
      .rst_ni(rst_pix_ni),
      .d_i   (en_i),
      .q_o   (en_pix_o)
  );

  logic held_q;

  vte_sync2 i_sync_held (
      .clk_i (clk_pix_i),
      .rst_ni(rst_pix_ni),
      .d_i   (held_q),
      .q_o   (held_in_pix)
  );

  always_comb begin
    pstate_d    = pstate_q;
    hold_d      = hold_q;
    cfg_valid_d = cfg_valid_q;
    cfg_pix_d   = cfg_pix_q;
    drain_d     = 1'b0;

    case (pstate_q)
      P_IDLE: begin
        hold_d      = 1'b0;
        cfg_valid_d = 1'b0;
        if (en_pix_o) pstate_d = P_REQ;
      end
      P_REQ: begin
        hold_d = 1'b1;
        if (held_in_pix) pstate_d = P_LATCH;
      end
      P_LATCH: begin
        // The shadow is frozen and has been stable for at least one register
        // clock, so the whole bundle can be taken in one go.
        cfg_pix_d   = cfg_shadow_q;
        cfg_valid_d = 1'b1;
        pstate_d    = P_DRAIN;
      end
      P_DRAIN: begin
        drain_d = 1'b1;
        if (fifo_empty_i) pstate_d = P_REL;
      end
      P_REL: begin
        hold_d = 1'b0;
        if (!held_in_pix) pstate_d = P_RUN;
      end
      P_RUN: begin
        if (frame_edge_i) pstate_d = P_REQ;
      end
      default: pstate_d = P_IDLE;
    endcase

    if (!en_pix_o) pstate_d = P_IDLE;
  end

  always_ff @(posedge clk_pix_i or negedge rst_pix_ni) begin
    if (!rst_pix_ni) begin
      pstate_q    <= P_IDLE;
      hold_q      <= 1'b0;
      cfg_valid_q <= 1'b0;
      cfg_pix_q   <= '0;
      drain_q     <= 1'b0;
    end else begin
      pstate_q    <= pstate_d;
      hold_q      <= hold_d;
      cfg_valid_q <= cfg_valid_d;
      cfg_pix_q   <= cfg_pix_d;
      drain_q     <= drain_d;
    end
  end

  assign cfg_pix_o       = cfg_pix_q;
  assign cfg_pix_valid_o = cfg_valid_q;
  assign fifo_drain_o    = drain_q;

  // ---------------------------------------------------------------------------
  // Register domain: handshake target
  // ---------------------------------------------------------------------------
  logic hold_in_reg;
  logic hold_in_reg_q;
  logic [1:0] hold_cnt_q;
  vte_pkg::sts_t sts_q;
  logic frame_evt_q, underrun_evt_q;
  logic sample;
  logic refresh;

  vte_sync2 i_sync_hold (
      .clk_i (clk_i),
      .rst_ni(rst_ni),
      .d_i   (hold_q),
      .q_o   (hold_in_reg)
  );

  vte_sync2 i_sync_running (
      .clk_i (clk_i),
      .rst_ni(rst_ni),
      .d_i   (cfg_valid_q),
      .q_o   (running_o)
  );

  vte_sync2 i_sync_vblank (
      .clk_i (clk_i),
      .rst_ni(rst_ni),
      .d_i   (vblank_pix_i),
      .q_o   (vblank_o)
  );

  // Phase counter inside the hold window. Counts 0,1,2,3 and sticks at 3.
  //   0,1: shadow tracks the live registers
  //     2: shadow frozen, pixel domain counters sampled
  //     3: held asserted, one clock after the freeze
  assign refresh = hold_in_reg && (hold_cnt_q < 2'd2);
  assign sample  = hold_in_reg && (hold_cnt_q == 2'd2);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      hold_cnt_q     <= '0;
      hold_in_reg_q  <= 1'b0;
      held_q         <= 1'b0;
      cfg_shadow_q   <= '0;
      sts_q          <= '0;
      frame_evt_q    <= 1'b0;
      underrun_evt_q <= 1'b0;
    end else begin
      hold_in_reg_q <= hold_in_reg;
      if (!hold_in_reg) hold_cnt_q <= '0;
      else if (hold_cnt_q != 2'd3) hold_cnt_q <= hold_cnt_q + 2'd1;

      held_q <= hold_in_reg && (hold_cnt_q == 2'd3);

      if (refresh) cfg_shadow_q <= cfg_live_i;

      frame_evt_q    <= 1'b0;
      underrun_evt_q <= 1'b0;
      if (sample) begin
        sts_q          <= sts_pix_i;
        frame_evt_q    <= (sts_pix_i.frame_cnt != sts_q.frame_cnt);
        underrun_evt_q <= (sts_pix_i.underrun_cnt != sts_q.underrun_cnt);
      end
    end
  end

  assign cfg_frame_o    = cfg_shadow_q;
  assign sts_o          = sts_q;
  assign frame_evt_o    = frame_evt_q;
  assign underrun_evt_o = underrun_evt_q;

  // The fetch engine is parked for the whole handshake and restarts its address
  // sequence from cell zero as soon as hold is released.
  assign fetch_run_o    = en_i && !hold_in_reg && !hold_in_reg_q && !held_q;

endmodule
