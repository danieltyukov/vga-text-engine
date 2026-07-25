"""Scene definitions for the vga_text_engine testbenches.

A scene is a register script plus a cell buffer image. Both the RTL testbench and the
Python reference renderer consume the same two files, so nothing about a scene is
described twice and a mismatch can only come from the renderer itself.

Register script format: one "offset value" pair of hex numbers per line, applied in
order over AXI4-Lite before the engine is enabled. CTRL is always written last.

Cell buffer format: $readmemh, one 32 bit cell word per line, word index
row * cols + col.
"""

import argparse
import pathlib

import modes

# Register offsets, mirroring rtl/vte_pkg.sv.
REG_ID = 0x00
REG_CTRL = 0x04
REG_STATUS = 0x08
REG_GEOM = 0x0C
REG_BASE = 0x10
REG_CURSOR = 0x14
REG_CURSHAPE = 0x18
REG_BLINK = 0x1C
REG_FRAME = 0x20
REG_MODEDIM = 0x24
REG_UNDERRUN = 0x28
REG_SCRATCH = 0x2C
REG_PAL = 0x40

ID_VALUE = 0x56544501

# Default reset palette, mirroring vte_pkg::PalDefault.
PAL_DEFAULT = [
    0x000, 0x00A, 0x0A0, 0x0AA, 0xA00, 0xA0A, 0xA50, 0xAAA,
    0x555, 0x55F, 0x5F5, 0x5FF, 0xF55, 0xF5F, 0xFF5, 0xFFF,
]

# Box drawing and block glyph codes from scripts/font_data.py.
G_SHADE_LIGHT = 0x01
G_SHADE_MED = 0x02
G_SHADE_DARK = 0x03
G_BLOCK = 0x04
G_HALF_LEFT = 0x05
G_HALF_LOW = 0x06
G_BULLET = 0x07
G_HLINE = 0x08
G_VLINE = 0x09
G_TL = 0x0A
G_TR = 0x0B
G_BL = 0x0C
G_BR = 0x0D


def cell(ch, fg=7, bg=0, blink=False, rev=False, uline=False):
    """Pack one 32 bit cell word."""
    v = (ch & 0xFF) | ((fg & 0xF) << 8) | ((bg & 0xF) << 12)
    if blink:
        v |= 1 << 16
    if rev:
        v |= 1 << 17
    if uline:
        v |= 1 << 18
    return v


