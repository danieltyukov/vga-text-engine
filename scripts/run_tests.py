#!/usr/bin/env python3
"""Build and run the whole vga_text_engine test suite.

Compiles one Icarus binary per testbench, generates the scene stimulus, then runs every
case. Independent cases run in parallel. A case passes only when its simulation prints
TEST_RESULT: PASS and, where a reference comparison applies, the checker agrees.

  lint       Verilator -Wall over the RTL, no warnings allowed
  timing     VESA conformance for every mode, checked against scripts/modes.py
  frame      pixel exact comparison of whole frames against scripts/model.py
  regs       register map walk
  blink      cursor and attribute blink period and duty in frames
  underrun   fetch port starvation, sync stability, and self healing alignment
"""

import argparse
import concurrent.futures
import pathlib
import re
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent

RTL = [
    "vte_modes_pkg.sv", "vte_pkg.sv", "vte_mode_lut.sv", "vte_sync2.sv", "vte_cdc_fifo.sv",
    "vte_frame_sync.sv", "vte_timing_gen.sv", "vte_glyph_rom.sv", "vte_shader.sv",
    "vte_fetch_engine.sv", "vte_axil_regs.sv", "vga_text_engine.sv",
]

TBS = {
    "tb_vte_frame": ["vte_cell_mem.sv", "tb_vte_frame.sv"],
    "tb_vte_timing": ["vte_cell_mem.sv", "tb_vte_timing.sv"],
    "tb_vte_regs": ["vte_cell_mem.sv", "tb_vte_regs.sv"],
    "tb_vte_blink": ["vte_cell_mem.sv", "tb_vte_blink.sv"],
    "tb_vte_underrun": ["vte_cell_mem.sv", "tb_vte_underrun.sv"],
}

# scene name -> (mode index, skip, frames)
FRAME_SCENES = ["demo", "palette", "attr", "font16", "font8", "cursor", "mode1024"]

SIM = ROOT / "results" / "sim"
SCENES = ROOT / "results" / "scenes"


def sh(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, **kw)


def rtl_paths():
    return [str(ROOT / "rtl" / f) for f in RTL]


def lint():
    r = sh(["verilator", "--lint-only", "-Wall", "--top-module", "vga_text_engine"] + rtl_paths())
    out = (r.stdout + r.stderr).strip()
    return (r.returncode == 0 and not out), out


def compile_tbs(jobs):
    SIM.mkdir(parents=True, exist_ok=True)
    results = {}
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as ex:
        futs = {}
        for top, files in TBS.items():
            cmd = ["iverilog", "-g2012", "-I", str(ROOT / "tb"), "-o", str(SIM / f"{top}.vvp"),
                   "-s", top] + rtl_paths() + [str(ROOT / "tb" / f) for f in files]
            futs[ex.submit(sh, cmd)] = top
        for f in concurrent.futures.as_completed(futs):
            top = futs[f]
            r = f.result()
            # Icarus prints informational "sorry:" notes about sensitivity inference.
            noise = [ln for ln in (r.stdout + r.stderr).splitlines()
                     if ln.strip() and "sorry:" not in ln]
            results[top] = (r.returncode == 0, "\n".join(noise))
    return results


def run_sim(top, plusargs):
    r = sh(["vvp", str(SIM / f"{top}.vvp")] + plusargs)
    out = r.stdout + r.stderr
    ok = "TEST_RESULT: PASS" in out
    return ok, out


def case_timing(mode):
    import modes
    m = modes.BY_INDEX[mode]
    out_file = SIM / f"timing_{mode}.txt"
    ok, log = run_sim("tb_vte_timing", [
        f"+mode={mode}", "+cols=80", "+rows=25",
        f"+hspol={m['h_pos']}", f"+vspol={m['v_pos']}", f"+out={out_file}"])
    if not ok:
        return False, log
    r = sh([sys.executable, str(HERE / "check_timing.py"), str(out_file)])
    return "TEST_RESULT: PASS" in r.stdout, log + r.stdout + r.stderr


def case_frame(scene):
    import modes
    import scenes as scenemod
    s = scenemod.build(scene)
    w, h = s.dims()
    del modes
    ok, log = run_sim("tb_vte_frame", [
        f"+regs={SCENES / (scene + '.regs')}", f"+mem={SCENES / (scene + '.mem')}",
        f"+ppm={SIM / scene}", f"+width={w}", f"+height={h}", "+skip=1", "+frames=1"])
    if not ok:
        return False, log
    r = sh([sys.executable, str(HERE / "check_frames.py"), "--scene", scene,
            "--dir", str(SIM), "--skip", "1", "--frames", "1"])
    return "TEST_RESULT: PASS" in r.stdout, log + r.stdout + r.stderr


