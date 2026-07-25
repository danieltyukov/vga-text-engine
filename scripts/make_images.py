#!/usr/bin/env python3
"""Regenerate every image in docs/img from simulation output.

Nothing here is a mock up. The screenshots are the RGB pins of the RTL sampled during
active video, written out as PPM by the testbenches and converted to PNG. The animation
is a run of consecutive simulated frames. The two SVGs are hand written markup, and the
area and timing charts come from real synthesis and static timing analysis against the
IHP SG13G2 PDK.

  make images     runs this with the default set
  --only NAME     limit the work to one target
"""

import argparse
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))

import model  # noqa: E402
import scenes as scenemod  # noqa: E402

SIM = ROOT / "results" / "sim"
SCENES = ROOT / "results" / "scenes"
IMG = ROOT / "docs" / "img"

RTL = [
    "vte_modes_pkg.sv", "vte_pkg.sv", "vte_mode_lut.sv", "vte_sync2.sv", "vte_cdc_fifo.sv",
    "vte_frame_sync.sv", "vte_timing_gen.sv", "vte_glyph_rom.sv", "vte_shader.sv",
    "vte_fetch_engine.sv", "vte_axil_regs.sv", "vga_text_engine.sv",
]

# Screenshot targets: scene name, output PNG stem, frame index to capture.
# The attribute showcase is captured on frame 2 because that scene deliberately runs
# both blink dividers at zero, so frame 1 lands in the invisible phase.
SHOTS = [
    ("demo", "screen_demo", 1),
    ("palette", "screen_palette", 1),
    ("attr", "screen_attributes", 2),
    ("font16", "screen_font_8x16", 1),
    ("font8", "screen_font_8x8", 1),
    ("mode1024", "screen_1024x768", 1),
]

CURSOR_FRAMES = 8


def sh(cmd):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
        raise SystemExit(f"command failed: {' '.join(str(c) for c in cmd)}")
    return r.stdout


def build_tb():
    SIM.mkdir(parents=True, exist_ok=True)
    sh(["iverilog", "-g2012", "-I", str(ROOT / "tb"), "-o", str(SIM / "tb_vte_frame.vvp"),
        "-s", "tb_vte_frame"] + [str(ROOT / "rtl" / f) for f in RTL]
       + [str(ROOT / "tb" / "vte_cell_mem.sv"), str(ROOT / "tb" / "tb_vte_frame.sv")])


def render_scene(scene, skip, frames):
    s = scenemod.build(scene)
    s.write(SCENES)
    w, h = s.dims()
    out = sh(["vvp", str(SIM / "tb_vte_frame.vvp"),
              f"+regs={SCENES / (scene + '.regs')}", f"+mem={SCENES / (scene + '.mem')}",
              f"+ppm={SIM / scene}", f"+width={w}", f"+height={h}",
              f"+skip={skip}", f"+frames={frames}"])
    if "TEST_RESULT: PASS" not in out:
        raise SystemExit(f"frame capture for {scene} failed:\n{out}")
    return w, h


def ppm_to_png(ppm, png, scale=1):
    from PIL import Image
    arr = model.read_ppm(ppm)
    im = Image.fromarray(arr, mode="RGB")
    if scale != 1:
        im = im.resize((im.width * scale, im.height * scale), Image.NEAREST)
    png.parent.mkdir(parents=True, exist_ok=True)
    im.save(png, optimize=True)
    return im.size


def do_screens():
    build_tb()
    for scene, stem, idx in SHOTS:
        w, h = render_scene(scene, idx, 1)
        size = ppm_to_png(SIM / f"{scene}_{idx}.ppm", IMG / f"{stem}.png")
        print(f"{stem}.png  {size[0]}x{size[1]}  from RTL frame {idx} of scene {scene}")


