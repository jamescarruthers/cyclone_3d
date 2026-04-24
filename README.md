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
make snapshot   # build/cyclone.z80      (tap2sna.py simulates the SpeedLock loader)
make ctl-auto   # build/cyclone.auto.ctl (sna2ctl.py — fresh static analysis)
make skool      # build/cyclone.skool    (sna2skool.py using cyclone.ctl)
make html       # build/html/            (skool2html.py)
```

`make` with no arguments runs through to `skool`.

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
