#!/usr/bin/env python3
"""Reference for the landscape: a Lander-style tile map, seen from an elevated camera
with no yaw, projected into rows of points and filled a strip at a time (strip.py).

Everything is integer, as the BBC will compute it:
  - the map: MAP x MAP tiles (wrapping), each corner a height 0..HMAX (in 1/HSCALE
    tile) from Lander's sum of sines, softened, and each tile a shade;
  - the camera: (cx, cz) in 8.8 tiles, at height CAMH tiles, looking along +z;
  - the grid: columns at whole tiles inside cx +- W, plus the two edges pinned at
    exactly cx - W and cx + W; rows at whole tiles between cz + ZNEAR and cz + ZFAR,
    plus those two pinned (virus's scheme: the landscape's outline on screen is then a
    fixed trapezoid, no screen clipping); a pinned corner's height is interpolated;
  - a row at depth d (8.8 tiles from the camera) has R = recip(d) = F / d pixels per
    tile (8.8); a corner at x (8.8, from the camera) and height h projects to
        sx = 128 + x * R          sy = HORIZON + (CAMH * HSCALE - h) * R / HSCALE
    (each rounded as the 6502 does: see project());
  - the strips: from the far row to the near one, each the band between a row and the
    next nearer, filled as strip.py (dithers by tile colour).

    python3 proto/land.py [frames]   renders a pan (land_NNN.png), checks every strip's
                                     guarantees (strip.ok), and prints the statistics
"""
import sys
import math
import numpy as np

import points as P
import strip as S

MAP = 128                 # tiles a side (the map wraps)
HSCALE = 16               # height units a tile
HMAX = 16                 # heights 0..HMAX (a tile: Lander's softened)
SEA = 4                   # sea level: lower corners are flattened to it
W = 6                     # the grid's half-width, tiles (12 across, as Lander)
ZNEAR, ZFAR = 5, 11       # the near and far rows, tiles in front of the camera
CAMH = 9                  # camera height, tiles above height 0
F = 84                    # focal length, pixels
HORIZON = 4               # screen y of the horizon
# the palette (proto/swatch35.py's numbering): the user's picks
LAND = [1, 3, 6, 10, 11, 16, 18, 21, 22, 26, 28, 32]
SEAC = [0, 2, 5, 15, 17, 27, 31]
STEPS = 16                # camera positions a tile (coarse panning: few distinct depths)


def heightmap():
    """Lander's altitude formula (six sines; the sum spans +-5 tiles there), scaled to
    0..HMAX and softened; corners below SEA flattened to it.  Also each tile's base
    (Lander's: bits 2 and 3 of the raw altitude, i.e. a hash) and a sea shade."""
    h = np.zeros((MAP, MAP), dtype=int)
    base = np.zeros((MAP, MAP), dtype=int)
    t = 2 * math.pi / MAP
    for z in range(MAP):
        for x in range(MAP):
            a, b = x * t, z * t
            s = (2 * math.sin(a - 2 * b) + 2 * math.sin(4 * a + 3 * b) + 2 * math.sin(3 * b - 5 * a)
                 + 2 * math.sin(7 * a + 5 * b) + math.sin(5 * a + 11 * b) + math.sin(10 * a + 7 * b))
            h[z, x] = round((s + 10) / 20 * HMAX)
            raw = int((s + 10) / 20 * (1 << 24))      # Lander's altitude, finely
            base[z, x] = (raw >> 2) & 3
    return np.maximum(h, SEA), base


def lander_rgb(base, bright):
    """Lander's tile colour: red = bit 2, green = bit 3 (+4), blue 0, plus the
    brightness in all three, each to 15 (0-1 here)."""
    r, g, b = (base & 1) * 4, (base >> 1) * 4 + 4, 0
    return tuple(min(15, c + bright) / 15 for c in (r, g, b))


def nearest(rgb, choices):
    import swatch35 as SW
    def avg(i):
        cl = SW.cell(*SW.ALL[i])
        return [sum(SW.PHYS[v][ch] for v in cl.values()) / 4 / 255 for ch in range(3)]
    return min(choices, key=lambda i: sum((a - b) ** 2 for a, b in zip(avg(i), rgb)))


LANDTAB = [[nearest(lander_rgb(bs, br), LAND) for br in range(16)] for bs in range(4)]


