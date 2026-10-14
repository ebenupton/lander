#!/usr/bin/env python3
"""The ship's tables: Lander's ship (ref/lander/ship.py) pre-rotated and pre-projected for
every orientation the BBC draws, plus the reference rasteriser the 6502 must match.

    python3 tools/shipgen.py OUTDIR   -> OUTDIR/ship.inc (ca65 data), OUTDIR/ships.png

Orientation: Lander's (pitch a, direction b) (ref/lander/NOTES.md 2.1).  a in NPITCH steps
of 90/NPITCH degrees from 0 (the ship never goes upside down: a < 90), b in NDIR steps
round the circle.  The camera never yaws, so the ship at (a, 180 - b) is the ship at
(a, b) mirrored left to right (the model is symmetric in its z): only b in -90..90 is
stored (NDIR/2 + 1 directions), the rest drawn mirrored.

Projection: the ship sits at a fixed depth below the camera (which looks along +z,
level, as the landscape's does), so to first order a model offset (x, y, z) (y down)
lands at
    sx = S * x            sy = S * (y - TANV * z)
S pixels a tile, TANV the slope down from the camera to the ship: a parallel projection
along v = (0, -TANV, -1) (towards the camera).  A face shows when its rotated normal n
has n . v > 0.  Its shade is Lander's (ship.lander_brightness: from n's y, +1 if n's x
< 0; light from above and the left), its colour + shade a step on a ramp of swatch35's
dithers for its hue (RAMPS).  Mirrored, n's x changes sign: the "n's x < 0" bits are inverted.

The tables (entry e = p * ND2 + kk, kk the stored direction 0..ND2-1 for b = (kk - NDIR/4)
steps, p the pitch):
  SVXi, SVYi + e     vertex i's offset from the ship's centre, pixels (signed)
  SVIS + e           faces 0-7 that show (bit f); the exhaust (face 8) shows with face 7
  SNEG + e           faces 0-7 whose rotated normal's x < 0 (face 8: face 7's)
  SHD + (p*9 + f)*2 + neg   face f's palette entry (swatch35's numbering)
  KMAP, KMIR + k     direction k (0..NDIR-1): its stored kk, and 0 or $FF if mirrored
  FVA, FVB, FVC + f  face f's vertices
  SDE, SDO + entry   a palette entry's dither bytes (even, odd lines)

The rasteriser (tri(), as ship.s does it): the triangle's corners sorted by y (a top,
b, c bottom); lines a.y .. c.y - 1; on each, the long edge's x (a to c) and the short
edge's (a to b above b.y, b to c from it), each x0 + floor(dx * t / dy) at t lines down
from its upper end (Bresenham: q = floor(dx / dy), r = dx - q dy); pixels xl <= x < xr
between them.  Edges shared by two faces then split their pixels exactly.
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'proto'))
sys.path.insert(0, os.path.join(HERE, '..', 'ref', 'lander'))
import swatch35 as SW   # noqa: E402
import ship as SH       # noqa: E402
import landgen as G     # noqa: E402

NDIR = 32                  # directions round the circle
NPITCH = 8                 # pitches 0 .. 90 - 90/NPITCH degrees
ND2 = NDIR // 2 + 1        # stored directions: -90 .. 90
NE = ND2 * NPITCH          # entries
S = 14.0                   # pixels a tile (Lander's ship on its screen, scaled to 256 wide)
TANV = 0.5                 # the camera's slope down to the ship
NV, NF = 9, 9

FACEV = [f['verts'] for f in SH.FACES]
MV = [tuple(c / SH.TILE for c in v) for v in SH.VERTICES]
MN = [tuple(c / SH.ONE for c in f['normal']) for f in SH.FACES]


def rnd(v):
    return int(math.floor(v + 0.5))


def avg_rgb(i):
    cl = SW.cell(*SW.ALL[i])
    return [sum(SW.PHYS[v][ch] for v in cl.values()) / 4 for ch in range(3)]


AVG = [avg_rgb(i) for i in range(len(SW.ALL))]


def nearest(rgb):
    return min(range(len(SW.ALL)), key=lambda i: sum((a - b) ** 2 for a, b in zip(AVG[i], rgb)))


def angles(kk, p):
    return p * math.pi / 2 / NPITCH, (kk - NDIR // 4) * 2 * math.pi / NDIR


def entry(kk, p):
    """(vertex offsets [(dx, dy)], visible mask, neg mask) of stored entry (kk, p)."""
    a, b = angles(kk, p)
    m = SH.rotation_matrix(a, b)
    pts = []
    for v in MV:
        x, y, z = SH.mat_vec(m, v)
        pts.append((rnd(S * x), rnd(S * (y - TANV * z))))
    vis = neg = 0
    for f in range(8):
        nx, ny, nz = SH.mat_vec(m, MN[f])
        if -TANV * ny - nz > 1e-9:
            vis |= 1 << f
        if nx < -1e-9:
            neg |= 1 << f
    return pts, vis, neg


# Lander's colours + brightness, through the four inks' dithers: nearest-colour picks
# lose the facets (the top's greens all land on one dither), so each of the ship's
# three hues has a ramp of dithers, dark to light, indexed by the green channel Lander
# would show (its colour's green + the brightness, to 15).
RAMPS = {'green': [26] * 8 + [16] * 3 + [18] * 2 + [3] * 2 + [6],
         'cyan': [34] * 4 + [31] * 3 + [25] * 3 + [15] * 3 + [0] * 3,
         'orange': [22] * 10 + [11] * 6}
HUE = {0x080: 'green', 0x040: 'green', 0x088: 'cyan', 0x044: 'cyan', 0xC80: 'orange'}


def shade(p, f, ng):
    """Face f's palette entry at pitch p, its rotated normal's x negative or not."""
    a = p * math.pi / 2 / NPITCH
    ny = math.sin(a) * MN[f][0] + math.cos(a) * MN[f][1]       # (the matrix's y row)
    br = SH.lander_brightness(-1 if ng else 1, int(ny * SH.ONE))
    col = SH.FACES[f]['colour']
    return RAMPS[HUE[col]][min(15, (col >> 4 & 15) + br)]


ENT = {(kk, p): entry(kk, p) for p in range(NPITCH) for kk in range(ND2)}
SHD = [[[shade(p, f, ng) for ng in range(2)] for f in range(NF)] for p in range(NPITCH)]


def kmap(k):
    """Direction k: (stored kk, mirrored)."""
    kk = (k + NDIR // 4) % NDIR
    if kk < ND2:
        return kk, False
    return (NDIR // 2 - k + NDIR // 4) % NDIR, True


def orient(k, p):
    """Direction k (0..NDIR-1), pitch p: the vertex offsets and the faces to draw, in
    order, with their palette entries -- as the 6502 reads the tables."""
    kk, mir = kmap(k)
    pts, vis, neg = ENT[(kk, p)]
    if mir:
        pts = [(-x, y) for x, y in pts]
        neg ^= 0xFF
    faces = []
    for f in range(NF):
        bit = 7 if f == 8 else f
        if vis >> bit & 1:
            faces.append((f, SHD[p][f][neg >> bit & 1]))
    return pts, faces


def tri(img, pts, val):
    """Fill the triangle (three (x, y)) with val in img[y, x], as ship.s does."""
    (ax, ay), (bx, by), (cx, cy) = sorted(pts, key=lambda t: t[1])
    if ay == cy:
        return
    def xs(x0, y0, x1, y1, y):
        return x0 + ((x1 - x0) * (y - y0)) // (y1 - y0)
    for y in range(ay, cy):
        xa = xs(ax, ay, cx, cy, y)
        xb = xs(ax, ay, bx, by, y) if y < by else xs(bx, by, cx, cy, y)
        xl, xr = min(xa, xb), max(xa, xb)
        img[y, xl:xr] = val


def draw(img, k, p, cx, cy):
    """The ship, direction k, pitch p, centred at (cx, cy): img gets palette entry + 1."""
    pts, faces = orient(k, p)
    for f, pal in faces:
        tri(img, [(cx + pts[v][0], cy + pts[v][1]) for v in FACEV[f]], pal + 1)


def asm(out):
    L = ['; ship.inc: from tools/shipgen.py -- do not edit',
         f'SHIP_NDIR = {NDIR}', f'SHIP_NPITCH = {NPITCH}', f'SHIP_ND2 = {ND2}', f'SHIP_NE = {NE}']
    def tab(name, vals):
        L.append(f'{name}:')
        for i in range(0, len(vals), 16):
            L.append('        .byte ' + ', '.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    es = [ENT[(kk, p)] for p in range(NPITCH) for kk in range(ND2)]
    for i in range(NV):
        tab(f'SVX{i}', [e[0][i][0] for e in es])
    for i in range(NV):
        tab(f'SVY{i}', [e[0][i][1] for e in es])
    tab('SVIS', [e[1] for e in es])
    tab('SNEG', [e[2] for e in es])
    tab('SHD', [SHD[p][f][n] for p in range(NPITCH) for f in range(NF) for n in range(2)])
    tab('KMAP', [kmap(k)[0] for k in range(NDIR)])
    tab('KMIR', [0xFF if kmap(k)[1] else 0 for k in range(NDIR)])
    tab('FVA', [f[0] for f in FACEV])
    tab('FVB', [f[1] for f in FACEV])
    tab('FVC', [f[2] for f in FACEV])
    db = [G.dither_bytes(e) for e in range(len(SW.ALL))]
    tab('SDE', [d[0] for d in db])
    tab('SDO', [d[1] for d in db])
    open(os.path.join(out, 'ship.inc'), 'w').write('\n'.join(L) + '\n')


def sheet(path, scale=3):
    """Every orientation, drawn by the reference rasteriser (dithered as the BBC shows)."""
    from PIL import Image
    cw, ch = 64, 56
    img = np.zeros((ch * NPITCH, cw * NDIR // 2), dtype=np.uint8)
    big = np.zeros((ch * NPITCH * 2, cw * NDIR // 2), dtype=np.uint8)
    for p in range(NPITCH):
        for k in range(NDIR):
            r, c = p + NPITCH * (k // (NDIR // 2)), k % (NDIR // 2)
            draw(big, k, p, c * cw + cw // 2, r * ch + ch // 2)
    cells = [None] + [SW.cell(*t) for t in SW.ALL]
    out = np.full(big.shape + (3,), 40, dtype=np.uint8)
    for y in range(big.shape[0]):
        for x in range(big.shape[1]):
            e = big[y, x]
            if e:
                out[y, x] = SW.PHYS[cells[e][(x & 1, y & 1)]]
    Image.fromarray(out).resize((out.shape[1] * scale, out.shape[0] * scale), Image.NEAREST).save(path)


def stats():
    w = max(max(abs(x) for x, _ in e[0]) for e in ENT.values())
    h = max(max(abs(y) for _, y in e[0]) for e in ENT.values())
    nf = max(bin(e[1]).count('1') for e in ENT.values())
    return f'{NE} entries ({NDIR * NPITCH} orientations by mirroring), |dx| <= {w}, |dy| <= {h}, <= {nf}(+1) faces'


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    asm(out)
    print(stats())
    if '--sheet' in sys.argv:
        sheet(os.path.join(out, 'ships.png'))
