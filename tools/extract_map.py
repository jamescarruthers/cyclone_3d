#!/usr/bin/env python3
"""Extract Cyclone's world map as portable data (JSON).

Reads a post-init snapshot (build/cyclone-endgame.z80 by default) and emits
a single JSON file with everything needed to reconstruct the archipelago in
any language or engine — no Z80 emulator required at consumption time:

  - 14 island records from the master table at $F230
    (type, sub-type, world bounds, altitude bounds, shape pointer, etc.)
  - per-island NAVIGATION-MAP sprite + screen position
    (decoded by the algorithm at $8D5D-$8DA9 — reads source bytes from
    shape_base+$0102 at stride 4 with threshold $0F, packs into bitmap)
  - per-island 16x16 OBJECT layout (people / palm trees / fuel pods at
    each tile of an island; this is what the flight engine projects via
    #R$7777, NOT a silhouette of the island shape)
  - the 8x8-pixel glyph font at $FA00 (1536 bytes -> 192 glyphs)
  - the tile attribute table at $FE00 (256 attribute bytes,
    decoded into ink/paper/bright/flash)

Decoding references in cyclone.ctl: the master record schema is documented
at $F230, the tile renderer is #R$762C, the navigation-map renderer is
$5B71-$5B81 -> $8D5D, and the world coordinates live at ($7500)/($7502).

Usage:
    python3 tools/extract_map.py [SNAPSHOT] [OUTPUT.json]
"""
import json
import sys
from pathlib import Path

from skoolkit.snapshot import Snapshot


MASTER_TABLE = 0xF230
RECORD_SIZE = 0x14
RECORD_COUNT = 14
END_MARKER = 0xFF
END_MARKER_ADDR = 0xF348

FONT = 0xFA00
ATTRS = 0xFE00
ATTRS_LEN = 0x100

# Spectrum 8-colour palette (215/255 split for non-bright/bright).
PALETTE = [
    "black", "blue", "red", "magenta",
    "green", "cyan", "yellow", "white",
]

# 14 island names in master-table order.  The names live in a shared compact
# control stream at $6A50 (decoded by #R$8D5D / #R$8DEB) so we hard-code the
# canonical list rather than re-implement the stream walker here.
ISLAND_NAMES = [
    "BANANA ISLAND",
    "FORTE ROCKS",
    "KOKOLA ISLAND",
    "LAGOON ISLAND",
    "PEAK ISLAND",
    "BASE ISLAND",
    "GILLIGANS ISLAND",
    "RED ISLAND",
    "SKEG ISLAND",
    "BONE ISLAND",
    "GIANTS GATEWAY",
    "CLAW ISLAND",
    "LUKELAND ISLES",
    "ENTERPRISE ISLAND",
]


def decode_attribute(byte: int) -> dict:
    return {
        "value": byte,
        "ink": PALETTE[byte & 7],
        "paper": PALETTE[(byte >> 3) & 7],
        "bright": bool((byte >> 6) & 1),
        "flash": bool((byte >> 7) & 1),
    }


