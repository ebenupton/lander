#!/usr/bin/env python3
"""The landscape: Lander's height map seen from a camera above and behind the ship,
projected into rows of screen points that frame.py fills a strip at a time.  Every
quantity is an integer computed as land.s computes it; tools/landgen.py tabulates
the functions here for sideways RAM, and test/landsoak.py checks land.s's rows and
pixels against project and frame.draw.

Coordinates and units:
  - the map is MAP x MAP tiles and wraps; corner (x, z) has a height 0..HMAX in
    height units, HSCALE to a tile (heightmap); tile (i, j) lies between corners i
    and i + 1 across and j and j + 1 deep and has one colour (colour);
  - a map position is in 8.8 fixed point tiles (256 to a tile): the camera is at
    (cx, cz), xt = cx >> 8 its tile and fx = cx & 255 its fraction; its line of
    sight is at map x (cx + 128) / 256 and runs along +z; it is CAMH height units
    above the ground ZSHIP tiles ahead of it (ground), plus a raise e of 0..EMAX;
  - a row is the corners at one map z, which is depth d = z * 256 - cz ahead of
    the camera (8.8 tiles); it has R = recip(d) pixels a tile (8.8); a corner x
    tiles across (8.8, from the line of sight) and h units high projects to
        sx = XC + x R / 256                       (rounded)
        sy = HORIZON + (CAMH + hg - h) R / (HSCALE 256) + ey    (rounded, as project)
    with hg the ground's height under the ship and ey the raise's lines;
  - the screen is 256 x 160 (points.W, H): x 0..255 left to right, y down.

A frame's rows (project), far to near: the far clip plane at ZFCLIP tiles, the
corner rows nearer than it, and the near clip plane at ZCLIP tiles; 11 points each
(NX - 2 XSKIP), the end points on the x clip planes at -XCLIP and +XCLIP.  The
rows between clip planes are at whole-tile depths, so the frame's set of depths is
fixed by fz alone; each row traces to one y a pixel because its segments are
shallow (the largest height step between adjacent corners on this map is 6 units
against a corner gap of 16 pixels or more, and an end segment, cut short by its x
clip plane, keeps its corners' slope); rung i joins point i of a row to point i of
the next.  land.s relies on strip.py's guarantees holding for every
consecutive pair of rows (main here and frame.py's report the strips failing them:
none on this map), and draws nothing outside the strips.

    python3 proto/land.py [frames]   pans 3/16 tile across and 5/16 deep a frame,
                                     writes proto/land_000.png .. land_003.png (the
                                     first four frames as the BBC shows them) and
                                     prints the strips failing strip.ok
"""
import math
import os
import sys

import numpy as np

import points as P
import strip as S
import swatch35 as SW
import nula as NU

# The map
MAP = 64                  # tiles a side (wrapping): landgen's MAP table, 64 bytes a row
HSCALE = 16               # height units a tile
HMAX = int(os.environ.get('LAND_HMAX', 15))     # heights 0..HMAX: the MAP byte's low
                          # nibble, SYT7's 2 HMAX + 1 entries in a 32-byte row and
                          # LERPQ7's differences -15..15 (LQOFF) all need HMAX <= 15
                          # (LAND_HMAX in the environment overrides it; nothing in
                          # the tree sets it)
SEA = 0                   # sea level: corners under SEAS are flattened to it
SEAS = -10 / 12           # the six-sine sum's sea level: 39% of corners are under it
# The grid: Lander's 13 x 11 corners (12 x 10 tiles).  Corner i (0..12) of a row is
# at (i - 5) * 256 - fx - 128 across (8.8 tiles from the line of sight) and corner
# row j (0..10) at depth (ZBACK - j) * 256 - fz.
NX, NZ = 13, 11           # corners across and deep (land.s: 16 bytes a row for PX, PY;
                          # landgen's DI0 is the near row's least depth, from NZ)
ZBACK = 20                # corner row 0's depth, tiles (at fz 0)
XSKIP = 1                 # corner columns not drawn either side: columns 1..11 are
                          # (11 points a row: land.s's np, tables.inc's NX)
XCLIP = 1152              # the x clip planes, 8.8 tiles either side of the line of
                          # sight (4.5): a row's end points are on them, between
                          # corners 1 and 2 and corners 10 and 11 (PINL7, PINR7)
ZCLIP = 10                # the near clip plane's depth, tiles: the last row is on it
                          # (row j = ZBACK - ZCLIP replaced; land.s's RN, PXN7)
ZFCLIP = 16               # the far clip plane's depth, tiles: the first row is on it
                          # (corner row ZBACK - ZFCLIP at fz 0, else the row before
                          # it replaced; PXF7)
