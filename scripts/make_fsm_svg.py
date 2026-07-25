#!/usr/bin/env python3
"""Render the frame synchronisation handshake as a state diagram.

  docs/img/fsm_frame_sync.svg   the pixel side state machine from rtl/vte_frame_sync.sv,
                                with the register side phases shown alongside so the two
                                halves of the handshake can be read together

Transcribed by hand from the RTL rather than extracted by a tool: the useful thing about
this diagram is which side of the handshake owns each step, and no extractor knows that.

A gate level schematic of the mapped synchroniser was tried and dropped. netlistsvg has no
cell shapes for the sg13g2 library, so it renders the flip flops as bare clipped text with
no wiring, which is worse than no figure.
"""

import argparse
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
OUT = ROOT / "synth" / "out"

# Transcribed from the pstate_e case statement in rtl/vte_frame_sync.sv.
DOT = r"""digraph frame_sync {
  rankdir=LR;
  bgcolor="#f8fafc";
  fontname="Helvetica";
  labelloc=t;
  labeljust=l;
  label=<<b>vte_frame_sync</b>: the once per frame handshake, pixel side states in blue,<br align="left"/>register side phases in amber. Runs entirely inside vertical blanking.<br align="left"/>>;
  fontsize=13;
  node [fontname="DejaVu Sans Mono", fontsize=11, style="filled,rounded",
        shape=box, color="#1d4ed8", fillcolor="#dbeafe", penwidth=1.6, margin="0.16,0.10"];
  edge [fontname="Helvetica", fontsize=9.5, color="#334155", penwidth=1.2];

  P_IDLE   [label="P_IDLE\nhold=0\ncfg_valid=0"];
  P_REQ    [label="P_REQ\nhold=1"];
  P_LATCH  [label="P_LATCH\ncfg_pix <= shadow\ncfg_valid=1"];
  P_DRAIN  [label="P_DRAIN\ndrain=1"];
  P_REL    [label="P_REL\nhold=0"];
  P_RUN    [label="P_RUN\ncounters running"];

  P_IDLE  -> P_REQ   [label="en_pix"];
  P_REQ   -> P_LATCH [label="held seen"];
  P_LATCH -> P_DRAIN [label="always"];
  P_DRAIN -> P_REL   [label="fifo empty"];
  P_REL   -> P_RUN   [label="held released"];
  P_RUN   -> P_REQ   [label="frame_edge\nlast active pixel"];

  P_REQ   -> P_IDLE  [label="en_pix low", style=dashed, constraint=false];
  P_RUN   -> P_IDLE  [label="en_pix low", style=dashed, constraint=false];

  subgraph cluster_reg {
    label=<<b>register side</b>, driven by the hold line>;
    fontsize=11;
    fontname="Helvetica";
    color="#b45309";
    bgcolor="#fffbeb";
    style=rounded;
    node [color="#b45309", fillcolor="#fef3c7"];
    R0 [label="cnt 0,1\nshadow <= live"];
    R2 [label="cnt 2\nshadow frozen\nstatus sampled"];
    R3 [label="cnt 3\nheld <= 1"];
    R4 [label="hold released\nfetch restarts\nat cell zero"];
    R0 -> R2 -> R3 -> R4;
  }

  P_REQ  -> R0 [label="hold", style=dotted, color="#7c3aed", constraint=false];
  R3     -> P_LATCH [label="held", style=dotted, color="#7c3aed", constraint=false];
  P_REL  -> R4 [label="hold released", style=dotted, color="#7c3aed", constraint=false];
}
"""


def make_fsm(out):
    if shutil.which("dot") is None:
        raise SystemExit("graphviz dot is not on PATH")
    dot_path = OUT / "fsm_frame_sync.dot"
    dot_path.parent.mkdir(parents=True, exist_ok=True)
    dot_path.write_text(DOT)
    r = subprocess.run(["dot", "-Tsvg", str(dot_path), "-o", str(out)],
                       capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stderr)
        raise SystemExit("dot failed")
    print(f"wrote {out}")



def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", default=str(ROOT / "docs" / "img"))
    args = ap.parse_args()
    out = pathlib.Path(args.outdir)
    out.mkdir(parents=True, exist_ok=True)
    make_fsm(out / "fsm_frame_sync.svg")
    return 0


if __name__ == "__main__":
    sys.exit(main())
