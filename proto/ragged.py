#!/usr/bin/env python3
"""The fill rule for a band between two traced rows: rungs as boundaries stepped in
y, pixels assigned to boxes by counting boundaries, a ragged bottom by byte column.

A strip has a top row and a bottom row (points.trace's lines) and a rung from each
top point i to bottom point i.  Each rung must go down (yb > yt) and is a boundary
B_i(y) for y in yt..yb: one x a line, Bresenham from the top point to the bottom
one (boundary); above yt it stands at xt and below yb at xb.  Pixel (x, y) is in
box  #{i : B_i(y) <= x} - 1  (so a boundary's own pixel is in the box to its right;
-1 and the last count are outside), at or below the top row's line where the top
row has a pixel, and no lower than its byte column's floor: the lowest bottom-row
pixel in that column (bottoms).  The bottom of the band is therefore ragged, a
whole byte column at a time, which is what lets land.s fill it with byte stores;
the next strip down overwrites the overhang since its top row is this bottom row.

land.s's rungs do the same stepping by the lines where each pixel the rung crosses
changes box (transitions, in closed form); tools/landgen.py's TRk, TLk tables hold
those lines for the short rungs.
"""
import numpy as np

import points as P

COLS = range(P.W // 4)


def boundary(xt, yt, xb, yb):
    """The rung's boundary {y: x} for y in yt..yb, yb > yt: one x a line, Bresenham
    stepped in y (points.bresenham_ys with the axes swapped), so a shallow rung's x
    moves several pixels a line."""
    assert yb > yt, 'a rung must go down'
    return {yt + k: x for k, x in enumerate(P.bresenham_ys(yt, xt, yb, xb))}


def transitions(xt, yt, xb, yb):
    """For each pixel x the rung crosses (min(xt, xb) <= x < max(xt, xb)), the first
    line where `B(y) <= x` differs from its value at yt: the line that pixel changes
    box.  Equal to yt + ceil(D (2j - 1) / 2a) for the j'th pixel from xt (j from 1,
    pixel xt + j - 1 leaning right, xt - j leaning left), D = yb - yt, a = |xb - xt|:
    the form land.s's rungs and tools/landgen.py's TRk, TLk tables use.  Nothing in
    the tree calls this: it states, in their terms, the rule boundary gives, which
    test/landsoak.py checks through the pixels land.s and mask produce."""
    b = boundary(xt, yt, xb, yb)
    out = {}
    for x in range(min(xt, xb), max(xt, xb)):
        at_top = b[yt] <= x
        out[x] = next(y for y in range(yt, yb + 1) if (b[y] <= x) != at_top)
    return out


def bottoms(bot):
    """{byte column: the lowest y of the bottom row's line in it}, for the columns
    the line has a pixel in."""
    return {c: max(bot[x] for x in range(4 * c, 4 * c + 4) if x in bot)
            for c in COLS if any(x in bot for x in range(4 * c, 4 * c + 4))}


def boxes(top, bot, rungs):
    """The band's pixels by the rule above: an (H, W) int array, the box 0..n-2 of
    each pixel (n rungs) or -1 outside.  top, bot: the rows' lines (points.trace);
    rungs: (xt, yt, xb, yb) for each, in order from left to right."""
    bs = [boundary(*r) for r in rungs]
    floor = np.full(P.W, -1)                  # each pixel's lowest line, by column
    for c, y in bottoms(bot).items():
        floor[4 * c:4 * c + 4] = y
    ceil = np.zeros(P.W, dtype=int)           # and its highest: the top row's pixel
    for x, y in top.items():
        ceil[x] = y
    xs = np.arange(P.W)
    out = np.full((P.H, P.W), -1, dtype=int)
    for y in range(P.H):
        edges = [b[min(max(y, r[1]), r[3])] for b, r in zip(bs, rungs)]
        n = np.searchsorted(edges, xs, side='right') - 1
        inside = (y <= floor) & (y >= ceil) & (n >= 0) & (n < len(rungs) - 1)
        out[y] = np.where(inside, n, -1)
    return out
