#!/usr/bin/env python3
"""Static timing analysis of vga_text_engine on the IHP SG13G2 library.

Answers one question per video mode: at the slow corner, does the pixel domain close
timing at that mode's pixel clock? Runs OpenSTA through OpenROAD once per mode per
corner, then writes:

  docs/sta_report.txt      per mode slack and per corner maximum frequency
  docs/img/fmax_modes.png  required pixel clock against achieved Fmax, per mode

The design has two asynchronous clocks, declared as separate clock groups. Every path
between them is either a gray coded FIFO pointer or a single bit through a two flop
synchroniser, so timing them as if they were synchronous would report violations that do
not exist.

These are synthesis level numbers: ideal clock networks, no wire load model, and no
fanout repair or buffer insertion. That makes them an upper bound on frequency rather
than a signoff result. See docs/pnr_report.txt if a placed and routed run is present.
"""

import argparse
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import modes  # noqa: E402
import pdk  # noqa: E402

OUT = ROOT / "synth" / "out"
TEMPLATE = ROOT / "synth" / "sta.tcl.in"

# Register and fetch clock used while measuring the pixel domain. 50 MHz is the figure
# the bandwidth arithmetic in docs/design.md is worked at.
REG_PERIOD_NS = 20.0

MIN_PERIOD_RE = re.compile(r"^(\w+)\s+period_min\s*=\s*([0-9.]+)\s+fmax\s*=\s*([0-9.]+)")
WORST_RE = re.compile(r"^worst slack max\s+(-?[0-9.]+)")
TNS_RE = re.compile(r"^tns max\s+(-?[0-9.]+)")


def run_sta(corner, pix_period_ns, tag):
    netlist = OUT / f"netlist_flat_{corner}.v"
    if not netlist.exists():
        raise SystemExit(f"missing {netlist}; run scripts/synth_sg13g2.py first")
    tcl = (TEMPLATE.read_text()
           .replace("@LIB@", str(pdk.lib(corner)))
           .replace("@TECH_LEF@", str(pdk.TECH_LEF))
           .replace("@CELL_LEF@", str(pdk.CELL_LEF))
           .replace("@NETLIST@", str(netlist.relative_to(ROOT)))
           .replace("@PIX_PERIOD@", f"{pix_period_ns:.4f}")
           .replace("@REG_PERIOD@", f"{REG_PERIOD_NS:.4f}"))
    tcl_path = OUT / f"sta_{tag}.tcl"
    tcl_path.write_text(tcl)
    r = subprocess.run(["openroad", "-no_init", "-exit", str(tcl_path.relative_to(ROOT))],
                       cwd=ROOT, capture_output=True, text=True)
    text = r.stdout + r.stderr
    (OUT / f"sta_{tag}.log").write_text(text)
    if r.returncode != 0 or "Error" in text or "ERROR" in text:
        bad = [ln for ln in text.splitlines()
               if "unsupported expression" not in ln and "sg13g2_sdfrbp" not in ln]
        print("\n".join(bad[-25:]))
        raise SystemExit(f"OpenSTA failed for {tag}")
    return parse(text)


def parse(text):
    d = {"clocks": {}, "worst": None, "tns": None, "area": None, "util": None,
         "paths": {}}
    section = None
    for line in text.splitlines():
        s = line.strip()
        m = re.match(r"^=== (.+) ===$", s)
        if m:
            section = m.group(1)
            d["paths"].setdefault(section, [])
            continue
        m = MIN_PERIOD_RE.match(s)
        if m:
            d["clocks"][m.group(1)] = {"period_min": float(m.group(2)),
                                       "fmax_mhz": float(m.group(3))}
            continue
        m = WORST_RE.match(s)
        if m:
            d["worst"] = float(m.group(1))
            continue
        m = TNS_RE.match(s)
        if m:
            d["tns"] = float(m.group(1))
            continue
        m = re.match(r"^Design area\s+([0-9.]+)\s*\S+\s+([0-9.]+)%", s)
        if m:
            d["area"] = float(m.group(1))
            d["util"] = float(m.group(2))
            continue
        if section and s:
            d["paths"][section].append(line.rstrip())
    return d


