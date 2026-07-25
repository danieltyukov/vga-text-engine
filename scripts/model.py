"""Independent Python reference renderer for vga_text_engine.

This is a second implementation of the display path, written from the register map and
the documented attribute resolution order rather than from the RTL. It shares only the
glyph bitmaps (scripts/font_data.py) and the stimulus files with the hardware, so a
disagreement points at one of the two renderers and not at the scene description.

Rendering rules, in order, matching the header comment of rtl/vte_shader.sv:

  1. pixel = glyph bitmap bit, most significant bit is the leftmost pixel
  2. ULINE  forces the pixel on when row_in_glyph == CURSHAPE.ULINE_ROW
  3. BLINK  forces the pixel off during the off phase of the TXT_DIV divider
  4. REV    swaps the foreground and background palette indices
  5. cursor inverts the pixel inside CURSHAPE.START .. CURSHAPE.END
  6. index  = pixel ? foreground : background
  7. inside active video but outside the text grid: CTRL.BORDER
  8. RGB444 entry expanded to 8 bits per channel by nibble replication

The grid is clamped to the active area: cols_eff = min(COLS, h_active/8) and
rows_eff = min(ROWS, v_active/glyph_h). The cell buffer row stride stays at the
programmed COLS regardless of the clamp.
"""

import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import font_data  # noqa: E402
import modes  # noqa: E402
import scenes  # noqa: E402


def parse_regs(path):
    """Replay a register script and return the resulting register state."""
    state = {}
    for line in pathlib.Path(path).read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        a, v = line.split()
        state[int(a, 16)] = int(v, 16)
    return state


def parse_mem(path):
    return [int(t, 16) for t in pathlib.Path(path).read_text().split()]


