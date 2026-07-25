# Adapting vga_text_engine

Four changes people actually want to make, in increasing order of how much they touch:
resize the text grid, change the DAC widths, add a video mode, swap the font. Each section
lists every file that has to move and what fails if one is missed.

The general rule: the mode table is a package, the font is generated from a Python source
of truth, and everything the software can change is a register. Anything outside those three
is a code change, and the test suite is written so a half finished code change fails rather
than renders something subtly wrong.

## Resize the text grid

### At runtime, no rebuild

Write `GEOM` at offset `0x0C`: columns in `[7:0]`, rows in `[23:16]`. The change lands
atomically on the next frame boundary. Nothing else needs touching, and the reset value is
80 by 30.

Two rules govern what appears:

- **Display is clamped.** Columns are clamped to `h_active / 8` and rows to
  `v_active / glyph_h`, so a grid that cannot fit is truncated rather than allowed to run
  the prefetch window past the end of a line. `MODEDIM` at `0x24` reports the active size
  the pixel domain actually latched, which is how software can compute the limits without a
  mode table of its own.
- **The buffer stride is not clamped.** The word index stays `row * GEOM.COLS + col` at the
  programmed `COLS`, not the clamped one. So a 200 column grid on a 640x480 screen shows the
  leftmost 80 cells of each 200 cell row, which is exactly what you want for a wide virtual
  console that scrolls horizontally by moving `BASE`.

Both clamps are computed identically in `vte_timing_gen` and `vte_fetch_engine` from the
same frozen snapshot, which is what keeps the elastic buffer index mapping aligned. If you
change one, change both, or the display shears.

### Beyond 255 columns or rows

`GEOM` gives each field 8 bits, so 255 is the ceiling. Widening it is mechanical but touches
five places:

1. `rtl/vte_pkg.sv`: the `cols` and `rows` fields of `cfg_t`.
2. `rtl/vte_axil_regs.sv`: the `GEOM` read and write paths and the reset value.
3. `rtl/vte_timing_gen.sv` and `rtl/vte_fetch_engine.sv`: the `[8:0]` clamp arithmetic, one
   bit wider than the field so the comparison against the limit cannot overflow.
4. `scripts/model.py`: the reference renderer's own field decode.
5. The register test's walking patterns in `tb/tb_vte_regs.sv`, which pin down the
   implemented bit mask and will fail on the new reserved bits.

`make test` catches 1 to 4 by pixel comparison and 5 by an explicit mask check.

### A glyph width other than 8

This is the one invasive change in the design, and it is worth knowing why before starting.
Eight pixels per cell is assumed in five separate mechanisms: the three bit phase counters
in `vte_timing_gen`, the shift of `hcnt` that yields a column index, the eight pixel
prefetch window and its placement inside the back porch, the one byte per glyph row ROM
word, and the `<< 3` in the fetch address arithmetic. A width of 16 is a rewrite of the
pixel pipeline rather than a parameter change. `vte_pkg::GlyphW` names the constant where
the prefetch lead is expressed, so the intent is documented, but changing it on its own only
moves the prefetch window and leaves the phase counters and the address arithmetic behind.

## Change the DAC widths

`RedW`, `GreenW` and `BlueW` are top level parameters, any value from 1 to 12, independently.
The palette is RGB444 internally; each nibble is expanded by replicating it four times into
a 16 bit vector and taking the top `RedW` bits. That is exact at 4, 8 and 12 bits and
monotonic in between.

```systemverilog
vga_text_engine #(
    .RedW  (5),   // 5:6:5 into an RGB565 display bridge
    .GreenW(6),
    .BlueW (5)
) i_vte (...);
```

Out of range values fail at elaboration with `$fatal` from `vte_shader`, so a typo does not
silently truncate.

What the tests do and do not cover: `make lint-config` elaborates and lints the whole design
at RGB444 with a 64 entry buffer, so the parameterisation cannot rot. The frame comparison
suite is fixed at 8 bits per channel, because `scripts/model.py` expands to 8 bits and the
captured frames are 8 bit PPM. To get pixel exact checking at another width, change
`expand444` in `scripts/model.py` and the PPM writer in `tb/tb_vte_frame.sv` together; until
then, treat a non default width as linted and elaborated rather than pixel verified.

## Add a video mode

The timing table is a package precisely so this is small. Adding 1280x1024 at 60 Hz, VESA
DMT, 108 MHz pixel clock:

**1. `rtl/vte_modes_pkg.sv`.** One localparam, field order as commented in the file, plus
the row count:

```systemverilog
// 1280x1024 @ 60 Hz, 108.000 MHz pixel clock. H total 1688, V total 1066.
localparam logic [ModeW-1:0] Mode1280x1024x60 = {
  12'd1280, 12'd48, 12'd112, 12'd248, 12'd1024, 12'd1, 12'd3, 12'd38, 1'b1, 1'b1
};
```

`NumModes` becomes 5. `ModeSelW` is 4 bits, so there is room for 16 modes before the
selector has to grow; `CTRL.MODE` is the same 4 bits and an index past the end of the table
falls back to mode 0.

**2. The summary constants in the same file.** `MaxHTotal`, `MaxVTotal` and
`MinVBlankPixels` are literals because Yosys cannot evaluate package functions, and
`vte_mode_lut` re-derives all three from the table at elaboration time and `$fatal`s if they
disagree. 1280x1024 raises `MaxHTotal` to 1688 and `MaxVTotal` to 1066; its vertical
blanking is `(3 + 38) * 1688 = 69208` pixel clocks, longer than the current 29568 minimum,
so `MinVBlankPixels` stays. Get one wrong and elaboration stops with the expected and actual
value printed. This is the check that makes the whole edit safe.