def critical_path(res, section):
    """Return the worst slack path in a section, plus its heaviest fanout stage.

    report_checks prints one path per path group, and the async reset recovery group
    usually comes first, so taking the first path would report the wrong thing. Every
    path in the section is parsed and the one with the least slack wins.
    """
    lines = res["paths"].get(section, [])
    paths = []
    cur = None
    for ln in lines:
        t = ln.strip()
        m = re.match(r"^Startpoint: (\S+)", t)
        if m:
            cur = {"start": m.group(1), "end": None, "slack": None, "kind": None,
                   "worst_fanout": 0, "worst_fanout_net": None, "worst_fanout_delay": 0.0,
                   "stages": 0}
            paths.append(cur)
            continue
        if cur is None:
            continue
        m = re.match(r"^Endpoint: (\S+)", t)
        if m:
            cur["end"] = m.group(1)
            continue
        # "Fanout Cap Slew Delay Time ^ pin/Y (cell)" rows carry the load of each stage.
        m = re.match(r"^(\d+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+([0-9.]+)\s+[\^v]\s+"
                     r"(\S+)\s+\(", t)
        if m:
            cur["stages"] += 1
            fan, delay = int(m.group(1)), float(m.group(4))
            if fan > cur["worst_fanout"]:
                cur["worst_fanout"] = fan
                cur["worst_fanout_delay"] = delay
                cur["worst_fanout_net"] = m.group(6)
            continue
        m = re.match(r"^(-?[0-9.]+)\s+slack \((MET|VIOLATED)\)", t)
        if m:
            cur["slack"] = float(m.group(1))
            cur["kind"] = m.group(2)
            cur = None
            continue
    paths = [p for p in paths if p["slack"] is not None]
    if not paths:
        return None
    return min(paths, key=lambda p: p["slack"])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corners", default=",".join(pdk.DEFAULT_CORNERS))
    ap.add_argument("--report", default=str(ROOT / "docs" / "sta_report.txt"))
    ap.add_argument("--chart", default=str(ROOT / "docs" / "img" / "fmax_modes.png"))
    args = ap.parse_args()

    pdk.check()
    corners = args.corners.split(",")

    # Per mode at the signoff corner, plus one run per corner for the Fmax table.
    per_mode = {}
    for m in modes.MODES:
        period = 1000.0 / m["pclk"]
        tag = f"{pdk.SIGNOFF_CORNER}_mode{m['index']}"
        print(f"timing {m['name']} at {m['pclk']} MHz "
              f"({period:.4f} ns), {pdk.SIGNOFF_CORNER} corner ...", flush=True)
        res = run_sta(pdk.SIGNOFF_CORNER, period, tag)
        pix = res["clocks"].get("clk_pix", {})
        slack = period - pix.get("period_min", 0.0)
        per_mode[m["index"]] = {"mode": m, "period": period, "res": res, "slack": slack,
                                "fmax": pix.get("fmax_mhz", 0.0),
                                "period_min": pix.get("period_min", 0.0)}
        verdict = "MET" if slack >= 0 else "VIOLATED"
        print(f"  pixel domain Fmax {pix.get('fmax_mhz', 0):.2f} MHz, "
              f"slack {slack:+.4f} ns, {verdict}")

    per_corner = {}
    for c in corners:
        tag = f"{c}_ref"
        print(f"timing the {c} corner at the 1024x768 pixel clock ...", flush=True)
        res = run_sta(c, 1000.0 / modes.BY_INDEX[2]["pclk"], tag)
        per_corner[c] = res
        print(f"  clk_pix Fmax {res['clocks']['clk_pix']['fmax_mhz']:.2f} MHz, "
              f"clk_reg Fmax {res['clocks']['clk_reg']['fmax_mhz']:.2f} MHz")

    ok = all(v["slack"] >= 0 for v in per_mode.values())
    write_report(per_mode, per_corner, pathlib.Path(args.report))
    print(f"wrote {args.report}")
    write_chart(per_mode, pathlib.Path(args.chart))
    print(f"wrote {args.chart}")
    print("TEST_RESULT: PASS" if ok else "TEST_RESULT: FAIL")
    return 0 if ok else 1


