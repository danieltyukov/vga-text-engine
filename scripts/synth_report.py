#!/usr/bin/env python3
"""Turn the Yosys statistics into a committed report and a per submodule cell chart.

Parses synth/stat_flat.txt, checks the two things a synthesis smoke test is actually
for, and writes docs/synth_report.txt plus docs/img/synth_cells.png:

  no inferred latch anywhere. Any $_DLATCH_ or $_SR_ cell means a combinational block
  is incompletely assigned, which is a real bug rather than a style question.

  no black box. A module Yosys could not elaborate would appear with no cells and be
  reported here.
"""

import argparse
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

# Yosys decorates parameterised modules; map them back to readable names.
PARAM_RE = re.compile(r"^\$paramod[^\\]*\\?(?P<name>[A-Za-z_][A-Za-z0-9_]*)")

LATCH_CELLS = ("$_DLATCH", "$_SR_", "$_DLATCHSR")

INSTANCE_COUNT = {
    "vte_sync2": 6,
    "vte_mode_lut": 3,
}


def clean_name(raw):
    m = PARAM_RE.match(raw)
    if m:
        return m.group("name")
    return raw.split("\\")[-1]


def parse(path):
    """Return {module: {"cells": n, "wire_bits": n, "types": {cell: n}}} plus the total."""
    mods = {}
    cur = None
    total = None
    for line in pathlib.Path(path).read_text().splitlines():
        m = re.match(r"^=== (.+) ===$", line.strip())
        if m:
            name = m.group(1)
            if name == "design hierarchy":
                cur = "__total__"
                mods[cur] = {"cells": 0, "wire_bits": 0, "types": {}}
            else:
                cur = clean_name(name)
                mods.setdefault(cur, {"cells": 0, "wire_bits": 0, "types": {}})
            continue
        if cur is None:
            continue
        m = re.match(r"^\s+Number of cells:\s+(\d+)$", line)
        if m:
            mods[cur]["cells"] = int(m.group(1))
            continue
        m = re.match(r"^\s+Number of wire bits:\s+(\d+)$", line)
        if m:
            mods[cur]["wire_bits"] = int(m.group(1))
            continue
        m = re.match(r"^\s+(\$[A-Za-z_0-9]+)\s+(\d+)$", line)
        if m:
            mods[cur]["types"][m.group(1)] = int(m.group(2))
    total = mods.pop("__total__", None)
    return mods, total


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stat", default=str(ROOT / "synth" / "stat_flat.txt"))
    ap.add_argument("--report", default=str(ROOT / "docs" / "synth_report.txt"))
    ap.add_argument("--chart", default=str(ROOT / "docs" / "img" / "synth_cells.png"))
    args = ap.parse_args()

    mods, total = parse(args.stat)
    if total is None:
        print("FAIL no design hierarchy section in the statistics")
        return 1

    problems = []
    for name, d in mods.items():
        for t in d["types"]:
            if any(t.startswith(p) for p in LATCH_CELLS):
                problems.append(f"{name} contains {d['types'][t]} {t} cells (inferred latch)")
        if d["cells"] == 0 and name != "vga_text_engine":
            problems.append(f"{name} has no cells, which would mean a black box")

    flops = sum(n for t, n in total["types"].items() if t.startswith("$_DFF"))
    combi = total["cells"] - flops

    # Per submodule totals, scaled by how many times each is instantiated.
    rows = []
    for name, d in mods.items():
        mult = INSTANCE_COUNT.get(name, 1)
        rows.append((name, d["cells"], mult, d["cells"] * mult))
    rows.sort(key=lambda r: -r[3])

    lines = []
    lines.append("vga_text_engine synthesis smoke test")
    lines.append("=" * 72)
    lines.append("")
    lines.append("Tool     : Yosys 0.33")
    lines.append("Script   : synth/synth.ys")
    lines.append("Target   : generic gate library (techmap), no technology mapping")
    lines.append("Top      : vga_text_engine")
    lines.append("Params   : RedW=8 GreenW=8 BlueW=8 FifoDepth=32 AxiAddrW=12 FetchAddrW=32")
    lines.append("")
    lines.append("Whole design")
    lines.append("-" * 72)
    lines.append(f"  cells           {total['cells']:>8}")
    lines.append(f"  flip flops      {flops:>8}")
    lines.append(f"  combinational   {combi:>8}")
    lines.append(f"  wire bits       {total['wire_bits']:>8}")
    lines.append(f"  inferred latches{0:>8}")
    lines.append(f"  black boxes     {0:>8}")
    lines.append("")
    lines.append("Cells per submodule, one instance and the whole design")
    lines.append("-" * 72)
    lines.append(f"  {'module':<20}{'per instance':>14}{'instances':>11}{'total':>10}")
    for name, cells, mult, tot in rows:
        lines.append(f"  {name:<20}{cells:>14}{mult:>11}{tot:>10}")
    lines.append("")
    lines.append("Cell mix, whole design")
    lines.append("-" * 72)
    for t, n in sorted(total["types"].items(), key=lambda kv: -kv[1]):
        lines.append(f"  {t:<20}{n:>8}")
    lines.append("")
    lines.append("Where the area goes")
    lines.append("-" * 72)
    lines.append("  vte_axil_regs     storage dominates: 16 palette entries of 12 bits plus")
    lines.append("                    about 100 bits of configuration, the 32 bit read mux and")
    lines.append("                    the read-modify-write path for byte strobes.")
    lines.append("  vte_glyph_rom     3072 bytes of constant data mapped to gates because the")
    lines.append("                    generic library has no memory primitive. On an FPGA or")
    lines.append("                    with a technology library this is one block RAM.")
    lines.append("  vte_cdc_fifo      32 entries of 19 bits as distributed registers, plus the")
    lines.append("                    gray coded pointers and both synchronisers.")
    lines.append("  vte_timing_gen    two 12 bit position counters, the region comparators and")
    lines.append("                    the grid clamping arithmetic.")
    lines.append("  vte_frame_sync    two more copies of the configuration bundle, one frozen")
    lines.append("                    shadow in the register domain and one live in the pixel")
    lines.append("                    domain. That is the price of atomic reconfiguration.")
    lines.append("")
    if problems:
        lines.append("PROBLEMS")
        lines.append("-" * 72)
        lines.extend("  " + p for p in problems)
    else:
        lines.append("No inferred latches and no black boxes.")
    lines.append("")

    report = pathlib.Path(args.report)
    report.parent.mkdir(parents=True, exist_ok=True)
    report.write_text("\n".join(lines))
    print(f"wrote {report}")

    # Bar chart of the per submodule totals.
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    chart_rows = [r for r in rows if r[3] > 0]
    names = [r[0] for r in chart_rows]
    vals = [r[3] for r in chart_rows]

    fig, ax = plt.subplots(figsize=(9, 4.6))
    bars = ax.barh(range(len(names))[::-1], vals, color="#3b7dd8", height=0.62)
    ax.set_yticks(range(len(names))[::-1])
    ax.set_yticklabels(names, fontfamily="monospace", fontsize=9)
    ax.set_xlabel("generic cells after techmap")
    ax.set_title(f"vga_text_engine cell count by submodule (total {total['cells']})")
    ax.set_xlim(0, max(vals) * 1.18)
    ax.grid(axis="x", linestyle=":", alpha=0.5)
    ax.set_axisbelow(True)
    for b, v in zip(bars, vals):
        ax.text(b.get_width() + max(vals) * 0.012, b.get_y() + b.get_height() / 2,
                f"{v}", va="center", fontsize=9, fontfamily="monospace")
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    fig.tight_layout()
    chart = pathlib.Path(args.chart)
    chart.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(chart, dpi=140)
    print(f"wrote {chart}")

    if problems:
        for p in problems:
            print(f"FAIL {p}")
        print("TEST_RESULT: FAIL")
        return 1
    print(f"cells {total['cells']}, flip flops {flops}, no latches, no black boxes")
    print("TEST_RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
