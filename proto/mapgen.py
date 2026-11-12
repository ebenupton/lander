#!/usr/bin/env python3
"""The builds' 64-tile map, made a corner and a tile at a time from integer tables
(land.py uses it when LAND_GEN=1, which tools/gen.py and test/soak.py set).  The 32K
build makes it as it comes into view (src/mapgen.s computes the same, from gen.py's
mapgen.inc); the sideways RAM build stores it whole (gen.py's banks 4 and 5).  It
follows land.py's own map (Lander's six sines, the rank-spread colours) as
closely as tables a few hundred bytes long allow:

  - a corner's height: S = the six sines' sum from SIN16 (256 sin, 64 entries: every
    term's frequency is whole cycles a wrap, so its phase is (p x + q z) & 63), then
    h = 0 under the sea threshold, else 1 + the height thresholds HT16 it reaches
    (the float formula's rounding, tabulated over every S); the pad flat at PADH;
  - a tile's colour from its four corners: the pad PADC; the sea (all four at SEA)
    SEAC[R1 & 3]; land the LAND entry LUT[qy][ql], qy and ql the tile's places
    among 8 quantiles (YQ, LQ: this map's) of the two axes land.py ranks it on,
        TY = 4 R1 + 60 - the corners' sum                (yellow: lower, yellower)
        TL = 3 R2 + 7 clamp(6 - slope2, 0, 12)           (light: lit from the left)
    (slope2 = the left corners' sum less the right's), land.py's ty exactly (/ 15) and
    tl nearly (/ 28), as bytes; R1, R2 = the low and high nibbles of RA[(i + RA[j]) &
    63], one 64-byte random table in place of land.py's 64 x 64 TILERND, TILERND2.

    python3 proto/mapgen.py     writes proto/mapgen.png: land.py's map (left) and
                                this one (right), and prints how many corners and
                                tiles differ
"""
import math
import os

import numpy as np

MAP = 64
TERMS = [(2, 1, -2), (2, 4, 3), (2, -5, 3), (2, 7, 5), (1, 5, 11), (1, 10, 7)]   # (k, p, q)
SIN16 = [min(255, round(256 * math.sin(2 * math.pi * i / MAP))) for i in range(MAP)]
# (held at 255: SIN16 + 256 is then 0..511, its high bit set exactly for i <= 32)
assert all((SIN16[i] + 256 >= 256) == (i <= 32) and 0 <= SIN16[i] + 256 < 512 for i in range(MAP))
SEAS = -10 / 12
HMAX = 15
SEA = 0
PADN, PADH = 6, 4


def ssum(x, z):
    return sum(k * SIN16[(p * x + q * z) & (MAP - 1)] for k, p, q in TERMS)


SMAX = max(ssum(x, z) for z in range(MAP) for x in range(MAP))
SMIN = -sum(256 * k for k, _, _ in TERMS)


def _hfloat(s):
    """land.py's quantisation of a sum (s / 256), with this map's greatest."""
    v = s / 256
    if v < SEAS:
        return 0
    return int(1 + np.round((v - SEAS) / (SMAX / 256 - SEAS) * (HMAX - 1)))


# HT16[k]: the least sum with height k + 1 or more (k 0..HMAX-1; HT16[0] the sea's)
HT16 = [min(s for s in range(SMIN, SMAX + 1) if _hfloat(s) > k) for k in range(HMAX)]
assert all(1 + sum(s >= t for t in HT16[1:]) == _hfloat(s) for s in range(HT16[0], SMAX + 1))


def height(x, z):
    x &= MAP - 1
    z &= MAP - 1
    if x <= PADN and z <= PADN:
        return PADH
    s = ssum(x, z)
    if s < HT16[0]:
        return 0
    return 1 + sum(s >= t for t in HT16[1:])


_rng = np.random.default_rng(6502)
# RA: each nibble value 4 times in each half, shuffled apart (a map row reads all 64
# entries once, so its R1 and R2 are evenly spread); row j's offset into it RA[j] & 63
RA = [int(lo) | int(hi) << 4 for lo, hi in zip(_rng.permutation(list(range(16)) * 4),
                                                 _rng.permutation(list(range(16)) * 4))]


def rnd(i, j):
    """(R1, R2) for tile (i, j)."""
    r = RA[(i + RA[j & (MAP - 1)]) & (MAP - 1)]
    return r & 15, r >> 4


