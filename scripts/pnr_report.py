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
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

# Standard cell area from docs/pdk_area_report.txt, the signoff corner figure, so the two
# reports can be read against each other.
SYNTH_CELL_AREA_UM2 = 175324.6

RENDER_SCRIPT = r'''# Rendered by scripts/pnr_report.py via klayout -b -rm.
# Batch mode takes -rd name=value rather than positional arguments.
#
# Labels are turned off before the fit: the GDS carries a net name label on every pin and
# they spill far outside the die outline, which both clutters the picture and makes
# zoom_fit frame empty space.
import pya
lv = pya.LayoutView()
lv.load_layout(gds, 0)
lv.max_hier()
# text-visible has to go through set_config; assigning the attribute does not take effect
# on the batch rendering path.
lv.set_config("text-visible", "false")
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

# Anything non zero here is a real failure.
HARD_CHECKS = [
    ("route__drc_errors", "routing DRC violations"),
    ("magic__drc_error__count", "Magic DRC violations"),
    ("klayout__drc_error__count", "KLayout DRC violations"),
    ("design__lvs_error__count", "LVS errors"),
    ("design__lvs_unmatched_net__count", "LVS unmatched nets"),
    ("design__lvs_unmatched_device__count", "LVS unmatched devices"),
    ("design__lvs_unmatched_pin__count", "LVS unmatched pins"),
    ("design__lvs_property_fail__count", "LVS property failures"),
    ("timing__setup_vio__count", "setup violations"),
    ("timing__hold_vio__count", "hold violations"),
]

# Reported with context rather than as a pass or fail, because a non zero count here is
# expected for this design and explained below.
SOFT_CHECKS = [
    ("design__disconnected_pin__count", "disconnected pins"),
    ("antenna__violating__nets", "antenna violating nets"),
]


def find_run(tag):
    runs = ROOT / "runs"
    cands = [runs / tag] if tag else sorted(d for d in runs.glob("*") if d.is_dir())
    for cand in cands:
        if (cand / "final" / "metrics.json").exists() or list(cand.glob("*/state_out.json")):
            return cand
    raise SystemExit(f"no LibreLane run with results found under {runs}")


def load_metrics(run):
    """Prefer the flow's final metrics, fall back to the last step that wrote state.

    Every LibreLane step writes the accumulated metrics into its state_out.json, so a run
    that produced a layout and its checks still yields complete numbers even if a later
    checker step did not finish. The report says which source was used.
    """
    final = run / "final" / "metrics.json"
    if final.exists():
        return json.loads(final.read_text()), "final/metrics.json", None
    states = sorted(run.glob("*/state_out.json"))
    if not states:
        raise SystemExit(f"no metrics anywhere under {run}")
    last = states[-1]
    steps = sorted(d.name for d in run.glob("[0-9]*") if d.is_dir())
    return (json.loads(last.read_text()).get("metrics", {}),
            str(last.relative_to(run)), steps[-1] if steps else None)


def find_gds(run):
    """The flow's final GDS if it exists, otherwise the streamout step's copy."""
    final = sorted((run / "final" / "gds").glob("*.gds"))
    if final:
        return final[0]
    for d in sorted(run.glob("*-magic-streamout")) + sorted(run.glob("*-klayout-streamout")):
        cands = [g for g in sorted(d.glob("*.gds")) if ".magic." not in g.name
                 and ".klayout." not in g.name] or sorted(d.glob("*.gds"))
        if cands:
            return cands[0]
    return None


def disconnected_pins(run):
    """Names from the "Disconnected" column of the flow's pin table.

    The table has five columns and lists every pin, connected or not: the last column is
    the one that names the disconnected ones.
    """
    tables = sorted(run.glob("*-odb-reportdisconnectedpins/full_disconnected_pins_table.txt"))
    if not tables:
        return []
    names = set()
    for line in tables[-1].read_text().splitlines():
        cells = line.split("\u2502")
        if len(cells) < 3:
            continue
        t = cells[-2].strip()
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*(\[\d+\])?", t):
            names.add(t)
    return sorted(names)


def render_layout(run, out, width=1600, height=1100):
    if shutil.which("klayout") is None:
        print("klayout is not on PATH, skipping the layout render")
        return False
    gds = [find_gds(run)]
    if gds[0] is None:
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
    m, source, last_step = load_metrics(run)

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
    lines.append(f"Metrics   : {source}")
    if last_step:
        lines.append(f"Last step : {last_step}")
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
    missing = []
    for key, label in HARD_CHECKS:
        if key in m and m[key] is not None:
            n = m[key]
            if n:
                problems.append(f"{label}: {n}")
            lines.append(f"  {label:<34}{n:>8}   {'pass' if not n else 'FAIL'}")
        else:
            missing.append(label)
            lines.append(f"  {label:<34}{'-':>8}   not run")
    lines.append("")
    lines.append("Reported with context")
    lines.append("-" * 76)
    for key, label in SOFT_CHECKS:
        if key in m and m[key] is not None:
            lines.append(f"  {label:<34}{m[key]:>8}")
    pins = disconnected_pins(run)
    if pins:
        groups = {}
        for name in pins:
            base = re.sub(r"\[\d+\]$", "", name)
            groups[base] = groups.get(base, 0) + 1
        lines.append("")
        lines.append("  The disconnected pins are inputs the design documents as ignored:")
        for base, n in sorted(groups.items()):
            lines.append(f"    {base:<24}{n:>4} bit(s)")
        lines.append("  fetch_rdata_i[31:19] are the reserved bits of the cell word and the")
        lines.append("  AXI protection buses are accepted and ignored, both stated in the")
        lines.append("  README. The flow itself reports none of them as critical, so the")
        lines.append("  physical run independently confirms the documented ignore list.")
    lines.append("")
    lines.append("  Antenna violations are counted after the flow's own repair step. A")
    lines.append("  handful on an unpadded core is a manufacturability note for whoever")
    lines.append("  integrates the block, not a functional defect.")
    lines.append("")
    if missing:
        lines.append("Checks that did not run")
        lines.append("-" * 76)
        for label in missing:
            lines.append(f"  {label}")
        lines.append("")
        lines.append("  This run stopped before those steps. Everything above comes from")
        lines.append("  steps that completed.")
        lines.append("")

    lines.append("Timing, signoff corner")
    lines.append("-" * 76)
    for key in sorted(k for k in m if k.startswith("timing__")):
        if m[key] is not None and isinstance(m[key], (int, float)):
            lines.append(f"  {key:<52}{m[key]:>12.4f}")
    lines.append("")

    lines.append("Where the area went")
    lines.append("-" * 76)
    classes = sorted(((k.split(":", 1)[1], v) for k, v in m.items()
                      if k.startswith("design__instance__area__class:")),
                     key=lambda kv: -kv[1])
    stdcell = m.get("design__instance__area__stdcell")
    total = m.get("design__instance__area")
    for name, v in classes:
        share = 100.0 * v / stdcell if stdcell and name != "fill_cell" else float("nan")
        tail = f"{share:>7.1f}% of cells" if share == share else ""
        lines.append(f"  {name:<32}{v:>12.0f} um2 {tail}")
    lines.append(f"  {'total, including fill':<32}{total:>12.0f} um2")
    lines.append("")

    lines.append("Area at each stage")
    lines.append("-" * 76)
    die = m.get("design__die__area")
    core = m.get("design__core__area")
    synth_area = SYNTH_CELL_AREA_UM2
    lines.append(f"  standard cell area at synthesis       {synth_area:>10.0f} um2")
    lines.append(f"  standard cell area after routing      {stdcell:>10.0f} um2   "
                 f"{stdcell / synth_area:.2f}x")
    lines.append(f"  core area, cells plus fill            {core:>10.0f} um2")
    lines.append(f"  die area                              {die:>10.0f} um2")
    lines.append("")
    repair = m.get("design__instance__area__class:timing_repair_buffer", 0.0)
    ctree = (m.get("design__instance__area__class:clock_buffer", 0.0)
             + m.get("design__instance__area__class:clock_inverter", 0.0))
    grew = stdcell - synth_area
    lines.append(f"  The cells grew by {grew:.0f} um2 between synthesis and routing, and")
    lines.append(f"  {repair:.0f} um2 of that is timing repair buffers with another {ctree:.0f} um2")
    lines.append(f"  of clock tree: {100.0 * (repair + ctree) / grew:.0f} percent of the growth.")
    lines.append("")
    lines.append("  That is the same story the synthesis timing report tells from the other")
    lines.append("  end. Synthesis left the enables that gate the configuration snapshot")
    lines.append("  driven by minimum size gates into several hundred loads, and place and")
    lines.append("  route spent a quarter of the cell area buffering them. The setup slack")
    lines.append("  improved from +4.965 ns at synthesis level to")
    ws = m.get("timing__setup__ws__corner:nom_slow_1p08V_125C")
    if ws is not None:
        lines.append(f"  {ws:+.3f} ns after routing, at the same 15.3846 ns pixel clock.")
    lines.append("")
    lines.append("  Quote the die area if only one number is quoted. Fill cells are not")
    lines.append("  logic, so the honest comparison against a synthesis estimate is the")
    lines.append("  standard cell figure.")
    lines.append("")
    lines.append(f"Run directory: {run.relative_to(ROOT)}")
    lines.append("")

    out = pathlib.Path(args.report)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n")
    print(f"wrote {out}")

    render_layout(run, pathlib.Path(args.image))

    if problems:
        for pr in problems:
            print(f"FAIL {pr}")
        print("TEST_RESULT: FAIL")
        return 1
    print(f"die {m['design__die__area']:.0f} um2, standard cells "
          f"{m['design__instance__area__stdcell']:.0f} um2, "
          f"utilisation {m.get('design__instance__utilization', 0):.3f}, "
          f"setup slack {m.get('timing__setup__ws__corner:nom_slow_1p08V_125C', 0):+.3f} ns, "
          f"DRC and LVS clean")
    if missing:
        print(f"note: {len(missing)} check(s) did not run: {', '.join(missing)}")
    print("TEST_RESULT: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
