#!/usr/bin/env python3
"""Compare captured RTL frames against the Python reference renderer, pixel for pixel.

Usage:
  check_frames.py --scene NAME --dir RESULTS [--skip N] [--frames N]

Reads results/scenes/NAME.regs and NAME.mem, renders each captured frame index with
scripts/model.py and diffs it against the PPM the testbench wrote. Any single differing
byte is a failure; the first few offending pixels are printed to make debugging quick.
"""

import argparse
import pathlib
import sys

import numpy as np

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import model  # noqa: E402


def compare(scene, scene_dir, out_dir, skip, frames, verbose=True):
    regs = model.parse_regs(pathlib.Path(scene_dir) / f"{scene}.regs")
    mem = model.parse_mem(pathlib.Path(scene_dir) / f"{scene}.mem")
    ok = True
    for i in range(frames):
        idx = skip + i
        ppm = pathlib.Path(out_dir) / f"{scene}_{idx}.ppm"
        if not ppm.exists():
            print(f"FAIL {scene} frame {idx}: {ppm} was not produced")
            ok = False
            continue
        got = model.read_ppm(ppm)
        exp = model.render(regs, mem, idx)
        if got.shape != exp.shape:
            print(f"FAIL {scene} frame {idx}: shape {got.shape} vs model {exp.shape}")
            ok = False
            continue
        bad = (got != exp).any(axis=2)
        n = int(bad.sum())
        if n:
            ok = False
            ys, xs = np.nonzero(bad)
            print(f"FAIL {scene} frame {idx}: {n} of {bad.size} pixels differ")
            for k in range(min(6, len(ys))):
                y, x = int(ys[k]), int(xs[k])
                print(f"     ({x},{y}) rtl={tuple(int(v) for v in got[y, x])} "
                      f"model={tuple(int(v) for v in exp[y, x])}")
        elif verbose:
            print(f"pass {scene} frame {idx}: {bad.size} pixels identical "
                  f"({exp.shape[1]}x{exp.shape[0]})")
    return ok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", required=True)
    ap.add_argument("--scene-dir", default="results/scenes")
    ap.add_argument("--dir", default="results/sim")
    ap.add_argument("--skip", type=int, default=1)
    ap.add_argument("--frames", type=int, default=1)
    args = ap.parse_args()
    ok = compare(args.scene, args.scene_dir, args.dir, args.skip, args.frames)
    print("TEST_RESULT: PASS" if ok else "TEST_RESULT: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
