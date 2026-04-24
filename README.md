# cyclone_3d

SkoolKit disassembly workspace for **Cyclone** (Vortex Software, 1985 — Costa
Panayi). The repo ships the original TZX dump and the pipeline needed to turn
it into a readable annotated Z80 source file.

## What's in here

| File | Purpose |
| ---- | ------- |
| `Cyclone.tzx.zip` | Original two-side TZX dump. |
| `cyclone.ctl` | Hand-curated [SkoolKit control file][ctl]. This is the file you edit as you learn the code. |
| `Makefile` | Reproducible pipeline: unzip → tap2sna → sna2ctl → sna2skool → skool2html. |
| `build/` | All generated artefacts (snapshot, auto control file, skool file, HTML). Ignored by git. |
| `tzx/` | Unpacked tapes. Ignored by git. |

## One-time setup

```sh
pip install skoolkit      # installs tap2sna.py, sna2skool.py, sna2ctl.py, ...
```

If `pip` won't install system-wide, use a venv or:

```sh
git clone https://github.com/skoolkid/skoolkit /tmp/skoolkit
pip install /tmp/skoolkit
```

## Pipeline

```sh
make snapshot   # build/cyclone.z80              (tap2sna.py simulates the SpeedLock loader)
make ctl-auto   # build/cyclone.auto.ctl         (sna2ctl.py — fresh static analysis)
make map        # build/cyclone.map              (rzxplay.py --map over cyclone.rzx)
make ctl-rzx    # build/cyclone.auto-rzx.ctl     (sna2ctl.py -m map — trace-informed analysis)
make skool      # build/cyclone.skool            (sna2skool.py using cyclone.ctl)
make verify     # build/cyclone.reassembled.bin  (skool2bin.py + byte-compare vs snapshot)
make html       # build/html/                    (skool2html.py)
```

`make` with no arguments runs through to `skool`.

## GitHub Pages deployment

`.github/workflows/pages.yml` rebuilds the HTML disassembly on every push
to `main` (and on manual `workflow_dispatch`) and deploys it to
GitHub Pages. The workflow runs `pip install skoolkit` then `make html`,
checks the round-trip via `make verify`, and uploads `build/html/cyclone/`
as the Pages artifact.

**One-time repo setup**: in **Settings → Pages**, set **Build and
deployment → Source** to **GitHub Actions**. After the next push to main
the disassembly will be live at `https://<owner>.github.io/<repo>/`.

## RZX-driven control file refinement

The repo ships `cyclone.rzx`, a ~1 hour Spectaculator recording of actual
gameplay. `rzxplay.py --map` replays it headless and logs every executed
instruction address to `build/cyclone.map` (4,207 unique addresses for this
recording). Feeding that map into `sna2ctl.py -m` produces a second auto
control file (`build/cyclone.auto-rzx.ctl`) informed by what the game
*actually did*, not just what static analysis can prove reachable.

Comparing the two with `python3 tools/compare_ctl.py`:

```
Code blocks both agree on         : 100   (high-confidence heavy hitters)
Static says code, map did not see : 247   (rarely-executed paths / dead code)
Map says code, static missed      :  13   (indirect-jump targets)
```

The three categories drive different decisions:

1. **Consensus code (100)** — both analyses say "this is code". Start
   annotating these first; they include `$5B00` MAIN_LOOP, `$6F00`, the
   sprite-render chain at `$77xx-$79xx`, etc.
2. **Static-only (247)** — reachable by static analysis, untouched by this
   particular playthrough. Most are real code on rarely-hit branches
   (level-specific handlers, death animations, attract mode paths); some
   may be genuine dead code. Verify by playing longer / recording more
   RZXs.
3. **Map-only (13)** — bytes the RZX proves are code but static analysis
   missed. These are reached via indirect jumps (`JP (HL)`, runtime-built
   vectors) and are the most important discoveries. For Cyclone they
   include `$83C2` (the real IM 2 interrupt entry) and `$FFF4` (the IM 2
   trampoline the game builds at runtime — see the `$FFDF` block
   description in `cyclone.ctl`).

The hand-curated `cyclone.ctl` uses the fine-grained static analysis as its
base (so rarely-executed routines still get disassembled as code) and
layers RZX discoveries on top as notes / labels at the map-only addresses.

## Checking the disassembly is correct

"Correct" has two levels here — *lossless* (all bytes preserved) and
*semantic* (code is marked as code, data as data, strings as strings).

### 1. Round-trip byte equality (`make verify`)

The cheap, automated check. `skool2bin.py` reassembles `cyclone.skool` into
raw bytes; `tools/verify.py` compares them against the RAM
(`$4000–$FFFF`) of `cyclone.z80`:

```
$ make verify
...
OK: 49152 bytes match (build/cyclone.z80 == build/cyclone.reassembled.bin)
```

A byte-perfect match proves the skool file is a **lossless** representation
of the snapshot: every directive in `cyclone.ctl` — `b`, `c`, `t`, `s`, `w`
— round-trips to the same bytes. It's a hard regression check: any edit to
`cyclone.ctl` that accidentally drops or duplicates bytes will break it.

What it does *not* prove: that we've classified bytes *correctly*. A `c`
block over pure data still reassembles to the same bytes even though the
mnemonics are nonsense. For that, see the next two checks.

During `skool2bin.py` you'll also see warnings like:

```
WARNING: Address $FF07 replaced with 65287 in unsubbed LD operation:
  65170 FE92   LD HL,$FF07
```