class Scene:
    def __init__(self, name, mode=0, cols=80, rows=30, font_h16=True, border=0,
                 cur_en=False, cur_col=0, cur_row=0, cur_start=14, cur_end=15,
                 uline_row=15, cur_div=15, txt_div=15, palette=None, blank=False):
        self.name = name
        self.mode = mode
        self.cols = cols
        self.rows = rows
        self.font_h16 = font_h16
        self.border = border
        self.cur_en = cur_en
        self.cur_col = cur_col
        self.cur_row = cur_row
        self.cur_start = cur_start
        self.cur_end = cur_end
        self.uline_row = uline_row
        self.cur_div = cur_div
        self.txt_div = txt_div
        self.blank = blank
        self.palette = list(palette) if palette else list(PAL_DEFAULT)
        self.grid = [[cell(0x20, 7, 0) for _ in range(cols)] for _ in range(rows)]

    # -- content helpers ---------------------------------------------------
    def put(self, row, col, word):
        if 0 <= row < self.rows and 0 <= col < self.cols:
            self.grid[row][col] = word

    def text(self, row, col, s, fg=7, bg=0, **kw):
        for i, ch in enumerate(s):
            self.put(row, col + i, cell(ord(ch), fg, bg, **kw))

    def fill(self, row, col, count, word):
        for i in range(count):
            self.put(row, col + i, word)

    def box(self, row, col, w, h, fg=7, bg=0):
        self.put(row, col, cell(G_TL, fg, bg))
        self.put(row, col + w - 1, cell(G_TR, fg, bg))
        self.put(row + h - 1, col, cell(G_BL, fg, bg))
        self.put(row + h - 1, col + w - 1, cell(G_BR, fg, bg))
        for i in range(1, w - 1):
            self.put(row, col + i, cell(G_HLINE, fg, bg))
            self.put(row + h - 1, col + i, cell(G_HLINE, fg, bg))
        for j in range(1, h - 1):
            self.put(row + j, col, cell(G_VLINE, fg, bg))
            self.put(row + j, col + w - 1, cell(G_VLINE, fg, bg))

    # -- emitters ----------------------------------------------------------
    def ctrl_word(self):
        v = 1  # EN
        if self.font_h16:
            v |= 1 << 1
        if self.blank:
            v |= 1 << 2
        v |= (self.mode & 0xF) << 4
        v |= (self.border & 0xF) << 8
        return v

    def reg_writes(self):
        w = [
            (REG_GEOM, (self.rows << 16) | self.cols),
            (REG_BASE, 0x0000_0000),
            (REG_CURSOR, ((1 << 31) if self.cur_en else 0) | (self.cur_row << 16) | self.cur_col),
            (REG_CURSHAPE, (self.uline_row << 16) | (self.cur_end << 8) | self.cur_start),
            (REG_BLINK, (self.txt_div << 16) | self.cur_div),
        ]
        for i, v in enumerate(self.palette):
            if v != PAL_DEFAULT[i]:
                w.append((REG_PAL + 4 * i, v))
        w.append((REG_CTRL, self.ctrl_word()))
        return w

    def mem_words(self):
        out = []
        for r in range(self.rows):
            out.extend(self.grid[r])
        return out

    def dims(self):
        m = modes.BY_INDEX[self.mode]
        return m["h_active"], m["v_active"]

    def write(self, outdir):
        outdir = pathlib.Path(outdir)
        outdir.mkdir(parents=True, exist_ok=True)
        regs = outdir / f"{self.name}.regs"
        mem = outdir / f"{self.name}.mem"
        regs.write_text("".join(f"{a:08x} {v:08x}\n" for a, v in self.reg_writes()))
        mem.write_text("".join(f"{v:08x}\n" for v in self.mem_words()))
        return regs, mem


# ---------------------------------------------------------------------------
# Scene catalogue
# ---------------------------------------------------------------------------

