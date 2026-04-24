#!/usr/bin/env python3
"""Round-trip check for the Cyclone disassembly.

Reassembles the skool file back into raw bytes and compares them against the
48K of RAM in the source snapshot. A byte-perfect match proves the skool file
is a lossless representation of the snapshot -- every directive in cyclone.ctl
preserves the original program.

Usage:
    tools/verify.py [SNAPSHOT] [REASSEMBLED_BIN]

Defaults: build/cyclone.z80 and build/cyclone.reassembled.bin (both produced
by `make verify`).
"""
import sys
from pathlib import Path

from skoolkit.snapshot import Snapshot


def main(snap_path: str, bin_path: str) -> int:
    snap = Snapshot.get(snap_path)
    ram = bytes(snap.ram(-1))        # $4000-$FFFF, 49152 bytes
    reasm = Path(bin_path).read_bytes()

    if len(ram) != len(reasm):
        print(f'SIZE MISMATCH: snapshot RAM={len(ram)} reassembled={len(reasm)}')
        return 1

    if ram == reasm:
        print(f'OK: {len(ram)} bytes match ({snap_path} == {bin_path})')
        return 0

    diffs = [i for i in range(len(ram)) if ram[i] != reasm[i]]
    print(f'MISMATCH: {len(diffs)} differing bytes')
    for i in diffs[:20]:
        addr = 0x4000 + i
        print(f'  ${addr:04X}: snap=${ram[i]:02X} reasm=${reasm[i]:02X}')
    if len(diffs) > 20:
        print(f'  ... and {len(diffs) - 20} more')
    return 1


if __name__ == '__main__':
    snap = sys.argv[1] if len(sys.argv) > 1 else 'build/cyclone.z80'
    binf = sys.argv[2] if len(sys.argv) > 2 else 'build/cyclone.reassembled.bin'
    sys.exit(main(snap, binf))