These fire when an instruction operand points inside a different block, and
they are informational — the reassembled bytes are still identical. Adding
an `@ $FF07 label=...` directive (and `@label` on the calling line) makes
the warning go away and gives the target a proper symbol.

### 2. Sanity-check the skool file

Open `build/cyclone.skool` and scan for tell-tale wrongness:

- **`DEFB` runs full of what look like mnemonics** — a code block has been
  mis-classified as data. Flip `b` → `c`.
- **Code blocks that `LD` from themselves or contain long sequences of
  `NOP`/`RST 0`** — usually a data table being interpreted as instructions.
  Flip `c` → `b`.
- **Text blocks (`t`) that emit `DEFM` of unprintable bytes** — flip `t` →
  `b`.
- **`WARNING: Instruction at $XXXX overlaps...`** emitted by `sna2skool.py`
  means a block boundary lands in the middle of a Z80 instruction. Move
  the boundary or widen the preceding block.

### 3. Run the reassembled game

The strongest semantic check: take `build/cyclone.reassembled.bin`, wrap it
back into a snapshot with `bin2sna.py`, and boot it in an emulator. If it
plays identically to the tape, the disassembly is a faithful model of the
program.

```sh
bin2sna.py -o 16384 -s 0x5B00 build/cyclone.reassembled.bin build/cyclone.check.z80
# then load build/cyclone.check.z80 in Fuse / SpecEmu / ZEsarUX
```

(The `-s` start address is a guess based on the main-loop entry at `$5B00`;
the real entry is whatever address the SpeedLock loader JP's to once
decryption finishes — something to nail down as the disassembly progresses.)

### 4. Static analysis cross-check

Regenerate the auto control file and diff against the hand-curated one:

```sh
make ctl-auto
diff build/cyclone.auto.ctl cyclone.ctl | less
```

Places where `sna2ctl.py`'s fresh opinion disagrees with the committed
`cyclone.ctl` are the most likely places to find a mis-classification.

## How the control file makes sense of the Z80

`sna2skool.py` by itself assumes the entire 48K is code and produces noise.
A control file tells it where the code lives, where the data lives, and how to
label what it finds. The minimum useful control file is just:

```
@ $4000 start          # ASM directive: entry point
@ $4000 org            # ASM directive: origin
b $4000                # $4000+ is a data block (the screen)
c $5B00                # $5B00+ is a code block (main game loop)
```

That alone is enough for `sna2skool.py` to emit `DEFB` for the screen and
proper Z80 mnemonics for the code. The single-letter directives are:

- `b` data, `c` code, `t` text, `w` 2-byte words, `s` same-byte runs,
  `u` unused, `i` ignored.
- Uppercase variants (`B`, `C`, `T`, `W`, `S`) mark *sub-blocks* of a
  different type inside a containing block — useful when a data table
  embeds a short routine, or a code block ends with a jump table.
- `D` adds a block description, `N` a mid-block comment, `E` an end-of-block
  comment, `R` documents register entry/exit values, `M` attaches one comment
  to a span of instructions.
- `@` lines are ASM directives (`@start`, `@org`, `@label=NAME`, `@equ=...`).

### The workflow used here

1. **Seed from static analysis.** `sna2ctl.py --hex build/cyclone.z80` walks
   the snapshot and guesses block boundaries by tracing reachable code.
   `make ctl-auto` drops the result in `build/cyclone.auto.ctl` (≈2,170
   blocks for Cyclone). It's a byte-accurate skeleton but has no titles.
2. **Copy the boundaries into `cyclone.ctl`.** `cyclone.ctl` here *is* the
   seeded file, with a header comment explaining the format and hand-written
   titles/`D` descriptions layered on at the interesting addresses
   (`$4000`, `$5800`, `$5B00`, `$5CB2`).
3. **Iterate.** Run `make skool`, open `build/cyclone.skool`, and look for
   mis-classified regions — data that was disassembled as code, strings that
   became DEFBs, etc. Fix them by flipping the directive letter
   (`b` ↔ `c` ↔ `t`) or splitting a block at a new address.
4. **Annotate.** As each routine becomes understood, add a title after its
   `c $ADDR` line, paragraph descriptions with `D $ADDR …`, and `@ $ADDR
   label=NAME` to give it a readable symbol in the disassembly. Comments
   survive a round-trip through `skool2ctl.py`, so you can regenerate the
   skool file any time.

### Known map (starting point)

| Address | Kind | Notes |
| ------- | ---- | ----- |
| `$4000–$57FF` | data | Loading screen bitmap (display file). |
| `$5800–$5AFF` | data | Loading screen attributes. |
| `$5B00`       | code | Main per-frame loop — chains CALLs to init/draw/input. |
| `$5CB2+`      | mixed | Remains of the BASIC autostart + game state variables. |
| `$F7F0+`      | code | SpeedLock tape loader (snapshot PC stopped here — loader self-terminates once the tape runs out). |

Everything above `$5B00` needs manual triage; the auto-seeded boundaries in
`cyclone.ctl` are a reasonable first cut, not ground truth.

## Useful extras

- `tapinfo.py "tzx/Cyclone - Side 1.tzx"` — dump the TZX block list and spot
  the SpeedLock 1 protection blocks.
- `snapinfo.py build/cyclone.z80` — register state and RAM page breakdown of
  the post-load snapshot.
- `sna2skool.py --hex -c cyclone.ctl --start $5B00 --end $5C00 build/cyclone.z80`
  — disassemble just a window, handy while hunting for the end of a routine.

[ctl]: https://skoolkit.ca/docs/skoolkit/control-files.html