ZSKIP = 3                 # corner rows 0..ZSKIP-1 are never drawn: row ZSKIP is the
                          # far clip's at fz not 0.  land.s's first row is ZB =
                          # ZFCLIP or ZFCLIP + 1 from czs; its ZBACK - ZSKIP is the
                          # far clip off, a case never taken, and its assert on nr
assert ZSKIP == ZBACK - ZFCLIP - 1
# The camera
CAMH = int(os.environ.get('LAND_CAMH', 96))     # its height above the ground under the
                          # ship, units (6 tiles; game.s raises it by CAME; LAND_CAMH
                          # in the environment overrides it; nothing in the tree sets
                          # it)
EMAX = 95                 # the most the camera is raised (e, game.s's CAME): at EMAX
                          # the far row's highest possible corner (ground 0, height
                          # HMAX) is at line HORIZON + 81 + 95 = 160, past YGND, so
                          # every row is below the screen whatever the ground
ZSHIP = 13                # the ship's depth, tiles: the ground under it sets the
                          # camera's height (ground, land.s's hgnd); the clip planes'
                          # middle; game.s puts the camera ZSHIP behind the ship and
                          # gamegen's SHYT uses recip(ZSHIP * 256)
# The landing pad
PADN = 6                  # tiles 0..PADN-1 across and deep (corners 0..PADN flat)
PADH = 4                  # its height, units (game.s spawns the ship on it)
PADC = 19                 # its colour: swatch35 entry 19, K1C1M1Y1, a grey (gamegen's
                          # map marker)
# The projection
F256 = 65536              # the focal length, 8.8 pixels: 256 pixels (Lander's, there
                          # on a 320-pixel screen: the view here is narrower)
HORIZON = -16             # the horizon's screen line, above the screen: the far row
                          # (depth 16 tiles, R 4096) puts its highest possible corner
                          # (ground 0, height HMAX) at HORIZON + (CAMH - HMAX) = 65,
                          # frame.py's YSKY + 1, so the sky strip is never empty;
                          # game.s's ship line is HORIZON + SHYT
XC = 128                  # the line of sight's screen x (Lander's 160 of 320)
YLIM = 156                # unused: nothing in the tree reads it and tables.inc does
                          # not carry it
XL, XR = 4, 252           # the screen edges rows are clipped to (clip) and frame.py's
                          # margins stop at: the land is drawn in x 4..251.  With
                          # these constants no row reaches them (the near row's ends
                          # are at 13 and 243)
# The palette: swatch35 entries, yellows and greens for land, cyans for sea
LAND = [3, 6, 10, 11, 16, 18, 21, 22, 26, 28]
SEAC = [0, 2, 15, 17]
if NU.enabled():          # the NULA build: fewer, flat (proto/nula.py)
    LAND, SEAC = NU.LAND, NU.SEAC
STEPS = 16                # camera positions a tile: a step is 256 / STEPS in 8.8
                          # (land.s's cxs, czs are sixteenths)


def heightmap():
    """The map: (h, base), each a (MAP, MAP) int array indexed [z, x].

    h is Lander's altitude formula, six sines in x and z summing to +-9.6: a corner
    under SEAS is SEA (0), the rest are 1..HMAX by linear scaling of the sum above
    SEAS, rounded; then corners 0..PADN both ways are PADH, the landing pad.  base is
    Lander's tile hash, bits 2 and 3 of its 24-bit altitude (s + 10) / 20 * 2^24;
    nothing in the build uses it (the tools unpack and drop it)."""
    s = np.zeros((MAP, MAP))
    base = np.zeros((MAP, MAP), dtype=int)
    t = 2 * math.pi / MAP
    for z in range(MAP):
        for x in range(MAP):
            a, b = x * t, z * t
            s[z, x] = (2 * math.sin(a - 2 * b) + 2 * math.sin(4 * a + 3 * b) + 2 * math.sin(3 * b - 5 * a)
                       + 2 * math.sin(7 * a + 5 * b) + math.sin(5 * a + 11 * b) + math.sin(10 * a + 7 * b))
            raw = int((s[z, x] + 10) / 20 * (1 << 24))
            base[z, x] = (raw >> 2) & 3
    land = s >= SEAS
    h = np.where(land, 1 + np.round((s - SEAS) / (s.max() - SEAS) * (HMAX - 1)), 0).astype(int)
    h[:PADN + 1, :PADN + 1] = PADH
    return h, base


