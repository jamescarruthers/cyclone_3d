#!/usr/bin/env python3
"""Reconstruct the full Cyclone world map from actual in-game screenshots.

Scans the shipped RZX replay, finds the frame where the helicopter is best
centred over each of the 14 islands (bounds taken from the decoded master
table at $F230), grabs a snapshot, renders the screen via sna2img.py, then
crops the playfield and composites all 14 onto a single 768x768 canvas at
each island's GLOBAL world coordinates.

The world is not 256x256 but 768x768: a 3x3 grid of 256x256 cells indexed
by the high bytes of helX ($7501) and helY ($7503).  Each master-table
record carries (cell_x, cell_y) at +$00/+$01 and a local low-byte rectangle
at +$02..+$05.  The helicopter's true position in the world is therefore
(cell_x*256 + xlo, cell_y*256 + ylo) — that's the coordinate we paste at.

The point: every step uses the actual game's data or its own renderer
— no hand-drawn island artwork, no custom geometry.  If the composite
matches reference maps such as Pavero's 2004 one, the decoding in
cyclone.ctl is correct.
"""
import glob
import re
import subprocess
import sys
from pathlib import Path

from PIL import Image
from skoolkit.snapshot import Snapshot


# (record addr, shape base, human name, cell_x, cell_y, (x_min, x_max, y_min, y_max))
# Local low-byte bounds within the cell.  Global = cell*256 + local.
ISLANDS = [
    (0xF230, 0x9300, "BANANA ISLAND",     2, 1, ( 92, 168, 128, 184)),
    (0xF244, 0x9D00, "FORTE ROCKS",       1, 2, (136, 211,   0,  57)),
    (0xF258, 0xA900, "KOKOLA ISLAND",     1, 0, ( 87, 161, 148, 204)),
    (0xF26C, 0xB600, "LAGOON ISLAND",     0, 0, (116, 203, 184, 240)),
    (0xF280, 0xC300, "PEAK ISLAND",       2, 0, ( 40, 101,  88, 144)),
    (0xF294, 0xCF80, "BASE ISLAND",       1, 1, ( 28, 130,  80, 136)),
    (0xF2A8, 0x9354, "GILLIGANS ISLAND",  1, 0, ( 28,  94,  88, 145)),
    (0xF2BC, 0x9FD8, "RED ISLAND",        1, 2, (120, 182,  64, 120)),
    (0xF2D0, 0xADD8, "SKEG ISLAND",       0, 2, (112, 173,   0,  56)),
    (0xF2E4, 0xB843, "BONE ISLAND",       1, 0, (172, 255, 124, 180)),
    (0xF2F8, 0x9337, "GIANTS GATEWAY",    1, 1, (152, 203,  12,  80)),
    (0xF30C, 0xA735, "CLAW ISLAND",       1, 1, (196, 253, 192, 254)),
    (0xF320, 0xC628, "LUKELAND ISLES",    0, 2, ( 48, 109,  48, 108)),
    (0xF334, 0xC64F, "ENTERPRISE ISLAND", 0, 1, ( 68, 139, 176, 251)),
]


def is_flight_view(ram: bytes) -> bool:
    """Heuristic: in the 3D flight view the playfield attribute rows use
    cyan paper (sea); in the pop-up navigation map they use white paper."""
    attr = ram[0x1800:0x1B00]  # $5800-$5AFF
    cyan = white = 0
    for row in range(19):
        for col in range(22):
            paper = (attr[row * 32 + col] >> 3) & 7
            if paper == 5: cyan += 1
            elif paper == 7: white += 1
    return cyan > white


def pick_best_frames(scan_dir: str) -> dict:
    """Scan snapshot dir, return {island_name: (frame, snapshot_path)}.

    Compares the FULL 16-bit helicopter position (cell + local) against each
    island's full (cell, local-bounds) rectangle.  This rules out spurious
    matches when the low bytes happen to fall in another cell's island
    rectangle (e.g. helX-low=92 is "BANANA's range" only when cell_x=2;
    when cell_x=0 the same low byte is over LAGOON ISLAND).
    """
    paths = sorted(
        glob.glob(f"{scan_dir}/f*.z80"),
        key=lambda p: int(re.search(r"f(\d+)", p).group(1)),
    )
    best = {}
    for p in paths:
        frame = int(re.search(r"f(\d+)", p).group(1))
        ram = bytes(Snapshot.get(p).ram(-1))
        xlo, xhi = ram[0x7500 - 0x4000], ram[0x7501 - 0x4000]
        ylo, yhi = ram[0x7502 - 0x4000], ram[0x7503 - 0x4000]
        mode = ram[0x7505 - 0x4000]
        if mode != 0:
            continue
        if not is_flight_view(ram):
            continue
        for _, _, name, cx_cell, cy_cell, (xmin, xmax, ymin, ymax) in ISLANDS:
            if (xhi, yhi) != (cx_cell, cy_cell):
                continue
            if not (xmin <= xlo <= xmax and ymin <= ylo <= ymax):
                continue
            mid_x, mid_y = (xmin + xmax) // 2, (ymin + ymax) // 2
            dist = max(abs(xlo - mid_x), abs(ylo - mid_y))
            if name not in best or dist < best[name][0]:
                best[name] = (dist, frame, p)
    return {name: (f, p) for name, (_, f, p) in best.items()}