def decode_screen_addr(addr: int) -> dict:
    """Decode a Spectrum display-file address into (col, char_row, y).

    Layout: bit 13 = $4000 base flag; bits 12-11 = y bits 7-6; bits 10-8 =
    y bits 2-0; bits 7-5 = y bits 5-3; bits 4-0 = x // 8.
    """
    col = addr & 0x1F
    y_top = (addr >> 11) & 0x03   # y[7:6]
    y_low = (addr >> 8) & 0x07    # y[2:0]
    y_mid = (addr >> 5) & 0x07    # y[5:3]
    y = (y_top << 6) | (y_mid << 3) | y_low
    return {"col": col, "char_row": y // 8, "pixel_y": y, "raw": f"0x{addr:04X}"}


def decode_navmap_sprite(ram: bytes, shape_base: int, width: int, height: int) -> list:
    """Decode an island's nav-map sprite using the algorithm at $8D5D-$8DA9.

    The renderer walks `height` rows.  Each row reads `width` source bytes
    at stride 4 from `shape_base + $0102`, packing the high-bit of "byte
    >= $0F" into a bit pattern that becomes the row's display-file bytes.
    Source rows are spaced by `+$0200` (2 scanlines on a Spectrum, which
    matches how the renderer advances HL between rows).
    """
    def get(addr):
        a = addr & 0xFFFF
        return ram[a - 0x4000] if 0x4000 <= a else 0

    src = (shape_base + 0x0102) & 0xFFFF
    rows = []
    for row in range(height):
        row_src = (src + row * 0x0200) & 0xFFFF
        e = width
        offset = 0
        bits = []
        while e > 0:
            c = 0
            b = 8
            while b > 0 and e > 0:
                byte = get(row_src + offset)
                c = ((c << 1) | (1 if byte >= 0x0F else 0)) & 0xFF
                offset += 4
                e -= 1
                b -= 1
            c = (c << b) & 0xFF
            bits.append(c)
        rows.append(bits)
    return rows


def extract(snapshot_path: str) -> dict:
    snap = Snapshot.get(snapshot_path)
    ram = bytes(snap.ram(-1))

    def at(addr: int, n: int = 1) -> bytes:
        off = addr - 0x4000
        return ram[off : off + n]

    # Sanity: the master table must be populated and terminated.
    first = at(MASTER_TABLE, RECORD_SIZE)
    if first[0] == END_MARKER or all(b == 0 for b in first):
        raise SystemExit(
            f"{snapshot_path}: master table at ${MASTER_TABLE:04X} is empty. "
            "Use a post-init snapshot (run `make midgame`)."
        )
    if at(END_MARKER_ADDR, 1)[0] != END_MARKER:
        raise SystemExit(
            f"{snapshot_path}: expected end-marker $FF at ${END_MARKER_ADDR:04X}, "
            f"got ${at(END_MARKER_ADDR, 1)[0]:02X}."
        )

    islands = []
    for i in range(RECORD_COUNT):
        rec_addr = MASTER_TABLE + i * RECORD_SIZE
        rec = at(rec_addr, RECORD_SIZE)
        shape_base = rec[0x0A] | (rec[0x0B] << 8)
        display_addr = rec[0x0C] | (rec[0x0D] << 8)
        attr_high = rec[0x12]

        # 16x16 tile-index grid at shape_base.
        tiles = list(at(shape_base, 256))
        grid = [tiles[row * 16 : (row + 1) * 16] for row in range(16)]

        navmap_w = rec[0x0E]
        navmap_h = rec[0x0F]
        navmap_sprite = decode_navmap_sprite(ram, shape_base, navmap_w, navmap_h)
        navmap_sprite_addr = (shape_base + 0x0102) & 0xFFFF

        islands.append({
            "index": i,
            "name": ISLAND_NAMES[i],
            "record_addr": f"0x{rec_addr:04X}",
            "type": rec[0x00],
            "subtype": rec[0x01],
            "world_bounds": {
                "x_min": rec[0x02], "x_max": rec[0x03],
                "y_min": rec[0x04], "y_max": rec[0x05],
            },
            "altitude": {"z_min": rec[0x06], "z_max": rec[0x07]},
            "secondary_bounds": [rec[0x08], rec[0x09]],
            "shape_base": f"0x{shape_base:04X}",
            "navmap_position": decode_screen_addr(display_addr),
            "navmap_sprite": {
                "source_addr": f"0x{navmap_sprite_addr:04X}",
                "width_cols": navmap_w,
                "height_rows": navmap_h,
                "bitmap": navmap_sprite,
            },
            "name_stream_ptr": f"0x{rec[0x10] | (rec[0x11] << 8):04X}",
            "attribute_high_byte": f"0x{attr_high:02X}",
            "raw_record": [f"0x{b:02X}" for b in rec],
            "object_tiles_at_shape_base": grid,
        })

    # Glyph font at $FA00.  Only addresses up to $FFFF are real RAM, so the
    # in-RAM font holds (0x10000 - 0xFA00) / 8 = 192 glyphs.  Some islands
    # use indices 192..255 (e.g. SKEG uses 207), which on the real machine
    # wrap to ROM at $0000-$01FF; our snapshot doesn't cover that range, so
    # we emit empty glyph bytes for those indices and tag them. Consumers
    # render them as a solid attribute fill (matching the game's visual,
    # which has no ink pixels in those tiles since the game's tile renderer
    # XORs against an unrelated ROM region).
    in_ram_glyphs = (0x10000 - FONT) // 8
    glyphs = []
    for idx in range(256):
        addr = FONT + idx * 8
        if idx < in_ram_glyphs:
            glyph_bytes = list(at(addr, 8))
            in_ram = True
        else:
            glyph_bytes = [0] * 8
            in_ram = False
        glyphs.append({
            "index": idx,
            "addr": f"0x{addr:04X}",
            "bytes": glyph_bytes,
            "in_ram": in_ram,
        })

    # Attribute table at $FE00 (256 entries).
    attr_bytes = at(ATTRS, ATTRS_LEN)
    attributes = [
        {"index": i, **decode_attribute(b)} for i, b in enumerate(attr_bytes)
    ]

    return {
        "source": snapshot_path,
        "game": "Cyclone (Vortex Software, 1985)",
        "world": {"width": 256, "height": 256, "units": "abstract world units"},
        "tile_grid": {"cols": 16, "rows": 16},
        "tile_pixels": {"width": 8, "height": 8},
        "addresses": {
            "master_table": f"0x{MASTER_TABLE:04X}",
            "master_end": f"0x{END_MARKER_ADDR:04X}",
            "name_stream": "0x6A50",
            "font": f"0x{FONT:04X}",
            "attributes": f"0x{ATTRS:04X}",
            "shape_region": ["0x9300", "0xCFFF"],
        },
        "record_layout": [
            {"offset": "+0x00", "field": "type"},
            {"offset": "+0x01", "field": "subtype"},
            {"offset": "+0x02", "field": "x_min"},
            {"offset": "+0x03", "field": "x_max"},
            {"offset": "+0x04", "field": "y_min"},
            {"offset": "+0x05", "field": "y_max"},
            {"offset": "+0x06", "field": "z_min"},
            {"offset": "+0x07", "field": "z_max"},
            {"offset": "+0x08..+0x09", "field": "secondary_bounds"},
            {"offset": "+0x0A..+0x0B", "field": "shape_base_pointer"},
            {"offset": "+0x0C..+0x0D", "field": "navmap_screen_addr (display-file address where this island's icon is drawn on the navigation-map screen)"},
            {"offset": "+0x0E", "field": "navmap_sprite_width (columns for $8D5D inner loop)"},
            {"offset": "+0x0F", "field": "navmap_sprite_height (rows for $8D5D outer loop)"},
            {"offset": "+0x10..+0x11", "field": "name_stream_ptr"},
            {"offset": "+0x12", "field": "attribute_high_byte"},
            {"offset": "+0x13", "field": "record_terminator"},
        ],
        "navmap_renderer": {
            "trigger": "main loop $5B71-$5B81 (when bit 4 of ($7526) is set)",
            "walker": "$8D5D — walks $F230 records emitting both sprite and name per island",
            "sprite_decoder": "$8D7D-$8DA9 — reads source bytes at stride 4 with threshold $0F, packs into display-file bitmap",
            "sprite_source_offset": "shape_base + 0x0102",
            "row_stride_bytes": 0x0200,
            "byte_threshold": 0x0F,
            "column_stride": 4,
        },
        "islands": islands,
        "tile_glyphs": glyphs,
        "tile_attributes": attributes,
    }


def main() -> None:
    snap = sys.argv[1] if len(sys.argv) > 1 else "build/cyclone-endgame.z80"
    out = sys.argv[2] if len(sys.argv) > 2 else "build/cyclone-map.json"
    Path(out).parent.mkdir(parents=True, exist_ok=True)

    data = extract(snap)
    with open(out, "w") as f:
        json.dump(data, f, indent=2)
        f.write("\n")

    n = len(data["islands"])
    g = len(data["tile_glyphs"])
    a = len(data["tile_attributes"])
    size = Path(out).stat().st_size
    print(f"Wrote {out} ({size:,} bytes): {n} islands, {g} glyphs, {a} attrs")


if __name__ == "__main__":
    main()
