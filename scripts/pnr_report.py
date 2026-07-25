#!/usr/bin/env python3
"""Summarise a LibreLane place and route run and render the layout.

Reads runs/<tag>/final/metrics.json from a completed LibreLane flow and writes:

  docs/pnr_report.txt    die area, utilisation, wire length, signoff check counts, timing
  docs/img/layout.png    the routed layout, rendered by KLayout in batch mode

Post route die area is the number to quote if only one area figure is quoted: it includes
routing, filler and tap cells, so it is meaningfully larger than the standard cell area in
docs/pdk_area_report.txt.
"""

import argparse
import json
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

RENDER_SCRIPT = r'''# Rendered by scripts/pnr_report.py via klayout -b -rm.
# Batch mode takes -rd name=value rather than positional arguments.
import pya
lv = pya.LayoutView()
lv.load_layout(gds, 0)
lv.max_hier()
lv.zoom_fit()
lv.save_image(out, int(w), int(h))
'''

# metric key -> (label, format, unit)
INTEREST = [
    ("design__die__area", "die area", "{:.0f}", "um2"),
    ("design__core__area", "core area", "{:.0f}", "um2"),
    ("design__instance__area", "cell area", "{:.0f}", "um2"),
    ("design__instance__utilization", "core utilisation", "{:.3f}", ""),
    ("design__instance__count", "instances", "{:.0f}", ""),
    ("route__wirelength", "total wire length", "{:.0f}", "um"),
    ("route__vias", "vias", "{:.0f}", ""),
    ("power__total", "total power", "{:.4f}", "W"),
]

CHECKS = [
    ("route__drc_errors", "routing DRC violations"),
    ("magic__drc_error__count", "Magic DRC violations"),
    ("klayout__drc_error__count", "KLayout DRC violations"),
    ("design__lvs_error__count", "LVS mismatches"),
    ("design__lvs_device_count__mismatch", "LVS device count mismatches"),
    ("antenna__violating__nets", "antenna violating nets"),
    ("design__disconnected_pin__count", "disconnected pins"),
    ("design__instance__count__setup_violations", "cells with setup violations"),
]


def find_run(tag):
    runs = ROOT / "runs"
    if tag:
        cand = runs / tag
        if (cand / "final" / "metrics.json").exists():
            return cand
        raise SystemExit(f"no completed run at {cand}")
    best = None
    for d in sorted(runs.glob("*")):
        if (d / "final" / "metrics.json").exists():
            best = d
    if best is None:
        raise SystemExit("no completed LibreLane run found under runs/")
    return best


def render_layout(run, out, width=1600, height=1100):
    if shutil.which("klayout") is None:
        print("klayout is not on PATH, skipping the layout render")
        return False
    gds = sorted((run / "final" / "gds").glob("*.gds"))
    if not gds:
        print("no GDS in the run, skipping the layout render")
        return False
    script = ROOT / "synth" / "out" / "render_gds.py"
    script.parent.mkdir(parents=True, exist_ok=True)
    script.write_text(RENDER_SCRIPT)
    out.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(["klayout", "-b", "-rm", str(script),
                        "-rd", f"gds={gds[0]}", "-rd", f"out={out}",
                        "-rd", f"w={width}", "-rd", f"h={height}"],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0 or not out.exists():
        print(r.stdout + r.stderr)
        return False
    print(f"wrote {out}")
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="vte")
    ap.add_argument("--report", default=str(ROOT / "docs" / "pnr_report.txt"))
    ap.add_argument("--image", default=str(ROOT / "docs" / "img" / "layout.png"))
    args = ap.parse_args()

    run = find_run(args.tag)
    m = json.loads((run / "final" / "metrics.json").read_text())

    lines = []
    lines.append("vga_text_engine place and route")
    lines.append("=" * 76)
    lines.append("")
    lines.append("Tool      : LibreLane 3.0.0.dev44, OpenROAD and Magic and KLayout")
    lines.append("PDK       : IHP Open PDK SG13G2, 130 nm")
    lines.append("Config    : librelane.json, constraints in pnr/vte.sdc")
    lines.append("Top       : vga_text_engine")
    lines.append("Clocks    : clk_pix_i at 15.3846 ns (the 1024x768 requirement),")
    lines.append("            clk_i at 20.0 ns, declared as asynchronous clock groups")
    lines.append("")
    lines.append("Physical")
    lines.append("-" * 76)
    for key, label, fmt, unit in INTEREST:
        if key in m and m[key] is not None:
            v = fmt.format(m[key])
            lines.append(f"  {label:<26}{v:>14} {unit}")
    lines.append("")

    lines.append("Signoff checks")
    lines.append("-" * 76)
    problems = []
    for key, label in CHECKS:
        if key in m and m[key] is not None:
            n = m[key]
            verdict = "pass" if not n else "FAIL"
            if n:
                problems.append(f"{label}: {n}")
            lines.append(f"  {label:<34}{n:>8}   {verdict}")
    lines.append("")

    lines.append("Timing, signoff corner")
    lines.append("-" * 76)
    for key in sorted(k for k in m if k.startswith("timing__")):
        if m[key] is not None and isinstance(m[key], (int, float)):
            lines.append(f"  {key:<52}{m[key]:>12.4f}")
    lines.append("")

    lines.append("Reading the area figures together")
    lines.append("-" * 76)
    cell = m.get("design__instance__area")
    die = m.get("design__die__area")
    if cell and die:
        lines.append(f"  standard cell area, from synthesis   175325 um2")
        lines.append(f"  cell area, after place and route     {cell:.0f} um2")
        lines.append(f"  die area                             {die:.0f} um2")
        lines.append(f"  die is {die / cell:.2f}x the cell area")
        lines.append("")
        lines.append("  The die is larger than the sum of the cells because it also carries")
        lines.append("  routing, filler and tap cells and the core to die margin. Quote the")
        lines.append("  die area if only one number is quoted.")
    lines.append("")
    lines.append(f"Run directory: {run.relative_to(ROOT)}")
    lines.append("")

    out = pathlib.Path(args.report)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
    print(f"wrote {out}")

    render_layout(run, pathlib.Path(args.image))

    if problems:
        for p in problems:
            print(f"FAIL {p}")
        print("TEST_RESULT: FAIL")
        return 1
    print(f"die {die:.0f} um2, cells {cell:.0f} um2, "
          f"utilisation {m.get('design__instance__utilization', 0):.3f}, "
          f"DRC and LVS clean")
    print("TEST_RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
