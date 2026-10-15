#!/usr/bin/env python3
"""A strip: the band between two rows of points, filled by ragged.py's rule, with
the guarantees land.s relies on, and a random stack of strips to look at them.

A strip has a top row and a bottom row with the same number of points, n; rung i
joins top point i to bottom point i; box i (0..n-2) is the pixels between rungs i
and i+1.  Its guarantees (ok) are:
  - the bottom row is no narrower: its first point no further right, its last no
    further left, than the top row's (the end rungs lean out or stand);
  - every segment of either row is shallow, |dy| < dx, or has no length (the two
    points the same: land.clip's points moved onto a screen edge together), so each
    row traces to one y a pixel (points.trace);
  - every rung goes down, yb > yt: one x a line (ragged.boundary), however shallow;
  - in each byte column, the top row's pixels are no lower than the bottom row's
    lowest (the column's floor), so no column's fill is inverted.
The fill (mask, ragged.boxes): pixel (x, y) is in box #{i : B_i(y) <= x} - 1 when
that is 0..n-2, at or below the top row's pixel in its column where there is one,
and no lower than its byte column's floor.  Every other pixel is left untouched:
nothing above the top row, nothing outside rungs 0 and n-1, and a partly covered
byte keeps its other pixels.  The strip below (whose top row is this one's bottom
row) overwrites the ragged overhang, and its end rungs leaning out cover the
overhang at the ends; only the last strip's ragged bottom shows (frame.py's
ground strip, whose bottom row is on or past the screen's last line).

land.s fills a strip from these points alone, byte column by byte column, and is
checked pixel for pixel against mask by test/landsoak.py.

    python3 proto/strip.py [seed]   writes proto/stack.png and stack_x4.png: a random
                                    stack of strips in perspective over a striped
                                    background that must survive outside them, and
                                    stack_points.png, stack_points_x4.png with the
                                    rows' points marked white
"""
import sys

import numpy as np

import points as P
import ragged as R

N = P.N


def ok(top_pts, bot_pts):
    """True if the strip (top_pts, bot_pts: equal-length lists of (x, y)) meets the
    four guarantees above."""
    if not (bot_pts[0][0] <= top_pts[0][0] and bot_pts[-1][0] >= top_pts[-1][0]):
        return False
    for row in (top_pts, bot_pts):
        if any(abs(y1 - y0) >= x1 - x0 and (x0, y0) != (x1, y1)
               for (x0, y0), (x1, y1) in zip(row, row[1:])):
            return False
    if any(yb <= yt for (xt, yt), (xb, yb) in zip(top_pts, bot_pts)):
        return False
    top, bot = P.trace(top_pts), P.trace(bot_pts)
    for c, yb in R.bottoms(bot).items():
        ts = [top[x] for x in range(4 * c, 4 * c + 4) if x in top]
        if ts and max(ts) > yb:
            return False
    return True


def mask(top_pts, bot_pts):
    """The strip's pixels: an (H, W) int array, each pixel's box 0..n-2 or -1 where
    the strip leaves the pixel alone (ragged.boxes over the traced rows)."""
    rungs = [(xt, yt, xb, yb) for (xt, yt), (xb, yb) in zip(top_pts, bot_pts)]
    return R.boxes(P.trace(top_pts), P.trace(bot_pts), rungs)


def draw(img, top_pts, bot_pts, colours):
    """Draw the strip over img (palette entry + 1 by pixel, 0 black): box i in
    colours[i] + 1.  Returns img."""
    m = mask(top_pts, bot_pts)
    img[m >= 0] = np.array(colours)[m[m >= 0]] + 1
    return img


# ---------------------------------------------------------------- main's random stack

def xs_of(X0, S):
    """A row's N x's from its first point X0 and spacing S, both in 1/256 pixel (8.8
    fixed point, as the BBC would add them), each rounded to the nearest pixel."""
    return [(X0 + i * S + 128) >> 8 for i in range(N)]


def make_row(rng, X0, S, y0, ymin=0, ymax=P.H - 1):
    """N points at xs_of(X0, S), y from y0 by normal steps (points.SD), each segment
    kept shallow and y within ymin..ymax."""
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


def next_row(rng, row, X0, S):
    """A row below row (first point X0, spacing S, 1/256 pixel) passing ok with it:
    spacing 1..4 pixels more, first point 2..12 pixels further left, last point
    further right, within the screen, its first y 18..29 lines down.  Returns
    (points, X0, S), or None when the next row would start below the screen."""
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
    """Rows from a narrow one near the top (spacing 10..15 pixels, about centred),
    each wider than the last, down to within six lines of the bottom."""
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


def background():
    """A pattern no strip writes: diagonal stripes of 'entry' 15 (shown grey) and 0."""
    y, x = np.mgrid[0:P.H, 0:P.W]
    return np.where(((x + y) // 3) % 2 == 0, 15, 0).astype(np.uint8)


# main's colours by entry + 1: nine pastels for the boxes, 14 white (the points),
# 15 grey (the background)
PAL = np.array([(0, 0, 0), (230, 120, 120), (120, 200, 120), (120, 140, 230), (230, 210, 110),
                (190, 120, 220), (110, 210, 210), (240, 160, 90), (170, 230, 140), (150, 170, 250)]
               + [(0, 0, 0)] * 4 + [(255, 255, 255), (70, 70, 70)], dtype=np.uint8)


def rgb(img):
    """img (entry + 1 by pixel) as RGB by PAL."""
    return PAL[img]


def outline(img, rows):
    """A copy of img with every row's points marked white."""
    out = img.copy()
    for r in rows:
        for x, y in r:
            out[y, x] = 14
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
