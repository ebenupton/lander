#!/usr/bin/env python3
"""Prototype, second form: shallow rows, steep rungs, a ragged bottom.

The rows are as points.py's (every segment shallow: |dy| < dx).  Each rung must be
steep (its bottom point more than |dx| below its top point), and is a boundary
B_i(y): Bresenham stepping in y, one x per line from the top point to the bottom
point, and the top or bottom point's x above or below them.  A pixel (x, y) is in
box  #{i : B_i(y) <= x} - 1  (the boundary's own pixel goes right; -1 and 8 are
outside), below the top row where there is one, and no lower than its byte column's
lowest bottom-row point: the bottom of the band is ragged, filled to that line.
"""
import sys
import numpy as np

import points as P

COLS = range(P.W // 4)


def boundary(xt, yt, xb, yb):
    """B(y) for y in yt..yb: x stepped per line, as bresenham_ys with x and y swapped."""
    assert yb > yt, 'a rung must go down'
    return {yt + k: x for k, x in enumerate(P.bresenham_ys(yt, xt, yb, xb))}


def transitions(xt, yt, xb, yb):
    """Each pixel x the rung passes: the first line where `B(y) <= x` changes."""
    b = boundary(xt, yt, xb, yb)
    out = {}
    for x in range(min(xt, xb), max(xt, xb)):
        was = b[yt] <= x
        out[x] = next(y for y in range(yt, yb + 1) if (b[y] <= x) != was)
    return out


def bottoms(bot):
    """Each byte column's lowest bottom-row point."""
    return {c: max(bot[x] for x in range(4 * c, 4 * c + 4) if x in bot)
            for c in COLS if any(x in bot for x in range(4 * c, 4 * c + 4))}


def fill(top, bot, rungs, colours):
    """rungs: (xt, yt, xb, yb) for each.  An image, palette entry + 1 by pixel."""
    bs = [boundary(*r) for r in rungs]
    botc = bottoms(bot)
    xs = np.arange(P.W)
    floor = np.full(P.W, -1)                # each pixel's lowest line
    for c, y in botc.items():
        floor[4 * c:4 * c + 4] = y
    ceil = np.zeros(P.W, dtype=int)         # and its highest: the top row's
    for x, y in top.items():
        ceil[x] = y
    img = np.zeros((P.H, P.W), dtype=np.uint8)
    for y in range(P.H):
        edges = [b[min(max(y, r[1]), r[3])] for b, r in zip(bs, rungs)]
        n = np.searchsorted(edges, xs, side='right') - 1
        inside = (y <= floor) & (y >= ceil) & (n >= 0) & (n < len(rungs) - 1)
        img[y] = np.where(inside, np.take(np.array(colours) + 1, np.clip(n, 0, len(rungs) - 2)), 0)
    return img


def ok(pts0, pts1):
    """A frame's constraints: steep rungs, and each top-row column above its bottom."""
    if any(yb - yt <= abs(xb - xt) for (xt, yt), (xb, yb) in zip(pts0, pts1)):
        return False
    top, botc = P.trace(pts0), bottoms(P.trace(pts1))
    return all(max(top[x] for x in range(4 * c, 4 * c + 4)) <= botc[c]
               for c in COLS if 4 * c in top and 4 * c + 3 in top)


def main():
    rng = np.random.default_rng(int(sys.argv[1]) if len(sys.argv) > 1 else None)
    while True:
        pts = [P.make_points(rng, *r) for r in P.ROWS]
        if ok(*pts):
            break
    for r, p in enumerate(pts):
        print(f'row {r}: ' + ' '.join(f'({x},{y})' for x, y in p))
    top, bot = P.trace(pts[0]), P.trace(pts[1])
    rungs = [(xt, yt, xb, yb) for (xt, yt), (xb, yb) in zip(*pts)]
    colours = list(range(8))
    img = fill(top, bot, rungs, colours)
    pal = np.array([(0, 0, 0)] + [tuple(int(v) for v in rng.integers(150, 256, 3)) for _ in range(8)],
                   dtype=np.uint8)
    rgb = pal[img]
    out = rgb.copy()
    for x, y in top.items():
        out[y, x] = (40, 40, 40)
    for x, y in bot.items():
        out[y, x] = (90, 90, 90)
    P.save(rgb, 'ragged')
    P.save(out, 'ragged_outline')


if __name__ == '__main__':
    main()
