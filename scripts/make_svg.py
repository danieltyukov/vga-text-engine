#!/usr/bin/env python3
"""Emit the two hand written SVG diagrams in docs/img.

The markup below is authored by hand; the only thing the script computes is the
geometry of the timing diagram, which is derived from scripts/modes.py so the labelled
counts can never drift away from the numbers the hardware is tested against.

  docs/img/block_diagram.svg    architecture, datapath against control, both bus ports,
                                the elastic buffer and the two clock domains
  docs/img/timing_diagram.svg   one horizontal line of 640x480 with the porch regions,
                                hsync, data enable and the RGB window labelled
"""

import argparse
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import modes  # noqa: E402

BG = "#f8fafc"
INK = "#111827"
MUTED = "#4b5563"
GRID = "#cbd5e1"

DATA_FILL, DATA_LINE = "#dbeafe", "#1d4ed8"
CTRL_FILL, CTRL_LINE = "#fef3c7", "#b45309"
PIN_FILL, PIN_LINE = "#e5e7eb", "#6b7280"

FONT = "ui-monospace, 'DejaVu Sans Mono', Menlo, Consolas, monospace"
SANS = "ui-sans-serif, 'DejaVu Sans', Helvetica, Arial, sans-serif"


def esc(s):
    return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


def text(x, y, s, size=13, fill=INK, family=SANS, anchor="start", weight="normal",
         style="normal"):
    return (f'<text x="{x}" y="{y}" font-family="{family}" font-size="{size}" fill="{fill}" '
            f'text-anchor="{anchor}" font-weight="{weight}" font-style="{style}">{esc(s)}</text>')


def box(x, y, w, h, title, lines, fill, line, straddle=False):
    out = []
    if straddle:
        out.append(f'<rect x="{x - 5}" y="{y - 5}" width="{w + 10}" height="{h + 10}" rx="8" '
                   f'fill="none" stroke="{line}" stroke-width="1.6" stroke-dasharray="7 4"/>')
    out.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="6" fill="{fill}" '
               f'stroke="{line}" stroke-width="2"/>')
    out.append(text(x + w / 2, y + 25, title, size=15, family=FONT, anchor="middle",
                    weight="bold"))
    for i, ln in enumerate(lines):
        out.append(text(x + w / 2, y + 46 + i * 17, ln, size=12, fill=MUTED, anchor="middle"))
    return "\n  ".join(out)


def arrow(pts, label=None, lx=0, ly=0, dashed=False, color=INK, both=False, size=11):
    d = "M" + " L".join(f"{x},{y}" for x, y in pts)
    dash = ' stroke-dasharray="6 4"' if dashed else ""
    head = ' marker-end="url(#ah)"'
    if both:
        head += ' marker-start="url(#ahs)"'
    out = [f'<path d="{d}" fill="none" stroke="{color}" stroke-width="1.8"{dash}{head}/>']
    if label:
        out.append(text(lx, ly, label, size=size, fill=MUTED, family=FONT))
    return "\n  ".join(out)


# ---------------------------------------------------------------------------
# Block diagram
# ---------------------------------------------------------------------------