def case_regs():
    return run_sim("tb_vte_regs", [])


def case_blink():
    scene = "blink"
    ok, log = run_sim("tb_vte_blink", [
        f"+regs={SCENES / 'blink.regs'}", f"+mem={SCENES / 'blink.mem'}",
        "+width=640", "+height=480", "+frames=16",
        "+ax=35", "+ay=72", "+bx=67", "+by=136", f"+out={SIM / 'blink.txt'}"])
    if not ok:
        return False, log
    r = sh([sys.executable, str(HERE / "check_blink.py"), "--data", str(SIM / "blink.txt"),
            "--regs", str(SCENES / f"{scene}.regs")])
    return "TEST_RESULT: PASS" in r.stdout, log + r.stdout + r.stderr


def case_underrun():
    ok, log = run_sim("tb_vte_underrun", [
        f"+regs={SCENES / 'demo.regs'}", f"+mem={SCENES / 'demo.mem'}",
        "+width=640", "+height=480", "+stall=500000", f"+ppm={SIM / 'demo_recover'}"])
    if not ok:
        return False, log
    idx = (SIM / "demo_recover_index.txt").read_text().strip()
    r = sh([sys.executable, str(HERE / "check_frames.py"), "--scene", "demo",
            "--prefix", "demo_recover", "--dir", str(SIM), "--skip", idx, "--frames", "1"])
    return "TEST_RESULT: PASS" in r.stdout, log + r.stdout + r.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-j", "--jobs", type=int, default=6)
    ap.add_argument("-v", "--verbose", action="store_true")
    ap.add_argument("--only", default=None, help="run only cases whose name contains this")
    args = ap.parse_args()

    sys.path.insert(0, str(HERE))

    t0 = time.time()
    print("== lint ==")
    ok, out = lint()
    if not ok:
        print(out)
        print("\nFAILED: Verilator lint is not clean")
        return 1
    print("verilator -Wall: clean")

    print("\n== scenes ==")
    r = sh([sys.executable, str(HERE / "scenes.py"), "-o", str(SCENES)])
    print(r.stdout.strip())
    if r.returncode != 0:
        print(r.stderr)
        return 1

    print("\n== compile ==")
    comp = compile_tbs(args.jobs)
    for top, (cok, log) in sorted(comp.items()):
        print(f"{'ok  ' if cok else 'FAIL'} {top}")
        if not cok or (log and args.verbose):
            print(log)
    if not all(c[0] for c in comp.values()):
        print("\nFAILED: testbench compilation")
        return 1

    # Derived from scripts/modes.py rather than hardcoded, so adding a video mode there
    # and in rtl/vte_modes_pkg.sv is enough to get a conformance case for it.
    import modes
    cases = []
    for m in [d["index"] for d in modes.MODES]:
        cases.append((f"timing/mode{m}", lambda m=m: case_timing(m)))
    for s in FRAME_SCENES:
        cases.append((f"frame/{s}", lambda s=s: case_frame(s)))
    cases.append(("regs", case_regs))
    cases.append(("blink", case_blink))
    cases.append(("underrun", case_underrun))

    if args.only:
        cases = [c for c in cases if args.only in c[0]]

    print(f"\n== run ({len(cases)} cases, {args.jobs} parallel) ==")
    passed = 0
    failed = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = {ex.submit(fn): name for name, fn in cases}
        for f in concurrent.futures.as_completed(futs):
            name = futs[f]
            cok, log = f.result()
            if cok:
                passed += 1
                print(f"PASS {name}")
                if args.verbose:
                    print("     " + "\n     ".join(log.strip().splitlines()))
            else:
                failed.append(name)
                print(f"FAIL {name}")
                print("     " + "\n     ".join(log.strip().splitlines()[-40:]))

    dt = time.time() - t0
    print(f"\n== summary ==")
    print(f"{passed} of {len(cases)} cases passed in {dt:.0f} s")
    if failed:
        print("failed: " + ", ".join(sorted(failed)))
        return 1
    print("ALL TESTS PASSED")
    return 0


if __name__ == "__main__":
    sys.exit(main())
