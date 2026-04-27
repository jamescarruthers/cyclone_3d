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

> ⚠️ **What this guide does NOT explain.**
> The 14 islands' world rectangles overlap each other heavily (21
> overlapping pairs!). They cannot all live in one shared 256×256 plane
> at the same time. The master table includes a `(type, subtype)`
> selector that the engine matches *before* the X/Y bound check, so
> at any given moment only a subset of islands is "active." The full
> archipelago you see in published reference maps and on the
> in-game navigation screen is the **union of multiple subsets**, and
> the algorithm that spreads them out into one big world is **not**
> currently decoded. The per-island PNGs in this repo are correct in
> each island's *own* coordinate frame — but if you stitch them
> together using the master-table `x_min`/`y_min` fields directly
> (the way `tools/build_full_map.py` does), they will sit on top of
> each other. That's a known limitation, not a bug in the per-island
> PNGs.

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

## 5. The 23 × 29 LDIR window (and why it doesn't matter for offline render)

When you actually play the game, the engine doesn't render the whole
island at once. Each frame it runs an LDIR loop that copies a
**23-column × 29-row window** of shape bytes into a working buffer at
`$F74E`, centred on the helicopter:

```
HL = shape_base
   + (helY - y_origin) * 128           # which row of shape data
   + (helX - x_origin)                 # which column
                                       # then LDIR copies 23 bytes,
                                       # advances HL by 128, repeats 29 times
```

For our offline PNG render we don't care about the helicopter — we
just want to see *every* byte the engine could ever read. The union of
all `helX ∈ [x_min, x_max]` × `helY ∈ [y_min, y_max]` LDIR windows is
exactly the rectangle:

```
shape rows 0 .. (y_max - y_min)
shape cols 0 .. (x_max - x_min)
```

→ **`width = x_max - x_min + 1`**, **`height = y_max - y_min + 1`**,
in world units. That's what the extractor dumps as `flight_shape.tiles`
in `cyclone-map.json`.

(*This was the bug behind the right-edge cutoff*: a previous fix used
`cols = x_upper - x_min`, which is `x_max - x_min - 22`, lopping off the
rightmost 23 columns. It was based on the wrong premise that `x_upper`
is the helicopter's hard right bound. It isn't — see §2.)

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

## 10. Open question: the global archipelago layout

The 14 islands' world rectangles overlap each other in the master
table. They cannot all coexist in one shared 256×256 plane at the same
time. Concretely:

```
BANANA ISLAND       x= 92-168  y=128-184   (type=2, sub=1)
KOKOLA ISLAND       x= 87-161  y=148-204   (type=1, sub=0)
LAGOON ISLAND       x=116-203  y=184-240   (type=0, sub=0)
PEAK ISLAND         x= 40-101  y= 88-144   (type=2, sub=0)
BASE ISLAND         x= 28-130  y= 80-136   (type=1, sub=1)
... etc
```

BANANA and KOKOLA both want world `(110, 160)`, but they have different
`(type, subtype)`. The engine's bound check at `$76EC..$7715` filters
records by `(type, subtype)` **first**, then by `(x, y)`. So at any
given moment only one island's bounds are even considered.

Within each `(type, subtype)` value, the bounds are disjoint — I
checked all pairs. So `(type, subtype)` is effectively a **scene
index**: each scene is a 256×256 plane containing 1-3 islands.

**What we don't yet know**: how the 14 islands are arranged into a
single big archipelago for human-readable world maps (Pavero's map,
the in-game navigation screen). The navigation screen position
(`+$0C..+$0D`) is a hand-placed display-file address per island; it
isn't computed from world coordinates. Whether the helicopter ever
crosses *between* scenes during normal gameplay — and if so, how the
"sea between scenes" is presented — is **not** decoded yet.

Practical implication for this repo:

- `images/island-<name>.png` (the per-island PNGs): **correct.**
  Each is rendered in its own scene's coordinate frame.
- `images/cyclone-full-map.png` (the stitched archipelago): **only
  approximate.** It pastes islands at their `(x_min, y_min)` on a single
  256×256 canvas, which is wrong precisely because the islands belong
  to different scenes. That's why some labels look misplaced.

If you want the *real* big-world layout, the missing piece is whatever
code or data tells the engine "scene `(type=1, sub=0)` lives at
archipelago position `(X, Y)`." That probably lives in the
mission/level setup code we haven't fully traced yet (somewhere
around the routines that initialise `($7501)` and `($7503)`).
