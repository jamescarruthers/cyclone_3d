#!/usr/bin/env python3
"""Render Cyclone's world map using ONLY the data we extracted from the tape.

Zero runtime dependency on the RZX replay:
- Reads the 14-island master table at $F230 out of build/cyclone.z80
  (the snapshot we built directly from the original tape with tap2sna.py).
- For each island, reads the 16x16 tile-index map from its shape base
  pointer (+$0A/+$0B in the record).
- Resolves each non-zero tile via the game's colour table at $FE00 and
  the 8x8-pixel glyph font at $FA00.
- Composites the islands onto a canvas using the world x/y bounds from
  the record.

If this matches the archipelago's real layout, the data decoding in
cyclone.ctl is definitively correct — no external reference or RZX used.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw
from skoolkit.snapshot import Snapshot


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

# Spectrum 8-colour palette (RGB).  Non-bright entries use 215; bright 255.
BASE = [
    (  0,   0,   0),  # 0 black
    (  0,   0, 215),  # 1 blue
    (215,   0,   0),  # 2 red
    (215,   0, 215),  # 3 magenta
    (  0, 215,   0),  # 4 green
    (  0, 215, 215),  # 5 cyan
    (215, 215,   0),  # 6 yellow
    (215, 215, 215),  # 7 white
]
BRIGHT = [(255, 255, 255) if c == (215, 215, 215) else
          (255, 0, 0) if c == (215, 0, 0) else
          (0, 255, 0) if c == (0, 215, 0) else
          (0, 0, 255) if c == (0, 0, 215) else
          (0, 255, 255) if c == (0, 215, 215) else
          (255, 0, 255) if c == (215, 0, 215) else
          (255, 255, 0) if c == (215, 215, 0) else
          c for c in BASE]


def palette(attr: int):
    """Return (ink_rgb, paper_rgb) for a Spectrum attribute byte."""
    ink = attr & 7
    paper = (attr >> 3) & 7
    bright = (attr >> 6) & 1
    p = BRIGHT if bright else BASE
    return p[ink], p[paper]


def render_tile(glyph: bytes, attr: int) -> Image.Image:
    ink, paper = palette(attr)
    img = Image.new("RGB", (8, 8), paper)
    for y, byte in enumerate(glyph):
        for x in range(8):
            if byte & (0x80 >> x):
                img.putpixel((x, y), ink)
    return img


def render(snapshot_path: str, out_path: str) -> None:
    snap = Snapshot.get(snapshot_path)
    ram = bytes(snap.ram(-1))

    def at(addr: int, n: int = 1) -> bytes:
        return ram[addr - 0x4000 : addr - 0x4000 + n]

    # Cache attributes and 8-byte glyphs for each tile index.
    attrs = at(0xFE00, 256)
    glyphs = [at(0xFA00 + i * 8, 8) for i in range(256)]

    # World canvas. 256 world units x 256. Each tile of an island's 16x16
    # map ends up 1 px per world unit, giving a compact top-down view.
    PPU = 4  # pixels per world unit
    W = H = 256 * PPU
    SEA = (0, 216, 216)
    canvas = Image.new("RGB", (W, H), SEA)
    d = ImageDraw.Draw(canvas)

    for rec_addr, name in ISLANDS:
        rec = at(rec_addr, 20)
        xmin, xmax, ymin, ymax = rec[2], rec[3], rec[4], rec[5]
        shape_base = rec[10] | (rec[11] << 8)

        # Render 16x16 tile grid = 128x128 px
        island = Image.new("RGBA", (16 * 8, 16 * 8), (0, 0, 0, 0))
        for ty in range(16):
            for tx in range(16):
                idx = ram[shape_base - 0x4000 + ty * 16 + tx]
                if idx == 0:
                    continue
                tile = render_tile(glyphs[idx], attrs[idx])
                island.paste(tile, (tx * 8, ty * 8))

        # Paste the 128x128 island centred on its world-coordinate centre
        cx = (xmin + xmax) // 2 * PPU
        cy = (ymin + ymax) // 2 * PPU
        canvas.paste(island, (cx - 64, cy - 64), island)

        # Label each island above its bounds
        lp = (cx, (ymin * PPU) - 10)
        for ox, oy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
            d.text((lp[0] + ox, lp[1] + oy), name, fill=(0, 0, 0), anchor="mm")
        d.text(lp, name, fill=(255, 255, 255), anchor="mm")

    # Title card
    d.rectangle([0, 0, W - 1, H - 1], outline=(0, 0, 0), width=4)
    d.text((20, 20), "Cyclone (Vortex Software, 1985)",
           fill=(255, 255, 255))
    d.text((20, 40),
           "World map reconstructed ONLY from data in build/cyclone.z80",
           fill=(240, 240, 240))
    d.text((20, 60),
           "14 islands, master table $F230, shape data $9300-$CFFF, font $FA00, attrs $FE00",
           fill=(240, 240, 240))

    canvas.save(out_path)
    print(f"Wrote {out_path} ({W}x{H})")


if __name__ == "__main__":
    snap = sys.argv[1] if len(sys.argv) > 1 else "build/cyclone.z80"
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-world-fromdata.png"
    Path("images").mkdir(exist_ok=True)
    render(snap, out)
