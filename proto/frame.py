#!/usr/bin/env python3
"""A frame as the BBC draws it: land.py's rows made into strips with black margins,
a sky strip above and a ground strip below, each filled by strip.py.

The strips, top to bottom (strips_of): the sky, from a flat row at line YSKY down to
the far row; the land, one between each pair of consecutive rows; the ground, from
the near row down to a row whose every point is at YGND (the screen's last line) or
a line below the near row's point above it, whichever is lower: flat at YGND unless
the near row passes it.  Every strip gets a margin box at each
end: its rows are extended flat to a byte boundary M or more pixels beyond the
bottom row's end points (the bottom row being the wider), within XL..XR, and the
boxes there are black.  Since consecutive strips share a row, the sky row is flat
and the ground row is on or past the screen's last line, the strips tile the land's
extent without gaps and nothing outside them is touched (strip.py).

The screen is double buffered and a frame is drawn over what the frame before last
left in its buffer.  The margins are what make that safe in this model: a frame's
strips cover everything a frame two steps of the pan away drew, which main checks
by drawing into two buffers in turn and comparing each with the frame drawn alone
on black.  land.s draws the same strips with margins only to the byte boundary and
instead blacks what the same screen's last frame drew outside them, from its TOPS
and BOTS records: above each column's new top (record), below its new bottom
(nearpost) and the columns the land has left (gone); on black the two agree, which
is what test/landsoak.py compares byte for byte.

A strip wholly below the screen (every point past YGND: the camera raised, the
rows held at 254) is dropped before it is counted or drawn: it has no pixel on the
screen, and with both rows held at 254 its rungs do not go down, so it would fail
strip.ok.  YSKY and YGND are tables.inc's; lines YSKY..YGND are the 96 the land can
occupy.

    python3 proto/frame.py [frames] [M]   pans at random, STEP sixteenths of a tile
                                          at most each way a frame, jumping every 40
                                          frames; counts the strips failing strip.ok
                                          and the frames whose buffer differs from
                                          the frame alone; writes proto/frame_000.png
                                          and frame_001.png.  A jump leaves the old
                                          camera's land in both buffers wherever the
                                          new strips do not reach, and it stays until
                                          the pan covers it, so the frames counted
                                          wrong after a jump (the default 300 frames
                                          count 56, all after the jump at frame 240)
                                          are not the margins failing: with the
                                          buffers cleared at each jump none is wrong
"""
import os
import sys

import numpy as np

import land as L
import points as P
import strip as S

STEP = 1                  # main's pan: the most sixteenths of a tile a frame, each way
M = 8                     # the margin boxes' least width, pixels
YSKY, YGND = 64, 159      # the sky strip's top line and the ground strip's bottom
BLACK = 34                # swatch35's K4, the margins' and sky's entry (drawn as 0)


def strips_of(hm, cx, cz, m=M, e=0):
    """The frame's strips, top to bottom, each (top points, bottom points, box
    entries) for strip.py: the sky, the land strips, the ground, with the margins
    above (m the least margin).  Each row has 13 points: the margin points and
    land.project's 11; the entries are BLACK, the 10 tiles' (land.colour: box i is
    tile (xs[i], the nearer row's z), the strip's land row k + 1 of len(rows) - 1)
    or BLACK for the sky and ground, and BLACK.
    Camera (cx, cz) in 8.8 tiles, raised e."""
    xs, rows = L.project(hm, cx, cz, e)
    pts = [[(sx, sy) for sx, sy, _ in row] for _, row in rows]
    n = len(xs) - 1
    cols = [[L.colour(hm, x, rows[k + 1][0], k + 1, len(rows) - 1) for x in xs[:-1]]
            for k in range(len(rows) - 1)]
    sky = [(x, YSKY) for x, _ in pts[0]]
    gnd = [(x, max(YGND, y + 1)) for x, y in pts[-1]]
    pairs = [(sky, pts[0], [BLACK] * n)] + list(zip(pts, pts[1:], cols)) + [(pts[-1], gnd, [BLACK] * n)]
    out = []
    for t, b, c in pairs:
        if min(y for _, y in t + b) > YGND:
            continue
        xl = max(L.XL, (b[0][0] - m) & ~3)
        xr = min(L.XR, (b[-1][0] + m + 3) & ~3)
        out.append(([(xl, t[0][1])] + t + [(xr, t[-1][1])],
                    [(xl, b[0][1])] + b + [(xr, b[-1][1])],
                    [BLACK] + c + [BLACK]))
    return out


def draw(img, hm, cx, cz, m=M, e=0):
    """Draw the frame over img ((H, W) uint8: palette entry + 1 by pixel, 0 black),
    every strip whether or not it passes strip.ok.  Returns the strips failing it."""
    bad = 0
    for t, b, c in strips_of(hm, cx, cz, m, e):
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
        if f % 40 == 0:
            cx, cz = int(rng.integers(0, 1024)) * 16, int(rng.integers(0, 1024)) * 16
        else:
            cx += 16 * int(rng.integers(-STEP, STEP + 1))
            cz += 16 * int(rng.integers(-STEP, STEP + 1))
        buf = bufs[f & 1]
        bad += draw(buf, hm, cx, cz, m)
        ref = np.zeros_like(buf)
        draw(ref, hm, cx, cz, m)
        if f % 40 > 1 and not (buf == ref).all():      # (the two frames after a jump
            wrong += 1                                 # draw over the old camera's
                                                       # land; what they leave of it
                                                       # can count later, see above)
        if f < 2:
            L.render(buf).save(os.path.join(P.DIR, f'frame_{f:03d}.png'))
    print(f'{frames} frames, margin {m}: {bad} strips failing the guarantees, '
          f'{wrong} frames wrong in their buffer')


if __name__ == '__main__':
    main()