def axes(i, j):
    """(land, TY, TL, R1) for tile (i, j)."""
    hs = (height(i, j), height(i + 1, j), height(i, j + 1), height(i + 1, j + 1))
    r1, r2 = rnd(i, j)
    land = any(h != SEA for h in hs)
    sumh = sum(hs)
    slope2 = (hs[0] + hs[2]) - (hs[1] + hs[3])
    ty = 4 * r1 + 60 - sumh                                  # (0..120)
    tl = 3 * r2 + 7 * min(12, max(0, 6 - slope2))            # (0..129)
    return land, ty, tl, r1


def arc_tile(i, j):
    """(kind, slope) of tile (i, j) for the arc build (proto/nula.py: Lander's colours
    by kind and brightness): the pad (4) on the landing pad, the sea (5) if the corners
    (i, j) and (i + 1, j) are both at SEA, else a land kind 0..3 (Lander's altitude
    bits 2 and 3: here those of the sum + 2560 at the corner (i + 1, j), pad or not) and
    the slope: how far the corner (i + 1, j) stands above (i, j), in thirds, held at 2."""
    i &= MAP - 1
    j &= MAP - 1
    if i < PADN and j < PADN:
        return 4, 0
    hp, hc = height(i, j), height(i + 1, j)
    if hp == SEA and hc == SEA:
        return 5, 0
    d = hc - hp
    return (ssum((i + 1) & (MAP - 1), j) + 2560 >> 2) & 3, 0 if d < 3 else 1 if d < 6 else 2


def _quantiles():
    ys, ls = [], []
    for j in range(MAP):
        for i in range(MAP):
            if i % MAP < PADN and j % MAP < PADN:
                continue
            land, ty, tl, _ = axes(i, j)
            if land:
                ys.append(ty)
                ls.append(tl)
    ys.sort()
    ls.sort()
    n = len(ys)
    # q-th boundary: the value at rank q n / 8 (q 1..7): qy = how many it reaches
    return [ys[q * n // 8] for q in range(1, 8)], [ls[q * n // 8] for q in range(1, 8)]


YQ, LQ = _quantiles()


def _lut():
    import land as L
    out = []
    for qy in range(8):
        row = []
        for ql in range(8):
            ty, tl = (qy + 0.5) / 8, (ql + 0.5) / 8
            k = min(range(len(L.LAND)), key=lambda n: (L.LANDAX[n][0] - ty) ** 2 + (L.LANDAX[n][1] - tl) ** 2)
            row.append(L.LAND[k])
        out.append(row)
    return out


_LUT = None


def colour(i, j):
    global _LUT
    import land as L
    if _LUT is None:
        _LUT = _lut()
    i &= MAP - 1
    j &= MAP - 1
    if i < PADN and j < PADN:
        return L.PADC
    land, ty, tl, r1 = axes(i, j)
    if not land:
        return L.SEAC[(r1 & 3) % len(L.SEAC)]    # (NULA's three seas: r1 & 3 = 3 as 0)
    qy = sum(ty >= t for t in YQ)
    ql = sum(tl >= t for t in LQ)
    return _LUT[qy][ql]


def heightmap():
    """land.heightmap's (h, base) from this generator (base unused: zeros)."""
    h = np.array([[height(x, z) for x in range(MAP)] for z in range(MAP)], dtype=int)
    return h, np.zeros((MAP, MAP), dtype=int)


def main():
    import sys
    sys.path.insert(0, os.path.dirname(__file__))
    os.environ.pop('LAND_GEN', None)
    import land as L
    import swatch35 as SW
    from PIL import Image
    hm = L.heightmap()
    h0 = hm[0]
    h1 = heightmap()[0]
    dh = int((h0 != h1).sum())
    cells = [SW.cell(*t) for t in SW.ALL]
    img = np.zeros((MAP * 4, MAP * 8 + 8, 3), dtype=np.uint8)
    dc = 0
    for j in range(MAP):
        for i in range(MAP):
            a = L.colour(hm, i, j, 0, 0)
            b = colour(i, j)
            dc += a != b
            for side, e in ((0, a), (1, b)):
                for yy in range(4):
                    for xx in range(4):
                        img[(MAP - 1 - j) * 4 + yy, side * (MAP * 4 + 8) + i * 4 + xx] = \
                            SW.PHYS[cells[e][(xx & 1, yy & 1)]]
    Image.fromarray(img).resize((img.shape[1] * 2, img.shape[0] * 2), Image.NEAREST).save(
        os.path.join(os.path.dirname(__file__), 'mapgen.png'))
    print(f'corners differing {dh} of {MAP * MAP}; tiles differing in colour {dc}')
    print(f'SMAX {SMAX}; HT16 {HT16}')
    print(f'YQ {YQ}\nLQ {LQ}')


if __name__ == '__main__':
    main()