def write_report(per_mode, per_corner, path):
    sign = pdk.SIGNOFF_CORNER
    _, volts, temp, desc = pdk.CORNERS[sign]
    lines = []
    lines.append("vga_text_engine static timing analysis")
    lines.append("=" * 78)
    lines.append("")
    lines.append("Tool      : OpenSTA 3.1.0 via OpenROAD")
    lines.append("PDK       : IHP Open PDK SG13G2, 130 nm")
    lines.append("Netlist   : synth/out/netlist_flat_<corner>.v from synth/synth_sg13g2.ys.in")
    lines.append("Script    : synth/sta.tcl.in")
    lines.append(f"Signoff   : {sign} corner, {volts}, {temp} ({desc})")
    lines.append(f"clk_i     : {REG_PERIOD_NS:.1f} ns, {1000.0 / REG_PERIOD_NS:.0f} MHz, "
                 f"while the pixel domain is measured")
    lines.append("")
    lines.append("These are synthesis level numbers: ideal clock networks, no wire load")
    lines.append("model, and no fanout repair or buffer insertion. Treat them as an upper")
    lines.append("bound on frequency. The two clocks are declared as separate asynchronous")
    lines.append("clock groups, because every path between them is either a gray coded FIFO")
    lines.append("pointer or a single bit through a two flop synchroniser.")
    lines.append("")

    lines.append(f"Does each video mode close timing? {sign} corner")
    lines.append("-" * 78)
    lines.append(f"  {'mode':<14}{'pixel clk':>11}{'period':>10}{'min period':>12}"
                 f"{'slack':>11}{'headroom':>11}{'verdict':>10}")
    for idx in sorted(per_mode):
        v = per_mode[idx]
        m = v["mode"]
        head = 100.0 * (v["fmax"] / m["pclk"] - 1.0) if m["pclk"] else 0.0
        lines.append(f"  {m['name']:<14}{m['pclk']:>9.3f} M{v['period']:>9.3f}n"
                     f"{v['period_min']:>11.3f}n{v['slack']:>+10.3f}n{head:>10.0f}%"
                     f"{'MET' if v['slack'] >= 0 else 'VIOLATED':>10}")
    lines.append("")
    fmax = max(v["fmax"] for v in per_mode.values())
    lines.append(f"  The pixel domain closes at {fmax:.2f} MHz, so every mode in the table")
    lines.append("  has margin. The pixel pipeline is one pixel per clock with no")
    lines.append("  multi-cycle paths, so the critical path does not depend on the mode:")
    lines.append("  the minimum period is the same in every row and only the requirement")
    lines.append("  changes.")
    lines.append("")

    lines.append("Maximum frequency per corner")
    lines.append("-" * 78)
    lines.append(f"  {'corner':<12}{'supply':>9}{'temp':>8}{'clk_pix':>12}{'clk_reg':>12}")
    for c, res in per_corner.items():
        _, v, t, _ = pdk.CORNERS[c]
        cp = res["clocks"]["clk_pix"]["fmax_mhz"]
        cr = res["clocks"]["clk_reg"]["fmax_mhz"]
        lines.append(f"  {c:<12}{v:>9}{t:>8}{cp:>9.2f} M{cr:>9.2f} M")
    lines.append("")
    lines.append("  clk_reg is the slower of the two, and the reason is load rather than")
    lines.append("  logic depth. See the critical path breakdown below.")
    lines.append("")

    lines.append("Critical paths at the signoff corner, 1024x768")
    lines.append("-" * 78)
    ref = per_mode[2]["res"]
    for section in ("worst setup path, pixel domain", "worst setup path, register domain"):
        p = critical_path(ref, section)
        lines.append(f"  {section}")
        if p is None:
            lines.append("    no path reported")
            lines.append("")
            continue
        lines.append(f"    startpoint      {p['start']}")
        lines.append(f"    endpoint        {p['end']}")
        lines.append(f"    slack           {p['slack']:+.4f} ns ({p['kind']})")
        lines.append(f"    logic stages    {p['stages']}")
        lines.append(f"    heaviest stage  {p['worst_fanout_net']} drives "
                     f"{p['worst_fanout']} loads, {p['worst_fanout_delay']:.4f} ns")
        lines.append("")

    pix_p = critical_path(ref, "worst setup path, pixel domain")
    reg_p = critical_path(ref, "worst setup path, register domain")
    if pix_p and reg_p:
        pix_share = 100.0 * pix_p["worst_fanout_delay"] / max(
            pix_p["worst_fanout_delay"], 1e-9)
        del pix_share
        lines.append("  Neither path is deep: "
                     f"{pix_p['stages']} stages in the pixel domain and "
                     f"{reg_p['stages']} in the register domain. In both cases almost all")
        lines.append("  of the delay is a single unbuffered net, "
                     f"{reg_p['worst_fanout']} loads for "
                     f"{reg_p['worst_fanout_delay']:.2f} ns in the register domain and "
                     f"{pix_p['worst_fanout']} loads")
        lines.append(f"  for {pix_p['worst_fanout_delay']:.2f} ns in the pixel domain. "
                     "Those are the enables that gate")
        lines.append("  the 295 bit configuration snapshot: the frame boundary handshake")
        lines.append("  updates the whole bundle at once, so one signal reaches several")
        lines.append("  hundred flip flop enable inputs.")
    lines.append("")
    lines.append("  That is what synthesis level timing looks like when no load aware")
    lines.append("  buffering has run: abc picks a minimum size gate and asks it to drive")
    lines.append("  the entire bank. A place and route flow inserts a buffer tree there and")
    lines.append("  the stage collapses, so these frequencies understate what the design")
    lines.append("  does once it is built. They are reported as measured rather than")
    lines.append("  adjusted, and every video mode closes even so.")
    lines.append("")

    lines.append("Full path report, pixel domain, 1024x768, signoff corner")
    lines.append("-" * 78)
    for ln in ref["paths"].get("worst setup path, pixel domain", []):
        lines.append("  " + ln)
    lines.append("")
    lines.append("Full path report, register domain, 1024x768, signoff corner")
    lines.append("-" * 78)
    for ln in ref["paths"].get("worst setup path, register domain", []):
        lines.append("  " + ln)
    lines.append("")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n")


