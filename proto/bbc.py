#!/usr/bin/env python3
"""The BBC's fill for a strip, modelled (proto/frame.py's strips; land.s ports it):
by byte column, each from its top-row pixels' highest line to its floor.

A column's pixels are in at most two boxes at any line: a rung (one at most: else the
slow way) splits them, its boundary bpos (pixels left of it) moving one pixel at each
of its transitions in the column.  So the column is
  - its TOP ZONE: lines from its pixels' highest top-row line to (not including) the
    lowest, or to the floor; each line the pixels at or below their top
    (read-modify-write), split by the rung as it is at that line;
  - then RUNS: from the lowest top-row line to the floor, a run of whole bytes between
    each transition and the next.
The slow way, for a column two rungs split: a line at a time, each pixel by itself.

    python3 proto/bbc.py [frames]   checks the model against frame.py's strips (each
                                    strip drawn over the last, so the order matters
                                    too) and prints what the fill does a frame
"""
import sys
import collections
import numpy as np

import land as L
import points as P
import ragged as R
import frame as F


def top_line(pts):
    """The row's line by pixel (strip.py's trace)."""
    return P.trace(pts)


def strip_plan(t, b, ncol):
    """The strip's columns as the BBC draws them: [(c, kind, ops)], ops a list of
    ('zone', y, mask, bpos) / ('run', y0, y1, bpos) / ('slow', y, [box or None]) with
    the column's L and R boxes."""
    top, bot = top_line(t), top_line(b)
    rungs = [(xt, yt, xb, yb) for (xt, yt), (xb, yb) in zip(t, b)]
    rt = [R.transitions(*r) for r in rungs]          # each rung's, by pixel
    bs = [R.boundary(*r) for r in rungs]
    xl, xr = b[0][0], b[-1][0]
    assert xl % 4 == 0 and xr % 4 == 0 and t[0][0] == xl and t[-1][0] == xr
    out = []
    i = 0                                     # rungs wholly left of the column: i
    for c in range(xl // 4, xr // 4):
        ys = [top[x] for x in range(4 * c, 4 * c + 4)]
        mn, mx = min(ys), max(ys)
        floor = max(bot[x] for x in range(4 * c, 4 * c + 4))
        while max(rungs[i][0], rungs[i][2]) <= 4 * c:
            i += 1
        aff = [r for r in range(i, len(rungs))
               if min(rungs[r][0], rungs[r][2]) <= 4 * c + 3]
        # (rungs i.. have hi > 4c, so lo <= 4c+3 is enough)
        box = i - 1
        if not aff:
            lbox = rbox = box
            p0, trans = 0, []
        elif len(aff) == 1:
            r = aff[0]
            assert r == i
            lbox, rbox = r - 1, r
            xt, yt, xb, yb = rungs[r]
            p0 = min(max(xt - 4 * c, 0), 4)
            p1 = min(max(xb - 4 * c, 0), 4)
            if p1 > p0:
                trans = [(rt[r][4 * c + p], p + 1) for p in range(p0, p1)]
            else:
                trans = [(rt[r][4 * c + p], p) for p in range(p0 - 1, p1 - 1, -1)]
        if len(aff) > 1:
            ops = []
            for y in range(mn, floor + 1):
                st = []
                for p in range(4):
                    x = 4 * c + p
                    if y < ys[p]:
                        st.append(None)
                    else:
                        st.append(sum(bb[min(max(y, r[1]), r[3])] <= x for bb, r in zip(bs, rungs)) - 1)
                ops.append(('slow', y, st))
            out.append((c, 'slow2' if len(aff) > 1 else 'slow', ops, None, None))
            continue
        ops = []
        bpos = p0
        for y in range(mn, min(mx, floor + 1)):
            while trans and trans[0][0] <= y:          # (transitions in the zone)
                bpos = trans.pop(0)[1]
            mask = sum(1 << p for p in range(4) if ys[p] <= y)
            ops.append(('zone', y, mask, bpos))
        y = mx
        for ty, nb in trans + [(floor + 1, None)]:
            if ty > floor + 1:
                ty = floor + 1
            if ty > y:
                ops.append(('run', y, ty, bpos))
                y = ty
            if nb is None or y > floor:
                break
            bpos = nb
        out.append((c, 'two' if aff else 'one', ops, lbox, rbox))
    return out


def execute(img, plan, colours):
    """Draw the plan over img (palette entry + 1 by pixel, black 0)."""
    def ink(b):
        e = colours[b]
        return 0 if e == F.BLACK else e + 1
    for c, kind, ops, lbox, rbox in plan:
        for op in ops:
            if op[0] == 'slow':
                _, y, st = op
                for p, s in enumerate(st):
                    if s is not None:
                        img[y, 4 * c + p] = ink(s)
            elif op[0] == 'zone':
                _, y, mask, bpos = op
                for p in range(4):
                    if mask >> p & 1:
                        img[y, 4 * c + p] = ink(lbox if p < bpos else rbox)
            else:
                _, y0, y1, bpos = op
                for p in range(4):
                    img[y0:y1, 4 * c + p] = ink(lbox if p < bpos else rbox)
    return img


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 100
    hm = L.heightmap()
    rng = np.random.default_rng(5)
    st = collections.Counter()
    for f in range(frames):
        cx, cz = int(rng.integers(0, 1024)) * 16, int(rng.integers(0, 1024)) * 16
        img = np.full((P.H, P.W), 99, np.uint8)
        want = img.copy()
        for t, b, cols in F.strips_of(hm, cx, cz):
            plan = strip_plan(t, b, None)
            execute(img, plan, cols)
            for c, kind, ops, _, _ in plan:
                st[kind] += 1
                for op in ops:
                    st[op[0]] += 1
                    if op[0] == 'run':
                        st['run lines'] += op[2] - op[1]
        F.draw(want, hm, cx, cz)
        inside = want != 99
        assert (img[inside] == want[inside]).all(), f'frame {f}: differs inside'
        outside = img[~inside]
        assert ((outside == 99) | (outside == 0)).all(), f'frame {f}: non-black outside'
    print(f'{frames} frames: the model matches frame.py (black or untouched outside)')
    for k, v in sorted(st.items()):
        print(f'  {k:12s} {v / frames:8.1f} a frame')


if __name__ == '__main__':
    main()
