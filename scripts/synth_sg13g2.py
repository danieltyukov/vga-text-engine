#!/usr/bin/env python3
"""Synthesise vga_text_engine to the IHP SG13G2 130 nm standard cell library.

Runs synth/synth_sg13g2.ys.in per corner, parses the real area and cell histogram out of
the Yosys statistics, and writes:

  docs/pdk_area_report.txt      area and cell mix, hierarchical and flattened, per corner
  docs/img/pdk_area.png         area per submodule at the signoff corner
  synth/out/netlist_<corner>.v  gate level netlist, the input to scripts/sta_sg13g2.py
  synth/out/*.json              JSON netlist, the input to the schematic figure

Area is real silicon: Yosys multiplies each mapped cell by its Liberty area, so the
figures are in square micrometres of standard cell, before place and route.
"""

import argparse
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import pdk  # noqa: E402

OUT = ROOT / "synth" / "out"
TEMPLATE = ROOT / "synth" / "synth_sg13g2.ys.in"

# Yosys decorates parameterised modules; map them back to readable names.
PARAM_RE = re.compile(r"^\$paramod[^\\]*\\?(?P<name>[A-Za-z_][A-Za-z0-9_]*)")

INSTANCE_COUNT = {"vte_sync2": 6, "vte_mode_lut": 3}

LATCH_PREFIXES = ("sg13g2_dlh", "sg13g2_dll", "$_DLATCH", "$_SR_")


def clean_name(raw):
    m = PARAM_RE.match(raw)
    return m.group("name") if m else raw.split("\\")[-1]


def run(corner, tag, quiet=True):
    """Run one synthesis pass. tag is "hier" or "flat"."""
    OUT.mkdir(parents=True, exist_ok=True)
    script = (TEMPLATE.read_text()
              .replace("@LIB@", str(pdk.lib(corner)))
              .replace("@CORNER@", corner)
              .replace("@OUT@", str(OUT.relative_to(ROOT)))
              .replace("@FLATTEN@", "-flatten" if tag == "flat" else "")
              .replace("@TAG@", tag))
    script_path = OUT / f"synth_{tag}_{corner}.ys"
    script_path.write_text(script)
    log = OUT / f"yosys_{tag}_{corner}.log"
    r = subprocess.run(["yosys", "-q", "-l", str(log), str(script_path)],
                       cwd=ROOT, capture_output=True, text=True)
    noise = [ln for ln in (r.stdout + r.stderr).splitlines()
             if ln.strip() and "Replacing memory" not in ln]
    if r.returncode != 0 or any("ERROR" in ln for ln in noise):
        print("\n".join(noise[-25:]))
        raise SystemExit(f"yosys failed for corner {corner} pass {tag}, see {log}")
    if not quiet and noise:
        print("\n".join(noise))
    return log


def verify_netlist(corner, tag="flat"):
    """Read the written netlist back and assert it is structurally sound.

    This is the check that matters. Asserting inside the synthesis script is unreliable
    after flatten: Yosys keeps the flattened alias of every port alongside the port
    itself, opt_clean removes the alias, and check then reports the alias as an undriven
    wire even though the port is driven by a cell. Reading the emitted netlist back with
    the standard cells as black boxes removes that ambiguity and checks the artifact that
    actually goes to timing analysis and to gate level simulation.
    """
    netlist = OUT / f"netlist_{tag}_{corner}.v"
    if not netlist.exists():
        raise SystemExit(f"missing netlist {netlist}")
    script = (f"read_liberty -lib {pdk.lib(corner)}\n"
              f"read_verilog {netlist.relative_to(ROOT)}\n"
              f"hierarchy -check -top vga_text_engine\n"
              f"check -assert\n")
    path = OUT / f"verify_{tag}_{corner}.ys"
    path.write_text(script)
    log = OUT / f"verify_{tag}_{corner}.log"
    r = subprocess.run(["yosys", "-q", "-l", str(log), str(path)],
                       cwd=ROOT, capture_output=True, text=True)
    bad = [ln for ln in (r.stdout + r.stderr).splitlines()
           if "unsupported expression" not in ln and ln.strip()]
    if r.returncode != 0 or bad:
        print("\n".join(bad[-20:]))
        return False
    return True


