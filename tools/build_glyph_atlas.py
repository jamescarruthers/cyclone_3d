#!/usr/bin/env python3
"""Build a visual atlas of all 256 tile glyphs grouped by category.

Reads build/cyclone-map.json and writes a single PNG that shows every
glyph at large size, labelled with index and grouped by the heuristic
category assigned in extract_map.py.  Useful for verifying the
categorisation by eye and for tagging individual glyphs by hand.

Usage:
    python3 tools/build_glyph_atlas.py [INPUT.json] [OUTPUT.png]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


CELL = 24      # pixel size per glyph
GAP = 6
COLS = 16


def render(json_path: str, out_path: str) -> None:
    data = json.loads(Path(json_path).read_text())
    glyphs = data["tile_glyphs"]
    cats = data["glyph_categories"]

    # Layout: one row of "category header" + N rows of glyph cells.
    # Estimate total rows.
    rows_total = sum(2 + (len(idxs) + COLS - 1) // COLS for idxs in cats.values())
    H = rows_total * (CELL + GAP) + 80
    W = COLS * (CELL + GAP) + 60

    img = Image.new("RGB", (W, H), (240, 240, 240))
    draw = ImageDraw.Draw(img)
    draw.text((20, 14), f"Cyclone tile glyph atlas — {len(glyphs)} glyphs",
              fill=(0, 0, 0))
    draw.text((20, 32),
              "Categories assigned heuristically by extract_map.py "
              "(see categorise_glyph())",
              fill=(80, 80, 80))

    y = 60
    for cat, idxs in sorted(cats.items(), key=lambda kv: -len(kv[1])):
        draw.text((20, y), f"{cat}  ({len(idxs)} glyphs)", fill=(0, 0, 96))
        y += 18
        col = 0
        for idx in idxs:
            g = glyphs[idx]["bytes"]
            x = 30 + col * (CELL + GAP)
            # Draw the 8x8 glyph at 3x scale (24x24)
            draw.rectangle([x, y, x + CELL - 1, y + CELL - 1],
                           outline=(160, 160, 160))
            for dy, byte in enumerate(g):
                for dx in range(8):
                    if byte & (0x80 >> dx):
                        draw.rectangle([x + dx * 3, y + dy * 3,
                                        x + dx * 3 + 2, y + dy * 3 + 2],
                                       fill=(0, 0, 0))
            draw.text((x, y + CELL + 1), f"{idx}", fill=(80, 80, 80))
            col += 1
            if col >= COLS:
                col = 0
                y += CELL + 14
        if col > 0:
            y += CELL + 14
        y += 10

    img.save(out_path)
    print(f"Wrote {out_path} ({W}x{y})")


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "build/cyclone-map.json"
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-glyph-atlas.png"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    render(src, out)
