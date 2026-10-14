#!/usr/bin/env python3
"""The BBC algorithm for proto/strip.py, modelled: a strip as byte columns of segments.

A pixel's state down its column (box 0..7, or untouched) changes only at a few lines:
its top (the top row's y, or the line where the end rung reaches it), where an inner
rung passes it (one transition per rung, the boundaries being monotone in y), and below
its byte column's floor (the ragged bottom).  So a byte column, from its highest pixel
to its floor, is a few SEGMENTS, each a run of lines over which every pixel's state is
fixed: one byte for even lines and one for odd (the boxes' dithers, masked), plus a
mask of untouched pixels (read-modify-write) when the segment has any.

    python3 proto/algo.py [grids]   checks the model against strip.py on that many
                                    random grids (by seed) and prints what the fill
                                    would do: segments, full runs, RMW lines
"""
import sys
import collections
import numpy as np

import points as P
import ragged as R
import strip as S

N = P.N


def transition(xt, yt, xb, yb, x):
    """The first line where B(y) <= x stops being what it is above the rung, or None."""
    b = R.boundary(xt, yt, xb, yb)
    was = xt <= x
    for y in range(yt, yb + 1):
        if (b[y] <= x) != was:
            return y
    return None


def plan(tops, bots):
    """The strip's columns: {c: (floor, [segments])}, a segment (y0, y1, states) for
    lines y0..y1-1, states a 4-tuple of box (0..7) or None (untouched) per pixel."""
    top, bot = P.trace(tops), P.trace(bots)
    floors = R.bottoms(bot)
    rungs = [(xt, yt, xb, yb) for (xt, yt), (xb, yb) in zip(tops, bots)]
    xl, xr = bots[0][0], bots[-1][0]
    cols = {}
    for c in range(xl // 4, xr // 4 + 1):
        if c not in floors:
            continue
        f = floors[c]
        px = []                                # per pixel: (ceil, n above, [(y, +-1)])
        for p in range(4):
            x = 4 * c + p
            n0 = sum(xt <= x for xt, _, _, _ in rungs) - 1
            ev = []
            for xt, yt, xb, yb in rungs:
                t = transition(xt, yt, xb, yb, x)
                if t is not None:
                    ev.append((t, -1 if xt <= x else 1))
            px.append((top.get(x, 0), n0, sorted(ev)))
        cuts = {f + 1}
        for ceil, n0, ev in px:
            cuts.add(ceil)
            cuts.update(t for t, _ in ev)
        cuts = sorted(y for y in cuts if y <= f + 1)
        segs = []
        lo = min(cuts)
        for y0, y1 in zip(cuts, cuts[1:]):
            st = []
            for ceil, n0, ev in px:
                n = n0 + sum(d for t, d in ev if t <= y0)
                st.append(n if (y0 >= ceil and 0 <= n < N - 1) else None)
            if any(s is not None for s in st):
                if segs and segs[-1][2] == tuple(st) and segs[-1][1] == y0:
                    segs[-1] = (segs[-1][0], y1, tuple(st))
                else:
                    segs.append((y0, y1, tuple(st)))
        if segs:
            cols[c] = (f, segs)
    return cols


def execute(img, cols, colours):
    """Draw the plan over img (palette entry + 1 by pixel), as the BBC would."""
    for c, (f, segs) in cols.items():
        for y0, y1, st in segs:
            for p, s in enumerate(st):
                if s is not None:
                    img[y0:y1, 4 * c + p] = colours[s] + 1
    return img


def kind(segs):
    """A column's shape, for the statistics: the composition of each segment."""
    out = []
    for y0, y1, st in segs:
        boxes = {s for s in st if s is not None}
        k = ('rmw ' if None in st else '') + ('one' if len(boxes) == 1 else f'{len(boxes)} boxes')
        out.append(k)
    return out


def main():
    grids = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    st = collections.Counter()
    for seed in range(grids):
        rng = np.random.default_rng(seed)
        rows = S.grid(rng)
        img = S.background()
        want = S.background()
        for k, (t, b) in enumerate(zip(rows, rows[1:])):
            colours = [(k * 3 + i) % 9 for i in range(8)]
            want = S.draw(want, t, b, colours)
            cols = plan(t, b)
            img = execute(img, cols, colours)
            st['strips'] += 1
            for c, (f, segs) in cols.items():
                st['columns'] += 1
                st[f'columns of {len(segs)} segments'] += 1
                for (y0, y1, s), kd in zip(segs, kind(segs)):
                    st[f'lines {kd}'] += y1 - y0
                    st[f'segments {kd}'] += 1
                    if 'rmw' not in kd and kd == 'one' and y1 - y0 >= 4:
                        st['runs of 4+ lines, one box'] += 1
        assert (img == want).all(), f'seed {seed}: model differs from strip.py'
    print(f'{grids} grids, {st["strips"]} strips: the model matches strip.py')
    n = st['strips']
    for k, v in sorted(st.items()):
        if k != 'strips':
            print(f'  {k:32s} {v / n:8.1f} a strip')


if __name__ == '__main__':
    main()
