#!/usr/bin/env python3
"""Prototype, third form: strips with free x geometry, stacked into a grid.

The picture: a grid of rows of nine points, seen in perspective (each row wider than
the one above), with the y's perturbed.  A strip is the band between two neighbouring
rows; the grid is drawn a strip at a time, top to bottom.

A row: nine points, x_i = round(X0 + i * S), X0 its first point and S its spacing in
1/256 pixel (8.8 fixed point; free at run time, so nothing is byte-aligned and the
gaps along a row can differ by a pixel: true perspective), y's on a random walk in
normal steps.
A strip: a top row and the row below it, its bottom row.  Constraints:
  - the bottom row is wider: its spacing is larger, its first point no further right
    and its last point no further left than the top row's (so the end rungs lean out);
  - (the grid's rows: each a pixel or more wider-spaced than the last)
  - the rows are shallow: every segment's |dy| < its width;
  - every rung (top point i to bottom point i) is steep: its dy > its |dx|;
  - each byte column's top is no lower than its bottom (lowest bottom-row point).
The fill, as ragged.py: each rung is a boundary B_i(y), stepped in y, one x per line
(top or bottom point's x above or below it); pixel (x, y) is in box
#{i : B_i(y) <= x} - 1 when that is 0..7, at or below the top row where there is one,
and no lower than its byte column's lowest bottom-row point (the ragged bottom).
EVERY OTHER PIXEL IS LEFT AS IT WAS: nothing above the top row, nothing outside rungs
0 and 8, and partial bytes keep their other pixels.  So the next strip down (whose
top row is this one's bottom row) overwrites this one's ragged bottom, and because its
end rungs lean out it covers the overhang at the ends too: the grid's edges are
continuous, and only the last strip's ragged bottom shows.

    python3 proto/strip.py [seed]   -> stack.png, stack_x4.png: a grid over a striped
                                       background (which must survive outside it);
                                       stack_points*.png: the points marked
"""
import sys
import numpy as np

import points as P
import ragged as R

N = P.N


def xs_of(X0, S):
    """A row's nine x's from its first point X0 and spacing S, both in 1/256 pixel
    (8.8 fixed point, as the BBC adds them): each rounded to the nearest pixel."""
    return [(X0 + i * S + 128) >> 8 for i in range(N)]


def make_row(rng, X0, S, y0, ymin=0, ymax=P.H - 1):
    """Nine points at xs_of(X0, S); y from y0 in normal steps, each segment shallow,
    kept to ymin..ymax."""
    xs = xs_of(X0, S)
    pts, y = [], y0
    for i in range(N):
        if i:
            while True:
                step = int(np.rint(rng.normal(0, P.SD)))
                if ymin <= y + step <= ymax and abs(step) < xs[i] - xs[i - 1]:
                    break
            y += step
        pts.append((xs[i], y))
    return pts


def ok(top_pts, bot_pts):
    """A strip's constraints (the docstring's)."""
    if not (bot_pts[0][0] <= top_pts[0][0] and bot_pts[-1][0] >= top_pts[-1][0]):
        return False
    for row in (top_pts, bot_pts):
        if any(abs(y1 - y0) >= x1 - x0 for (x0, y0), (x1, y1) in zip(row, row[1:])):
            return False
    if any(yb - yt <= abs(xb - xt) for (xt, yt), (xb, yb) in zip(top_pts, bot_pts)):
        return False
    top, bot = P.trace(top_pts), P.trace(bot_pts)
    botc = R.bottoms(bot)
    for c, yb in botc.items():
        ts = [top[x] for x in range(4 * c, 4 * c + 4) if x in top]
        if ts and max(ts) > yb:
            return False
    return True


