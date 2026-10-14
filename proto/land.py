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

MAP = 64                  # tiles a side (the map wraps)
HSCALE = 16               # height units a tile
# Lander's elevated view, 7 tiles across; a tile's height on screen over its width is
# about CAMH / depth, so the rows sit around the camera's height out (near-square)
HMAX = 12                 # heights 0..HMAX (softened: under a tile)
SEA = 3                   # sea level: lower corners are flattened to it
W = 896                   # the grid's half-width, 8.8 tiles (3.5)
ZNEAR, ZFAR = 1024, 1920  # the near and far rows, 8.8 tiles in front (4, 7.5)
CAMH = 80                 # camera height, height units (HSCALE a tile: 5)
F = 115                   # focal length, pixels
HORIZON = 4               # screen y of the horizon
# the palette (proto/swatch35.py's numbering): the user's picks
LAND = [1, 3, 6, 10, 11, 16, 18, 21, 22, 26, 28]
SEAC = [0, 2, 15, 17]
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


def lerp(a, b, f):
    """a to b by f/256 (f a multiple of 256/STEPS), rounded as the BBC's table."""
    return a + (((b - a) * f + 128) >> 8)


def corner(hm, x, z):
    """The height at (x, z), 8.8 tiles: across then down between the map corners
    (only the pinned edges have fractions)."""
    xi, xf, zi, zf = x >> 8, x & 255, z >> 8, z & 255
    g = lambda i, j: int(hm[0][j % MAP, i % MAP])
    return lerp(lerp(g(xi, zi), g(xi + 1, zi), xf), lerp(g(xi, zi + 1), g(xi + 1, zi + 1), xf), zf)


XGAP = 1                  # a column line this close to a pinned edge (8.8 tiles) is
ZGAP = 32                 # dropped, and a row line: columns only on the edge itself,
                          # rows within an eighth of a tile (a thinner strip can have a
                          # rung of no height; an eighth makes 6 rows at most).  Thin
                          # strips' rungs can be shallow: the fill takes them



def grid_lines(lo, hi, gap):
    """Whole-tile positions between lo and hi (8.8), at least gap from both, with the
    two pinned ends: the grid's lines along one axis (virus drops a line that lands on
    the edge)."""
    first = (lo + gap + 255) >> 8
    last = (hi - gap) >> 8
    return [lo] + [k << 8 for k in range(first, last + 1)] + [hi]


def project(hm, cx, cz):
    """The rows, far to near, each (z, [(sx, sy, height)] across); and the columns' x."""
    zs = grid_lines(cz + ZNEAR, cz + ZFAR, ZGAP)[::-1]
    xs = grid_lines(cx - W, cx + W, XGAP)
    rows = []
    for z in zs:
        r = recip(z - cz)
        row = []
        for x in xs:
            h = corner(hm, x, z)
            sx = 128 + (((x - cx) * r + 32768) >> 16)
            sy = HORIZON + (((CAMH - h) * r + HSCALE * 128) // (HSCALE * 256))
            row.append((sx, sy, h))
        rows.append((z, row))
    return xs, rows


TILERND = np.random.default_rng(12345).integers(0, 16, (MAP, MAP))   # (the BBC's map: 4 bits a tile)


def colour(hm, i, j, row, nrows):
    """A tile's palette entry (swatch35 numbering): a random pick, fixed per tile (the
    BBC's map holds it), from the sea set if both its front corners are at sea level,
    else from the land set."""
    h, base = hm
    a, p = int(h[j % MAP, (i + 1) % MAP]), int(h[j % MAP, i % MAP])
    r = int(TILERND[j % MAP, i % MAP])
    if a == SEA and p == SEA:
        return SEAC[r % len(SEAC)]
    return LAND[r % len(LAND)]


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
