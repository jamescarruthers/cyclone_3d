#!/usr/bin/env python3
"""Compact build/cyclone-map.json into the minimum data the 3D web app needs.

Reads build/cyclone-map.json (produced by tools/extract_map.py) and emits
web/data.json with only the fields the browser needs to reconstruct the
archipelago in 3D — island positions, per-island tile grids, the 256-entry
tile_stacks (column heights & per-level tile index), the 256 attribute
bytes (Spectrum colour) and the 256 8x8 glyph bitmaps.

Reduces ~600 KB of richly-annotated JSON to ~80 KB of plain arrays so the
page can fetch it cheaply.

Usage:
    python3 tools/build_web_data.py [INPUT.json] [OUTPUT.json]
"""
import json
import sys
from pathlib import Path


def build(src: str, dst: str) -> None:
    data = json.loads(Path(src).read_text())

    # Compact tile_stacks: one entry per tile index, list of {tile, skip}
    # becomes a list of integers where -1 marks a "skip" level.
    stacks = []
    for stack in data["tile_stacks"]:
        stacks.append([-1 if e["skip"] else e["tile"] for e in stack])

    attrs = [a["value"] for a in data["tile_attributes"]]
    glyphs = [g["bytes"] for g in data["tile_glyphs"]]

    islands = []
    for isl in data["islands"]:
        gb = isl["global_world_bounds"]
        islands.append({
            "name": isl["name"],
            # World position of the (0, 0) cell of this island's tile grid.
            "x": gb["x_min"],
            "y": gb["y_min"],
            "tiles": isl["flight_shape"]["tiles"],
        })

    out = {
        "world_w": data["world"]["width"],
        "world_h": data["world"]["height"],
        "cell_size": data["world"]["cell_size"],
        "islands": islands,
        "stacks": stacks,
        "attrs": attrs,
        "glyphs": glyphs,
    }

    Path(dst).parent.mkdir(parents=True, exist_ok=True)
    with open(dst, "w") as f:
        json.dump(out, f, separators=(",", ":"))
        f.write("\n")

    size = Path(dst).stat().st_size
    print(f"Wrote {dst} ({size:,} bytes): "
          f"{len(islands)} islands, {len(stacks)} stacks, "
          f"{len(glyphs)} glyphs")


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else "build/cyclone-map.json"
    dst = sys.argv[2] if len(sys.argv) > 2 else "web/data.json"
    build(src, dst)
