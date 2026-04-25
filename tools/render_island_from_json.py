#!/usr/bin/env python3
"""Render a single island top-down from the flight-shape data in JSON.

Reads build/cyclone-map.json and renders the named island by:
  - For each (Y, X) tile in the island's flight_shape, look up the
    8x8 glyph bitmap at $FA00 + index*8.
  - Apply the attribute byte at $FE00 + index for ink/paper colours.
  - Composite at (X*8, Y*8) on a sea-coloured canvas.

The result is the same view the in-game 3D engine would show if you
flew the helicopter slowly across the entire island while looking
straight down — every glyph the engine reads is rendered exactly
where it would appear.

Usage:
    python3 tools/render_island_from_json.py [ISLAND_NAME] [SCALE]
        ISLAND_NAME defaults to BANANA ISLAND
        SCALE defaults to 4 (each glyph pixel becomes SCALExSCALE)
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


PAL_DIM = [(0,0,0),(0,0,215),(215,0,0),(215,0,215),
           (0,215,0),(0,215,215),(215,215,0),(215,215,215)]
PAL_BR = [(0,0,0),(0,0,255),(255,0,0),(255,0,255),
          (0,255,0),(0,255,255),(255,255,0),(255,255,255)]


def attr_colours(attr_value: int) -> tuple:
    p = PAL_BR if attr_value & 0x40 else PAL_DIM
    return p[attr_value & 7], p[(attr_value >> 3) & 7]


def render(json_path: str, island_name: str, scale: int, out_path: str) -> None:
    data = json.loads(Path(json_path).read_text())
    glyphs = {g["index"]: g["bytes"] for g in data["tile_glyphs"]}
    attrs = {a["index"]: a["value"] for a in data["tile_attributes"]}

    isl = next((i for i in data["islands"] if i["name"] == island_name), None)
    if isl is None:
        print(f"Unknown island {island_name!r}.  Known islands:")
        for i in data["islands"]:
            print(f"  - {i['name']}")
        sys.exit(2)

    fs = isl["flight_shape"]
    rows = fs["tiles"]
    H, W = len(rows), len(rows[0])

    # 8 native pixels per tile, scaled.
    SEA = (0, 64, 128)
    img = Image.new("RGB", (W * 8 * scale, H * 8 * scale), SEA)

    for y, row in enumerate(rows):
        for x, idx in enumerate(row):
            if idx == 0:
                continue
            ink, paper = attr_colours(attrs[idx])
            for dy, byte in enumerate(glyphs[idx]):
                for dx in range(8):
                    px = ink if byte & (0x80 >> dx) else paper
                    x0 = (x * 8 + dx) * scale
                    y0 = (y * 8 + dy) * scale
                    for sy in range(scale):
                        for sx in range(scale):
                            img.putpixel((x0 + sx, y0 + sy), px)

    # Title bar
    draw = ImageDraw.Draw(img)
    title = f"{island_name}  —  rendered from cyclone-map.json"
    draw.rectangle([0, 0, img.width - 1, 24], fill=(0, 0, 0))
    draw.text((8, 6), title, fill=(255, 255, 255))
    info = (f"flight_shape  {W}x{H} tiles  "
            f"world (x={fs['world_x_range'][0]}-{fs['world_x_range'][1]}, "
            f"y={fs['world_y_range'][0]}-{fs['world_y_range'][1]})")
    draw.text((8, img.height - 18), info, fill=(255, 255, 255),
              stroke_width=2, stroke_fill=(0, 0, 0))

    img.save(out_path)
    print(f"Wrote {out_path} ({img.width}x{img.height})")


if __name__ == "__main__":
    name = sys.argv[1] if len(sys.argv) > 1 else "BANANA ISLAND"
    scale = int(sys.argv[2]) if len(sys.argv) > 2 else 4
    out = f"images/island-{name.replace(' ', '_').lower()}.png"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    render("build/cyclone-map.json", name, scale, out)
