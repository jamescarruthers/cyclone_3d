#!/usr/bin/env python3
"""Reference consumer: render Cyclone's world from cyclone-map.json alone.

Reads ONLY build/cyclone-map.json (no Z80 snapshot, no skoolkit).  If this
produces the expected archipelago, the JSON is a self-contained portable
representation of Cyclone's map data.

Usage:
    python3 tools/render_from_json.py [INPUT.json] [OUTPUT.png]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


# Spectrum 8-colour palette.  Non-bright entries use 215, bright 255.
COLOURS = {
    "black":   ((0, 0, 0),     (0, 0, 0)),
    "blue":    ((0, 0, 215),   (0, 0, 255)),
    "red":     ((215, 0, 0),   (255, 0, 0)),
    "magenta": ((215, 0, 215), (255, 0, 255)),
    "green":   ((0, 215, 0),   (0, 255, 0)),
    "cyan":    ((0, 215, 215), (0, 255, 255)),
    "yellow":  ((215, 215, 0), (255, 255, 0)),
    "white":   ((215, 215, 215), (255, 255, 255)),
}


def rgb(name: str, bright: bool) -> tuple:
    return COLOURS[name][1 if bright else 0]


def render_tile(glyph_bytes: list, attr: dict) -> Image.Image:
    ink = rgb(attr["ink"], attr["bright"])
    paper = rgb(attr["paper"], attr["bright"])
    img = Image.new("RGB", (8, 8), paper)
    for y, byte in enumerate(glyph_bytes):
        for x in range(8):
            if byte & (0x80 >> x):
                img.putpixel((x, y), ink)
    return img


def render(json_path: str, out_path: str) -> None:
    data = json.loads(Path(json_path).read_text())

    glyphs = {g["index"]: g["bytes"] for g in data["tile_glyphs"]}
    attrs = {a["index"]: a for a in data["tile_attributes"]}

    PPU = 4
    W = H = 256 * PPU
    SEA = (0, 216, 216)
    canvas = Image.new("RGB", (W, H), SEA)
    draw = ImageDraw.Draw(canvas)

    for isl in data["islands"]:
        wb = isl["world_bounds"]
        cx = (wb["x_min"] + wb["x_max"]) // 2 * PPU
        cy = (wb["y_min"] + wb["y_max"]) // 2 * PPU

        island = Image.new("RGBA", (16 * 8, 16 * 8), (0, 0, 0, 0))
        for ty, row in enumerate(isl["tiles"]):
            for tx, idx in enumerate(row):
                if idx == 0:
                    continue
                tile = render_tile(glyphs[idx], attrs[idx])
                island.paste(tile, (tx * 8, ty * 8))

        canvas.paste(island, (cx - 64, cy - 64), island)

        lp = (cx, (wb["y_min"] * PPU) - 10)
        for ox, oy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            draw.text((lp[0] + ox, lp[1] + oy), isl["name"],
                      fill=(0, 0, 0), anchor="mm")
        draw.text(lp, isl["name"], fill=(255, 255, 255), anchor="mm")

    draw.rectangle([0, 0, W - 1, H - 1], outline=(0, 0, 0), width=4)
    draw.text((20, 20), "Cyclone (Vortex Software, 1985)", fill=(255, 255, 255))
    draw.text((20, 40), f"Rendered from {json_path} — no snapshot, no emulator",
              fill=(240, 240, 240))

    canvas.save(out_path)
    print(f"Wrote {out_path} ({W}x{H})")


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "build/cyclone-map.json"
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-world-fromjson.png"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    render(src, out)
