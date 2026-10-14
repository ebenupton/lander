#!/usr/bin/env python3
"""The whole frame as the BBC draws it, into a double buffer: land.py's strips, each
strip widened by a black margin box at both ends (to a byte boundary M or more pixels
out), a black sky strip above the
far row (from a flat row at YSKY) and a black ground strip below the near row (to a
flat row at YGND), so a frame overwrites everything the frame before last left in its
buffer, and the bottom edge is exact.  Nothing outside those strips is ever drawn.

    python3 proto/frame.py [frames] [M]   pans at random, a step a frame, through both
                                          buffers; checks each drawn buffer against the
                                          frame alone on black, and every strip's
                                          guarantees; frame_NNN.png
"""
import sys
import numpy as np

import land as L
import points as P
import strip as S

STEP = 1                  # the most steps a frame the pan moves
M = 8                    # the margin boxes' width, pixels
YSKY, YGND = 64, 158      # the sky's and the ground's flat rows
BLACK = 34                # swatch35's K4


def strips_of(hm, cx, cz, m=M):
    """The frame's strips, top to bottom, each (top points, bottom points, box colours):
    the sky, land.py's, the ground.  Each strip gets its own margin points: a vertical
    rung either side, on a byte boundary (so no column has its pixels split by one), m
    or more pixels beyond the strip's bottom row (the wider), each row extended flat to
    them; the margin boxes black."""
    xs, rows = L.project(hm, cx, cz)
    pts = [[(sx, sy) for sx, sy, _ in row] for _, row in rows]
    n = len(xs) - 1
    cols = [[L.colour(hm, x, rows[k + 1][0], 0, 0) for x in xs[:-1]]
            for k in range(len(rows) - 1)]
    sky = [(x, YSKY) for x, _ in pts[0]]
    gnd = [(x, YGND) for x, _ in pts[-1]]
    pairs = [(sky, pts[0], [BLACK] * n)] + list(zip(pts, pts[1:], cols)) + [(pts[-1], gnd, [BLACK] * n)]
    out = []
    for t, b, c in pairs:
        xl = max(0, (b[0][0] - m) & ~3)          # (on the screen)
        xr = min(255, (b[-1][0] + m + 3) & ~3)
        out.append(([(xl, t[0][1])] + t + [(xr, t[-1][1])],
                    [(xl, b[0][1])] + b + [(xr, b[-1][1])],
                    [BLACK] + c + [BLACK]))
    return out


def draw(img, hm, cx, cz, m=M):
    """Draw the frame over img (palette entry + 1 by pixel, black 0); returns the strips failing the guarantees."""
    bad = 0
    for t, b, c in strips_of(hm, cx, cz, m):
        if not S.ok(t, b):
            bad += 1
        msk = S.mask(t, b)
        img[msk >= 0] = np.array([0 if e == BLACK else e + 1 for e in c])[msk[msk >= 0]]
    return bad


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 300
    m = int(sys.argv[2]) if len(sys.argv) > 2 else M
    hm = L.heightmap()
    rng = np.random.default_rng(7)
    bufs = [np.zeros((P.H, P.W), np.uint8) for _ in range(2)]
    cx, cz = 40 << 8, 30 << 8
    bad = wrong = 0
    for f in range(frames):
        if f % 40 == 0:                       # and now and then a jump
            cx, cz = int(rng.integers(0, 1024)) * 16, int(rng.integers(0, 1024)) * 16
        else:
            cx += 16 * int(rng.integers(-STEP, STEP + 1))
            cz += 16 * int(rng.integers(-STEP, STEP + 1))
        buf = bufs[f & 1]
        bad += draw(buf, hm, cx, cz, m)
        ref = np.zeros_like(buf)
        draw(ref, hm, cx, cz, m)
        if f % 40 > 1 and not (buf == ref).all():
            wrong += 1
        if f < 2:
            L.render(buf).save(f'frame_{f:03d}.png')
    print(f'{frames} frames, margin {m}: {bad} strips failing the guarantees, '
          f'{wrong} frames wrong in their buffer')


if __name__ == '__main__':
    main()