def do_font_compare():
    """The same sentences at both glyph heights, cropped out of two RTL frames.

    Both scenes place identical text on grid rows 9 to 15 and a caption on row 24, so
    the crops line up by construction. The captions are the engine's own glyphs, not an
    annotation added afterwards.
    """
    from PIL import Image
    build_tb()
    render_scene("font16", 1, 1)
    render_scene("font8", 1, 1)
    a = model.read_ppm(SIM / "font16_1.ppm")
    b = model.read_ppm(SIM / "font8_1.ppm")
    W = 528
    strips = [
        a[24 * 16:25 * 16, 0:W],   # 8x16 caption row
        a[9 * 16:16 * 16, 0:W],    # 8x16 sample rows
        None,                      # gap
        b[24 * 8:25 * 8, 0:W],     # 8x8 caption row
        b[9 * 8:16 * 8, 0:W],      # 8x8 sample rows
    ]
    gap, margin = 18, 8
    height = sum(gap if s is None else s.shape[0] for s in strips) + 2 * margin
    canvas = Image.new("RGB", (W, height), (0, 0, 0))
    y = margin
    for st in strips:
        if st is None:
            y += gap
            continue
        canvas.paste(Image.fromarray(st, mode="RGB"), (0, y))
        y += st.shape[0]
    canvas = canvas.resize((canvas.width * 2, canvas.height * 2), Image.NEAREST)
    IMG.mkdir(parents=True, exist_ok=True)
    canvas.save(IMG / "font_compare.png", optimize=True)
    print(f"font_compare.png  {canvas.width}x{canvas.height}  8x16 above, 8x8 below, "
          f"both cropped from RTL frames")


def do_cursor_gif():
    from PIL import Image
    build_tb()
    s = scenemod.build("cursor")
    s.write(SCENES)
    w, h = s.dims()
    out = sh(["vvp", str(SIM / "tb_vte_frame.vvp"),
              f"+regs={SCENES / 'cursor.regs'}", f"+mem={SCENES / 'cursor.mem'}",
              f"+ppm={SIM / 'cursor'}", f"+width={w}", f"+height={h}",
              "+skip=1", f"+frames={CURSOR_FRAMES}"])
    if "TEST_RESULT: PASS" not in out:
        raise SystemExit(f"cursor capture failed:\n{out}")
    frames = []
    for i in range(1, CURSOR_FRAMES + 1):
        arr = model.read_ppm(SIM / f"cursor_{i}.ppm")
        # Crop to the panel so the animation stays small and the cursor is obvious.
        frames.append(Image.fromarray(arr[16:230, 8:520], mode="RGB"))
    frames = [f.resize((f.width, f.height), Image.NEAREST) for f in frames]
    IMG.mkdir(parents=True, exist_ok=True)
    # 60 Hz frames, but a GIF that fast is unpleasant; hold each simulated frame for
    # 160 ms so the two frame cursor phase is visible.
    frames[0].save(IMG / "cursor_blink.gif", save_all=True, append_images=frames[1:],
                   duration=160, loop=0, optimize=True)
    print(f"cursor_blink.gif  {frames[0].width}x{frames[0].height}  "
          f"{len(frames)} consecutive RTL frames")


def do_synth_chart():
    """Real standard cell area per submodule, and the per mode timing closure chart."""
    out = sh([sys.executable, str(HERE / "synth_sg13g2.py")])
    print(out.strip().splitlines()[-1])
    out = sh([sys.executable, str(HERE / "sta_sg13g2.py")])
    print(out.strip().splitlines()[-1])


def do_svg():
    out = sh([sys.executable, str(HERE / "make_svg.py")])
    print(out.strip())
    out = sh([sys.executable, str(HERE / "make_fsm_svg.py")])
    print(out.strip())


def do_layout():
    """Re-render the layout views from an existing hardened run.

    This does not re-run place and route, which takes far longer than everything else here
    put together. Run `make harden` first if there is no run to render.
    """
    if not sorted((ROOT / "runs").glob("*/final/gds/*.gds")):
        print("no hardened run found under runs/, skipping the layout render")
        print("run `make harden` first")
        return
    out = sh([sys.executable, str(HERE / "pnr_report.py")])
    print("\n".join(out.strip().splitlines()[-4:]))


TARGETS = {
    "screens": do_screens,
    "font": do_font_compare,
    "cursor": do_cursor_gif,
    "synth": do_synth_chart,
    "svg": do_svg,
    "layout": do_layout,
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", default=None, choices=sorted(TARGETS))
    args = ap.parse_args()
    names = [args.only] if args.only else list(TARGETS)
    for n in names:
        print(f"== {n} ==")
        TARGETS[n]()
    print("\nall images regenerated into docs/img")


if __name__ == "__main__":
    sys.exit(main())
