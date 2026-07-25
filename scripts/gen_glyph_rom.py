#!/usr/bin/env python3
"""Generate rtl/vte_glyph_rom.sv from scripts/font_data.py.

The ROM holds both glyph height banks so switching CTRL.FONT_H16 needs no reload:

  words    0 .. 2047   8x16 bank, index = code * 16 + row
  words 2048 .. 3071   8x8  bank, index = 2048 + code * 8 + row

Only non zero words are emitted; the initial block clears the array first. That keeps
the generated file around a tenth of the size of a fully enumerated one while staying
a plain self contained ROM with no external memory file at elaboration time.
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import font_data  # noqa: E402

BANK8_BASE = 2048
ROM_DEPTH = 3072

HEADER = """// Copyright 2026 Daniel Tyukov
// SPDX-License-Identifier: Apache-2.0
//
// GENERATED FILE. Do not edit.
// Regenerate with: python3 scripts/gen_glyph_rom.py
// Source of truth for the bitmaps: scripts/font_data.py
//
// Dual bank glyph ROM, one 8 pixel row per word, most significant bit leftmost.
//
//   words    0 .. 2047   8x16 bank, index = code * 16 + row
//   words 2048 .. 3071   8x8  bank, index = 2048 + code * 8 + row
//
// Registered read port, one cycle latency, which is what lets the shader spend a
// whole clock on the lookup and lets the array map to a block RAM on an FPGA. The
// address is only rewritten once per character cell, so the output holds for the
// eight display pixels that follow without an extra register.

module vte_glyph_rom (
    input  logic                         clk_i,
    input  logic [vte_pkg::RomAddrW-1:0] addr_i,
    output logic [                  7:0] data_o
);

  logic [7:0] mem[0:vte_pkg::RomDepth-1];

  initial begin : p_rom_init
    for (int unsigned i = 0; i < vte_pkg::RomDepth; i++) mem[i] = 8'h00;
"""

FOOTER = """  end

  always_ff @(posedge clk_i) data_o <= mem[addr_i];

endmodule
"""


def code_label(code):
    if 0x20 <= code <= 0x7E:
        name = {0x20: "space", 0x22: "quote", 0x27: "apostrophe",
                0x5C: "backslash"}.get(code, chr(code))
        return f"0x{code:02X} {name}"
    return f"0x{code:02X}"


def emit_bank(lines, height, base, stride, title):
    lines.append(f"    // {title}")
    for code in range(font_data.GLYPH_COUNT):
        rows = font_data.glyph_rows(code, height)
        if not any(rows):
            continue
        items = [f"mem[{base + code * stride + r:4d}] = 8'h{v:02X};"
                 for r, v in enumerate(rows) if v]
        lines.append(f"    // glyph {code_label(code)}")
        for i in range(0, len(items), 4):
            lines.append("    " + " ".join(items[i:i + 4]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--output", default=None,
                    help="output path (default rtl/vte_glyph_rom.sv next to the repo root)")
    args = ap.parse_args()

    repo = pathlib.Path(__file__).resolve().parent.parent
    out = pathlib.Path(args.output) if args.output else repo / "rtl" / "vte_glyph_rom.sv"

    lines = []
    emit_bank(lines, 16, 0, 16, "8x16 bank")
    lines.append("")
    emit_bank(lines, 8, BANK8_BASE, 8, "8x8 bank")

    out.write_text(HEADER + "\n".join(lines) + "\n" + FOOTER)
    words = sum(1 for line in lines if line.strip().startswith("mem["))
    print(f"wrote {out} ({len(lines)} lines, {words} assignment groups)")


if __name__ == "__main__":
    main()