class Config:
    """Decoded register state, as the pixel domain sees it after the frame snapshot."""

    def __init__(self, regs):
        ctrl = regs.get(scenes.REG_CTRL, 0)
        self.en = bool(ctrl & 1)
        self.font_h16 = bool((ctrl >> 1) & 1)
        self.blank = bool((ctrl >> 2) & 1)
        self.mode = (ctrl >> 4) & 0xF
        self.border = (ctrl >> 8) & 0xF

        geom = regs.get(scenes.REG_GEOM, (30 << 16) | 80)
        self.cols = geom & 0xFF
        self.rows = (geom >> 16) & 0xFF

        cur = regs.get(scenes.REG_CURSOR, 0)
        self.cur_col = cur & 0xFF
        self.cur_row = (cur >> 16) & 0xFF
        self.cur_en = bool((cur >> 31) & 1)

        shp = regs.get(scenes.REG_CURSHAPE, (15 << 16) | (15 << 8) | 14)
        self.cur_start = shp & 0xF
        self.cur_end = (shp >> 8) & 0xF
        self.uline_row = (shp >> 16) & 0xF

        blk = regs.get(scenes.REG_BLINK, (15 << 16) | 15)
        self.cur_div = blk & 0xFF
        self.txt_div = (blk >> 16) & 0xFF

        self.base = regs.get(scenes.REG_BASE, 0)

        self.palette = list(scenes.PAL_DEFAULT)
        for i in range(16):
            off = scenes.REG_PAL + 4 * i
            if off in regs:
                self.palette[i] = regs[off] & 0xFFF

        m = modes.BY_INDEX.get(self.mode, modes.BY_INDEX[0])
        self.h_active = m["h_active"]
        self.v_active = m["v_active"]
        self.glyph_h = 16 if self.font_h16 else 8
        self.cols_eff = min(self.cols, self.h_active // 8)
        self.rows_eff = min(self.rows, self.v_active // self.glyph_h)

    def phase(self, div, frame_idx):
        """Blink phase for a frame. Both phases start in the visible state."""
        return (frame_idx // (div + 1)) % 2 == 0


def expand444(value):
    """RGB444 to three 8 bit channels by nibble replication."""
    r = (value >> 8) & 0xF
    g = (value >> 4) & 0xF
    b = value & 0xF
    return r * 17, g * 17, b * 17


def render(regs, mem, frame_idx):
    """Render one frame. Returns a (v_active, h_active, 3) uint8 array."""
    cfg = Config(regs)
    h, v = cfg.h_active, cfg.v_active
    out = np.zeros((v, h, 3), dtype=np.uint8)

    if cfg.blank or not cfg.en:
        return out

    rgb = np.array([expand444(p) for p in cfg.palette], dtype=np.uint8)
    border_rgb = rgb[cfg.border]
    out[:, :] = border_rgb

    cur_phase = cfg.phase(cfg.cur_div, frame_idx)
    txt_phase = cfg.phase(cfg.txt_div, frame_idx)

    text_w = cfg.cols_eff * 8
    text_h = cfg.rows_eff * cfg.glyph_h

    # Glyph row cache keyed by (code, row): the bitmap only depends on the font bank.
    height = cfg.glyph_h
    bank = font_data.bank(height)

    for text_row in range(cfg.rows_eff):
        for row_in_glyph in range(height):
            y = text_row * height + row_in_glyph
            if y >= text_h:
                break
            line = out[y]
            for col in range(cfg.cols_eff):
                word = mem[text_row * cfg.cols + col] if (text_row * cfg.cols + col) < len(mem) else 0
                ch = word & 0xFF
                fg = (word >> 8) & 0xF
                bg = (word >> 12) & 0xF
                blink = (word >> 16) & 1
                rev = (word >> 17) & 1
                uline = (word >> 18) & 1

                bits = 0 if ch >= font_data.GLYPH_COUNT else bank[ch][row_in_glyph]

                if uline and row_in_glyph == cfg.uline_row:
                    bits = 0xFF
                if blink and not txt_phase:
                    bits = 0x00

                fg_i, bg_i = (bg, fg) if rev else (fg, bg)

                cursor = (cfg.cur_en and col == cfg.cur_col and text_row == cfg.cur_row
                          and cfg.cur_start <= row_in_glyph <= cfg.cur_end)
                if cursor and cur_phase:
                    bits ^= 0xFF

                x0 = col * 8
                if bits == 0x00:
                    line[x0:x0 + 8] = rgb[bg_i]
                elif bits == 0xFF:
                    line[x0:x0 + 8] = rgb[fg_i]
                else:
                    for p in range(8):
                        on = (bits >> (7 - p)) & 1
                        line[x0 + p] = rgb[fg_i] if on else rgb[bg_i]

    # Anything inside active video but outside the grid keeps the border colour.
    if text_w < h:
        out[:, text_w:] = border_rgb
    if text_h < v:
        out[text_h:, :] = border_rgb
    return out


def read_ppm(path):
    """Read a binary P6 PPM into a (h, w, 3) uint8 array."""
    data = pathlib.Path(path).read_bytes()
    if not data.startswith(b"P6"):
        raise ValueError(f"{path} is not a binary PPM")
    fields = []
    pos = 2
    while len(fields) < 3:
        while pos < len(data) and data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            while data[pos:pos + 1] not in (b"\n", b""):
                pos += 1
            continue
        start = pos
        while pos < len(data) and not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(int(data[start:pos]))
    pos += 1
    w, h, maxval = fields
    if maxval != 255:
        raise ValueError(f"{path} has maxval {maxval}, expected 255")
    px = np.frombuffer(data[pos:pos + w * h * 3], dtype=np.uint8)
    if px.size != w * h * 3:
        raise ValueError(f"{path} holds {px.size} bytes of pixel data, expected {w * h * 3}")
    return px.reshape((h, w, 3))


def write_ppm(path, arr):
    h, w, _ = arr.shape
    with open(path, "wb") as f:
        f.write(f"P6\n{w} {h}\n255\n".encode())
        f.write(arr.tobytes())
