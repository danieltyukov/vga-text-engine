#!/usr/bin/env python3
"""Check the cursor and text blink duty and period, in frames.

The testbench records, per frame, whether a pixel inside the cursor cell and a pixel
inside a blinking glyph were lit. Each phase must toggle every DIV+1 frames, giving a
period of 2*(DIV+1) frames at 50 percent duty, starting in the visible phase.

The final run is ignored because the recording usually stops part way through it.
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import model  # noqa: E402


def runs(seq):
    out = []
    cur = seq[0]
    n = 0
    for v in seq:
        if v == cur:
            n += 1
        else:
            out.append((cur, n))
            cur = v
            n = 1
    out.append((cur, n))
    return out


def check(name, seq, div):
    want = div + 1
    r = runs(seq)
    fails = []
    if r[0][0] != 1:
        fails.append(f"{name}: starts in the off phase, expected the visible phase")
    # Drop the trailing run, which the recording may have cut short.
    body = r[:-1]
    if len(body) < 2:
        fails.append(f"{name}: only {len(r)} run(s) recorded, need at least three")
        return fails, r
    for lvl, n in body:
        if n != want:
            fails.append(f"{name}: {'on' if lvl else 'off'} run of {n} frames, "
                         f"expected {want} (DIV+1)")
    levels = [lvl for lvl, _ in r]
    for a, b in zip(levels, levels[1:]):
        if a == b:
            fails.append(f"{name}: two consecutive runs at the same level")
    return fails, r


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--regs", required=True)
    args = ap.parse_args()

    regs = model.parse_regs(args.regs)
    cfg = model.Config(regs)

    rows = [line.split() for line in pathlib.Path(args.data).read_text().splitlines()
            if line.strip()]
    a = [int(r[1]) for r in rows]
    b = [int(r[2]) for r in rows]

    fails = []
    fa, ra = check("cursor", a, cfg.cur_div)
    fb, rb = check("text blink", b, cfg.txt_div)
    fails += fa + fb

    print(f"cursor    CUR_DIV={cfg.cur_div} period={2 * (cfg.cur_div + 1)} frames "
          f"runs={[(int(l), n) for l, n in ra]}")
    print(f"attribute TXT_DIV={cfg.txt_div} period={2 * (cfg.txt_div + 1)} frames "
          f"runs={[(int(l), n) for l, n in rb]}")

    # The reference model predicts each frame's phase from the frame index, so it also
    # has to agree frame by frame.
    for i, (fa_, fb_) in enumerate(zip(a, b)):
        want_a = 1 if cfg.phase(cfg.cur_div, i) else 0
        want_b = 1 if cfg.phase(cfg.txt_div, i) else 0
        if fa_ != want_a:
            fails.append(f"frame {i}: cursor lit={fa_}, model says {want_a}")
        if fb_ != want_b:
            fails.append(f"frame {i}: blink lit={fb_}, model says {want_b}")

    for f in fails[:20]:
        print(f"FAIL {f}")
    print("TEST_RESULT: PASS" if not fails else "TEST_RESULT: FAIL")
    return 0 if not fails else 1


if __name__ == "__main__":
    sys.exit(main())
