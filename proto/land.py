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
HMAX = int(__import__('os').environ.get('LAND_HMAX', 15))   # heights 0..HMAX (softened:
                          # under a tile), sea level 0 (LAND_HMAX: the tests')
SEA = 0                   # sea level: lower corners are flattened to it
SEAS = -10 / 12            # the six-sine sum's sea level (39% of corners under it)
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
XSKIP = 1                 # the corner columns not drawn either side (their tiles: the
                          # left and right columns)
XCLIP = 1152              # the clip planes in x, 8.8 tiles from the camera either side (4.5)
ZCLIP = 10                # the near clip plane's depth, tiles (the ship's 15, less 5)
                          # (always on)
ZFCLIP = 16               # the far clip plane's depth, tiles (the near's, and 6)
FON = True                # the far clip on (always)
ZSKIP = 3                 # the far corner rows not drawn (their tiles: the far three rows)
CAMH = int(__import__('os').environ.get('LAND_CAMH', 96))   # camera height above the
                          # ground at the ship (ZSHIP ahead, at the camera's x), height
                          # units (HSCALE a tile: 6 tiles; LAND_CAMH: the tests')
EMAX = 46                 # the camera's most above CAMH (the near row's y's within a byte)
ZSHIP = 13                # the ship's depth, tiles (Lander's LANDSCAPE_Z_MID 15: here the clip planes' middle)
PADN = 6                  # the landing pad: tiles 0..PADN-1 in x and z (Lander's: 8)
PADH = 4                  # its height
PADC = 19                 # its colour (swatch35: one of each ink, a grey)
F256 = 65536              # focal length, 8.8 pixels (256: Lander's)
HORIZON = 0               # screen y of the horizon
XC = 128                  # screen x of the centre (Lander's 160 of 320)
YLIM = 156                # the lowest a row's corner goes (proto/frame.py's YGND - 1)
XL, XR = 4, 252           # the edges the rows are clipped to, either side of XC alike
                          # (XR the last byte boundary: the land is drawn in x 4..251)
# the palette (proto/swatch35.py's numbering): the user's picks
LAND = [3, 6, 10, 11, 16, 18, 21, 22, 26, 28]
SEAC = [0, 2, 15, 17]
STEPS = 16                # camera positions a tile (coarse panning: few distinct depths)


def heightmap():
    """Lander's altitude formula (six sines; the sum spans +-5 tiles there), the
    corners below SEAS at sea level (0), the rest scaled to 1..HMAX (softened).  Also
    each tile's base (Lander's: bits 2 and 3 of the raw altitude, i.e. a hash)."""
    s = np.zeros((MAP, MAP))
    base = np.zeros((MAP, MAP), dtype=int)
    t = 2 * math.pi / MAP
    for z in range(MAP):
        for x in range(MAP):
            a, b = x * t, z * t
            s[z, x] = (2 * math.sin(a - 2 * b) + 2 * math.sin(4 * a + 3 * b) + 2 * math.sin(3 * b - 5 * a)
                       + 2 * math.sin(7 * a + 5 * b) + math.sin(5 * a + 11 * b) + math.sin(10 * a + 7 * b))
            raw = int((s[z, x] + 10) / 20 * (1 << 24))      # Lander's altitude, finely
            base[z, x] = (raw >> 2) & 3
    land = s >= SEAS
    h = np.where(land, 1 + np.round((s - SEAS) / (s.max() - SEAS) * (HMAX - 1)), 0).astype(int)
    h[:PADN + 1, :PADN + 1] = PADH        # the landing pad: flat (0 <= x, z < PADN)
    return h, base


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


