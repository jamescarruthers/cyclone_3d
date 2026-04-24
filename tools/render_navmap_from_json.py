#!/usr/bin/env python3
"""Render Cyclone's navigation-map screen from cyclone-map.json alone.

Uses the per-island nav-map sprite + screen position decoded by
extract_map.py (via the algorithm at $8D5D-$8DA9).  This produces a
faithful reproduction of the in-game navigation map screen, suitable
for direct comparison with images/cyclone-map.png.

Usage:
    python3 tools/render_navmap_from_json.py [INPUT.json] [OUTPUT.png]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


# Spectrum playfield is 32 cols x 24 rows of 8x8 character cells.
# The navigation-map area lives in the left 23 cols x 22 rows.
SCALE = 3  # display 3x scale (matches sna2img.py default)


def render(json_path: str, out_path: str) -> None:
    data = json.loads(Path(json_path).read_text())

    # Native Spectrum screen 256x192.
    NW, NH = 256, 192
    img = Image.new("RGB", (NW * SCALE, NH * SCALE), (255, 255, 255))
    draw = ImageDraw.Draw(img)

    INK = (0, 160, 0)  # green ink, matches the in-game nav map
    LABEL = (0, 0, 0)

    for isl in data["islands"]:
        sprite = isl["navmap_sprite"]["bitmap"]
        pos = isl["navmap_position"]

        # Top-left pixel of the sprite on the native screen
        x0 = pos["col"] * 8
        y0 = pos["pixel_y"]

        # Each decoded row is one display-file scanline.  The renderer
        # advances the source pointer by +$0200 (2 scanlines) between
        # rows, but the destination only advances by 1 scanline per row.
        for row_idx, row_bytes in enumerate(sprite):
            y = y0 + row_idx
            x = x0
            for byte in row_bytes:
                for bit in range(8):
                    if byte & (0x80 >> bit):
                        px = (x + bit) * SCALE
                        py = y * SCALE
                        draw.rectangle(
                            [px, py, px + SCALE - 1, py + SCALE - 1], fill=INK
                        )
                x += 8

        # Name label to the right of the sprite (matches in-game layout)
        label_x = (x0 + isl["navmap_sprite"]["width_cols"] + 4) * SCALE
        label_y = (y0 + 2) * SCALE
        draw.text((label_x, label_y), isl["name"], fill=LABEL)

    # Frame and title
    draw.rectangle([0, 0, NW * SCALE - 1, NH * SCALE - 1],
                   outline=(0, 0, 0), width=2)
    draw.text((4, 4), "Cyclone navigation map — rendered from cyclone-map.json",
              fill=(0, 0, 0))

    img.save(out_path)
    print(f"Wrote {out_path} ({NW * SCALE}x{NH * SCALE})")


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "build/cyclone-map.json"
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-navmap-fromjson.png"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    render(src, out)