**3. `rtl/vte_mode_lut.sv`.** One case arm in the lookup:

```systemverilog
vte_modes_pkg::ModeSelW'(4): row = vte_modes_pkg::Mode1280x1024x60;
```

and three small edits inside the `p_table_check` block at the bottom of the same file, which
is the elaboration time check that re-derives the summary constants: a matching arm in its
own `case (i)` so index 4 does not fall into the `default`, one bit added to each of the
`exp_hpos` and `exp_vpos` polarity vectors, and the `i[1:0]` slice that indexes them widened
to `i[2:0]`. Miss the arm and the check compares mode 4 against mode 3's numbers and stops
elaboration with both values printed, which is the intended failure mode rather than a
silent wrong answer.

**4. `scripts/modes.py`.** The same numbers again, written from the VESA specification rather
than copied from the RTL. This duplication is deliberate: the conformance test measures the
pins against this file, so a transcription error in either place fails instead of cancelling
out. Copying the RTL row into here defeats the entire test.

**5. Nothing else.** `scripts/run_tests.py` builds a `timing/modeN` case for every entry in
`modes.MODES`, and `scripts/sta_sg13g2.py` times every entry at its own pixel clock, so both
pick the new mode up automatically. `make test` will now run 15 cases and the timing report
will have a fifth row.

**6. The README table**, if you are keeping the documentation honest, and a note on whether
the mode closes timing. At the slow corner this design's pixel domain closes at 95.96 MHz,
so a 108 MHz mode would be listed as not met at that corner and would need a faster process
corner, a place and route buffer tree, or a pipeline stage in the shader. The table in the
README is a claim about the built design, not a wish list.

One thing outside this repository: the pixel clock itself. `clk_pix_i` must be the exact
pixel clock of the selected mode. On an FPGA that is a PLL or MMCM setting per mode; on a
chip it is whatever the surrounding SoC provides.

## Swap the font ROM

### Different bitmaps, same ROM structure

`scripts/font_data.py` is the single source of truth for both banks. Edit it, then:

```
make font     # regenerates rtl/vte_glyph_rom.sv
make test     # every frame comparison re-renders against the new bitmaps
```

The generated file is marked `GENERATED FILE. Do not edit.` and the tests pick up the change
on both sides at once, because the reference renderer imports the same Python module the
generator does. That means a font change cannot break the frame comparisons, and it also
means the frame comparisons cannot catch a mistake in the bitmap itself; look at
`make images` output for that.

Constraints the rest of the design imposes: exactly 128 glyphs per bank (`vte_shader`
asserts `GlyphCount == 128`, because bit 7 of the character code is the out of range test),
8 pixels per row, most significant bit leftmost, and both an 8 row and a 16 row bank present.
The banks are laid out as word `code * 16 + row` for 8x16 and `2048 + code * 8 + row` for
8x8.

### A real memory instead of logic

`rtl/vte_glyph_rom.sv` is 3072 bytes of constant data mapped to gates, which is 8.5 percent
of the standard cell area, because a 130 nm standard cell library has no ROM primitive. The
module is deliberately a thin wrapper so it can be replaced:

```systemverilog
module vte_glyph_rom (
    input  logic                         clk_i,
    input  logic [vte_pkg::RomAddrW-1:0] addr_i,
    output logic [                  7:0] data_o
);
```

The only contract is **one cycle of registered read latency**, no enable, no stall. The
shader drives the address one phase before it needs the data and holds it for the eight
display pixels that follow, so a synchronous single port memory drops straight in:

- **FPGA.** The body is a synchronous read out of a byte array with an `initial` block,
  which is the pattern the vendor tools infer block RAM from. If you would rather
  instantiate a primitive explicitly, `scripts/gen_glyph_rom.py` is short and templated:
  point it at a different `HEADER` and `FOOTER` to emit a `$readmemh` image plus a wrapper
  instead of inline assignments.
- **ASIC.** Swap the body for a 3072x8 single port ROM or SRAM macro from the PDK. The
  address is stable for eight pixel clocks, so the macro's setup requirement is easy to
  meet even at 65 MHz.
- **Fewer glyphs.** Dropping to one bank halves it, but the ROM depth and `CTRL.FONT_H16`
  both stop meaning what they mean, so this is a design change rather than a swap.

`make gatesim` is the check that a replacement really behaves: it renders a whole frame from
the mapped netlist and diffs 307 200 pixels against the reference renderer.

## Where the numbers come from

Every figure quoted in the README is produced by a script and committed as a text report, so
after any of the above you can regenerate the evidence rather than editing prose:

| target | report | what it measures |
|---|---|---|
| `make test` | test output | 14 cases, pixel exact against an independent renderer |
| `make formal` | `docs/formal_report.txt` | sync generator properties, all reachable states |
| `make synth` | `docs/pdk_area_report.txt` | real standard cell area in um2 on the IHP PDK |
| `make sta` | `docs/sta_report.txt` | per mode and per corner timing, synthesis level |
| `make gatesim` | test output | the mapped netlist renders the reference frame |
| `make harden` + `make harden-report` | `docs/pnr_report.txt` | post route die area, DRC, LVS |
| `make images` | `docs/img/*` | every figure, re-simulated from scratch |
