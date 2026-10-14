#!/usr/bin/env python3
"""Check a frame of BAND against the prototype (proto/ragged.py), from a dump of
$0000-$7FFF.

    python3 test/check.py dump.bin

(the points live in low memory, so the dump must start at $0000).  The points (PTS0, PTS1) and box colours (BOXC) are read from the dump; the
prototype then gives what the interpolation must leave (TOPC: each top-row byte
column's first y; BOTC: each byte column's lowest bottom-row y; RT: each rung
pixel's line) and every pixel of the fill, which must match every screen byte
below the readout's two character rows, each box's pixels in its palette colour's
dither (tools/palette.py) at (x & 1, y & 1).
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'proto'))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import points as P  # noqa: E402
import ragged as R  # noqa: E402
import palette as PL  # noqa: E402

def _labels():
    out = {}
    for ln in open(os.path.join(os.path.dirname(__file__), '..', 'build', 'labels.txt')):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


_L = _labels()                                  # main.s's addresses, as built
RT, TOPC, BOTC = _L['RT'], _L['TOPC'], _L['BOTC']
PTS0, PTS1, BOXC = _L['PTS0'], _L['PTS1'], _L['BOXC']
SCREEN, LINES, TEXT = 0x5800, 160, 16

# each palette entry's bits for a line parity and pixel
LUT = np.zeros((len(PL.PALETTE) + 1, 2, 4), dtype=np.uint8)
for e in range(1, len(PL.PALETTE) + 1):
    for par in range(2):
        for p in range(4):
            col = PL.PATTERNS[e - 1][(p & 1, par)]
            LUT[e, par, p] = ((col >> 1) << (7 - p)) | ((col & 1) << (3 - p))


def addr(c, y):
    return SCREEN + (y >> 3) * 512 + (y & 7) + 8 * c


def screen_bytes(img):
    """img (palette entry + 1 by pixel) as MODE 1 bytes, by [y, column]."""
    par = np.broadcast_to((np.arange(P.H) & 1)[:, None], (P.H, P.W // 4))
    by = np.zeros((P.H, P.W // 4), dtype=np.uint8)
    for p in range(4):
        by |= LUT[img[:, p::4], par, p]
    return by


def check(rd):
    """Compare a frame, read through rd(address), with the prototype.

    Returns (points, box colours, table errors, bad screen bytes)."""
    pts = [[(rd(p + 2 * i), rd(p + 2 * i + 1)) for i in range(P.N)] for p in (PTS0, PTS1)]
    boxc = [rd(BOXC + b) for b in range(P.N - 1)]
    top, bot = P.trace(pts[0]), P.trace(pts[1])
    rungs = [(xt, yt, xb, yb) for (xt, yt), (xb, yb) in zip(*pts)]
    want = {}
    for c in range(pts[0][0][0] // 4, pts[0][-1][0] // 4):
        want[TOPC + c] = top[4 * c]
    for c, y in R.bottoms(bot).items():
        if 4 * c < pts[1][-1][0]:
            want[BOTC + c] = y + 1
    for r in rungs:
        for x, y in R.transitions(*r).items():
            want[RT + x] = y
    terr = sum(rd(a) != v for a, v in want.items())
    exp = screen_bytes(R.fill(top, bot, rungs, boxc))
    bad = []
    for y in range(TEXT, LINES):
        for c in range(64):
            got = rd(addr(c, y))
            if got != exp[y, c]:
                bad.append((c, y, got, int(exp[y, c])))
    return pts, boxc, terr, bad


def main():
    mem = open(sys.argv[1], 'rb').read()
    pts, boxc, terr, bad = check(lambda a: mem[a])
    print('rows', [y for _, y in pts[0]], [y for _, y in pts[1]], ' boxes', boxc)
    print('table errors', terr, ' screen byte errors', len(bad),
          '(of %d)' % ((LINES - TEXT) * 64))
    for c, y, got, want in bad[:12]:
        print(f'  column {c} (x {4*c}..{4*c+3}) line {y}: ${got:02X}, want ${want:02X}')
    if any(not 0 <= c < len(PL.PALETTE) for c in boxc) or any(a == b for a, b in zip(boxc, boxc[1:])):
        print('constraint: box colours')
        bad.append(None)
    if not R.ok(*pts):
        print('constraint: steep rungs, tops above bottoms')
        bad.append(None)
    sys.exit(1 if terr or bad else 0)


if __name__ == '__main__':
    main()