def scene_demo():
    s = Scene("demo", mode=0, cols=80, rows=30, font_h16=True, border=1,
              cur_en=True, cur_col=13, cur_row=26, cur_div=15, txt_div=15)
    s.box(0, 0, 80, 30, fg=11)
    s.text(0, 3, " vga_text_engine ", fg=15, bg=1)
    s.text(2, 3, "Colour VGA text mode display controller", fg=14)
    s.text(3, 3, "640x480 at 60 Hz, 80 by 30 cells, 8x16 glyphs", fg=7)

    s.text(5, 3, "PALETTE", fg=15, uline=True)
    names = ["black", "blue", "green", "cyan", "red", "magenta", "brown", "lt grey",
             "dk grey", "lt blue", "lt green", "lt cyan", "lt red", "lt mag", "yellow", "white"]
    for i in range(16):
        row = 6 + i % 8
        col = 3 + (i // 8) * 26
        s.fill(row, col, 3, cell(G_BLOCK, i, 0))
        s.text(row, col + 4, f"{i:2d} {names[i]}", fg=i if i else 8)

    s.text(15, 3, "ATTRIBUTES", fg=15, uline=True)
    s.text(16, 3, "normal", fg=7)
    s.text(16, 14, "reverse", fg=14, bg=0, rev=True)
    s.text(16, 26, "underline", fg=10, uline=True)
    s.text(16, 40, "blinking", fg=12, blink=True)
    s.text(16, 54, "rev+uline", fg=11, rev=True, uline=True)

    s.text(18, 3, "COLOUR PAIRS", fg=15, uline=True)
    for i in range(8):
        s.text(19 + i // 4, 3 + (i % 4) * 18, f" fg{i + 8:02d} on bg{i:02d} ", fg=i + 8, bg=i)

    s.text(22, 3, "SHADES", fg=15, uline=True)
    for i, g in enumerate([G_SHADE_LIGHT, G_SHADE_MED, G_SHADE_DARK, G_BLOCK]):
        s.fill(23, 3 + i * 8, 6, cell(g, 11, 1))
    s.fill(23, 40, 6, cell(G_HALF_LEFT, 14, 4))
    s.fill(23, 50, 6, cell(G_HALF_LOW, 10, 2))

    s.text(26, 3, "vte> _", fg=15)
    s.text(28, 3, "Apache-2.0  Daniel Tyukov 2026", fg=8)
    return s


def scene_palette():
    """Every foreground index against every background index."""
    s = Scene("palette", mode=0, cols=80, rows=30, font_h16=True, border=8)
    s.text(0, 20, "16 x 16 FOREGROUND / BACKGROUND MATRIX", fg=15)
    s.text(2, 6, "bg:", fg=7)
    for bg in range(16):
        s.text(2, 10 + bg * 4, f"{bg:2d}", fg=7)
    for fg in range(16):
        row = 4 + fg
        s.text(row, 2, f"fg{fg:2d}", fg=fg if fg else 8)
        for bg in range(16):
            s.text(row, 10 + bg * 4, "Ab", fg=fg, bg=bg)
    s.text(21, 2, "PROGRAMMED RAMP (palette rewritten below index 8 is untouched)", fg=15)
    for i in range(16):
        s.fill(23, 2 + i * 4, 4, cell(G_BLOCK, i, 0))
    for i in range(16):
        s.fill(25, 2 + i * 4, 4, cell(G_SHADE_MED, i, 15 - i))
    return s


def scene_attr():
    """Attribute showcase with the blink phase held on."""
    s = Scene("attr", mode=0, cols=80, rows=30, font_h16=True, border=0,
              cur_en=True, cur_col=40, cur_row=20, cur_start=0, cur_end=15,
              uline_row=13, cur_div=0, txt_div=0)
    s.text(1, 2, "ATTRIBUTE DECODE", fg=15, uline=True)
    rows = [
        ("plain", dict(fg=7)),
        ("bright white on blue", dict(fg=15, bg=1)),
        ("reverse video", dict(fg=14, bg=4, rev=True)),
        ("underline at row 13", dict(fg=10, uline=True)),
        ("underline plus reverse", dict(fg=11, bg=2, rev=True, uline=True)),
        ("blink attribute set", dict(fg=12, blink=True)),
        ("blink plus underline", dict(fg=13, blink=True, uline=True)),
        ("blink plus reverse", dict(fg=9, bg=6, blink=True, rev=True)),
    ]
    for i, (label, kw) in enumerate(rows):
        s.text(3 + i * 2, 4, f"{label:<26s}", **kw)
        s.text(3 + i * 2, 34, "ABCDEFGabcdefg 0123456789", **kw)

    s.text(19, 2, "BLOCK CURSOR, FULL CELL HEIGHT, ROW 20 COLUMN 40", fg=15, uline=True)
    s.text(20, 34, "cursor here ->", fg=7)
    s.text(20, 41, " <- and the cell to its right", fg=7)
    s.text(24, 2, "OUT OF RANGE GLYPH CODES RENDER BLANK", fg=15, uline=True)
    for i in range(16):
        s.put(25, 4 + i, cell(0x80 + i, 14, 4))
    s.text(25, 24, "^ codes 0x80..0x8F on a red background", fg=7)
    return s


def _font_sample(s):
    s.text(0, 1, "GLYPH SET", fg=15, uline=True)
    for block in range(6):
        base = 0x20 + block * 16
        s.text(2 + block, 1, f"{base:02X}", fg=8)
        for i in range(16):
            s.put(2 + block, 5 + i * 2, cell(base + i, 14))
    s.text(9, 1, "The quick brown fox jumps over the lazy dog.", fg=15)
    s.text(10, 1, "THE QUICK BROWN FOX JUMPS OVER THE LAZY DOG.", fg=11)
    s.text(11, 1, "0123456789 !\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~", fg=10)
    s.text(12, 1, "gjpqy descenders, bdfhklt ascenders, xzvw", fg=14)
    s.text(14, 1, "int main(void) { return 0; }  /* code sample */", fg=12)
    s.text(15, 1, "0x1F | (mask << 3) & ~flag  ==  result;", fg=13)
    for i, g in enumerate([G_SHADE_LIGHT, G_SHADE_MED, G_SHADE_DARK, G_BLOCK,
                           G_HALF_LEFT, G_HALF_LOW, G_BULLET]):
        s.fill(17, 1 + i * 6, 5, cell(g, 11, 1))
    s.box(19, 1, 40, 5, fg=9)
    s.text(20, 3, "box drawing joins in either height", fg=15)
    s.text(21, 3, "cell grid is unchanged, only the", fg=7)
    s.text(22, 3, "glyph height and row count differ", fg=7)
    return s


def scene_font16():
    s = Scene("font16", mode=0, cols=80, rows=30, font_h16=True, border=0, uline_row=13)
    _font_sample(s)
    s.text(24, 1, "CTRL.FONT_H16 = 1   8x16 glyphs   80 x 30 cells", fg=15, bg=1)
    return s


def scene_font8():
    s = Scene("font8", mode=0, cols=80, rows=60, font_h16=False, border=0, uline_row=6)
    _font_sample(s)
    s.text(24, 1, "CTRL.FONT_H16 = 0   8x8 glyphs   80 x 60 cells", fg=15, bg=1)
    s.text(26, 1, "The same 640x480 timing now carries twice the rows.", fg=14)
    for r in range(28, 60):
        s.text(r, 1, f"row {r:02d} " + "".join(chr(0x20 + ((r * 7 + c) % 95)) for c in range(60)),
               fg=1 + (r % 15))
    return s


def scene_cursor():
    """Short blink divider so a handful of consecutive frames show a full cycle."""
    s = Scene("cursor", mode=0, cols=80, rows=30, font_h16=True, border=1,
              cur_en=True, cur_col=22, cur_row=8, cur_start=0, cur_end=15,
              cur_div=1, txt_div=3, uline_row=15)
    s.box(2, 2, 60, 12, fg=11)
    s.text(2, 5, " hardware text cursor ", fg=15, bg=1)
    s.text(4, 4, "programmable position, scanline span and blink rate", fg=14)
    s.text(6, 4, "CURSOR.EN=1  ROW=8  COL=22", fg=7)
    s.text(7, 4, "CURSHAPE.START=0  END=15  BLINK.CUR_DIV=1", fg=7)
    s.text(8, 4, "vte> ls -la /dev/", fg=15)
    s.text(10, 4, "blinking attribute at TXT_DIV=3", fg=12, blink=True)
    s.text(11, 4, "steady attribute for comparison", fg=10)
    return s


def scene_1024():
    s = Scene("mode1024", mode=2, cols=128, rows=48, font_h16=True, border=4)
    s.box(0, 0, 128, 48, fg=14)
    s.text(0, 4, " 1024x768 at 60 Hz, 128 by 48 cells ", fg=15, bg=4)
    for r in range(2, 46):
        s.text(r, 2, f"{r:3d} " + "".join(chr(0x20 + ((r * 5 + c) % 95)) for c in range(120)),
               fg=1 + (r % 15))
    return s


SCENES = {
    "demo": scene_demo,
    "palette": scene_palette,
    "attr": scene_attr,
    "font16": scene_font16,
    "font8": scene_font8,
    "cursor": scene_cursor,
    "mode1024": scene_1024,
}


def build(name):
    return SCENES[name]()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-o", "--outdir", default="results/scenes")
    ap.add_argument("names", nargs="*", default=None)
    args = ap.parse_args()
    names = args.names if args.names else sorted(SCENES)
    for n in names:
        s = build(n)
        regs, mem = s.write(args.outdir)
        w, h = s.dims()
        print(f"{n}: {w}x{h} {s.cols}x{s.rows} cells -> {regs.name}, {mem.name}")


if __name__ == "__main__":
    main()