def parse_stat(path):
    """Parse a Yosys `stat -liberty` report.

    Returns {module: {"cells": n, "area": um2, "types": {cell: n}}} plus the whole
    design under the key "__design__".
    """
    mods = {}
    cur = None
    for line in pathlib.Path(path).read_text().splitlines():
        m = re.match(r"^=== (.+) ===$", line.strip())
        if m:
            name = m.group(1)
            cur = "__design__" if name == "design hierarchy" else clean_name(name)
            mods.setdefault(cur, {"cells": 0, "area": 0.0, "types": {}})
            continue
        if cur is None:
            continue
        m = re.match(r"^\s+Number of cells:\s+(\d+)$", line)
        if m:
            mods[cur]["cells"] = int(m.group(1))
            continue
        # The module name can itself contain a quote, because Yosys spells parameter
        # values as 32'000...1100, so the name has to be matched greedily.
        m = re.match(r"^\s+Chip area for (?:top )?module '(?:.*)': ([0-9.]+)$", line)
        if m:
            mods[cur]["area"] = float(m.group(1))
            continue
        m = re.match(r"^\s+([A-Za-z_$][A-Za-z_0-9$]*)\s+(\d+)$", line)
        if m and m.group(1) not in ("wires", "memories", "processes"):
            mods[cur]["types"][m.group(1)] = int(m.group(2))
    # A flattened design is a single module, so stat prints no "design hierarchy"
    # section. Treat the top module as the whole design in that case.
    if "__design__" not in mods and "vga_text_engine" in mods:
        mods["__design__"] = mods["vga_text_engine"]
    return mods


def flop_count(types):
    return sum(n for t, n in types.items() if "_df" in t or "_sdf" in t)


def latch_count(types):
    return sum(n for t, n in types.items() if any(t.startswith(p) for p in LATCH_PREFIXES))


def submodule_rows(hier):
    rows = []
    for name, d in hier.items():
        if name in ("__design__",):
            continue
        mult = INSTANCE_COUNT.get(name, 1)
        rows.append({"name": name, "cells": d["cells"], "area": d["area"], "mult": mult,
                     "total_cells": d["cells"] * mult, "total_area": d["area"] * mult,
                     "types": d["types"]})
    rows.sort(key=lambda r: -r["total_area"])
    return rows


def write_report(results, path):
    """results: {corner: {"hier": mods, "flat": mods}}"""
    sign = pdk.SIGNOFF_CORNER
    hier = results[sign]["hier"]
    flat = results[sign]["flat"]
    design = flat["__design__"]
    rows = submodule_rows(hier)
    lines = []

    lines.append("vga_text_engine standard cell synthesis")
    lines.append("=" * 76)
    lines.append("")
    lines.append("Tool      : Yosys 0.33")
    lines.append("PDK       : IHP Open PDK SG13G2, 130 nm BiCMOS, open source")
    lines.append(f"Library   : {pdk.STDCELL.name}")
    lines.append("Script    : synth/synth_sg13g2.ys.in")
    lines.append("Top       : vga_text_engine")
    lines.append("Params    : RedW=8 GreenW=8 BlueW=8 FifoDepth=32 AxiAddrW=12 FetchAddrW=32")
    lines.append(f"Signoff   : {sign} corner, {pdk.CORNERS[sign][1]}, {pdk.CORNERS[sign][2]}")
    lines.append("")
    lines.append("Area is standard cell area after technology mapping, in square")
    lines.append("micrometres: every mapped cell multiplied by its Liberty area. It excludes")
    lines.append("routing, filler and tap cells, so a placed and routed die is larger.")
    lines.append("")

    lines.append("Whole design, flattened")
    lines.append("-" * 76)
    lines.append(f"  standard cell area    {design['area']:>12.1f} um2")
    lines.append(f"  cell instances        {design['cells']:>12}")
    lines.append(f"  flip flops            {flop_count(design['types']):>12}")
    lines.append(f"  inferred latches      {latch_count(design['types']):>12}")
    eq = design["area"] / 5.6448 if design["area"] else 0.0
    lines.append(f"  equivalent NAND2      {eq:>12.0f}   (sg13g2_nand2_1 is 5.6448 um2)")
    lines.append("")

    lines.append("Multi corner comparison, flattened")
    lines.append("-" * 76)
    lines.append(f"  {'corner':<12}{'supply':>9}{'temp':>8}{'area um2':>13}{'cells':>9}"
                 f"{'flops':>8}")
    for c in pdk.DEFAULT_CORNERS:
        d = results[c]["flat"]["__design__"]
        _, v, t, _ = pdk.CORNERS[c]
        lines.append(f"  {c:<12}{v:>9}{t:>8}{d['area']:>13.1f}{d['cells']:>9}"
                     f"{flop_count(d['types']):>8}")
    lines.append("")
    lines.append("  Area is identical across corners, which is expected: Liberty cell areas")
    lines.append("  are process independent, so only the timing changes. The corner matters")
    lines.append("  for docs/sta_report.txt, not here.")
    lines.append("")

    lines.append(f"Area per submodule, hierarchical mapping, {sign} corner")
    lines.append("-" * 76)
    lines.append(f"  {'module':<20}{'area um2':>11}{'inst':>6}{'total um2':>12}"
                 f"{'cells':>8}{'share':>8}")
    hier_total = sum(r["total_area"] for r in rows)
    for r in rows:
        share = 100.0 * r["total_area"] / hier_total if hier_total else 0.0
        lines.append(f"  {r['name']:<20}{r['area']:>11.1f}{r['mult']:>6}"
                     f"{r['total_area']:>12.1f}{r['total_cells']:>8}{share:>7.1f}%")
    lines.append(f"  {'sum':<20}{'':>11}{'':>6}{hier_total:>12.1f}")
    lines.append("")
    lines.append("  The hierarchical sum is larger than the flattened total because")
    lines.append("  flattening lets the mapper optimise across module boundaries.")
    lines.append("")

    lines.append(f"Cell histogram, flattened, {sign} corner")
    lines.append("-" * 76)
    lines.append(f"  {'cell':<24}{'count':>8}{'area um2':>12}")
    for t, n in sorted(design["types"].items(), key=lambda kv: -kv[1]):
        lines.append(f"  {t:<24}{n:>8}")
    lines.append("")

    lines.append("Checks")
    lines.append("-" * 76)
    latches = latch_count(design["types"])
    lines.append(f"  inferred latches      {latches}   "
                 f"{'pass' if latches == 0 else 'FAIL'}")
    empty = [r["name"] for r in rows if r["cells"] == 0 and r["name"] != "vga_text_engine"]
    lines.append(f"  black boxes           {len(empty)}   "
                 f"{'pass' if not empty else 'FAIL: ' + ', '.join(empty)}")
    unmapped = sorted(t for t in design["types"] if t.startswith("$"))
    lines.append(f"  unmapped cells        {len(unmapped)}   "
                 f"{'pass' if not unmapped else 'FAIL: ' + ', '.join(unmapped)}")
    lines.append("")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")
    return latches == 0 and not empty and not unmapped, rows, design


