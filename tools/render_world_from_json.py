#!/usr/bin/env python3
"""Render the whole archipelago — all 14 islands at their global world
positions with the full $6300/$6400/$6500/... tile-stack pipeline.

Cyclone's world is 768x768 in absolute units (a 3x3 grid of 256x256
cells; the helicopter position is 16-bit at $7500/$7501 and
$7502/$7503).  This renderer uses each island's global_world_bounds
field so islands appear at their true archipelago positions, not
piled on top of each other in a single 256x256 frame.

Reads build/cyclone-map.json and produces a single composite PNG.

Usage:
    python3 tools/render_world_from_json.py [SCALE] [OUTPUT.png]
        SCALE defaults to 1 (world unit -> 8 native pixels)
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

    world = data["world"]
    world_w = world["width"]
    world_h = world["height"]

    # Add headroom above so tall stacks don't get clipped at the top.
    max_stack = max((len(tile_stacks[v])
                    for isl in data["islands"]
                    for row in isl["flight_shape"]["tiles"]
                    for v in row), default=1)
    headroom = max_stack
    W = world_w * 8 * scale
    H = (world_h + headroom) * 8 * scale

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

    # Render every island at its GLOBAL world position, with the full
    # vertical stack of cells for each shape byte.  Sort by global y_min
    # so northern islands draw first and southern ones overlap them.
    islands = sorted(data["islands"],
                     key=lambda i: i["global_world_bounds"]["y_min"])

    for isl in islands:
        fs = isl["flight_shape"]
        rows = fs["tiles"]
        # global_world_bounds.x_min/y_min map to flight_shape row/col 0.
        # No mask or trim needed: extract_map.py already clipped to the
        # engine's exact read window per the south/right self-modifying
        # variants, so every byte here is one the engine reads for THIS
        # island and only this island.
        gx_origin = isl["global_world_bounds"]["x_min"]
        gy_origin = isl["global_world_bounds"]["y_min"]

        for y, row in enumerate(rows):
            world_y = gy_origin + y
            for x, raw in enumerate(row):
                world_x = gx_origin + x
                stack = tile_stacks[raw]
                for level, entry in enumerate(stack):
                    if entry["skip"]:
                        continue
                    idx = entry["tile"]
                    sx = world_x * 8
                    sy = (world_y + headroom - level) * 8
                    draw_cell(idx, sx, sy)

    # Title bar + island labels.
    draw = ImageDraw.Draw(img)
    draw.rectangle([0, 0, W - 1, 32], fill=(0, 0, 0))
    draw.text((10, 10),
              f"Cyclone (Vortex Software, 1985) — full archipelago, "
              f"{world_w}x{world_h} world ({world['cells_x']}x{world['cells_y']} "
              f"cells of {world['cell_size']}) — all 14 islands, 3D stacks",
              fill=(255, 255, 255))

    for isl in data["islands"]:
        gb = isl["global_world_bounds"]
        cx = (gb["x_min"] + gb["x_max"]) // 2 * 8 * scale
        ly = (gb["y_min"] - 2) * 8 * scale + headroom * 8 * scale
        for ox, oy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            draw.text((cx + ox, ly + oy), isl["name"],
                      fill=(0, 0, 0), anchor="mm")
        draw.text((cx, ly), isl["name"], fill=(255, 255, 255), anchor="mm")

    img.save(out_path)
    print(f"Wrote {out_path} ({W}x{H})")


if __name__ == "__main__":
    scale = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-world-3d.png"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    render("build/cyclone-map.json", scale, out)
