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
HMAX = 12                 # heights 0..HMAX (softened: under a tile)
SEA = 3                   # sea level: lower corners are flattened to it
# Lander's camera (Lander.arm): TILES_X = 13, TILES_Z = 11 corners (12 x 10 tiles),
# the block's corners at z = 20 - fz - j (j 0..10, far to near) and x = -5.5 - fx + i
# (i 0..12: landscapeOffset's -LANDSCAPE_X, less xCamera's fraction) tiles from the
# camera (the ship's x: the screen's centre), so the block's edges average -6 and +6, fx, fz the camera's fractions of a tile (the
# block of whole tiles slides, a tile at a time: no pinned edges, no slivers); its
# projection on 320 x 256 (MODE 13): 160 + 256 x / z, 64 + 256 y / z.  Here: the
# same, scaled to 256 wide (focal 204.8), the horizon moved up to fit 160 lines;
# rows clipped at the screen's edges (the nearest overhang them, as in Lander)
NX, NZ = 13, 11           # corners across and deep
ZBACK = 20                # the back row's depth, tiles (fz = 0)
ZSKIP = 4                 # the far corner rows not drawn (their tiles: the far four rows)
CAMH = 80                 # camera height, height units (HSCALE a tile: 5)
F256 = 65536              # focal length, 8.8 pixels (256: Lander's)
HORIZON = 20              # screen y of the horizon
XC = 128                  # screen x of the centre (Lander's 160 of 320)
YLIM = 156                # the lowest a row's corner goes (proto/frame.py's YGND - 1)
XL, XR = 4, 252           # the edges the rows are clipped to, either side of XC alike
                          # (XR the last byte boundary: the land is drawn in x 4..251)
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
    return (F256 * 256 + d // 2) // d


def lerp(a, b, f):
    """a to b by f/256 (f a multiple of 256/STEPS), rounded as the BBC's table."""
    return a + (((b - a) * f + 128) >> 8)


def corner(hm, x, z):
    """The height at (x, z), 8.8 tiles: across then down between the map corners
    (only the pinned edges have fractions)."""
    xi, xf, zi, zf = x >> 8, x & 255, z >> 8, z & 255
    g = lambda i, j: int(hm[0][j % MAP, i % MAP])
    return lerp(lerp(g(xi, zi), g(xi + 1, zi), xf), lerp(g(xi, zi + 1), g(xi + 1, zi + 1), xf), zf)


def clip(row):
    """The row's points clipped to the screen (x XL..XR): the points beyond an edge
    moved onto it, at the row's y where it crosses it (rounded), so the strips' end
    rungs there are vertical, along the edge."""
    pts = [list(p) for p in row]
    k = 0
    while pts[k][0] < XL:
        k += 1
    if k:
        (x0, y0, _), (x1, y1, _) = pts[k - 1], pts[k]
        yc = y0 + ((y1 - y0) * (XL - x0) * 2 + (x1 - x0)) // (2 * (x1 - x0))
        for i in range(k):
            pts[i][0], pts[i][1] = XL, yc
    k = len(pts) - 1
    while pts[k][0] > XR:
        k -= 1
    if k < len(pts) - 1:
        (x0, y0, _), (x1, y1, _) = pts[k], pts[k + 1]
        yc = y0 + ((y1 - y0) * (XR - x0) * 2 + (x1 - x0)) // (2 * (x1 - x0))
        for i in range(k + 1, len(pts)):
            pts[i][0], pts[i][1] = XR, yc
    return [tuple(p) for p in pts]


def project(hm, cx, cz):
    """The rows, far to near, each (its tile z, [(sx, sy, height)] across); and the
    columns' tile x.  Camera (cx, cz) in 8.8 tiles."""
    xt, zt = cx >> 8, cz >> 8
    xs = [xt - 5 + i for i in range(NX)]
    rows = []
    for j in range(ZSKIP, NZ):
        z = zt + ZBACK - j
        r = recip((z << 8) - cz)
        row = []
        for x in xs:
            h = int(hm[0][z % MAP, x % MAP])
            dx = (x << 8) - cx - 128
            sx = XC + ((dx * r + 32768) >> 16)
            sy = HORIZON + (((CAMH - h) * r + HSCALE * 128) // (HSCALE * 256))
            row.append((sx, sy, h))
        row = clip([(sx, min(sy, YLIM), h) for sx, sy, h in row])
        rows.append((z, row))
        if any(sy >= YLIM for _, sy, _ in row):
            break                         # (the rows nearer: off the screen)
    return xs, rows


def off(top, bot, i):
    """Box i between rows top and bot (points) touches the screen's edges: a corner
    clipped at XL or XR or at YLIM (crudely, the box is then not drawn)."""
    return any(x <= XL or x >= XR or y >= YLIM
               for x, y, *_ in (top[i], top[i + 1], bot[i], bot[i + 1]))


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
        cols = [None if off(top, bot, i) else colour(hm, x, z1, k + 1, len(rows) - 1) for i, x in enumerate(xs[:-1])]
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
