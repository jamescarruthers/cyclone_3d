# An idiot's guide to how Cyclone stores its islands

Plain English. No assembly. The goal is: by the end you should be able to
look at the PNG output and know **exactly** what bytes produced each pixel.

---

## 1. The big picture

Cyclone has **14 islands**. Each island's terrain lives somewhere in RAM
between `$9300` and `$CFFF`. There is **one master table** at `$F230`
that tells the engine where each island's terrain bytes live and what
world rectangle it covers.

To recreate one island as a top-down PNG we need to answer three questions:

1. *Where in RAM is this island's terrain?*  → master table at `$F230`
2. *What does each terrain byte mean?* → glyph font at `$FA00` + colour table at `$FE00` + tile-stack tables at `$6300`/`$6400`/…
3. *How are the bytes laid out in 2-D?* → row stride is **128 bytes**, column stride is 1 byte.

That's enough to render a single island PNG correctly. The harder
question — *how the 14 islands are laid out into one big archipelago* —
is **not** answered by the master table alone. See §10.

> 📐 **The world is 768 × 768, not 256 × 256.** Cyclone uses 16-bit
> helicopter coordinates: low byte at `$7500`, high byte at `$7501`
> for X (same for Y at `$7502`/`$7503`). The world is a 3 × 3 grid of
> 256 × 256 cells. Master-table fields `+$00` / `+$01` (which earlier
> docs called "type" / "subtype") are actually the **cell index** —
> i.e. the high bytes of the helicopter's X / Y position.
> `+$02..+$05` are LOCAL within-cell bounds. Global island position
> is `(cell.x * 256 + x_local, cell.y * 256 + y_local)`. The
> derivation, including the proof from the disassembly and a
> cross-check against the in-game navigation map, is in §10.

---

## 2. The master table at `$F230`

14 records, 20 bytes each, terminated by `$FF` at `$F348`. Each record
describes one island. The fields you actually care about for rendering:

| Offset | Name | What it means in plain English |
|-------:|------|--------------------------------|
| `+$00` | `type` | **Scene selector**, high-level. The engine compares this with `($7501)` *before* doing the X/Y bound check. If they don't match the record is skipped entirely. |
| `+$01` | `subtype` | **Scene selector**, finer. Compared with `($7503)`, same idea. Together with `type` this picks which subset of islands is "active" at any given moment. |
| `+$02` | `x_min` | Westernmost world X the helicopter can reach over this island, *within its own scene*. |
| `+$03` | `x_max` | Easternmost world X (same caveat). |
| `+$04` | `y_min` | Northernmost world Y. |
| `+$05` | `y_max` | Southernmost world Y. |
| `+$06` | `x_origin` | **Always `x_min + 22`.** Used by the engine as a subtraction constant; you can ignore it for rendering. |
| `+$07` | `x_upper` | **Always `x_max - 22`.** A "quadrant boundary" the engine uses to decide which screen-edge code path to run. **Not** a hard helicopter bound — that was the mistake the previous fix made. |
| `+$08` | `y_origin` | `y_min + 28`. Same idea as `x_origin` but for Y. |
| `+$0A..0B` | `shape_base` | **Address of byte 0** of this island's terrain map. The single most important field. |

The hard bounds the helicopter actually obeys live at `$76F9-$7715`:
`helX` is rejected if it's `< x_min` or `> x_max`; same for Y. That's
why the engine genuinely reads up to world column `x_max` — and the
shape data must extend that far.

The `(type, subtype)` filter at `$76EC`-`$76F4` runs **first**, before
the X/Y check, and skips records that don't match. This is what makes
overlapping `(x_min..x_max, y_min..y_max)` rectangles safe: at most one
record matches the *current* `($7501, $7503)` pair plus the helicopter
position. In the master table, every pair of islands with overlapping
world rectangles has a different `(type, subtype)` — no within-scene
overlaps. So `(type, subtype)` is effectively a scene/level index.

---

## 3. Terrain layout in RAM (the "stride 128" trick)

Each island's terrain is a 2-D grid of bytes, laid out **like rows in a
spreadsheet**. There is *one byte per world cell*. To find the byte for
world cell `(world_x, world_y)`:

```
row_in_shape    = world_y - y_min            # 0..(y_max - y_min)
col_in_shape    = world_x - x_min            # 0..(x_max - x_min)
address         = shape_base
                + row_in_shape * 128         # row stride
                + col_in_shape               # column stride
```

