#!/usr/bin/env python3
"""Merge LAND's sideways-bank code segments into the table images they run from.

    python3 tools/mergebank.py BUILDDIR MAPFILE IMAGE:SEG,SEG,... ...

ld65 writes each bank segment to its own file, BUILDDIR/SEG, placed (src/land.cfg)
in space the tables leave free.  Each IMAGE (TABLES, TABLES2, TABLES7: 16K, bank
address $8000) is read, every SEG named for it copied in at its address less $8000
(the address from MAPFILE, ld65's map), and the image written back.  The bytes a
segment lands on must all be zero: a segment over a table, or over another
segment, is an error.
"""
import re
import sys

BASE, SIZE = 0x8000, 0x4000


def segments(mapfile):
    """{name: start address} for every segment in ld65's map file (its 'Segment list'
    lines: name, start, end and size in hex, then the alignment)."""
    pat = re.compile(r'^(\w+)\s+([0-9A-F]{6})\s+[0-9A-F]{6}\s+[0-9A-F]{6}\s+[0-9A-F]+$')
    out = {}
    for ln in open(mapfile):
        m = pat.match(ln.strip())
        if m:
            out[m.group(1)] = int(m.group(2), 16)
    return out


def merge(build, image, segs, starts):
    """Copy the segments segs (files in build) into build/image, each at its start
    address less BASE."""
    path = f'{build}/{image}'
    img = bytearray(open(path, 'rb').read())
    assert len(img) == SIZE, f'{image}: {len(img)} bytes, not 16K'
    for seg in segs:
        code = open(f'{build}/{seg}', 'rb').read()
        off = starts[seg] - BASE
        assert 0 <= off and off + len(code) <= SIZE, f'{seg}: not within the bank'
        assert not any(img[off:off + len(code)]), f'{image}: {seg} over the tables or another segment'
        img[off:off + len(code)] = code
    open(path, 'wb').write(img)


def main():
    build, mapfile = sys.argv[1], sys.argv[2]
    starts = segments(mapfile)
    for spec in sys.argv[3:]:
        image, segs = spec.split(':')
        merge(build, image, segs.split(','), starts)


if __name__ == '__main__':
    main()