def block_diagram():
    W, H = 1180, 720
    SPLIT = 620
    p = []
    p.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" '
             f'height="{H}" role="img" aria-label="vga_text_engine block diagram">')
    p.append('<defs>')
    p.append('<marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
             f'markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="{INK}"/></marker>')
    p.append('<marker id="ahs" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" '
             f'markerHeight="7" orient="auto"><path d="M10,0 L0,5 L10,10 z" fill="{INK}"/></marker>')
    p.append('</defs>')
    p.append(f'<rect width="{W}" height="{H}" fill="{BG}"/>')

    p.append(text(28, 40, "vga_text_engine", size=22, family=FONT, weight="bold"))
    p.append(text(232, 40, "colour VGA text mode display controller", size=15, fill=MUTED))

    # Clock domain boundary.
    p.append(f'<line x1="{SPLIT}" y1="62" x2="{SPLIT}" y2="598" stroke="{GRID}" '
             f'stroke-width="2.5" stroke-dasharray="10 7"/>')
    p.append(text(SPLIT - 14, 78, "clk_i / rst_ni", size=13, family=FONT, anchor="end",
                  weight="bold"))
    p.append(text(SPLIT - 14, 95, "register and fetch domain", size=12, fill=MUTED, anchor="end"))
    p.append(text(SPLIT + 14, 78, "clk_pix_i / rst_pix_ni", size=13, family=FONT, weight="bold"))
    p.append(text(SPLIT + 14, 95, "pixel domain, one pixel per clock", size=12, fill=MUTED))

    # Bus ports.
    p.append(f'<rect x="24" y="128" width="118" height="52" rx="6" fill="{PIN_FILL}" '
             f'stroke="{PIN_LINE}" stroke-width="2"/>')
    p.append(text(83, 150, "AXI4-Lite", size=13, family=FONT, anchor="middle", weight="bold"))
    p.append(text(83, 167, "subordinate", size=11, fill=MUTED, anchor="middle"))

    p.append(f'<rect x="24" y="330" width="118" height="52" rx="6" fill="{PIN_FILL}" '
             f'stroke="{PIN_LINE}" stroke-width="2"/>')
    p.append(text(83, 352, "fetch port", size=13, family=FONT, anchor="middle", weight="bold"))
    p.append(text(83, 369, "read only", size=11, fill=MUTED, anchor="middle"))

    # Modules.
    p.append(box(170, 118, 220, 86, "vte_axil_regs",
                 ["register file 0x00..0x7C", "16 entry RGB444 palette"],
                 CTRL_FILL, CTRL_LINE))
    p.append(box(170, 318, 220, 86, "vte_fetch_engine",
                 ["one address per cell,", "row then scanline then column"],
                 CTRL_FILL, CTRL_LINE))
    p.append(box(510, 128, 220, 176, "vte_frame_sync",
                 ["four phase handshake", "in vertical blanking:", "atomic cfg snapshot,",
                  "status readback,", "buffer realignment"],
                 CTRL_FILL, CTRL_LINE, straddle=True))
    p.append(box(510, 380, 220, 96, "vte_cdc_fifo",
                 ["elastic buffer, 32 x 19 b", "gray pointers, show ahead"],
                 DATA_FILL, DATA_LINE, straddle=True))
    p.append(box(830, 118, 220, 86, "vte_timing_gen",
                 ["sync, data enable,", "prefetch and display phase"],
                 CTRL_FILL, CTRL_LINE))
    p.append(box(830, 318, 220, 110, "vte_shader",
                 ["attribute decode,", "cursor overlay, palette,", "RGB444 to DAC width"],
                 DATA_FILL, DATA_LINE))
    p.append(box(830, 500, 220, 76, "vte_glyph_rom",
                 ["dual bank 8x16 and 8x8", "3072 x 8, one clock read"],
                 DATA_FILL, DATA_LINE))

    # Output pins.
    p.append(f'<rect x="1096" y="318" width="60" height="110" rx="6" fill="{PIN_FILL}" '
             f'stroke="{PIN_LINE}" stroke-width="2"/>')
    p.append(text(1126, 344, "VGA", size=13, family=FONT, anchor="middle", weight="bold"))
    p.append(text(1126, 362, "hsync", size=11, fill=MUTED, anchor="middle"))
    p.append(text(1126, 378, "vsync", size=11, fill=MUTED, anchor="middle"))
    p.append(text(1126, 394, "de", size=11, fill=MUTED, anchor="middle"))
    p.append(text(1126, 412, "R G B", size=11, fill=MUTED, anchor="middle"))

    # Wiring.
    p.append(arrow([(142, 154), (170, 154)]))
    p.append(arrow([(170, 356), (142, 356)], both=True))
    p.append(arrow([(1050, 373), (1096, 373)]))

    p.append(arrow([(390, 148), (510, 148)], "cfg 295 b", 404, 141))
    p.append(arrow([(510, 186), (390, 186)], "sts, events", 404, 202))
    p.append(arrow([(510, 268), (330, 268), (330, 318)], "cfg snapshot, run", 336, 260))
    p.append(arrow([(390, 356), (450, 356), (450, 404), (510, 404)], "cell 19 b", 398, 348))
    p.append(arrow([(730, 404), (830, 404)], "head", 748, 396))
    p.append(arrow([(830, 428), (780, 428), (780, 452), (730, 452)], "pop", 786, 470))
    p.append(arrow([(730, 168), (780, 168), (780, 148), (830, 148)], "cfg_pix", 748, 138))
    p.append(arrow([(830, 188), (780, 188), (780, 236), (730, 236)], "frame_edge", 742, 228))
    p.append(arrow([(940, 204), (940, 318)], "position and phase", 952, 264))
    p.append(arrow([(900, 428), (900, 500)], "addr", 862, 468))
    p.append(arrow([(980, 500), (980, 428)], "row bits", 992, 468))

    # Legend.
    ly = 626
    p.append(f'<rect x="170" y="{ly}" width="26" height="16" rx="3" fill="{CTRL_FILL}" '
             f'stroke="{CTRL_LINE}" stroke-width="2"/>')
    p.append(text(204, ly + 13, "control", size=12))
    p.append(f'<rect x="288" y="{ly}" width="26" height="16" rx="3" fill="{DATA_FILL}" '
             f'stroke="{DATA_LINE}" stroke-width="2"/>')
    p.append(text(322, ly + 13, "datapath", size=12))
    p.append(f'<rect x="418" y="{ly - 4}" width="26" height="24" rx="4" fill="none" '
             f'stroke="{MUTED}" stroke-width="1.6" stroke-dasharray="7 4"/>')
    p.append(text(452, ly + 13, "straddles both clock domains", size=12))
    p.append(f'<line x1="700" y1="{ly + 8}" x2="740" y2="{ly + 8}" stroke="{GRID}" '
             f'stroke-width="2.5" stroke-dasharray="10 7"/>')
    p.append(text(750, ly + 13, "clock domain boundary", size=12))
    p.append(text(170, ly + 42, "Only gray coded FIFO pointers and single bit handshake "
                                "lines cross the boundary, all through vte_sync2.", size=12,
                  fill=MUTED))
    p.append(text(170, ly + 62, "Cell word: [7:0] CHAR  [11:8] FG  [15:12] BG  [16] BLINK  "
                                "[17] REV  [18] ULINE", size=12, family=FONT, fill=MUTED))
    p.append('</svg>')
    return "\n  ".join(p) + "\n"