def write_chart(rows, design, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    rows = [r for r in rows if r["total_area"] > 0]
    names = [r["name"] for r in rows]
    vals = [r["total_area"] for r in rows]

    fig, ax = plt.subplots(figsize=(9.2, 4.8))
    ypos = list(range(len(names)))[::-1]
    bars = ax.barh(ypos, vals, color="#3b7dd8", height=0.62)
    ax.set_yticks(ypos)
    ax.set_yticklabels(names, fontfamily="monospace", fontsize=9)
    ax.set_xlabel("standard cell area, square micrometres")
    ax.set_title("vga_text_engine area by submodule, IHP SG13G2 130 nm\n"
                 f"flattened total {design['area']:.0f} um2, "
                 f"{design['cells']} cells, {flop_count(design['types'])} flip flops",
                 fontsize=11)
    ax.set_xlim(0, max(vals) * 1.20)
    ax.grid(axis="x", linestyle=":", alpha=0.5)
    ax.set_axisbelow(True)
    for b, v in zip(bars, vals):
        ax.text(b.get_width() + max(vals) * 0.012, b.get_y() + b.get_height() / 2,
                f"{v:,.0f}", va="center", fontsize=9, fontfamily="monospace")
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    fig.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=140)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corners", default=",".join(pdk.DEFAULT_CORNERS))
    ap.add_argument("--report", default=str(ROOT / "docs" / "pdk_area_report.txt"))
    ap.add_argument("--chart", default=str(ROOT / "docs" / "img" / "pdk_area.png"))
    args = ap.parse_args()

    pdk.check()
    corners = args.corners.split(",")

    results = {}
    for c in corners:
        print(f"synthesising at the {c} corner ...", flush=True)
        run(c, "hier")
        run(c, "flat")
        results[c] = {"hier": parse_stat(OUT / f"area_hier_{c}.txt"),
                      "flat": parse_stat(OUT / f"area_flat_{c}.txt")}
        if not verify_netlist(c):
            raise SystemExit(f"the emitted netlist for corner {c} is not sound")
        print("  netlist re-read and checked: sound")
        d = results[c]["flat"]["__design__"]
        print(f"  {d['area']:.1f} um2, {d['cells']} cells, "
              f"{flop_count(d['types'])} flip flops")

    ok, rows, design = write_report(results, pathlib.Path(args.report))
    print(f"wrote {args.report}")
    write_chart(rows, design, pathlib.Path(args.chart))
    print(f"wrote {args.chart}")

    print(f"signoff corner {pdk.SIGNOFF_CORNER}: {design['area']:.1f} um2, "
          f"{design['cells']} cells, {flop_count(design['types'])} flip flops, "
          f"{latch_count(design['types'])} latches")
    print("TEST_RESULT: PASS" if ok else "TEST_RESULT: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
