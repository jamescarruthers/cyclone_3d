#!/usr/bin/env python3
"""Render the whole archipelago — all 14 islands at their world positions
with the full $6300/$6400/$6500/... tile-stack pipeline.

Reads build/cyclone-map.json and produces a single composite PNG that
shows every island's 3D-stacked detail (cliffs, buildings, palms,
elevation) placed on a 256x256 world canvas.

Usage:
    python3 tools/render_world_from_json.py [SCALE] [OUTPUT.png]
        SCALE defaults to 2 (world unit -> 16 pixels)
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


def render(json_path: str, scale: int, out_path: str) -> None:
    data = json.loads(Path(json_path).read_text())
    glyphs = {g["index"]: g["bytes"] for g in data["tile_glyphs"]}
    attrs = {a["index"]: a["value"] for a in data["tile_attributes"]}
    tile_stacks = data["tile_stacks"]

    # World is 256x256 tile units; engine renders at 8 native pixels per
    # unit.  Add headroom above to fit the tallest stacks.
    max_stack = max((len(tile_stacks[v])
                    for isl in data["islands"]
                    for row in isl["flight_shape"]["tiles"]
                    for v in row), default=1)
    headroom = max_stack
    W = 256 * 8 * scale
    H = (256 + headroom) * 8 * scale

    # Default canvas is sea — attribute 0 in the engine's table.
    sea_attr = attrs[0]
    _, sea_paper = attr_colours(sea_attr)
    img = Image.new("RGB", (W, H), sea_paper)

    def draw_cell(idx: int, sx: int, sy: int) -> None:
        ink, paper = attr_colours(attrs[idx])
        bitmap_bytes = [0] * 8 if idx >= 0x80 else glyphs[idx]
        for dy, byte in enumerate(bitmap_bytes):
            for dx in range(8):
                px = ink if byte & (0x80 >> dx) else paper
                x0 = (sx + dx) * scale
                y0 = (sy + dy) * scale
                if 0 <= y0 < H and 0 <= x0 < W:
                    for sy_ in range(scale):
                        for sx_ in range(scale):
                            img.putpixel((x0 + sx_, y0 + sy_), px)

    # Render every island at its world position, with the full vertical
    # stack of cells for each shape byte (matches the engine's 3D look).
    # Y order matters: rendering north-to-south means later islands
    # correctly overlap earlier ones at lower world Y.  Stacks within an
    # island also draw bottom-up so closer cells overwrite farther ones.
    islands = sorted(data["islands"],
                     key=lambda i: i["world_bounds"]["y_min"])

    for isl in islands:
        fs = isl["flight_shape"]
        rows = fs["tiles"]
        # tiles spans data_x_range × world_y_range — the inner data X
        # extent (margins clipped to avoid bleed-through with neighbouring
        # islands sharing the same memory page) and the full world Y
        # range (helicopter approach length).
        x_origin = fs.get("data_x_range", fs["world_x_range"])[0]
        y_origin = fs["world_y_range"][0]

        for y, row in enumerate(rows):
            world_y = y_origin + y
            for x, raw in enumerate(row):
                world_x = x_origin + x
                stack = tile_stacks[raw]
                for level, entry in enumerate(stack):
                    if entry["skip"]:
                        continue
                    idx = entry["tile"]
                    sx = world_x * 8
                    sy = (world_y + headroom - level) * 8
                    draw_cell(idx, sx, sy)

    # Title
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, W - 1, 32], fill=(0, 0, 0))
    draw.text((10, 10),
              "Cyclone (Vortex Software, 1985) — full archipelago "
              "from cyclone-map.json (all 14 islands, 3D stacks)",
              fill=(255, 255, 255))

    img.save(out_path)
    print(f"Wrote {out_path} ({W}x{H})")


if __name__ == "__main__":
    scale = int(sys.argv[1]) if len(sys.argv) > 1 else 2
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-world-3d.png"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    render("build/cyclone-map.json", scale, out)
