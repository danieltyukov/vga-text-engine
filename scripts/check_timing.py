#!/usr/bin/env python3
"""Check measured VGA timing against the VESA table in scripts/modes.py.

The testbench measures the pins over a whole frame and reports minima and maxima. This
script asserts every count numerically and confirms the sync polarities from the raw
level run lengths: a positive sync has a high run equal to the sync width, a negative
sync has a low run equal to it.
"""

import argparse
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import modes  # noqa: E402


def load(path):
    out = {}
    for line in pathlib.Path(path).read_text().splitlines():
        if not line.strip():
            continue
        k, v = line.split()
        out[k] = int(v)
    return out


def check_mode(path):
    m_meas = load(path)
    idx = m_meas["mode"]
    m = modes.BY_INDEX[idx]
    ht = modes.h_total(m)
    fails = []

    def eq(name, got, want):
        if got != want:
            fails.append(f"{name}: measured {got}, VESA {want}")

    # Sync polarity falls out of which level run matches the sync width.
    if m["h_pos"]:
        eq("hsync pulse (high run)", m_meas["h_hi_min"], m["h_sync"])
        eq("hsync gap (low run)", m_meas["h_lo_min"], ht - m["h_sync"])
    else:
        eq("hsync pulse (low run)", m_meas["h_lo_min"], m["h_sync"])
        eq("hsync gap (high run)", m_meas["h_hi_min"], ht - m["h_sync"])

    # Constant across every line of the frame.
    eq("hsync high run jitter", m_meas["h_hi_max"], m_meas["h_hi_min"])
    eq("hsync low run jitter", m_meas["h_lo_max"], m_meas["h_lo_min"])
    eq("h_back jitter", m_meas["h_back_max"], m_meas["h_back_min"])
    eq("h_active jitter", m_meas["h_active_max"], m_meas["h_active_min"])
    eq("h_front jitter", m_meas["h_front_max"], m_meas["h_front_min"])

    eq("h_back", m_meas["h_back_min"], m["h_back"])
    eq("h_active", m_meas["h_active_min"], m["h_active"])
    eq("h_front", m_meas["h_front_min"], m["h_front"])
    eq("h_total", m_meas["h_hi_min"] + m_meas["h_lo_min"], ht)

    eq("v_sync", m_meas["v_sync"], m["v_sync"])
    eq("v_back", m_meas["v_back"], m["v_back"])
    eq("v_active", m_meas["v_active"], m["v_active"])
    eq("v_front", m_meas["v_front"], m["v_front"])
    eq("v_total", m_meas["v_sync"] + m_meas["v_back"] + m_meas["v_active"] + m_meas["v_front"],
       modes.v_total(m))

    return m, fails


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    args = ap.parse_args()
    ok = True
    for f in args.files:
        m, fails = check_mode(f)
        if fails:
            ok = False
            print(f"FAIL {m['name']}")
            for x in fails:
                print(f"     {x}")
        else:
            print(f"pass {m['name']}: "
                  f"h {m['h_active']}+{m['h_front']}+{m['h_sync']}+{m['h_back']}"
                  f"={modes.h_total(m)} {'+' if m['h_pos'] else '-'}  "
                  f"v {m['v_active']}+{m['v_front']}+{m['v_sync']}+{m['v_back']}"
                  f"={modes.v_total(m)} {'+' if m['v_pos'] else '-'}  "
                  f"{modes.refresh_hz(m):.2f} Hz")
    print("TEST_RESULT: PASS" if ok else "TEST_RESULT: FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