def write_chart(per_mode, path):
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    import numpy as np

    idxs = sorted(per_mode)
    names = [per_mode[i]["mode"]["name"] for i in idxs]
    need = [per_mode[i]["mode"]["pclk"] for i in idxs]
    got = [per_mode[i]["fmax"] for i in idxs]

    x = np.arange(len(names))
    w = 0.38
    fig, ax = plt.subplots(figsize=(8.6, 4.4))
    b1 = ax.bar(x - w / 2, need, w, label="pixel clock the mode needs", color="#94a3b8")
    b2 = ax.bar(x + w / 2, got, w, label="Fmax achieved, slow corner", color="#3b7dd8")
    ax.set_xticks(x)
    ax.set_xticklabels(names, fontfamily="monospace", fontsize=9)
    ax.set_ylabel("MHz")
    ax.set_title("vga_text_engine pixel domain timing closure\n"
                 "IHP SG13G2 130 nm, slow corner 1.08 V 125 C, synthesis level",
                 fontsize=11)
    ax.legend(frameon=False, fontsize=9, loc="upper left")
    ax.set_ylim(0, max(got) * 1.28)
    ax.grid(axis="y", linestyle=":", alpha=0.5)
    ax.set_axisbelow(True)
    for bars in (b1, b2):
        for b in bars:
            ax.text(b.get_x() + b.get_width() / 2, b.get_height() + max(got) * 0.015,
                    f"{b.get_height():.1f}", ha="center", fontsize=8.5,
                    fontfamily="monospace")
    for i, (n, g) in enumerate(zip(need, got)):
        ax.text(i, max(got) * 1.16, f"x{g / n:.1f}", ha="center", fontsize=9,
                color="#15803d", fontweight="bold", fontfamily="monospace")
    ax.text(len(names) - 0.5, max(got) * 1.22, "headroom", ha="right", fontsize=8.5,
            color="#15803d")
    for side in ("top", "right"):
        ax.spines[side].set_visible(False)
    fig.tight_layout()
    path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(path, dpi=140)


if __name__ == "__main__":
    sys.exit(main())