So:
- **Column stride is 1 byte** — adjacent world X cells are adjacent bytes in memory.
- **Row stride is 128 bytes** — going one cell south in the world means jumping 128 bytes in memory.

The `128` (= `$80`) comes from the engine's LDIR loop at `$7803-$780D`:
it copies 23 bytes per visible row, then adds `$0069` (= 105) to advance
to the next row. `23 + 105 = 128`. Done.

### Why 128 and not the island's width?

Because **stride is fixed across all islands**. The engine's LDIR loop
is one piece of code shared by all 14 records — it has to use the same
stride for everyone. Vortex chose 128, which is enough for any island
(world is 256 wide, but no island uses the full width).

### What's between rows?

The row 0 bytes are at `shape_base + 0..(width-1)`. Then bytes
`shape_base + width..127` are **wasted** for that row — they could
contain anything (junk, padding, or another island's data; see §6).
Row 1 starts at `shape_base + 128`.

---

## 4. From byte to picture: the rendering pipeline

A single byte `S` at `(row, col)` becomes a tower of 8×8 pixel tiles.
Three lookup tables turn `S` into pixels:

### Step 1 — tile transform (`$6300`)

The raw shape byte `S` is first remapped through the table at `$6300`:

```
base_tile = ram[$6300 + S]
```

This collapses many similar shape bytes onto the same visual tile —
e.g. all "sea" bytes (0, 1, 2, …) end up as tile `$80` (solid cyan),
all "grass" bytes end up as `$87` (solid green), and so on.

### Step 2 — tile stacks (`$6300` row 0, `$6400`, `$6500`, …)

Now `S` is also used to look up a **vertical stack** of additional
tiles at increasing pages:

```
stack_level_0 = ram[$6300 + S]    # base cell (the ground-level tile)
stack_level_1 = ram[$6400 + S]    # one tile UP the screen
stack_level_2 = ram[$6500 + S]    # two tiles UP
...
```

The walk continues page by page until a sentinel `$FF` is hit. A `$FE`
in the middle means "skip this row but keep walking" (used for spacing
between, say, the base of a palm tree and its leaves).

This is **how a single shape byte becomes a tall feature**. A "palm
tree" shape byte reads as: ground tile (level 0), trunk tile (level 1),
leaves tile (level 2), terminator. A "house" reads as: ground, wall,
wall, roof, terminator. A flat grass tile reads as: grass, terminator.

The renderer at `tools/render_island_from_json.py` walks these stacks
and stamps each level at `(col*8, (row - level)*8)` — i.e. each
successive level is drawn **8 pixels higher** on the canvas. That's
why the PNGs need extra headroom at the top.

### Step 3 — bitmap and colour

For each tile index `T` we now have:

```
attr   = ram[$FE00 + T]              # ZX Spectrum attribute byte: ink, paper, bright, flash
bitmap = ram[$FA00 + T*8 .. T*8+8]   # 8 bytes, one per scan line
```

If `T >= $80` the bitmap is treated as solid (no pixels drawn — just
the attribute fill, which is how you get plain cyan sea or plain green
grass). If `T < $80`, the 8 bytes are drawn as 8 pixel rows, MSB-first,
ink colour for `1` bits and paper colour for `0` bits.

`tools/extract_map.py` dumps the font (`tile_glyphs`), attribute table
(`tile_attributes`) and stack tables (`tile_stacks`) into the JSON so
you don't need a Z80 emulator at render time.

---

## 5. The 23 × 29 LDIR window — and the self-modifying clamp

When you play the game, the engine doesn't render the whole island at
once. Each frame it runs an LDIR loop that copies a window of shape
bytes into a working buffer at `$F74E`, centred on the helicopter.
The naive description is "23 columns × 29 rows centred on the
helicopter":

```
HL = shape_base
   + (helY - y_origin) * 128           # which row of shape data
   + (helX - x_origin)                 # which column
                                       # then LDIR 23 bytes per row,
                                       # advance HL by 128, repeat 29 times
```

But that's *only* what the centre variant does. The engine actually has
**nine variants**, dispatched by the jump table at `$78CF`, indexed by
which "quadrant" the helicopter is in (set in `$7728-$7740`):

- bit 2 set: `helX < x_origin` (LEFT)
- bit 3 set: `helX >= x_upper` (RIGHT)
- bit 4 set: `helY < y_origin` (NORTH)
- bit 5 set: `helY >= y_origin_alt = y_max - 28` (SOUTH)

The variants for the SOUTH and RIGHT edges **self-modify the LDIR loop**
to clip the read so the engine never goes past the island's data:

| Variant | Where | What it does |
|---|---|---|
| `$77AD` (centre) | helicopter in middle | `A = $1D` (29 rows), `BC = $0017` (23 cols) — full window |
| `$787D` (south) | helY ≥ y_max - 28 | **`A = y_max - helY + 1`** — row count shrinks as helY approaches y_max |
| `$77D2` (right) | helX ≥ x_max - 22 | self-modifies the immediate at `$783E` so **`BC = x_max - helX + 1`** — col count shrinks as helX approaches x_max |
| `$77B7` (left), `$77E8` (north) | mirror image | clip from the other side using x_min / y_min |

So at maximum helicopter X the engine reads only **one** column (col
`x_max - x_origin = x_max - x_min - 22`); at maximum helY only **one**
row (row `y_max - y_origin = y_max - y_min - 28`). The clamps prevent
the LDIR from *ever* going past those.

The union of all reads across all valid helicopter positions is
therefore the rectangle:

```
shape rows  0 .. (y_max - y_min - 28)        ->  y_max - y_min - 27 rows
shape cols  0 .. (x_max - x_min - 22)        ->  x_max - x_min - 21 cols
```

That's what `extract_map.py` extracts. **Anything outside that
rectangle is never touched by the engine** — which is how Vortex got
away with packing GIANTS GATEWAY's `shape_base` `$9337` only 55 bytes
into BANANA's row 0 (BANANA's clamped col range is 0..54, so it never
reads `$9337`+, and GIANTS' clamped row range starts at 0 = `$9337`).
The "garbage collection" that keeps the game looking clean is **the
self-modifying LDIR length**, not anything we add at render time.

If your offline render shows bleed-through from a packed neighbour, or
a wall of repeating buildings/trees at the bottom of an island, your
extractor is using the wrong cols/rows formula. The right one is
above; earlier values like `cols = x_upper - x_min` (off by one too
narrow) and `cols = x_max - x_min + 1` (way too wide) both fail.

---

## 6. Why some islands "share" addresses (the packing trick)

Look at the JSON — three islands all live in page `$93xx`:

```
BANANA ISLAND      shape_base = $9300
GIANTS GATEWAY     shape_base = $9337
GILLIGANS ISLAND   shape_base = $9354
```

Vortex didn't have unlimited RAM. To save space they **overlapped the
empty edges** of one island with the populated centre of another. As
long as the bytes that **both** islands' engines read are valid for
both renderings, you can store them once. In practice this means the
left edge of one island = the right edge of another, and both edges
are usually mostly sea / mostly empty.

Concretely:
- BANANA's row 0 is `$9300..$934C`. Its rightmost ~22 columns
  (`$9337..$934C`) are also GIANTS GATEWAY's leftmost row 0
  columns. When BANANA's engine flies near `helX = x_max` and
  GIANTS' engine flies near `helX = x_min`, **they read the same RAM
  bytes**. Both renderings show those bytes; both have to look right.
- Same trick: GILLIGANS overlaps BANANA's row 0 from `$9354` onward.
- Same trick: ENTERPRISE ISLAND (`$C64F`) is packed exactly
  `x_upper(LUKELAND) - x_min(LUKELAND)` bytes into LUKELAND's
  (`$C628`) row 0.

For a single-island PNG render, we extract the full world rectangle
and accept that some bytes near the right edge may "belong" to a
neighbour. Those bytes are exactly what the player sees flying east
along the island, so this is the correct thing to do.

---

## 7. The render flow, end to end

```
  cyclone.rzx (recorded gameplay)
      │
      │  rzxplay.py replays the tape until end of game
      ▼
  build/cyclone-endgame.z80          ← post-init snapshot, RAM is fully populated
      │
      │  tools/extract_map.py reads RAM:
      │    - master table at $F230 (14 records)
      │    - for each record, the shape rectangle at shape_base
      │      (width = x_max - x_min + 1, height = y_max - y_min + 1,
      │       row stride 128, col stride 1)
      │    - glyph font at $FA00 (192 glyphs in RAM, 64 unreachable in ROM)
      │    - attribute table at $FE00 (256 entries)
      │    - tile-transform at $6300, tile-stacks at $6300/$6400/...
      ▼
  build/cyclone-map.json             ← portable, no Z80 needed downstream
      │
      │  tools/render_island_from_json.py walks each row × col,
      │  expands each shape byte into its vertical tile stack,
      │  and stamps 8×8 glyph bitmaps with attribute colours.
      ▼
  images/island-<name>.png           ← top-down PNG per island
```

If the PNG looks wrong, walk back up the chain:

1. **Wrong island shape entirely** → the master-table fields are wrong (offsets `+$02..+$05` or `+$0A..+$0B`).
2. **Right edge cut off** → `cols` wasn't `x_max - x_min + 1` (the bug we just fixed).
3. **Top edge cut off** → renderer didn't reserve `max_stack` rows of headroom for tall stacks.
4. **Garbage at the bottom of tall islands** → shape data extends past real terrain into runtime work-RAM (visible on ENTERPRISE). The engine would read garbage too if the helicopter flew there; the original game presumably keeps the helicopter away or relies on an outer wrapper not modelled here.
5. **Houses/cliffs missing extrusion** → the tile-stack walk stopped at the wrong sentinel; check that the stacks read `$6300+S, $6400+S, ...` and stop at `$FF`.
6. **Wrong colours** → the attribute lookup `$FE00 + tile_index` is misindexed (use the *post-stack* tile, not the raw shape byte).

---

## 8. Quick reference: the addresses you need

| Address | What lives there |
|--------:|------------------|
| `$F230` | Master island table (14 × 20 bytes, `$FF` terminated at `$F348`) |
| `$9300-$CFFF` | Pool of island shape data; each `shape_base` points somewhere in here |
| `$FA00` | 8×8 glyph font (1536 bytes = 192 glyphs in RAM, indices 192..255 are unreachable ROM) |
| `$FE00` | Tile attribute table (256 bytes, one per tile index) |
| `$6300` | Tile-transform table (raw shape byte → render tile index) **and** stack level 0 |
| `$6400` | Tile-stack level 1 (one row UP the screen) |
| `$6500` | Tile-stack level 2 |
| ... | ... up to `$FE00` (sentinel `$FF` ends the stack first) |
| `$F74E` | Per-frame working buffer the LDIR copies into |
| `$7500/$7502` | Helicopter world (X, Y) — `($7500)` = X, `($7502)` = Y |
| `$76F9-$7715` | Hard helicopter bounds check (`x_min`/`x_max`/`y_min`/`y_max`) |
| `$7803-$780D` | LDIR loop (23 bytes/row × 29 rows, stride 128) |
| `$7E10` | Tile-transform pass over `$F74E` |
| `$762C` | Final compositor: tile → attribute + bitmap → screen |

---

## 9. TL;DR

- An island is a 2-D byte grid with **row stride 128, column stride 1**, starting at `shape_base`.
- Width = `x_max - x_min + 1`. Height = `y_max - y_min + 1`. (World cells are 1 byte each.)
- Each byte is **not** a pixel — it's a recipe. The recipe says "use this glyph + this colour, then stack these other glyphs UP the screen."
- The recipe lookup tables are at `$6300`, `$6400`, `$6500`, … (stacks), `$FA00` (bitmaps) and `$FE00` (colours).
- Some islands **share bytes** with adjacent islands by design — to save RAM. Both renderings of those bytes have to look reasonable.

Once you have the master table, the shape data, the font, the attribute
table and the stack tables, you can produce every island's PNG with
zero Z80 emulation. That's exactly what `extract_map.py` +
`render_island_from_json.py` do.

---

## 10. The global archipelago layout (decoded)

The 14 islands live in a **768 × 768** world made of a **3 × 3 grid
of 256 × 256 cells**. Each island sits in exactly one cell.

### How we know

**Step 1 — the helicopter position is 16-bit.** In the per-frame
motion update at `$81EC..$81F7`:

```
$81EC LD HL,($7500)   ; read 16-bit X from $7500/$7501
$81EF NOP             ; (self-modified at runtime to ADD HL, BC etc.)
$81F0 LD ($7500),HL   ; write back 16-bit X
$81F3 LD HL,($7502)   ; read 16-bit Y from $7502/$7503
$81F6 NOP             ; (self-modified)
$81F7 LD ($7502),HL   ; write back 16-bit Y
```

The motion routine reads, modifies and writes back the position as a
**word** at each step. So `$7501` and `$7503` are the high bytes of X
and Y, not separate fields.

**Step 2 — master table `+$00` / `+$01` are the high bytes of the
helicopter's position when over that island.** The bound check at
`$76EC..$76F4` does:

```
$76E9 LD A,($7501)      ; high byte of helicopter X
$76EC CP (IX+$00)       ; compare with the island's "+$00"
$76EF JR NZ, skip       ; record skipped if they don't match
$76F1 LD A,($7503)      ; high byte of helicopter Y
$76F4 CP (IX+$01)       ; compare with the island's "+$01"
$76F7 JR NZ, skip
... then the local x_min..x_max / y_min..y_max check
```

`+$00` / `+$01` are matched **directly** against the X / Y high bytes.
That makes them the cell index `(cell_x, cell_y)`, *not* arbitrary
selector bytes.

**Step 3 — sample the RZX and confirm.** I dumped `($7500..$7503)` at
58 frames spread across the recorded play-through. The helicopter
visits exactly **8 distinct `(xhi, yhi)` cells**:

```
(0,0) (0,1) (0,2)
(1,0) (1,1) (1,2)
(2,0) (2,1)
```

These are exactly the eight `(+$00, +$01)` values that occur in the
master table. Cell `(2,2)` is empty — no island lives there, and the
helicopter never enters it during the recording. So the inhabited
world is a 3 × 3 grid (one cell unused).

**Step 4 — cross-check against the navigation screen.** Sorting the
14 islands by `global_X = cell_x * 256 + x_local` and independently
by `navmap_col` produces **the same order**. Same for global Y vs
navmap pixel_y. The navmap is essentially a downscaled rendering of
the 768 × 768 world: navmap col ≈ `global_x_center / 32`, pixel_y ≈
`(global_y_center − 20) / 4`. The artist hand-placed the navmap
sprites within a few pixels of the mathematical mapping, but the
ordering is exact.

### The 14 islands in absolute world coordinates

| Island             | cell   | local x   | local y   | **global x** | **global y** |
|--------------------|:------:|----------:|----------:|-------------:|-------------:|
| LAGOON ISLAND      | (0, 0) |  116-203  |  184-240  |   **116-203** |   **184-240** |
| ENTERPRISE ISLAND  | (0, 1) |   68-139  |  176-251  |    **68-139** |   **432-507** |
| LUKELAND ISLES     | (0, 2) |   48-109  |   48-108  |    **48-109** |   **560-620** |
| SKEG ISLAND        | (0, 2) |  112-173  |    0- 56  |   **112-173** |   **512-568** |
| KOKOLA ISLAND      | (1, 0) |   87-161  |  148-204  |   **343-417** |   **148-204** |
| GILLIGANS ISLAND   | (1, 0) |   28- 94  |   88-145  |   **284-350** |    **88-145** |
| BONE ISLAND        | (1, 0) |  172-255  |  124-180  |   **428-511** |   **124-180** |
| BASE ISLAND        | (1, 1) |   28-130  |   80-136  |   **284-386** |   **336-392** |
| GIANTS GATEWAY     | (1, 1) |  152-203  |   12- 80  |   **408-459** |   **268-336** |
| CLAW ISLAND        | (1, 1) |  196-253  |  192-254  |   **452-509** |   **448-510** |
| FORTE ROCKS        | (1, 2) |  136-211  |    0- 57  |   **392-467** |   **512-569** |
| RED ISLAND         | (1, 2) |  120-182  |   64-120  |   **376-438** |   **576-632** |
| PEAK ISLAND        | (2, 0) |   40-101  |   88-144  |   **552-613** |    **88-144** |
| BANANA ISLAND      | (2, 1) |   92-168  |  128-184  |   **604-680** |   **384-440** |

In global coords there are **no overlaps** — every island has a
disjoint rectangle. The ASCII archipelago in `ISLANDS.md` (which uses
local-cell coords and so puts everyone on one 256-grid) misrepresents
the layout; the real layout has open sea between cells.

### Practical consequences

- `extract_map.py` now emits both `cell` and `global_world_bounds` per
  island. Use `global_world_bounds` if you want a Pavero-style world
  map.
- `tools/build_full_map.py` currently composites onto a 256 × 256
  canvas using the helicopter's *current* `($7500, $7502)` (low bytes
  only). That happens to work as a rough sketch because the
  helicopter's high bytes change as it moves between cells, but the
  composite ignores the high bytes when placing islands — that's why
  the labels look misplaced. The fix is straightforward: enlarge the
  canvas to 768 × 768 and paste at `(cell_x*256 + xlo, cell_y*256 + ylo)`.
- "How does the helicopter cross between cells?" — by simple 16-bit
  arithmetic. The motion routine at `$81EC..$81F7` adds a velocity
  vector to the 16-bit position, so when the low byte wraps, the
  high byte naturally advances and the engine starts seeing a
  different set of records on the next frame.