def mask(top_pts, bot_pts):
    """The strip's pixels: (H, W) array, box 0..7, or -1 outside."""
    top, bot = P.trace(top_pts), P.trace(bot_pts)
    rungs = [(xt, yt, xb, yb) for (xt, yt), (xb, yb) in zip(top_pts, bot_pts)]
    bs = [R.boundary(*r) for r in rungs]
    floor = np.full(P.W, -1)
    for c, y in R.bottoms(bot).items():
        floor[4 * c:4 * c + 4] = y
    ceil = np.zeros(P.W, dtype=int)
    for x, y in top.items():
        ceil[x] = y
    xs = np.arange(P.W)
    out = np.full((P.H, P.W), -1, dtype=int)
    for y in range(P.H):
        edges = [b[min(max(y, r[1]), r[3])] for b, r in zip(bs, rungs)]
        n = np.searchsorted(edges, xs, side='right') - 1
        inside = (y <= floor) & (y >= ceil) & (n >= 0) & (n < N - 1)
        out[y] = np.where(inside, n, -1)
    return out


def draw(img, top_pts, bot_pts, colours):
    """Draw a strip over img (palette entry + 1 by pixel; 0 black), leaving the rest."""
    m = mask(top_pts, bot_pts)
    img[m >= 0] = np.array(colours)[m[m >= 0]] + 1
    return img


def background():
    """A pattern no strip writes: stripes of 'entry' 15 (shown grey)."""
    y, x = np.mgrid[0:P.H, 0:P.W]
    return np.where(((x + y) // 3) % 2 == 0, 15, 0).astype(np.uint8)


def next_row(rng, row, X0, S):
    """The row below row (whose first point and spacing, in 1/256 pixel, are X0, S):
    wider (its spacing 1-4 pixels more, its first point 2-12 further left, so its last
    point is right of row's too), its y's a gap below.  Returns (points, X0, S)."""
    while True:
        nS = S + int(rng.integers(256, 1025))
        nX0 = X0 - int(rng.integers(2 * 256, 12 * 256 + 1))
        xs = xs_of(nX0, nS)
        if nX0 < 0 or xs[-1] > P.W - 1 or xs[-1] <= row[-1][0]:
            continue
        y0 = row[0][1] + int(rng.integers(18, 30))
        if y0 > P.H - 1:
            return None
        nrow = make_row(rng, nX0, nS, y0, 0, P.H - 1)
        if ok(row, nrow):
            return nrow, nX0, nS


def grid(rng):
    """Rows from a narrow one near the top, each strip between a row and the next."""
    S = int(rng.integers(10 * 256, 16 * 256))
    X0 = 128 * 256 - 4 * S + int(rng.integers(-8 * 256, 8 * 256))
    rows = [make_row(rng, X0, S, int(rng.integers(8, 20)), 0, 40)]
    while True:
        r = next_row(rng, rows[-1], X0, S)
        if r is None or max(y for _, y in r[0]) > P.H - 6:
            break
        rows.append(r[0])
        X0, S = r[1], r[2]
    return rows


PAL = np.array([(0, 0, 0), (230, 120, 120), (120, 200, 120), (120, 140, 230), (230, 210, 110),
                (190, 120, 220), (110, 210, 210), (240, 160, 90), (170, 230, 140), (150, 170, 250)]
               + [(0, 0, 0)] * 4 + [(255, 255, 255), (70, 70, 70)], dtype=np.uint8)


def rgb(img):
    return PAL[img]


def outline(img, rows):
    out = img.copy()
    for r in rows:
        for x, y in r:
            out[y, x] = 14                   # the points (shown white)
    return out


def main():
    rng = np.random.default_rng(int(sys.argv[1]) if len(sys.argv) > 1 else None)
    rows = grid(rng)
    img = background()
    for k, (t, b) in enumerate(zip(rows, rows[1:])):
        img = draw(img, t, b, [(k * 3 + i) % 9 for i in range(8)])
        print(f'strip {k}: top xs {[x for x, _ in t]}  bottom xs {[x for x, _ in b]}')
    P.save(rgb(img), 'stack')
    P.save(rgb(outline(img, rows)), 'stack_points')


if __name__ == '__main__':
    main()
