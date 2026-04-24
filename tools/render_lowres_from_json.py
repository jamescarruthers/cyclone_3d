#!/usr/bin/env python3
"""Render Cyclone's world from the JSON at the in-game nav-map resolution.

The in-game navigation map renders each island's 16x16 tile grid at
roughly 1 pixel per tile (so each island becomes a small ~2-3 char wide
icon) and uses a single fixed ink colour rather than per-tile attributes.

This script produces the same low-res monochrome view from
build/cyclone-map.json so the result can be compared directly against
images/cyclone-map.png.

Usage:
    python3 tools/render_lowres_from_json.py [INPUT.json] [OUTPUT.png]
"""
import json
import sys
from pathlib import Path

from PIL import Image, ImageDraw


WORLD_W = 256
WORLD_H = 256
SCALE = 2  # pixels per world unit; gives a 512x512 image, easy to read.


def render(json_path: str, out_path: str) -> None:
    data = json.loads(Path(json_path).read_text())
    W, H = WORLD_W * SCALE, WORLD_H * SCALE

    img = Image.new("RGB", (W, H), (255, 255, 255))  # white paper
    draw = ImageDraw.Draw(img)

    INK = (0, 160, 0)  # green ink, matches the in-game nav map

    for isl in data["islands"]:
        wb = isl["world_bounds"]
        cx = (wb["x_min"] + wb["x_max"]) // 2
        cy = (wb["y_min"] + wb["y_max"]) // 2

        # The 16x16 tile grid spans 16 world units centred on (cx, cy).
        # 1 world unit per tile, 1 tile per pixel -> 16x16-pixel icon.
        ox = cx - 8
        oy = cy - 8
        for ty, row in enumerate(isl["tiles"]):
            for tx, idx in enumerate(row):
                if idx == 0:
                    continue
                px = (ox + tx) * SCALE
                py = (oy + ty) * SCALE
                draw.rectangle(
                    [px, py, px + SCALE - 1, py + SCALE - 1],
                    fill=INK,
                )

        # Label to the right of the sprite, like the in-game map.
        lp = ((cx + 9) * SCALE, cy * SCALE)
        draw.text(lp, isl["name"], fill=(0, 0, 0), anchor="lm")

    draw.rectangle([0, 0, W - 1, H - 1], outline=(0, 0, 0), width=2)
    draw.text((10, 8), "Cyclone — low-res render of cyclone-map.json",
              fill=(0, 0, 0))
    draw.text((10, 24),
              f"1 tile = 1 world unit, {SCALE}px/unit, {WORLD_W}x{WORLD_H} world",
              fill=(0, 0, 0))

    img.save(out_path)
    print(f"Wrote {out_path} ({W}x{H})")


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "build/cyclone-map.json"
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-world-fromjson-lowres.png"
    Path(out).parent.mkdir(parents=True, exist_ok=True)
    render(src, out)