def recip(d):
    """Pixels a tile at depth d (8.8 tiles): F256 * 256 / d rounded to the nearest,
    8.8 (landgen's R7L, R7H by depth)."""
    return (F256 * 256 + d // 2) // d


def lerp(a, b, f):
    """a + (b - a) f / 256, rounded half up: the interpolation land.s does by its
    LERPQ7 table (lerp(0, b - a, f) by f a multiple of 16, -15 <= b - a <= 15)."""
    return a + (((b - a) * f + 128) >> 8)


def clip(row):
    """The row's points ((sx, sy, h), x non-decreasing) clipped to x XL..XR: the
    points left of XL all become (XL, y) with y the row's at x = XL (rounded) and
    likewise at XR, so a strip's rungs there are vertical, on the edge, and the
    moved points make zero-length segments (strip.ok allows them)."""
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
    """The ground's height under the ship: at map position (cx + 128, cz + ZSHIP *
    256), on the line of sight ZSHIP tiles ahead, lerped across then down between
    the four corners round it (land.s's hgnd)."""
    x, z = cx + 128, cz + ZSHIP * 256
    xi, xf, zi, zf = x >> 8, x & 255, z >> 8, z & 255
    g = lambda i, j: int(hm[0][j % MAP, i % MAP])
    return lerp(lerp(g(xi, zi), g(xi + 1, zi), xf), lerp(g(xi, zi + 1), g(xi + 1, zi + 1), xf), zf)


def project(hm, cx, cz, e=0):
    """The frame's rows for the camera at (cx, cz), 8.8 tiles, raised e units
    (0..EMAX).  Returns (xs, rows): xs the map x of the 11 drawn columns, xt - 4 ..
    xt + 6; rows, far to near, each (z, points) with z the row's map z and points
    eleven (sx, sy, h), screen x and y and the height.  Box i of the strip between
    two rows is tile (xs[i], the nearer row's z).

    The rows are corner rows j from the far clip's to ZBACK - ZCLIP, 8 of them when
    fz is not 0 and 7 when it is:
      - the last is on the near clip plane: R = recip(ZCLIP * 256) and its heights
        lerped from the corner row before to its own by 1 - fz;
      - when fz is not 0 the first is on the far clip plane: R = recip(ZFCLIP *
        256) and its heights lerped from its own corner row to the next by 1 - fz;
        at fz 0 corner row ZBACK - ZFCLIP is on the plane as it stands;
      - a row's end points are on the x clip planes, -XCLIP and +XCLIP, with
        heights lerped between corners 1 and 2, and 10 and 11, by fx (at fx 0 the
        ends coincide with corners 1 and 10); corners 2..10 lie between.
    Each y is rounded (half up) as the formula above with ey = (e (R >> 5) + 64) >> 7
    (land.s's eyrow) and held at 254 at most; the row is clipped to XL..XR; then the near
    clip's row is held a line or more below the row before it (255 at most) and the
    far clip's row a line or more above the row after it, so those rungs go down
    however the heights are interpolated."""
    xt, zt, fx, fz = cx >> 8, cz >> 8, cx & 255, cz & 255
    xs = [xt - 5 + i for i in range(XSKIP, NX - XSKIP)]
    hg = ground(hm, cx, cz)
    rows = []
    jc = ZBACK - ZCLIP                    # the corner row the near clip plane replaces
    jp = ZBACK - ZFCLIP                   # the corner row on the far clip plane at fz 0
    jf = jp - 1 if fz else jp             # the first row
    for j in range(jf, jc + 1):
        z = zt + ZBACK - j
        r = recip((z << 8) - cz)
        hs = [int(hm[0][z % MAP, x % MAP]) for x in xs]
        if j == jc:
            r = recip(ZCLIP << 8)
            hp = [int(hm[0][(z + 1) % MAP, x % MAP]) for x in xs]
            hs = [lerp(a, b, 256 - fz) for a, b in zip(hp, hs)]
        elif fz and j == jf:
            r = recip(ZFCLIP << 8)
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
            row.append((sx, min(254, sy), h))
        row = clip(row)
        if j == jc:
            row = [(x, min(255, max(y, py + 1)), h)
                   for (x, y, h), (_, py, _) in zip(row, rows[-1][1])]
        if fz and j == jf + 1:
            rows[0] = (rows[0][0], [(x, min(y, ny - 1), h)
                                    for (x, y, h), (_, ny, _) in zip(rows[0][1], row)])
        rows.append((z, row))
    return xs, rows


# The tiles' colours.  Each tile has two 4-bit random picks; TILERND is also the
# MAP byte's high nibble (landgen).  A land tile's colour is the LAND entry nearest
# a target on two axes, each a weighted mean of a pick and the lighting:
#   yellow:  LIGHT  of 1 - its mean height (yellow low, green high), the rest TILERND
#   light:   LIGHTL of how its left corners stand above its right (lit from the
#            left: the mean of its left corners' heights less its right's, in
#            units, dark at +SLOPE1 / 2 and above, light at -SLOPE1 / 2 and below),
#            the rest TILERND2
# both spread evenly by rank over the map's land tiles so the whole palette is used.
# The 6502 sees only the result, bank 5's CMAPE, CMAPO (landgen.build2).
TILERND = np.random.default_rng(12345).integers(0, 16, (MAP, MAP))
TILERND2 = np.random.default_rng(54321).integers(0, 16, (MAP, MAP))
LIGHT = 0.5
LIGHTL = 0.65
SLOPE1 = 6


def _land_axes():
    """Each LAND entry's place on the two axes as ranks 0..1 among them: yellow (its
    mean red over red plus green) and light (its luminance), from its dither's
    average colour."""
    def avg(e):
        cl = SW.cell(*SW.ALL[e])
        return [sum(SW.PHYS[v][ch] for v in cl.values()) / 4 for ch in range(3)]
    ys = [avg(e)[0] / (avg(e)[0] + avg(e)[1] + 1e-9) for e in LAND]
    ls = [0.3 * avg(e)[0] + 0.59 * avg(e)[1] + 0.11 * avg(e)[2] for e in LAND]
    rank = lambda v: [sorted(v).index(x) / (len(v) - 1) for x in v]
    return list(zip(rank(ys), rank(ls)))


LANDAX = _land_axes()


def _targets(hm):
    """{(i, j): (yellow, light)} for every land tile (one with a corner above SEA),
    each axis the weighted mean above, then replaced by its rank among the land
    tiles scaled to 0..1 (ties broken by position)."""
    h, _ = hm
    g = lambda x, z: int(h[z % MAP, x % MAP])
    raw = {}
    for j in range(MAP):
        for i in range(MAP):
            if all(g(i + dx, j + dz) == SEA for dx in (0, 1) for dz in (0, 1)):
                continue
            hs = (g(i, j), g(i + 1, j), g(i, j + 1), g(i + 1, j + 1))
            alt = min(1.0, max(0.0, (sum(hs) / 4 - SEA) / (HMAX - SEA)))
            slope = ((hs[0] + hs[2]) - (hs[1] + hs[3])) / 2
            ty = (1 - LIGHT) * TILERND[j, i] / 15 + LIGHT * (1 - alt)
            tl = (1 - LIGHTL) * TILERND2[j, i] / 15 + LIGHTL * min(1.0, max(0.0, 0.5 - slope / SLOPE1))
            raw[(i, j)] = (ty + 1e-6 * (i + MAP * j), tl + 1e-6 * (j + MAP * i))
    keys = list(raw)
    out = {}
    for ax in (0, 1):
        order = sorted(keys, key=lambda t: raw[t][ax])
        for n, t in enumerate(order):
            out.setdefault(t, [0, 0])[ax] = n / (len(order) - 1)
    return out


_TGT = {}                 # _targets of the last map seen, by id(hm[0])


def colour(hm, i, j, row, nrows):
    """Tile (i, j)'s palette entry (swatch35 numbering), fixed per tile: PADC on the
    landing pad; for a sea tile (all four corners at SEA) the SEAC entry picked by
    TILERND; for a land tile the LAND entry nearest its _targets point in the plane
    of LANDAX.  row and nrows are accepted and ignored."""
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
    """The land strips alone on black: (img, bad, n) with img (H, W) uint8, palette
    entry + 1 by pixel and 0 black; bad the strips failing strip.ok, which are not
    drawn; n the strips.  No sky, ground or margins (frame.py adds those)."""
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
    """img (palette entry + 1 by pixel, 0 black) as the BBC shows it, a PIL image
    scale times larger: each pixel the ink its entry's dither puts at (x & 1, y & 1)
    (MODE 1's pixels are near enough square)."""
    out = np.zeros((P.H, P.W, 3), dtype=np.uint8)
    cells = [None] + [SW.cell(*t) for t in SW.ALL]
    for y in range(P.H):
        for x in range(P.W):
            e = img[y, x]
            if e:
                out[y, x] = SW.PHYS[cells[e][(x & 1, y & 1)]]
    from PIL import Image
    return Image.fromarray(out).resize((P.W * scale, P.H * scale), Image.NEAREST)


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 8
    hm = heightmap()
    cx, cz = 40 << 8, 30 << 8
    bad = 0
    for f in range(frames):
        img, b, n = frame(hm, cx, cz)
        bad += b
        if f < 4:
            render(img).save(os.path.join(P.DIR, f'land_{f:03d}.png'))
        cx += 256 // STEPS * 3
        cz += 256 // STEPS * 5
    print(f'{frames} frames, {bad} strips failing the guarantees')


if __name__ == '__main__':
    main()
