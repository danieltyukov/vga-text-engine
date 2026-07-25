#!/usr/bin/env python3
"""Generate docs/img/schematic_top.svg: the top level as the tools see it.

Yosys elaborates the design and writes the netlist as JSON, netlistsvg lays it out. The
hand drawn block diagram in the README is the readable one; this is the cross check. It is
generated from the same source files the simulator and the synthesiser read, so a connection
that exists here exists in the design, and a submodule port the hand drawing omits shows up.

Hierarchy is kept rather than flattened, so the figure has one box per submodule instance
with its real port names. Yosys renames a parameterised module to
`$paramod\\vte_axil_regs\\AxiAddrW=32'000...`, which is accurate and unreadable, so the cell
types are rewritten back to the plain module name in the JSON before netlistsvg sees it.
"""

import argparse
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
IMG = ROOT / "docs" / "img"
WORK = ROOT / "results" / "schematic"

RTL = [
    "vte_modes_pkg.sv", "vte_pkg.sv", "vte_mode_lut.sv", "vte_sync2.sv", "vte_cdc_fifo.sv",
    "vte_frame_sync.sv", "vte_timing_gen.sv", "vte_glyph_rom.sv", "vte_shader.sv",
    "vte_fetch_engine.sv", "vte_axil_regs.sv", "vga_text_engine.sv",
]
TOP = "vga_text_engine"

# $paramod\vte_axil_regs\AxiAddrW=32'0000... and the hashed form $paramod$<hash>\vte_shader
PARAMOD_RE = re.compile(r"^\$paramod[^\\]*\\\\?([A-Za-z_][A-Za-z_0-9]*)")


def sh(cmd, **kw):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
        raise SystemExit(f"command failed: {' '.join(str(c) for c in cmd)}")
    return r.stdout


def plain_name(name):
    m = PARAMOD_RE.match(name)
    return m.group(1) if m else name.lstrip("\\")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(IMG / "schematic_top.svg"))
    args = ap.parse_args()

    WORK.mkdir(parents=True, exist_ok=True)
    raw = WORK / "top_hier.json"
    clean = WORK / "top_hier_named.json"

    # proc turns the always blocks into logic; opt_clean drops what nothing reads. No
    # flatten and no techmap: the point is the module boundaries, not the gates.
    sh(["yosys", "-q", "-l", str(WORK / "yosys.log"), "-p",
        "read_verilog -sv -DSYNTHESIS " + " ".join(f"rtl/{f}" for f in RTL)
        + f"; hierarchy -top {TOP}; proc; opt_clean; write_json {raw.relative_to(ROOT)}"])

    netlist = json.loads(raw.read_text())
    top = netlist["modules"].get(TOP) or netlist["modules"][next(iter(netlist["modules"]))]
    renamed = 0
    for cell in top["cells"].values():
        new = plain_name(cell["type"])
        if new != cell["type"]:
            cell["type"] = new
            renamed += 1
    # netlistsvg draws whichever module it is given, so hand it the top alone. Keeping the
    # submodule bodies would make it pick one of them instead.
    clean.write_text(json.dumps({"modules": {TOP: top}}))

    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    sh(["netlistsvg", str(clean.relative_to(ROOT)), "-o", str(out)])

    svg = out.read_text()
    dims = re.search(r'width="(\d+)" height="(\d+)"', svg)
    print(f"{out.relative_to(ROOT)}  {dims.group(1)}x{dims.group(2)}  "
          f"{len(top['cells'])} submodule instances, {renamed} parameterised names cleaned")
    return 0


if __name__ == "__main__":
    sys.exit(main())
