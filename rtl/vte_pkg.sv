// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// Shared types and the register map for vga_text_engine.
//
// Only typedefs and localparams live here. Package functions are avoided so the
// package stays readable by Yosys 0.33.

package vte_pkg;

  // ---------------------------------------------------------------------------
  // Character cell
  // ---------------------------------------------------------------------------
  //
  // One 32 bit word in the fetch address space describes one cell:
  //
  //   bits    field   meaning
  //   [7:0]   CHAR    glyph index, 0..GlyphCount-1; higher codes render blank
  //   [11:8]  FG      foreground palette index
  //   [15:12] BG      background palette index
  //   [16]    BLINK   character blinks at the TXT_DIV rate
  //   [17]    REV     reverse video, swaps FG and BG
  //   [18]    ULINE   light the glyph row selected by CURSHAPE.ULINE_ROW
  //   [31:19] -       reserved, ignored
  //
  // Only the 19 meaningful bits are carried through the elastic buffer.

  localparam int unsigned CellChLsb = 0;
  localparam int unsigned CellFgLsb = 8;
  localparam int unsigned CellBgLsb = 12;
  localparam int unsigned CellBlinkBit = 16;
  localparam int unsigned CellRevBit = 17;
  localparam int unsigned CellUlineBit = 18;

  localparam int unsigned CellW = 19;

  typedef struct packed {
    logic       uline;
    logic       rev;
    logic       blink;
    logic [3:0] bg;
    logic [3:0] fg;
    logic [7:0] ch;
  } cell_t;

  // ---------------------------------------------------------------------------
  // Glyph ROM organisation
  // ---------------------------------------------------------------------------
  //
  // Two banks share one ROM so both glyph heights are live at the same time and
  // switching height costs no reload:
  //
  //   bank 8x16: word index = ch * 16 + row,        words     0 .. 2047
  //   bank 8x8:  word index = 2048 + ch * 8 + row,  words  2048 .. 3071
  //
  // Every word is one 8 pixel glyph row, most significant bit leftmost.

  localparam int unsigned GlyphCount = 128;
  localparam int unsigned GlyphW = 8;
  localparam int unsigned Bank8Base = 2048;
  localparam int unsigned RomDepth = 3072;
  localparam int unsigned RomAddrW = 12;

  // ---------------------------------------------------------------------------
  // Palette
  // ---------------------------------------------------------------------------
  //
  // 16 programmable RGB444 entries. Entry i occupies pal[12*i +: 12] with red in
  // the upper nibble: {R[3:0], G[3:0], B[3:0]}.

  // Signed int so that a genvar loop bound needs no cast, which Yosys 0.33 rejects.
  localparam int PalEntries = 16;
  localparam int unsigned PalEntryW = 12;
  localparam int unsigned PalW = 192;

  // Reset palette: the conventional 16 colour text palette.
  // Written entry 15 first because a concatenation fills from the MSB down.
  localparam logic [PalW-1:0] PalDefault = {
    12'hFFF,  // 15 white
    12'hFF5,  // 14 yellow
    12'hF5F,  // 13 light magenta
    12'hF55,  // 12 light red
    12'h5FF,  // 11 light cyan
    12'h5F5,  // 10 light green
    12'h55F,  //  9 light blue
    12'h555,  //  8 dark grey
    12'hAAA,  //  7 light grey
    12'hA50,  //  6 brown
    12'hA0A,  //  5 magenta
    12'hA00,  //  4 red
    12'h0AA,  //  3 cyan
    12'h0A0,  //  2 green
    12'h00A,  //  1 blue
    12'h000   //  0 black
  };

  // ---------------------------------------------------------------------------
  // Configuration bundle
  // ---------------------------------------------------------------------------
  //
  // Everything the fetch engine and the pixel pipeline need for one frame. The
  // bundle is snapshotted once per frame inside the resynchronisation handshake,
  // so both domains always render a frame from a single consistent set of values.


  typedef struct packed {
    logic [PalW-1:0] pal;
    logic [    31:0] base;
    logic [     7:0] cols;
    logic [     7:0] rows;
    logic [     7:0] cur_col;
    logic [     7:0] cur_row;
    logic [     7:0] cur_div;
    logic [     7:0] txt_div;
    logic [     3:0] cur_start;
    logic [     3:0] cur_end;
    logic [     3:0] uline_row;
    logic [     3:0] border;
    logic [     3:0] mode;
    logic            cur_en;
    logic            font_h16;
    logic            blank;
  } cfg_t;

  // Status bundle travelling back from the pixel domain. Both counters only change
  // outside active video, which is what makes the once per frame sample safe.

  typedef struct packed {
    logic [31:0] frame_cnt;
    logic [15:0] underrun_cnt;
  } sts_t;

  // ---------------------------------------------------------------------------
  // Register map, byte offsets from the subordinate base address
  // ---------------------------------------------------------------------------

  localparam int unsigned RegAddrW = 8;

  localparam logic [RegAddrW-1:0] RegId = 8'h00;  // RO  identification
  localparam logic [RegAddrW-1:0] RegCtrl = 8'h04;  // RW  enable and mode
  localparam logic [RegAddrW-1:0] RegStatus = 8'h08;  // RO + W1C
  localparam logic [RegAddrW-1:0] RegGeom = 8'h0C;  // RW  text grid size
  localparam logic [RegAddrW-1:0] RegBase = 8'h10;  // RW  cell buffer base address
  localparam logic [RegAddrW-1:0] RegCursor = 8'h14;  // RW  cursor position
  localparam logic [RegAddrW-1:0] RegCurShape = 8'h18;  // RW  cursor and underline rows
  localparam logic [RegAddrW-1:0] RegBlink = 8'h1C;  // RW  blink dividers
  localparam logic [RegAddrW-1:0] RegFrame = 8'h20;  // RO  frame counter
  localparam logic [RegAddrW-1:0] RegModeDim = 8'h24;  // RO  active size of latched mode
  localparam logic [RegAddrW-1:0] RegUnderrun = 8'h28;  // RO  underrun event counter
  localparam logic [RegAddrW-1:0] RegScratch = 8'h2C;  // RW  free 32 bit register
  localparam logic [RegAddrW-1:0] RegPalBase = 8'h40;  // RW  PAL0 .. PAL15 at 0x40..0x7C

  localparam logic [31:0] IdValue = 32'h5654_4501;  // "VTE" + revision 1

  // CTRL bit positions
  localparam int unsigned CtrlEnBit = 0;
  localparam int unsigned CtrlFontH16Bit = 1;
  localparam int unsigned CtrlBlankBit = 2;
  localparam int unsigned CtrlModeLsb = 4;
  localparam int unsigned CtrlBorderLsb = 8;

  // STATUS bit positions
  localparam int unsigned StRunningBit = 0;  // RO
  localparam int unsigned StVblankBit = 1;  // RO
  localparam int unsigned StUnderrunBit = 2;  // W1C
  localparam int unsigned StFrameBit = 3;  // W1C
  localparam int unsigned StFifoLvlLsb = 8;  // RO

  // GEOM / CURSOR field positions
  localparam int unsigned GeomColsLsb = 0;
  localparam int unsigned GeomRowsLsb = 16;

  localparam int unsigned CurColLsb = 0;
  localparam int unsigned CurRowLsb = 16;
  localparam int unsigned CurEnBit = 31;

  localparam int unsigned ShpStartLsb = 0;
  localparam int unsigned ShpEndLsb = 8;
  localparam int unsigned ShpUlineLsb = 16;

  localparam int unsigned BlkCurDivLsb = 0;
  localparam int unsigned BlkTxtDivLsb = 16;


endpackage
