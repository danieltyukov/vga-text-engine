# vga_text_engine design notes

Why the microarchitecture is the way it is, the arithmetic behind the elastic buffer,
and the verification plan. The register map and the interface contracts live in the
[README](../README.md); this document is about the decisions.

## Contents

- [Shape of the problem](#shape-of-the-problem)
- [Microarchitecture decisions](#microarchitecture-decisions)
- [Elastic buffer sizing](#elastic-buffer-sizing)
- [Clock domain crossing](#clock-domain-crossing)
- [Verification plan](#verification-plan)
- [What the silicon says](#what-the-silicon-says)
- [SystemVerilog subset](#systemverilog-subset)
- [Known limitations](#known-limitations)

## Shape of the problem

A text mode display controller has a hard real time obligation and a soft one. The hard
obligation is the sync generator: a monitor loses lock if a single line comes out the
wrong length, so the horizontal and vertical counters must never stall for any reason.
The soft obligation is the picture: if the cell data is late the frame is wrong, which is
ugly but recoverable.

Almost every design decision below follows from keeping those two obligations separate.
The sync generator is a free running counter pair that depends on nothing but the pixel
clock and a latched mode. Everything that can be late lives behind an elastic buffer,
and when it is late the display degrades and then repairs itself rather than taking the
sync with it.

## Microarchitecture decisions

### A line is walked SYNC, BACK PORCH, ACTIVE, FRONT PORCH

The conventional ordering puts active video first. Walking the sync pulse first instead
puts the whole blanking gap that precedes active video into one contiguous run at the low
end of the horizontal counter, which matters because the character pipeline needs a
prefetch window immediately before the first active pixel.

With this ordering the window is a plain subtraction: `h_act_start - 8`. The smallest
`h_act_start` in the mode table is 144 (640x480, 96 sync plus 48 back porch), so the
subtraction can never underflow and the window never wraps around the end of a line.
With active video first, the same window would straddle the end of the previous line and
every comparison would need a modulo.

The cost is that the reported `hcnt` does not match the convention used in most VGA
articles. The testbench measures the pins rather than the counter, so nothing in the
verification depends on the internal numbering.

### Three pipeline stages inside one character cell

A character cell is 8 pixels wide, which is an 8 clock budget in the pixel domain. The
pipeline spends it like this:

| phase | action | register |
|---|---|---|
| 5 | pop the elastic buffer, capture the cell | `cell_q` |
| 6 | drive the glyph ROM address | `rom_addr_q` |
| 7 | capture the attribute half of the cell | `attr_q` |

The point of spreading it out is the ROM. Giving the lookup a whole clock of latency
means the glyph array can be a synchronous read memory, which maps to one block RAM on an
FPGA instead of a 24 Kbit mux tree. The alternative, a combinational ROM read in the same
cycle as the address, would work in simulation and cost real area in hardware.

`rom_addr_q` is only rewritten once per cell group, so the ROM output holds its value for
the whole eight pixel display window without an extra holding register. That is worth
being precise about, because it is the one place where the pipeline depends on a timing
argument rather than on structure:

- `rom_addr_q` takes the address of cell `w` at the clock edge ending phase 6 of window
  `w`, and holds it until the edge ending phase 6 of window `w+1`.
- The ROM output therefore takes the bits of cell `w` at the edge ending phase 7 of
  window `w` and holds them until the edge ending phase 7 of window `w+1`.
- Cell `w` is displayed during phases 0 to 7 of window `w+1`, which sits exactly inside
  that interval.

### Re-read a text row once per scanline instead of caching it

An 8x16 glyph row covers 16 scanlines, so the naive reading is that a line buffer would
cut the fetch traffic by 16. The engine re-reads the row instead, and the reason is that
the traffic was never the problem: the worst case in the mode table needs 6.19 million
cells per second against a port that delivers 50 million (see below). Trading an 8x
bandwidth margin for a line buffer of up to 128 cells plus its addressing would be
paying real area for headroom that is already there.

What re-reading buys is a much smaller and more obviously correct fetch engine: two
address registers, three counters, and no cache coherency question when software rewrites
a cell mid frame. It also makes the producer and the consumer symmetric, which is what
the alignment invariant below rests on.

### 32 bit cells rather than 16

A 16 bit cell would halve the buffer memory and the fetch traffic, and it is what the
monochrome designs this one is measured against use. It does not have room for what this
engine renders: 8 bits of glyph code, 4 bits of foreground, 4 bits of background and
three effect bits is 19 bits.

Something had to give: a 3 bit background like classic VGA, or dropping two of the three
effect bits, or a wider cell. Given that the bandwidth headroom is 8x and the buffer is
32 cells either way, the wider cell is the cheapest of the three. Only the 19 meaningful
bits cross into the elastic buffer, so the extra width costs memory in the cell buffer
and nothing inside the engine.

### The alignment invariant, and why an underrun breaks it

The pixel pipeline pops exactly one cell per eight active pixels inside the text grid,
which is `cols * rows * glyph_h` pops per frame. The fetch engine issues exactly the same
count. Both derive `cols` and `rows` by clamping the same frozen configuration snapshot
against the same mode table, using the same expression in
`vte_timing_gen` and `vte_fetch_engine`. So the mapping from buffer index to screen
position is fixed by construction, with no per-scanline synchronisation, no line start
signal, and no way for the two sides to disagree about where they are.

An underrun is the one event that breaks it. When the buffer is empty at the pop point
the pipeline cannot advance the read pointer, so it substitutes a blank cell and the
producer is now one cell ahead of the consumer for the rest of the frame. Without a
repair mechanism that shift would be permanent: a momentary memory stall would leave the
text displaced by one character until the next reset.

The repair is the drain phase of the frame handshake. Once per frame, inside vertical
blanking and with the producer parked, the pixel side pops the buffer until it reports
empty. Both pointers are then at a known relationship, the producer restarts from cell
zero, and the next frame is correct regardless of how much drift the previous one
accumulated. The underrun test proves this by comparing a post recovery frame against
the reference model pixel for pixel.

### One outstanding fetch, with a reserved slot

The fetch port allows one read in flight and permits a new request in the same cycle the
previous response returns, so a zero wait state target sustains one cell per clock with
two signals of handshake and no reordering.

The subtlety is the buffer full test. Gating requests on the buffer merely not being full
is wrong: a request can be accepted while there is one slot free, and by the time its
response arrives the response to the *previous* request has taken that slot, so the write
lands on a full buffer and is dropped. A dropped cell shifts the rest of the frame by one
character, which is exactly the failure mode the alignment invariant is supposed to make
impossible.

So the engine gates on `wr_afull_o`, which the buffer raises when fewer than two slots
are free: room for the response already owed plus the response the new request will
produce. The occupancy the almost full test uses is the write domain estimate, which
compares against a read pointer up to two write clocks stale and therefore never
under-reports the level. The error is in the direction of holding back, which is the safe
one.

This bug was in the first version of the design and was caught by the pixel exact frame
comparison, which is a good argument for having a golden model rather than eyeballing a
screenshot.

### Show ahead buffer read

The buffer presents the head of the queue continuously and advances on a pop, rather than
returning data a cycle after the read is asserted. The pipeline has a fixed eight clock
budget per cell and no spare stage to absorb a read latency, so a registered output would
have to be compensated by moving the pop a phase earlier, which puts the pop and the ROM
address in adjacent phases and leaves nothing between them.

### RGB444 palette, expanded by replication

Palette entries are 12 bits and the DAC width is a parameter from 1 to 12 bits per
channel. The expansion takes the top `W` bits of the nibble repeated four times, which
is exact at widths 4, 8 and 12 (a 4 bit nibble becomes `v`, `v*17` and `v*273`) and
monotonic at every width in between. Zero maps to zero and full scale maps to full scale,
which a plain left shift would not do.

Twelve bits per entry rather than 24 halves the configuration bundle, and the bundle is
duplicated three times across the two clock domains, so the saving is 288 flip flops.
A text mode display gains very little from more than 4 bits per channel.

### Two independently drawn fonts

The 8x8 and 8x16 banks are separate designs, not one scaled from the other. Deriving the
16 row bank by doubling the 8 row one is a tempting shortcut and it looks like a
shortcut: doubled rows give 2 pixel horizontal strokes on glyphs whose vertical strokes
are still 2 pixels, so the weight goes wrong and the descenders have nowhere to go. The
8x16 bank is drawn with an 11 row cap height, a 7 row x-height and real 3 row
descenders.

Both banks live in the same ROM at the same time, 8x16 at `code * 16 + row` in words 0 to
2047 and 8x8 at `2048 + code * 8 + row` in words 2048 to 3071, so switching
`CTRL.FONT_H16` costs nothing and needs no reload. The box drawing pieces put the
horizontal rule on the vertical centre rows of whichever cell they are in and the
vertical rule on columns 3 and 4, so frames join up at either height.

`scripts/font_data.py` is the single source of truth. It feeds the generated
SystemVerilog ROM and the Python reference renderer, so the hardware and the model can
never disagree about a bitmap; they can only disagree about the rendering, which is what
the comparison is testing.

## Elastic buffer sizing

### Demand

The pipeline consumes one cell per eight pixel clocks while it is inside the text grid.
Two rates matter. The instantaneous rate during the prefetch window is what the buffer
has to keep up with. The frame average is what the memory system sees.

Three rates matter, at the widest grid each mode supports:

| mode | pixel clock | cols | line time | instantaneous | sustained per active line | frame average |
|---|---|---|---|---|---|---|
| 640x480@60 | 25.175 MHz | 80 | 31.78 us | 3.15 Mcell/s | 2.52 Mcell/s | 2.30 Mcell/s |
| 800x600@60 | 40.000 MHz | 100 | 26.40 us | 5.00 Mcell/s | 3.79 Mcell/s | 3.57 Mcell/s |
| 1024x768@60 | 65.000 MHz | 128 | 20.68 us | 8.13 Mcell/s | 6.19 Mcell/s | 5.90 Mcell/s |
| 720x400@70 | 28.322 MHz | 90 | 31.78 us | 3.54 Mcell/s | 2.83 Mcell/s | 2.52 Mcell/s |

- **Instantaneous** is `pixel_clock / 8`, the rate at which the buffer drains during the
  prefetch window. The buffer exists to absorb this, so the port does not have to match
  it.
- **Sustained per active line** is `cols / line_time`. The port has to meet this, because
  the buffer starts and ends each line at the same fill level.
- **Frame average** is what the memory system sees, since nothing is fetched during
  vertical blanking.

Glyph height does not change any of these. Each cell is re-read once per scanline of its
row, so the traffic is one cell per eight active pixels regardless of height. Choosing
8x8 doubles the number of distinct cells in the buffer and halves how often each one is
re-read; the product is the same. What it does change is the cell buffer footprint: a
128 by 96 grid needs 48 KiB against 24 KiB for 128 by 48.

### Supply

The fetch port issues one cell per register clock against a target that returns data the
cycle after the grant. At a 50 MHz register clock that is 50 Mcell/s. A target that takes
`L` cycles from grant to data returns one cell every `L` cycles, so the supply is
`f_reg / L`:

| register clock | L = 1 | L = 2 | L = 4 | L = 8 |
|---|---|---|---|---|
| 25 MHz | 25.0 | 12.5 | 6.3 | 3.1 |
| 50 MHz | 50.0 | 25.0 | 12.5 | 6.3 |
| 100 MHz | 100.0 | 50.0 | 25.0 | 12.5 |

in Mcell/s. The figure to meet is the sustained one, 6.19 Mcell/s at 1024x768, so a
50 MHz register clock against a 1 cycle target has 8.1x headroom, and still 2x against a
target with a 4 cycle read latency. A 25 MHz register clock with a 4 cycle latency is the
first entry in the table that does not clear it.

### Depth

Startup is never the constraint. The buffer fills during vertical blanking before the
first active pixel, and the shortest blanking interval in the table is 28 lines of
1056 pixels, or 29568 pixel clocks. Filling 32 cells at one per register clock takes 32
register clocks, which is orders of magnitude less.

The depth therefore buys exactly one thing: tolerance to a burst of unavailability from
the memory system. A full buffer of `D` cells covers `8 * D` pixel clocks of complete
starvation before the first cell is missed:

| depth | pixel clocks covered | 640x480 | 800x600 | 1024x768 | 720x400 |
|---|---|---|---|---|---|
| 8 | 64 | 2.54 us | 1.60 us | 0.98 us | 2.26 us |
| 16 | 128 | 5.08 us | 3.20 us | 1.97 us | 4.52 us |
| 32 | 256 | 10.17 us | 6.40 us | 3.94 us | 9.04 us |
| 64 | 512 | 20.34 us | 12.80 us | 7.88 us | 18.08 us |
| 128 | 1024 | 40.68 us | 25.60 us | 15.75 us | 36.16 us |

The default of 32 covers a stall of roughly 4 us in the most demanding mode, which is a
comfortable margin against an arbiter that loses a few hundred cycles to a competing
master. Recovery is fast: with 8x headroom the net refill rate is about 44 Mcell/s, so a
drained buffer of 32 cells is full again in 0.73 us, well inside one line.

There is an upper bound too. The drain phase of the frame handshake pops the buffer at
one cell per pixel clock, so it takes at most `D` pixel clocks and has to fit inside
vertical blanking. `vga_text_engine` asserts `FifoDepth < MinVBlankPixels / 4`, which is
7392 with the current table. The real constraint is area, not that bound.

### Why an estimate is enough for the level

`STATUS.FIFO_LEVEL` and the almost full test both use the write domain occupancy, which
compares the write pointer against a read pointer that has been through two synchroniser
stages and is therefore up to two write clocks stale. That makes the reported level a
lower bound on how much room there is, never an upper bound. For a software watermark
that is the useful direction, and for the slot reservation it is the safe one.

## Clock domain crossing

Every crossing in the design is inside `vte_frame_sync` or `vte_cdc_fifo`, so a reviewer
has two files to read rather than twelve.

| what crosses | direction | mechanism |
|---|---|---|
| cell data | register to pixel | gray coded pointer FIFO, two flop synchronisers both ways |
| configuration, 295 bits | register to pixel | frozen shadow sampled during a level handshake |
| frame and underrun counters, 48 bits | pixel to register | sampled at the same quiescent point |
| `CTRL.EN` | register to pixel | two flop synchroniser, single bit |
| `hold` | pixel to register | two flop synchroniser, single bit |
| `held` | register to pixel | two flop synchroniser, single bit |
| `running`, `vblank` | pixel to register | two flop synchroniser, single bit |

The multi bit bundles are the interesting case. Sampling a 295 bit bus across clocks
without a handshake gives torn data, and a torn configuration is worse than a late one:
a half updated palette or a mismatched column count produces garbage rather than a stale
picture. The handshake makes the sample provably safe:

1. The pixel domain asserts `hold` at the last active pixel of the frame and waits.
2. The register domain sees `hold`, refreshes its shadow copy of the configuration from
   the live registers for two clocks, then freezes it, samples the pixel domain status
   counters, and asserts `held` one clock after the freeze.
3. The pixel domain sees `held`, which is at least one register clock plus two pixel
   clocks after the shadow last changed, and samples the whole bundle in one go.
4. The pixel domain drains the buffer, releases `hold`, and waits for `held` to drop.
5. The register domain sees `hold` release, restarts the address sequence from cell zero
   and resumes fetching, using the same frozen shadow the pixel domain just took.

Both sides therefore render a frame from one consistent snapshot, and the snapshot only
changes at a frame boundary. The frame and underrun counters are safe to sample at step 2
because neither changes during blanking: the frame counter advances exactly at the
`hold` assertion and the underrun counter only moves during active video.

The whole sequence costs about ten clocks in each domain plus at most `FifoDepth` pixel
clocks for the drain, against at least 29568 pixel clocks of vertical blanking. The
margin is more than three orders of magnitude, which is why `clk_i` only has to be
faster than `clk_pix_i / 1000`.

## Verification plan

### What could go wrong

| risk | how it is covered |
|---|---|
| a count in the mode table is wrong | measured on the pins, asserted against an independently written copy of the VESA figures |
| sync polarity inverted for a mode | derived from the raw level run lengths, not from a register read |
| one line in a frame is a different length | every horizontal quantity recorded as a min and a max over a whole frame |
| the pipeline is off by a cell or a scanline | pixel exact comparison against an independent renderer |
| an attribute is decoded in the wrong order | the model implements the documented order; both agree on the full attribute matrix |
| the glyph ROM banks are swapped or misindexed | both heights compared pixel exact, including a 60 row grid |
| the cursor lands on the wrong cell or scanline | full height cursor in the attribute scene, several positions across scenes |
| a blink divider is off by one | run lengths measured in frames and cross checked frame by frame against the model |
| a register field is the wrong width or position | all ones, all zeros and two walking patterns per register |
| reserved bits are readable | included in the mask comparison |
| a byte strobe is ignored or over-applied | partial writes with three different strobe patterns |
| a sticky flag cannot be cleared or clears itself | write one to clear, then a zero write, then three more frames |
| the memory stalls and takes the sync with it | hsync period measured across the whole starvation window |
| the picture never recovers from an underrun | post recovery frame compared pixel exact |
| a latch is inferred | the area report fails on any latch cell in the mapped netlist |
| the parameterisation has rotted | a second parameter set is linted on every run |
| synthesis changes behaviour | the mapped netlist renders a frame and is diffed against the reference renderer |
| a video mode is listed but unreachable | per mode static timing analysis at the slow corner |

### Independence

The value of the pixel exact comparison comes entirely from the two renderers being
independent, so it is worth being explicit about what they share and what they do not.

Shared: the glyph bitmaps in `scripts/font_data.py`, and the stimulus files, which are a
register replay script and a `$readmemh` cell image. Both sides consume byte identical
stimulus, so nothing about a scene is described twice and a mismatch cannot come from the
scene.

Not shared: the renderer. `scripts/model.py` was written from the register map and the
attribute resolution order in the README, not from the RTL. It walks cells in a different
order, has no notion of a pipeline or a prefetch window, and computes the blink phase
from a frame index with a closed form expression rather than a divider.

The VESA numbers are duplicated on purpose. `rtl/vte_modes_pkg.sv` and
`scripts/modes.py` were both written from the specification, so a typo in either one
fails rather than cancelling out. `vte_mode_lut` additionally re-derives the summary
constants and both polarities from the table at elaboration time.

### Coverage the suite does not have

Stated plainly rather than left to be discovered:

- No formal property checking. The alignment invariant is argued in this document and
  tested at frame granularity, not proved.
- No post layout simulation. Gate level simulation runs on the mapped netlist with zero
  delay cell models, so it proves function, not timing. Timing comes from static analysis.
- Static timing analysis is at synthesis level: ideal clocks, no wire load model, no
  fanout repair. The frequencies are load limited by unbuffered high fanout enables and
  would improve after place and route.
- Gate level simulation covers one frame of one scene, not the whole scene catalogue. It
  takes roughly a hundred times longer than the RTL run.
- No metastability injection. The synchronisers are structurally standard but the
  testbench cannot exercise a genuinely asynchronous sample.
- Frames are compared at a handful of blink phases, not at every phase of every divider.
  The blink test covers the phase arithmetic separately over sixteen consecutive frames.
- The `CTRL.MODE` change while enabled is documented as producing one malformed frame and
  is not tested, because the malformed frame is the specified behaviour.

## What the silicon says

The design is taken through synthesis, static timing analysis and gate level simulation on
the IHP Open PDK SG13G2, an open source 130 nm BiCMOS process. Three things came out of
that which are worth recording as design feedback rather than just as numbers.

### Atomic reconfiguration costs about a quarter of the area

`vte_frame_sync` is 44 689 um2 of the 182 546 um2 hierarchical total, and almost all of it
is flip flops: two extra copies of the 295 bit configuration bundle, one frozen shadow in
the register domain and one live in the pixel domain. Together with the elastic buffer,
which is another 50 966 um2 of flip flops because a 130 nm standard cell library has no
small dual port RAM, storage is 52 percent of the design.

That is the honest price of the guarantee in the handshake section: software never sees a
torn frame. A cheaper design would let the pixel domain read the live registers and accept
a corrupted frame whenever a write straddled the boundary. Knowing the cost is a quarter of
the area makes that a real engineering choice rather than an assumption.

### The critical path is load, not logic

Both worst paths are only a few gates deep, and almost all of the delay is a single
unbuffered net:

| domain | stages | heaviest net | fanout | delay |
|---|---|---|---|---|
| register | 3 | hold line of the frame handshake | 419 | 11.50 ns |
| pixel | 5 | pixel side snapshot enable | 155 | 7.33 ns |

Those are exactly the signals that make the configuration update atomic: one enable
reaching every flip flop of the bundle at once. Synthesis level mapping does no load aware
buffering, so `abc` picks a minimum size gate and asks it to drive the whole bank. A place
and route flow inserts a buffer tree and the stage collapses.

The design implication is not "fix the RTL". It is that the frequency this design reaches
depends on buffering rather than on restructuring logic, which is the easy kind of
dependency: no pipeline stage has to be added, and the numbers already clear every video
mode at the slow corner.

### Every video mode is a verified claim

The mode table used to be a list of numbers the sync generator reproduces. It is now also a
statement about frequency: at the slow corner the pixel domain closes at 95.96 MHz, so
1024x768 at 65 MHz has 1.5x margin and the other three have 2.4x or more. The pixel
pipeline is one pixel per clock with no multi-cycle paths, so the critical path is the same
in every mode and only the requirement changes.

### Gate level simulation replaces a structural argument

The earlier version of this document leaned on `check -assert` to claim the netlist was
sound. That check turned out to be unreliable after `flatten`: Yosys keeps the flattened
alias of every port alongside the port itself, `opt_clean` drops the alias, and `check`
then reports the alias as undriven even though the port is driven by a cell. 87 warnings
in the script, zero when the emitted netlist is read back on its own, identical under
Yosys 0.33 and 0.54.

The replacement is stronger and needs no argument at all: run the frame capture testbench
against the mapped netlist and the PDK cell models, and diff the result against the same
independent Python renderer the RTL is checked against. Either the netlist produces the
same 307 200 pixels or it does not. It does, at the slow corner, in about 22 minutes of
simulation against 11 seconds for the same frame at RTL.

Getting there needed one thing understood about the PDK's cell models. Their `specify`
blocks are what drive the `delayed_CLK`, `delayed_D` and `delayed_RESET_B` wires the
sequential cells read, so deleting the blocks to get past Icarus Verilog's refusal to parse
`ifnone` with edge sensitive paths turns the entire design X. All 505 delays in the file are
zero, so `scripts/gatesim.py` rewrites each block into the identity it stands for instead,
and refuses to run if a non zero delay appears or if a delayed wire has no port to alias.

## SystemVerilog subset

The RTL is deliberately restricted so Icarus Verilog 12, Verilator 5 and Yosys 0.33 all
read the same files with no preprocessing step. Anyone extending it should stay inside
these rules, all of which were arrived at by hitting the corresponding failure:

| rule | why |
|---|---|
| one design unit per file, filename matching the unit | Verilator `DECLFILENAME` |
| no `import pkg::*` inside a module, use `pkg::NAME` | Yosys rejects the import |
| no functions in packages | Yosys cannot resolve them |
| no `type'(expr)` casts, size casts like `12'(x)` are fine | Yosys rejects the type cast |
| no struct assignment patterns `'{...}`; concatenate or assign fields | Icarus cannot elaborate them |
| functions end with `funcname = value`, not `return` | Yosys rejects `return` |
| no `$bits(type)` in a package | Yosys rejects it |
| no loop with a variable part select base, unroll or use a generate loop | Icarus silently merges rather than replaces, which turned every byte strobe write after the first into a no-op |
| a combinational block whose right hand side calls a function must be `always_comb`, not `assign` | a continuous assignment is not re-evaluated when a signal the function reads internally changes, which made every register read return the value from when the address last changed |
| simulation only code behind `` `ifndef SYNTHESIS `` | Yosys is invoked with `-DSYNTHESIS` |

The last two are the ones that cost real debugging time, and both produced silent wrong
behaviour rather than an error.

## Known limitations

- The pixel clock must be the exact clock of the selected mode. There is no internal
  divider, because a divider would either restrict the achievable set of modes or add a
  fractional accumulator whose jitter shows up on the sync pins.
- Cells are 32 bits, so a 128 by 96 grid needs 48 KiB of buffer. A packed 16 bit format
  with a reduced attribute set would halve that and is not implemented.
- The glyph ROM is fixed at elaboration time with 128 glyphs per bank. There is no write
  port, so a font cannot be replaced at runtime.
- Character codes 128 and above render blank rather than wrapping, which is the useful
  behaviour but does mean the upper half of a code page is unavailable.
- `CTRL.MODE` changes take effect at a frame boundary, and the frame during which the new
  geometry is latched may be short or long. Disable, reprogram and re-enable for a clean
  transition.
- There is no interrupt controller, only one clock wide `frame_o` and `underrun_o` pulses
  in the register domain and the sticky bits in `STATUS`.
