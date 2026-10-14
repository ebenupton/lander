#!/usr/bin/env python3
"""Check a frame of BAND against the prototype, from a dump of $3000-$7FFF.

    python3 test/check.py dump.bin

The points (PTS0, PTS1) and box colours (BOXC) are read from the dump; the
prototype's own trace, line_ys and fill (proto/points.py) then give the rows,
the rungs and every pixel of the fill, which must match TOPY, BOTY, RUNGY and
every screen byte below the readout's two character rows, each box's pixels in its
palette colour's dither (tools/palette.py) at (x & 1, y & 1).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'proto'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import points as P  # noqa: E402
import palette as PL  # noqa: E402

BASE = 0x3000
TOPY, BOTY, RUNGY = 0x4800, 0x4900, 0x4A00   # as main.s
PTS0, PTS1, BOXC = 0x5700, 0x5720, 0x5740
SCREEN, LINES, TEXT = 0x5800, 160, 16


def addr(c, y):
    return SCREEN + (y >> 3) * 512 + (y & 7) + 8 * c


def check(rd):
    """Compare a frame, read through rd(address), with the prototype.

    Returns (points, box colours, table errors, bad screen bytes)."""
    pts = [[(rd(p + 2 * i), rd(p + 2 * i + 1)) for i in range(P.N)] for p in (PTS0, PTS1)]
    boxc = [rd(BOXC + b) for b in range(P.N - 1)]
    top, bot = P.trace(pts[0]), P.trace(pts[1])
    rungs = [(P.line_ys(x0, y0, x1, y1), x0, x1)
             for (x0, y0), (x1, y1) in zip(*pts)]
    rung = {x: y for r, _, _ in rungs for x, y in r.items()}
    terr = sum(rd(t + x) != m.get(x, 0xFF)
               for t, m in ((TOPY, top), (BOTY, bot), (RUNGY, rung)) for x in range(256))
    img, spans = P.fill(top, bot, rungs, [(c + 1,) * 3 for c in boxc])
    entry = img[:, :, 0]                  # palette entry + 1, 0 outside the band
    bad = []
    for y in range(TEXT, LINES):
        for c in range(64):
            want = 0
            for p in range(4):
                x = 4 * c + p
                e = entry[y, x]
                col = PL.PATTERNS[e - 1][(x & 1, y & 1)] if e else 0
                want |= ((col >> 1) << (7 - p)) | ((col & 1) << (3 - p))
            got = rd(addr(c, y))
            if got != want:
                bad.append((c, y, got, want))
    return pts, boxc, terr, bad


def main():
    mem = open(sys.argv[1], 'rb').read()
    pts, boxc, terr, bad = check(lambda a: mem[a - BASE])
    print('rows', [y for _, y in pts[0]], [y for _, y in pts[1]], ' boxes', boxc)
    print('table errors', terr, ' screen byte errors', len(bad),
          '(of %d)' % ((LINES - TEXT) * 64))
    for c, y, got, want in bad[:12]:
        print(f'  column {c} (x {4*c}..{4*c+3}) line {y}: ${got:02X}, want ${want:02X}')
    if any(not 0 <= c < len(PL.PALETTE) for c in boxc) or any(a == b for a, b in zip(boxc, boxc[1:])):
        print('constraint: box colours')
        bad.append(None)
    sys.exit(1 if terr or bad else 0)


if __name__ == '__main__':
    main()
