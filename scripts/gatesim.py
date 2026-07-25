#!/usr/bin/env python3
"""Gate level simulation of the synthesised netlist, checked pixel for pixel.

Runs the same frame capture testbench that exercises the RTL, but against the mapped
sg13g2 netlist and the PDK's behavioural cell models, then diffs the captured frame
against the independent Python reference renderer. A pass means the netlist Yosys emitted
renders exactly the pixels the RTL does, which is a far stronger statement about the
synthesis result than any structural check.

The PDK cell models carry specify blocks that Icarus Verilog cannot parse: it rejects
"ifnone with an edge-sensitive path" whether or not specify parsing is enabled. All 505
delay assignments in that file are (0.0, 0.0), so a zero delay functional model loses
nothing by removing them, but they cannot simply be deleted. The sequential cells route
their inputs through delayed_CLK, delayed_D and delayed_RESET_B, and the specify block is
what drives those wires. Deleting the block leaves them permanently X and the whole design
goes X, which is exactly what happened on the first attempt.

So this script rewrites each specify block into the zero delay identity it stands for:
"assign delayed_X = X;" for every delayed wire in that module. Two guards keep the
rewrite honest: it refuses to proceed if any delay is non zero, and it refuses to proceed
if a delayed_X has no matching port X to alias.
"""

import argparse
import pathlib
import re
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import pdk  # noqa: E402
import scenes as scenemod  # noqa: E402

SIM = ROOT / "results" / "sim"
SCENES = ROOT / "results" / "scenes"
OUT = ROOT / "synth" / "out"

SPECIFY_RE = re.compile(r"^\s*specify\s*$")
ENDSPECIFY_RE = re.compile(r"^\s*endspecify\s*$")
MODULE_RE = re.compile(r"^\s*module\s+(\w+)")
ENDMODULE_RE = re.compile(r"^\s*endmodule")
# re.M matters: without it the ^ anchor only matches the start of the chunk.
PORT_RE = re.compile(r"^\s*(?:input|output|inout)\s+([^;]+);", re.M)
DELAYED_RE = re.compile(r"\bdelayed_(\w+)\b")
DELAY_RE = re.compile(r"=\s*\(([0-9.,:\s]+)\)")


def rewrite_specify(src, dst):
    """Replace every specify block with the zero delay identity it stands for.

    Returns (blocks rewritten, delayed wires aliased).
    """
    text = pathlib.Path(src).read_text()

    for m in DELAY_RE.finditer(text):
        if any(float(v) != 0.0 for v in re.split(r"[,:]", m.group(1)) if v.strip()):
            raise SystemExit(
                f"{src} contains a non zero specify delay {m.group(0)!r}. The zero delay "
                f"rewrite would change the simulation, so this script needs reworking.")

    # Per module, collect the delayed_ wires and the ports they must alias.
    per_module = {}
    for chunk in re.split(r"(?=^module )", text, flags=re.M):
        m = MODULE_RE.match(chunk)
        if not m:
            continue
        ports = set()
        for pm in PORT_RE.finditer(chunk):
            ports |= {x.strip() for x in pm.group(1).split(",") if x.strip()}
        delayed = set(DELAYED_RE.findall(chunk))
        missing = delayed - ports
        if missing:
            raise SystemExit(
                f"{src}: module {m.group(1)} has delayed_{sorted(missing)[0]} with no "
                f"matching port to alias. The rewrite cannot be trusted.")
        per_module[m.group(1)] = sorted(delayed)

    out, skipping, blocks, aliased = [], False, 0, 0
    module = None
    for line in text.splitlines():
        m = MODULE_RE.match(line)
        if m:
            module = m.group(1)
        if ENDMODULE_RE.match(line):
            module = None
        if SPECIFY_RE.match(line):
            skipping = True
            blocks += 1
            out.append("\t// specify block rewritten by scripts/gatesim.py: every delay in")
            out.append("\t// the original was zero, so the delayed_ wires are plain aliases.")
            for w in per_module.get(module, []):
                out.append(f"\tassign delayed_{w} = {w};")
                aliased += 1
            continue
        if ENDSPECIFY_RE.match(line):
            skipping = False
            continue
        if not skipping:
            out.append(line)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text("\n".join(out) + "\n")
    return blocks, aliased


def sh(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--corner", default=pdk.SIGNOFF_CORNER)
    ap.add_argument("--scene", default="demo")
    ap.add_argument("--frame", type=int, default=1)
    args = ap.parse_args()

    pdk.check()
    netlist = OUT / f"netlist_flat_{args.corner}.v"
    if not netlist.exists():
        raise SystemExit(f"missing {netlist}; run scripts/synth_sg13g2.py first")

    vdir = pdk.STDCELL / "verilog"
    cells = SIM / "sg13g2_stdcell_zerodelay.v"
    blocks, aliased = rewrite_specify(vdir / "sg13g2_stdcell.v", cells)
    print(f"rewrote {blocks} zero delay specify blocks, aliased {aliased} delayed wires, "
          f"into {cells.relative_to(ROOT)}")

    scene = scenemod.build(args.scene)
    scene.write(SCENES)
    w, h = scene.dims()

    vvp = SIM / "tb_gate.vvp"
    print("compiling the gate level testbench ...", flush=True)
    t0 = time.time()
    r = sh(["iverilog", "-g2012", "-DGATE_LEVEL", "-I", str(ROOT / "tb"),
            "-o", str(vvp), "-s", "tb_vte_frame",
            str(vdir / "sg13g2_udp.v"), str(cells), str(netlist),
            str(ROOT / "tb" / "vte_cell_mem.sv"), str(ROOT / "tb" / "tb_vte_frame.sv")])
    noise = [ln for ln in (r.stdout + r.stderr).splitlines() if ln.strip()]
    if r.returncode != 0:
        print("\n".join(noise[:25]))
        raise SystemExit("gate level compile failed")
    print(f"  compiled in {time.time() - t0:.0f} s")

    print(f"simulating frame {args.frame} of scene {args.scene} at the gate level "
          f"({w}x{h}) ...", flush=True)
    t0 = time.time()
    r = sh(["vvp", str(vvp),
            f"+regs={SCENES / (args.scene + '.regs')}",
            f"+mem={SCENES / (args.scene + '.mem')}",
            f"+ppm={SIM / ('gate_' + args.scene)}",
            f"+width={w}", f"+height={h}",
            f"+skip={args.frame}", "+frames=1"])
    out = r.stdout + r.stderr
    (SIM / "gatesim.log").write_text(out)
    dt = time.time() - t0
    if "TEST_RESULT: PASS" not in out:
        print("\n".join(ln for ln in out.splitlines() if "WARNING" not in ln)[-3000:])
        raise SystemExit("gate level simulation failed")
    print(f"  simulated in {dt:.0f} s")

    print("comparing against the reference renderer ...", flush=True)
    r = sh([sys.executable, str(HERE / "check_frames.py"), "--scene", args.scene,
            "--prefix", f"gate_{args.scene}", "--dir", str(SIM),
            "--skip", str(args.frame), "--frames", "1"])
    print(r.stdout.strip())
    ok = "TEST_RESULT: PASS" in r.stdout
    if ok:
        print(f"the {args.corner} corner netlist renders the same pixels as the RTL")
    print("TEST_RESULT: PASS" if ok else "TEST_RESULT: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