def render_snapshot(snap_path: str, out_png: str) -> None:
    subprocess.run(
        ["sna2img.py", "-s", "1", snap_path, out_png],
        check=True, capture_output=True,
    )


def compose_map(best: dict, out_path: str) -> None:
    # Playfield occupies roughly the left 22 char columns (176 px wide) by
    # the top 19 char rows (152 px tall); the HUD / ammo row sits to the
    # right and below.
    PLAY = (0, 0, 176, 152)  # left, top, right, bottom

    # World canvas — 768 world units per axis (3 cells x 256).
    PPU = 8
    WORLD = 768
    W = H = WORLD * PPU
    SEA = (0, 216, 216)  # Cyclone's in-game cyan
    canvas = Image.new("RGB", (W, H), SEA)

    tmpdir = Path("build/tmp")
    tmpdir.mkdir(parents=True, exist_ok=True)

    from PIL import ImageDraw
    d = ImageDraw.Draw(canvas)

    for rec, base, name, cx_cell, cy_cell, (xmin, xmax, ymin, ymax) in ISLANDS:
        if name not in best:
            print(f'  skip {name}: no frame found')
            continue
        frame, snap_path = best[name]

        # Render this snapshot to PNG, crop the playfield
        png_path = tmpdir / f"{name.replace(' ', '_')}.png"
        render_snapshot(snap_path, str(png_path))
        screen = Image.open(png_path).convert("RGB").crop(PLAY)

        # Transparent-mask the cyan "sea" pixels so tiles blend cleanly
        mask = Image.new("L", screen.size, 0)
        px_screen = screen.load()
        px_mask = mask.load()
        for yy in range(screen.size[1]):
            for xx in range(screen.size[0]):
                r, g, b = px_screen[xx, yy]
                # Treat anything not pure cyan/dark-cyan as "land"
                is_sea = (abs(r) + abs(g - 200) + abs(b - 216) < 80) or \
                         (r == 0 and g == 216 and b == 216) or \
                         (r == 0 and g == 184 and b == 184)
                px_mask[xx, yy] = 0 if is_sea else 255

        # Read actual 16-bit helicopter (x, y) at this frame
        ram = bytes(Snapshot.get(snap_path).ram(-1))
        xlo = ram[0x7500 - 0x4000]
        xhi = ram[0x7501 - 0x4000]
        ylo = ram[0x7502 - 0x4000]
        yhi = ram[0x7503 - 0x4000]
        hx = xhi * 256 + xlo  # global X
        hy = yhi * 256 + ylo  # global Y

        # Paste so the helicopter's GLOBAL world position maps to the
        # playfield centre on the canvas.
        pw, ph = PLAY[2] - PLAY[0], PLAY[3] - PLAY[1]
        px = hx * PPU - pw // 2
        py = hy * PPU - ph // 2
        canvas.paste(screen, (px, py), mask)

        # Label above each island's GLOBAL world centre
        gxmin = cx_cell * 256 + xmin
        gxmax = cx_cell * 256 + xmax
        gymin = cy_cell * 256 + ymin
        gymax = cy_cell * 256 + ymax
        cx, cy = (gxmin + gxmax) // 2 * PPU, (gymin + gymax) // 2 * PPU
        label_y = cy - (gymax - gymin) // 2 * PPU - 10
        for ox, oy in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1)]:
            d.text((cx + ox, label_y + oy), name, fill=(0, 0, 0), anchor="mm")
        d.text((cx, label_y), name, fill=(255, 255, 255), anchor="mm")

        print(f'  pasted {name:20} at global ({hx},{hy}) '
              f'cell=({xhi},{yhi}) local=({xlo},{ylo}) frame {frame}')

    # Title card
    d.rectangle([0, 0, W - 1, H - 1], outline=(0, 0, 0), width=4)
    d.text((20, 20), "Cyclone (Vortex Software, 1985)",
           fill=(255, 255, 255))
    d.text((20, 40),
           f"World map reconstructed from RZX gameplay screenshots — "
           f"{WORLD}x{WORLD} world (3x3 cells of 256x256)",
           fill=(240, 240, 240))
    d.text((20, 60),
           f"{len(best)}/14 islands captured; positions from master table at $F230",
           fill=(240, 240, 240))

    canvas.save(out_path)
    print(f"Wrote {out_path} ({W}x{H})")


def main():
    scan_dir = sys.argv[1] if len(sys.argv) > 1 else "build/scan"
    out = sys.argv[2] if len(sys.argv) > 2 else "images/cyclone-full-map.png"

    best = pick_best_frames(scan_dir)
    compose_map(best, out)


if __name__ == "__main__":
    main()