def recip(d):
    """F / d, d in 8.8 tiles: pixels a tile, 8.8 (as a table lookup would give it)."""
    return (F * 65536 + d // 2) // d


def corner(hm, x, z):
    """The height at (x, z), 8.8 tiles: bilinear between the four map corners."""
    xi, xf, zi, zf = x >> 8, x & 255, z >> 8, z & 255
    g = lambda i, j: int(hm[0][j % MAP, i % MAP])
    top = g(xi, zi) * (256 - xf) + g(xi + 1, zi) * xf
    bot = g(xi, zi + 1) * (256 - xf) + g(xi + 1, zi + 1) * xf
    return (top * (256 - zf) + bot * zf + 32768) >> 16


def grid_lines(lo, hi):
    """Whole-tile positions between lo and hi (8.8), at least half a tile from both,
    with the two pinned ends: the grid's lines along one axis (no sliver next to a
    pinned edge; virus drops a line that lands on the edge)."""
    first = (lo + 128 + 255) >> 8
    last = (hi - 128) >> 8
    return [lo] + [k << 8 for k in range(first, last + 1)] + [hi]


def project(hm, cx, cz):
    """The rows, far to near, each (z, [(sx, sy, height)] across); and the columns' x."""
    zs = grid_lines(cz + (ZNEAR << 8), cz + (ZFAR << 8))[::-1]
    xs = grid_lines(cx - (W << 8), cx + (W << 8))
    rows = []
    for z in zs:
        r = recip(z - cz)
        row = []
        for x in xs:
            h = corner(hm, x, z)
            sx = 128 + (((x - cx) * r + 32768) >> 16)
            sy = HORIZON + (((CAMH * HSCALE - h) * r + HSCALE * 128) // (HSCALE * 256))
            row.append((sx, sy, h))
        rows.append((z, row))
    return xs, rows


def colour(hm, i, j, row, nrows):
    """A tile's palette entry (swatch35 numbering): Lander's, from the corner at
    (i, j) and the one to its left; row counts from 1 at the back."""
    h, base = hm
    a, p = int(h[j % MAP, (i + 1) % MAP]), int(h[j % MAP, i % MAP])
    if a == SEA and p == SEA:
        return SEAC[(i * 7 + j * 13 + (i * j) % 5) % len(SEAC)]       # random, by tile
    slope = max(0, p - a)
    bright = (row * 7) // nrows + (4 * slope) // HSCALE
    return LANDTAB[base[j % MAP, (i + 1) % MAP]][min(bright, 15)]


def frame(hm, cx, cz):
    """The frame (palette entry + 1 by pixel, 0 black) and the strips' guarantees."""
    xs, rows = project(hm, cx, cz)
    img = np.zeros((P.H, P.W), dtype=np.uint8)
    bad = 0
    for k, ((z0, top), (z1, bot)) in enumerate(zip(rows, rows[1:])):
        t = [(sx, sy) for sx, sy, _ in top]
        b = [(sx, sy) for sx, sy, _ in bot]
        if not S.ok(t, b):
            bad += 1
            continue
        cols = [colour(hm, (x >> 8), (z1 >> 8), k + 1, len(rows) - 1) for x in xs[:-1]]
        m = S.mask(t, b)
        img[m >= 0] = np.array(cols)[m[m >= 0]] + 1
    return img, bad, len(rows) - 1


def render(img, scale=4):
    """img (swatch35 entry + 1 by pixel, 0 black) as the BBC shows it: each pixel its
    dither's ink (MODE 1's pixels are near enough square)."""
    import swatch35 as SW
    out = np.zeros((P.H, P.W, 3), dtype=np.uint8)
    cells = [None] + [SW.cell(*t) for t in SW.ALL]
    for y in range(P.H):
        for x in range(P.W):
            e = img[y, x]
            if e:
                out[y, x] = SW.PHYS[cells[e][(x & 1, y & 1)]]
    from PIL import Image
    im = Image.fromarray(out).resize((P.W * scale, P.H * scale), Image.NEAREST)
    return im


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    hm = heightmap()
    cx, cz = 40 << 8, 30 << 8
    bad = 0
    for f in range(frames):
        img, b, n = frame(hm, cx, cz)
        bad += b
        if f < 4:
            render(img).save(f'land_{f:03d}.png')
        cx += 256 // STEPS * 3
        cz += 256 // STEPS * 5
    print(f'{frames} frames, {bad} strips failing the guarantees')
    print('land colour by base (rows) and brightness 0..15:')
    for r in LANDTAB:
        print('  ', r)


if __name__ == '__main__':
    main()
