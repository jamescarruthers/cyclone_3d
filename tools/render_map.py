#!/usr/bin/env python3
"""Render Cyclone's world map to PNG.

Reads the 14-island master table at $F230 and each island's 16x16 tile-map
at its +$0A/+$0B base pointer from a post-init snapshot
(build/cyclone-endgame.z80 by default). Each tile index dereferences an
8x8-pixel glyph at $FA00 + index*8. Islands are composited onto a
256-world-unit canvas at their world-coordinate centres.

Usage:
    python3 tools/render_map.py [SNAPSHOT] [OUTPUT.png]
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont
from skoolkit.snapshot import Snapshot


# Master-table record addresses -> (shape base, human name)
ISLANDS = [
    (0xF230, "BANANA ISLAND"),
    (0xF244, "FORTE ROCKS"),
    (0xF258, "KOKOLA ISLAND"),
    (0xF26C, "LAGOON ISLAND"),
    (0xF280, "PEAK ISLAND"),
    (0xF294, "BASE ISLAND"),
    (0xF2A8, "GILLIGANS ISLAND"),
    (0xF2BC, "RED ISLAND"),
    (0xF2D0, "SKEG ISLAND"),
    (0xF2E4, "BONE ISLAND"),
    (0xF2F8, "GIANTS GATEWAY"),
    (0xF30C, "CLAW ISLAND"),
    (0xF320, "LUKELAND ISLES"),
    (0xF334, "ENTERPRISE ISLAND"),
]

SEA = (36, 88, 176)
LAND = (240, 232, 192)
INK = (20, 20, 32)


def render(snapshot_path: str, out_path: str) -> None:
    snap = Snapshot.get(snapshot_path)
    ram = bytes(snap.ram(-1))

    def at(addr: int, n: int = 1) -> bytes:
        return ram[addr - 0x4000 : addr - 0x4000 + n]

    # Sanity: verify the master table is populated
    first_rec = at(0xF230, 20)
    if first_rec[0] == 0xFF or all(b == 0 for b in first_rec):
        raise SystemExit(
            f"{snapshot_path}: island table at $F230 is empty — "
            "use a post-init snapshot (run `make midgame`)."
        )

    # World canvas: 256 world units x 256. 3 px per unit = 768 px, so the
    # 128-px island bitmaps are big enough to read against the canvas.
    SCALE = 3  # px per world unit
    W = 256 * SCALE
    H = 256 * SCALE

    img = Image.new("RGB", (W, H), SEA)

    def render_glyph(gidx: int) -> Image.Image:
        """Decode one 8x8 glyph at $FA00 + gidx*8 into a 2-colour image."""
        gaddr = 0xFA00 + gidx * 8
        if gaddr + 8 > 0x10000:
            return Image.new("RGB", (8, 8), SEA)
        bytes_ = at(gaddr, 8)
        g = Image.new("RGB", (8, 8), SEA)
        for y, byte in enumerate(bytes_):
            for x in range(8):
                if byte & (0x80 >> x):
                    g.putpixel((x, y), LAND)
        return g

    # For each island, render its 16x16 tile map into a 128x128 bitmap
    # then paste onto the world canvas at (cx, cy).
    overlay = Image.new("RGB", (W, H), SEA)
    draw = ImageDraw.Draw(img)

    for rec_addr, name in ISLANDS:
        rec = at(rec_addr, 20)
        xmin, xmax, ymin, ymax = rec[2], rec[3], rec[4], rec[5]
        shape_base = rec[10] | (rec[11] << 8)
        # 16x16 tiles at shape_base
        island = Image.new("RGB", (16 * 8, 16 * 8), SEA)
        for ty in range(16):
            for tx in range(16):
                idx = ram[shape_base - 0x4000 + ty * 16 + tx]
                if idx == 0:
                    continue
                g = render_glyph(idx)
                island.paste(g, (tx * 8, ty * 8))

        # Place at world centre.  Island bitmap is 128 px;
        # world centre in px = ((x_min + x_max) / 2) * SCALE.
        cx_world = (xmin + xmax) // 2
        cy_world = (ymin + ymax) // 2
        px = cx_world * SCALE - (16 * 8) // 2
        py = cy_world * SCALE - (16 * 8) // 2
        # Paste with mask so the sea around the island stays the canvas sea colour
        mask = Image.eval(island.convert("L"), lambda v: 0 if v < 40 else 255)
        img.paste(island, (px, py), mask)

        # Label each island with a dark halo so it reads against the ocean
        label_pos = (cx_world * SCALE, cy_world * SCALE + 72)
        for ox, oy in [(-1,0),(1,0),(0,-1),(0,1)]:
            draw.text((label_pos[0]+ox, label_pos[1]+oy), name,
                      fill=(0, 0, 0), anchor="mm")
        draw.text(label_pos, name, fill=(255, 255, 220), anchor="mm")

    # Frame + title
    title_draw = ImageDraw.Draw(img)
    title_draw.rectangle([0, 0, W - 1, H - 1], outline=(0, 0, 0), width=2)
    title_draw.text((12, 8), "Cyclone (Vortex Software, 1985)", fill=(255, 255, 255))
    title_draw.text((12, 24), "World map reconstructed from snapshot", fill=(230, 230, 230))

    img.save(out_path)
    print(f"Wrote {out_path} ({W}x{H})")

    # Also render a clean silhouette version: every non-zero tile index
    # becomes a solid land block, giving a readable top-down map view.
    silo = Image.new("RGB", (W, H), SEA)
    sdraw = ImageDraw.Draw(silo)
    for rec_addr, name in ISLANDS:
        rec = at(rec_addr, 20)
        xmin, xmax, ymin, ymax = rec[2], rec[3], rec[4], rec[5]
        shape_base = rec[10] | (rec[11] << 8)
        cx_world = (xmin + xmax) // 2
        cy_world = (ymin + ymax) // 2
        # Each tile -> SCALE*2 px square of land (2 world units per tile,
        # scaled to canvas). Islands are roughly 16 tiles wide.
        TILE_PX = SCALE * 2
        # Top-left corner of the island's tile grid on the canvas
        grid_w = 16 * TILE_PX
        ox = cx_world * SCALE - grid_w // 2
        oy = cy_world * SCALE - grid_w // 2
        for ty in range(16):
            for tx in range(16):
                idx = ram[shape_base - 0x4000 + ty * 16 + tx]
                if idx == 0:
                    continue
                sdraw.rectangle(
                    [ox + tx * TILE_PX, oy + ty * TILE_PX,
                     ox + (tx + 1) * TILE_PX - 1, oy + (ty + 1) * TILE_PX - 1],
                    fill=LAND,
                )
        # Label
        lp = (cx_world * SCALE, cy_world * SCALE + grid_w // 2 + 8)
        for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]:
            sdraw.text((lp[0]+dx, lp[1]+dy), name, fill=(0,0,0), anchor="mm")
        sdraw.text(lp, name, fill=(255,255,220), anchor="mm")

    sdraw.rectangle([0,0,W-1,H-1], outline=(0,0,0), width=2)
    sdraw.text((12, 8), "Cyclone (Vortex Software, 1985)", fill=(255,255,255))
    sdraw.text((12, 24), "World map — silhouette (land = any non-zero tile)", fill=(230,230,230))
    silo_path = str(Path(out_path).with_name(Path(out_path).stem + "-silhouette.png"))
    silo.save(silo_path)
    print(f"Wrote {silo_path} ({W}x{H})")


if __name__ == "__main__":
    snap = sys.argv[1] if len(sys.argv) > 1 else "build/cyclone-endgame.z80"
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-world.png"
    render(snap, out)
