// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Video mode timing table for vga_text_engine.
//
// Each MODE_* localparam is one complete VESA DMT line/frame description packed
// into a mode_t. The engine walks a line in the order SYNC, BACK PORCH, ACTIVE,
// FRONT PORCH, which puts the entire blanking gap that precedes active video into
// one contiguous run at the low end of the horizontal counter. That ordering is
// what lets the 8 pixel wide character prefetch window sit inside the back porch
// instead of wrapping around the end of the line.
//
// Adding a mode is two lines: one MODE_* localparam here, one case arm in
// vte_mode_lut.sv. Nothing else in the design knows how many modes exist.
//
// The localparams are plain vectors rather than struct-typed so that the package
// stays readable by Icarus Verilog, Verilator and Yosys alike. Field order is
// fixed by mode_t and repeated in a comment on every row.

package vte_modes_pkg;

  // Horizontal and vertical counter widths. 12 bits covers every total in the
  // table with room for 4095 pixel modes.
  localparam int unsigned HCntW = 12;
  localparam int unsigned VCntW = 12;

  // Width of one packed table row: 8 twelve bit counts plus 2 polarity bits.
  localparam int unsigned ModeW = 98;

  // Selector width. Four bits leaves room for 16 modes.
  localparam int unsigned ModeSelW = 4;

  // Number of populated table rows.
  localparam int unsigned NumModes = 4;

  typedef struct packed {
    logic [HCntW-1:0] h_active;
    logic [HCntW-1:0] h_front;
    logic [HCntW-1:0] h_sync;
    logic [HCntW-1:0] h_back;
    logic [VCntW-1:0] v_active;
    logic [VCntW-1:0] v_front;
    logic [VCntW-1:0] v_sync;
    logic [VCntW-1:0] v_back;
    logic             h_pos;  // 1: hsync is high inside the sync region
    logic             v_pos;  // 1: vsync is high inside the sync region
  } mode_t;

  // Field order: h_active h_front h_sync h_back v_active v_front v_sync v_back h_pos v_pos

  // 640x480 @ 60 Hz, 25.175 MHz pixel clock. H total 800, V total 525.
  localparam logic [ModeW-1:0] Mode640x480x60 = {
    12'd640, 12'd16, 12'd96, 12'd48, 12'd480, 12'd10, 12'd2, 12'd33, 1'b0, 1'b0
  };

  // 800x600 @ 60 Hz, 40.000 MHz pixel clock. H total 1056, V total 628.
  localparam logic [ModeW-1:0] Mode800x600x60 = {
    12'd800, 12'd40, 12'd128, 12'd88, 12'd600, 12'd1, 12'd4, 12'd23, 1'b1, 1'b1
  };

  // 1024x768 @ 60 Hz, 65.000 MHz pixel clock. H total 1344, V total 806.
  localparam logic [ModeW-1:0] Mode1024x768x60 = {
    12'd1024, 12'd24, 12'd136, 12'd160, 12'd768, 12'd3, 12'd6, 12'd29, 1'b0, 1'b0
  };

  // 720x400 @ 70 Hz, 28.322 MHz pixel clock. H total 900, V total 449.
  // The classic VGA text resolution, 90 by 25 cells at 8x16.
  localparam logic [ModeW-1:0] Mode720x400x70 = {
    12'd720, 12'd18, 12'd108, 12'd54, 12'd400, 12'd12, 12'd2, 12'd35, 1'b0, 1'b1
  };

  // Largest totals in the table. Used to bound the elaboration time checks in the
  // top level; kept as literals because Yosys cannot evaluate package functions.
  // vte_mode_lut asserts that these still match the table.
  localparam int unsigned MaxHTotal = 1344;  // 1024x768
  localparam int unsigned MaxVTotal = 806;  // 1024x768

  // Shortest vertical blanking interval in pixel clocks, over all modes.
  // 800x600: (1+4+23) lines * 1056 pixels = 29568. The frame resynchronisation
  // handshake and the FIFO drain both have to fit inside this window.
  localparam int unsigned MinVBlankPixels = 29568;

endpackage
