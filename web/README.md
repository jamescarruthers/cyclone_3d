# Cyclone 3D — isometric world map

A browser app that turns Cyclone's 14-island archipelago into a navigable 3D
isometric world.  Every cell of every island becomes a stack of cubes whose
colours come from the game's Spectrum attribute table at `$FE00` and whose
top faces are textured with the original 8×8 glyphs from the font at
`$FA00`.  Stack heights come from the `$6300/$6400/…` vertical-stack
lookup tables that drive Cyclone's flight-mode terrain renderer at
`#R$7E10`.

## Running

The page uses ES module imports and `fetch()`, so it needs to be served
over HTTP — opening `index.html` from disk won't work.

From the repo root:

```sh
make webdata        # rebuild web/data.json from build/cyclone-map.json
python3 -m http.server 8000
# then open http://localhost:8000/web/
```

`web/data.json` is committed, so the `make webdata` step is only needed if
you regenerate `build/cyclone-map.json` (e.g. after editing
`tools/extract_map.py`).

## Controls

| Action            | Keys / mouse                                  |
| ----------------- | --------------------------------------------- |
| Pan               | <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> / arrows / left-drag |
| Rotate            | <kbd>Q</kbd>/<kbd>E</kbd> / right-drag        |
| Pitch             | <kbd>R</kbd>/<kbd>F</kbd>                     |
| Zoom              | mouse wheel / pinch                           |
| Jump to island    | <kbd>1</kbd>…<kbd>9</kbd>, <kbd>0</kbd> / click legend |
| Reset view        | <kbd>Space</kbd>                              |
| Toggle ground glyphs | <kbd>G</kbd> (debug — show flat colour without 8×8 glyph texture) |

## How it's built

The whole pipeline goes:

1. `tap2sna.py` decrypts the SpeedLock-loaded tape into `build/cyclone.z80`.
2. `rzxplay.py cyclone.rzx` produces a post-init snapshot
   (`build/cyclone-endgame.z80`) so the shape data at `$9300-$CFFF` is
   populated.
3. `tools/extract_map.py` walks the master table at `$F230`, decodes each
   island's flight-mode tile grid (clipped to the engine's actual read
   window — see `extract_flight_shape()`), and dumps it together with the
   font, attribute table and 256 vertical-stack tables to
   `build/cyclone-map.json`.
4. `tools/build_web_data.py` strips the rich JSON down to the minimum the
   browser needs and writes `web/data.json`.
5. `web/app.js` (Three.js + an orthographic isometric camera) walks every
   cell of every island, looks up `data.stacks[tile]` for the column, and
   builds one cube per non-empty stack level.  All cubes are merged into a
   small number of `BufferGeometry` chunks sharing a single 128×128 atlas
   texture (the 16×16 grid of 8×8 glyphs, each rendered with its
   attribute's ink and paper).

The result is roughly 30 000 cubes across 14 islands in a 768×768 world,
rendered in two or three draw calls.