# ---------------------------------------------------------------------------
# Timing diagram
# ---------------------------------------------------------------------------

def timing_diagram(mode_index=0):
    m = modes.BY_INDEX[mode_index]
    ht = modes.h_total(m)
    W, H = 1180, 524
    X0, X1 = 112, 1128
    sx = (X1 - X0) / ht

    def px(v):
        return X0 + v * sx

    # Region edges in the order the engine walks a line.
    e_sync = m["h_sync"]
    e_back = e_sync + m["h_back"]
    e_act = e_back + m["h_active"]
    e_tot = ht

    by, bh = 104, 26
    hi, lo = 158, 194        # hsync rails, smaller y is a logic high
    dhi, dlo = 250, 286      # data enable rails
    rtop, rbot = 338, 378    # rgb band
    guide_bot = 416

    p = []
    p.append(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" '
             f'height="{H}" role="img" aria-label="one horizontal line of timing">')
    p.append('<defs>')
    p.append('<marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
             f'markerHeight="7" orient="auto"><path d="M0,0 L10,5 L0,10 z" fill="#7c3aed"/></marker>')
    p.append('<linearGradient id="rgbband" x1="0" y1="0" x2="1" y2="0">')
    for i, c in enumerate(["#f87171", "#fbbf24", "#4ade80", "#38bdf8", "#a78bfa", "#f472b6"]):
        p.append(f'<stop offset="{i / 5:.2f}" stop-color="{c}"/>')
    p.append('</linearGradient>')
    p.append('</defs>')
    p.append(f'<rect width="{W}" height="{H}" fill="{BG}"/>')

    p.append(text(28, 38, "One horizontal line", size=21, family=FONT, weight="bold"))
    p.append(text(28, 62, f"{m['name']}, {m['pclk']} MHz pixel clock, h_total = {ht} pixel "
                          f"clocks = {ht / m['pclk']:.2f} us", size=14, fill=MUTED))
    p.append(text(28, 84, "The engine walks a line SYNC, BACK PORCH, ACTIVE, FRONT PORCH, so "
                          "the whole blanking gap before active video is one contiguous run.",
                  size=12.5, fill=MUTED))

    bands = [(0, e_sync, "SYNC", m["h_sync"], "#fecaca", "#b91c1c"),
             (e_sync, e_back, "BACK PORCH", m["h_back"], "#fde68a", "#a16207"),
             (e_back, e_act, "ACTIVE", m["h_active"], "#bbf7d0", "#15803d"),
             (e_act, e_tot, "FRONT PORCH", m["h_front"], "#fde68a", "#a16207")]
    for a, b, name, n, fill, stroke in bands:
        p.append(f'<rect x="{px(a):.1f}" y="{by}" width="{px(b) - px(a):.1f}" height="{bh}" '
                 f'fill="{fill}" stroke="{stroke}" stroke-width="1.4"/>')
        mid = (px(a) + px(b)) / 2
        if px(b) - px(a) > 76:
            p.append(text(mid, by + 18, f"{name}  {n}", size=12, family=FONT, anchor="middle",
                          fill=stroke, weight="bold"))
        else:
            anchor = "end" if a >= e_act else "middle"
            p.append(text(px(b) if anchor == "end" else mid, by - 7, f"{name} {n}", size=11,
                          family=FONT, anchor=anchor, fill=stroke, weight="bold"))

    # Vertical guides and a staggered tick label at every region edge.
    prev_x = -1e9
    for v in (0, e_sync, e_back, e_act, e_tot):
        x = px(v)
        p.append(f'<line x1="{x:.1f}" y1="{by}" x2="{x:.1f}" y2="{guide_bot}" stroke="{GRID}" '
                 f'stroke-width="1.2" stroke-dasharray="4 4"/>')
        ty = 452 if (x - prev_x) < 40 else 434
        p.append(text(x, ty, str(v), size=11.5, family=FONT, anchor="middle", fill=MUTED))
        prev_x = x
    p.append(text((X0 + X1) / 2, 476, "position within the line, in pixel clocks", size=12,
                  fill=MUTED, anchor="middle"))

    # hsync. A negative sync sits low during the pulse and high everywhere else.
    pulse_y, idle_y = (lo, hi) if m["h_pos"] == 0 else (hi, lo)
    p.append(f'<path d="M{X0},{pulse_y} L{px(e_sync):.1f},{pulse_y} L{px(e_sync):.1f},{idle_y} '
             f'L{X1},{idle_y}" fill="none" stroke="{DATA_LINE}" stroke-width="2.6"/>')
    p.append(text(X0 - 16, hi + 22, "hsync", size=13, family=FONT, anchor="end", weight="bold"))
    p.append(text(X0 - 16, hi + 40, "active low" if m["h_pos"] == 0 else "active high", size=11,
                  fill=MUTED, anchor="end"))

    # data enable.
    p.append(f'<path d="M{X0},{dlo} L{px(e_back):.1f},{dlo} L{px(e_back):.1f},{dhi} '
             f'L{px(e_act):.1f},{dhi} L{px(e_act):.1f},{dlo} L{X1},{dlo}" fill="none" '
             f'stroke="{DATA_LINE}" stroke-width="2.6"/>')
    p.append(text(X0 - 16, dhi + 22, "de", size=13, family=FONT, anchor="end", weight="bold"))
    p.append(text(X0 - 16, dhi + 40, "active high", size=11, fill=MUTED, anchor="end"))

    # rgb band: forced black outside active video, palette colour inside.
    p.append(f'<rect x="{X0}" y="{rtop}" width="{px(e_back) - X0:.1f}" height="{rbot - rtop}" '
             f'fill="#1f2937" stroke="{MUTED}" stroke-width="1.2"/>')
    p.append(f'<rect x="{px(e_back):.1f}" y="{rtop}" width="{px(e_act) - px(e_back):.1f}" '
             f'height="{rbot - rtop}" fill="url(#rgbband)" stroke="{MUTED}" stroke-width="1.2"/>')
    p.append(f'<rect x="{px(e_act):.1f}" y="{rtop}" width="{X1 - px(e_act):.1f}" '
             f'height="{rbot - rtop}" fill="#1f2937" stroke="{MUTED}" stroke-width="1.2"/>')
    p.append(text(X0 - 16, rtop + 20, "R G B", size=13, family=FONT, anchor="end", weight="bold"))
    p.append(text(X0 - 16, rtop + 38, "black when !de", size=11, fill=MUTED, anchor="end"))
    p.append(text((px(e_back) + px(e_act)) / 2, rtop + 26,
                  f"{m['h_active']} pixels, one palette lookup each", size=12, family=FONT,
                  anchor="middle", fill="#111827"))

    # The 8 pixel character prefetch window, entirely inside the back porch.
    pre_a = e_back - 8
    p.append(f'<rect x="{px(pre_a):.1f}" y="{by - 3}" '
             f'width="{max(px(e_back) - px(pre_a), 3):.1f}" height="{rbot - by + 8}" '
             f'fill="#7c3aed" fill-opacity="0.20" stroke="#7c3aed" stroke-width="1.4"/>')
    p.append(arrow([(px(pre_a) + 96, 500), (px(pre_a) + 22, 500), (px(pre_a) + 3, rbot + 12)],
                   None, color="#7c3aed"))
    p.append(text(px(pre_a) + 106, 504, "8 pixel character prefetch window: the pipeline pulls "
                  "one cell out of the elastic buffer and turns it into a glyph row here",
                  size=12, fill="#6d28d9"))

    p.append('</svg>')
    return "\n  ".join(p) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=str(ROOT / "docs" / "img"))
    args = ap.parse_args()
    out = pathlib.Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    (out / "block_diagram.svg").write_text(block_diagram())
    print(f"wrote {out / 'block_diagram.svg'}")
    (out / "timing_diagram.svg").write_text(timing_diagram(0))
    print(f"wrote {out / 'timing_diagram.svg'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
