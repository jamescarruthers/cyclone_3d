#!/usr/bin/env python3
"""Compare two SkoolKit control files and classify the differences.

Intended use: diff a statically-generated control file (sna2ctl.py) against
one informed by an RZX execution map (sna2ctl.py -m). Blocks that agree are
high-confidence; blocks where only the static analysis says "code" are code
paths the RZX didn't exercise (probably correct, but unconfirmed); blocks
where only the map says "code" are routines the static analyser missed
(often because they're only reached via indirect jumps).

Usage:
    tools/compare_ctl.py build/cyclone.auto.ctl build/cyclone.auto-rzx.ctl
"""
import re
import sys
from pathlib import Path

BLOCK = re.compile(r'^([cbtsuwi]) \$([0-9A-F]{4})')


def blocks(path: str) -> dict[int, str]:
    out: dict[int, str] = {}
    for line in Path(path).read_text().splitlines():
        m = BLOCK.match(line)
        if m:
            out[int(m.group(2), 16)] = m.group(1)
    return out


def main(static_path: str, map_path: str) -> int:
    static = blocks(static_path)
    mapped = blocks(map_path)

    consensus = sorted(a for a in static if static[a] == 'c' and mapped.get(a) == 'c')
    static_only = sorted(a for a in static if static[a] == 'c' and mapped.get(a) != 'c')
    map_only = sorted(a for a in mapped if mapped[a] == 'c' and static.get(a) != 'c')

    print(f'Inputs:')
    print(f'  {static_path:<40} {len(static)} blocks')
    print(f'  {map_path:<40} {len(mapped)} blocks')
    print()
    print(f'Code blocks both agree on  : {len(consensus):>4}  (high-confidence heavy hitters)')
    print(f'Static says code, map did not see : {len(static_only):>4}  (rarely-executed paths / dead code)')
    print(f'Map says code, static missed      : {len(map_only):>4}  (indirect-jump targets)')
    print()
    if map_only:
        print('Map-only code entries (worth investigating):')
        for a in map_only[:30]:
            print(f'  ${a:04X}')
        if len(map_only) > 30:
            print(f'  ... and {len(map_only) - 30} more')
    return 0


if __name__ == '__main__':
    a = sys.argv[1] if len(sys.argv) > 1 else 'build/cyclone.auto.ctl'
    b = sys.argv[2] if len(sys.argv) > 2 else 'build/cyclone.auto-rzx.ctl'
    sys.exit(main(a, b))