def ground(hm, cx, cz):
    """The ground's height under the ship: ZSHIP tiles ahead of the camera, at its x
    (x + 128: corner i's x is (xt - 5 + i) - cx - 0.5 tiles), between the four corners
    round it (lerp: across, then down)."""
    x, z = cx + 128, cz + ZSHIP * 256
    xi, xf, zi, zf = x >> 8, x & 255, z >> 8, z & 255
    g = lambda i, j: int(hm[0][j % MAP, i % MAP])
    return lerp(lerp(g(xi, zi), g(xi + 1, zi), xf), lerp(g(xi, zi + 1), g(xi + 1, zi + 1), xf), zf)


def project(hm, cx, cz, e=0):
    """The rows, far to near, each (its tile z, [(sx, sy, height)] across); and the
    columns' tile x (each point's: box i is tile xs[i]).  Camera (cx, cz) in 8.8
    tiles.  Clipped in x at -XCLIP and +XCLIP tiles from the camera: a row's points
    the edge there (its height between corners 1 and 2, or 10 and 11, by fx, as
    lerp), corners 2..10 between (at fx 0, corner 10 is on the right edge: the edge
    repeats it).  Clipped in z at ZCLIP (near: its row between the corner rows
    either side, by 1 - fz, a line or more below the row before) and, if FON, at
    ZFCLIP (far: likewise, a line or more above the row after; at fz 0 a corner row
    is on it).  e: the camera that much higher (height units, 0..EMAX: the ship's
    camera), each row's y's lower by (e (r >> 5) + 64) >> 7."""
    xt, zt, fx, fz = cx >> 8, cz >> 8, cx & 255, cz & 255
    xs = [xt - 5 + i for i in range(XSKIP, NX - XSKIP)]      # corners 1..11
    hg = ground(hm, cx, cz)               # (the camera: CAMH above it)
    rows = []
    jc = ZBACK - ZCLIP                    # (the corner row the near clip replaces)
    jp = ZBACK - ZFCLIP                   # (the corner row on the far clip plane at fz 0)
    jf = (jp - 1 if fz else jp) if FON else ZSKIP   # (the first: the far clip's, from it
                                                    # and the next, at fz not 0)
    for j in range(jf, jc + 1):
        z = zt + ZBACK - j
        r = recip((z << 8) - cz)
        hs = [int(hm[0][z % MAP, x % MAP]) for x in xs]
        if j == jc:                       # on the near clip plane: from the row
            r = recip(ZCLIP << 8)         # before by 1 - fz
            hp = [int(hm[0][(z + 1) % MAP, x % MAP]) for x in xs]
            hs = [lerp(a, b, 256 - fz) for a, b in zip(hp, hs)]
        elif FON and fz and j == jf:      # on the far clip plane: to the row after by
            r = recip(ZFCLIP << 8)        # 1 - fz
            hn = [int(hm[0][(z - 1) % MAP, x % MAP]) for x in xs]
            hs = [lerp(a, b, 256 - fz) for a, b in zip(hs, hn)]
        pts = [(-XCLIP, lerp(hs[0], hs[1], fx))]
        pts += [((x << 8) - cx - 128, h) for x, h in zip(xs[1:-1], hs[1:-1])]
        pts += [(XCLIP, lerp(hs[-2], hs[-1], fx))]
        row = []
        ey = (e * (r >> 5) + 64) >> 7
        for dx, h in pts:
            sx = XC + ((dx * r + 32768) >> 16)
            sy = HORIZON + (((CAMH + hg - h) * r + HSCALE * 128) // (HSCALE * 256)) + ey
            row.append((sx, sy, h))
        row = clip(row)
        if j == jc:                       # (at least a line below the row before: the
            row = [(x, max(y, py + 1), h) # strip between can be thin)
                   for (x, y, h), (_, py, _) in zip(row, rows[-1][1])]
        if FON and fz and j == jf + 1:    # (the far clip's: a line or more above this)
            rows[0] = (rows[0][0], [(x, min(y, ny - 1), h)
                                    for (x, y, h), (_, ny, _) in zip(rows[0][1], row)])
        rows.append((z, row))
    return xs, rows


TILERND = np.random.default_rng(12345).integers(0, 16, (MAP, MAP))   # (the BBC's map: 4 bits a tile)


TILERND2 = np.random.default_rng(54321).integers(0, 16, (MAP, MAP))  # (a second pick)
LIGHT = 0.5               # the lighting's weight against the random pick (gentle: half)
SLOPE1 = 6                # a slope (sixteenths a tile) that takes the light from middling
                          # to the dark or light end


def _land_axes():
    """Each land colour's place on two axes, as ranks 0..1 among them: yellow (its
    average red over red and green: yellow 1, green 0) and light (its luminance)."""
    import swatch35 as SW
    def avg(e):
        cl = SW.cell(*SW.ALL[e])
        return [sum(SW.PHYS[v][ch] for v in cl.values()) / 4 for ch in range(3)]
    ys = [avg(e)[0] / (avg(e)[0] + avg(e)[1] + 1e-9) for e in LAND]
    ls = [0.3 * avg(e)[0] + 0.59 * avg(e)[1] + 0.11 * avg(e)[2] for e in LAND]
    rank = lambda v: [sorted(v).index(x) / (len(v) - 1) for x in v]
    return list(zip(rank(ys), rank(ls)))


LANDAX = _land_axes()


def _targets(hm):
    """Each land tile's targets on the two axes (the docstring of colour), each
    spread evenly over 0..1 by rank across the map's land tiles (so the palette is
    all used); None for sea."""
    h, base = hm
    g = lambda x, z: int(h[z % MAP, x % MAP])
    raw = {}
    for j in range(MAP):
        for i in range(MAP):
            if all(g(i + dx, j + dz) == SEA for dx in (0, 1) for dz in (0, 1)):
                continue                  # (sea: all four corners at sea level)
            hs = (g(i, j), g(i + 1, j), g(i, j + 1), g(i + 1, j + 1))
            alt = min(1.0, max(0.0, (sum(hs) / 4 - SEA) / (HMAX - SEA)))
            slope = ((hs[0] + hs[2]) - (hs[1] + hs[3])) / 2
            ty = (1 - LIGHT) * TILERND[j, i] / 15 + LIGHT * (1 - alt)
            tl = (1 - LIGHT) * TILERND2[j, i] / 15 + LIGHT * min(1.0, max(0.0, 0.5 - slope / SLOPE1))
            raw[(i, j)] = (ty + 1e-6 * (i + MAP * j), tl + 1e-6 * (j + MAP * i))
    keys = list(raw)
    out = {}
    for ax in (0, 1):
        order = sorted(keys, key=lambda t: raw[t][ax])
        for n, t in enumerate(order):
            out.setdefault(t, [0, 0])[ax] = n / (len(order) - 1)
    return out


_TGT = {}


def colour(hm, i, j, row, nrows):
    """A tile's palette entry (swatch35 numbering), fixed per tile (the BBC's map
    holds it).  Sea (all four corners at sea level: flat): a random pick from the
    sea set.  Land: lit, gently -- the land colour nearest a target on two axes,
    each half a random pick (TILERND, TILERND2) and half the lighting: yellow low
    down, green high up (its corners' mean height); darker where it slopes down to
    the right, lighter down to the left (its left corners' heights less its right's);
    each axis spread evenly by rank over the map's land tiles."""
    key = id(hm[0])
    if key not in _TGT:
        _TGT.clear()
        _TGT[key] = _targets(hm)
    if i % MAP < PADN and j % MAP < PADN:
        return PADC
    t = _TGT[key].get((i % MAP, j % MAP))
    if t is None:
        return SEAC[int(TILERND[j % MAP, i % MAP]) % len(SEAC)]
    k = min(range(len(LAND)), key=lambda n: (LANDAX[n][0] - t[0]) ** 2 + (LANDAX[n][1] - t[1]) ** 2)
    return LAND[k]


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
        cols = [colour(hm, x, z1, k + 1, len(rows) - 1) for x in xs[:-1]]
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
