#!/usr/bin/env python3
"""The 32K build's ship, rasterised at run time: the reference model of b32/src/ship32.s.

    python3 b32/tools/ship32.py [OUTDIR]   ->  OUTDIR/ship32.inc, OUTDIR/ships32.png

Lander's ship (ref/lander/ship.py: nine vertices, nine faces) as tools/shipgen.py draws
it -- direction k (32), pitch p (13, PFLAT level), the camera's parallel projection with
slope TANV, S pixels a tile, faces in face order by tri()'s rule, Lander's shading
through RAMPS -- but in the 6502's integer arithmetic, so that ship32.s can do the same
whenever the attitude changes:

  - The model in fixed point: each vertex V = round(4 S v) (quarter pixels), each face
    normal N = round(64 n); the angles' sines and cosines round(64 sin), round(64 cos)
    (pitch a = (p - PFLAT) 10 degrees, direction b = k 11.25 degrees).
  - A point (vertex or normal) pitched: Px = ca X - sa Y, Py = sa X + ca Y (8 x 8 -> 16
    bits), Px8 = (Px + 32) >> 6; then turned: Xr = cb Px8 + sb Z, Zr = cb Z - sb Px8.
  - A vertex's pixel offset from the centre: sx = (Xr + 128) >> 8, sy = (Py - T + 128)
    >> 8, T = (Zr * TQ) >> 8 (TQ = 100: TANV 0.39).
  - A face's normal: shown if -(Py * TQ >> 8) - Zr > 0 (face 8, the exhaust, with face
    7); "negative x" (lit from the left: a brighter shade) if Xr < 0.  Its brightness
    max(0, (4096 - Py) >> 9 + neg - 5) (Lander's, from the pitched normal's y), its
    entry RAMPS[hue][min(15, green + brightness)] (shipgen's).
  - Rasterised as shipgen's tri() (rows ay .. cy - 1, each edge x0 + floor(dx t /
    dy), pixels xl <= x < xr), face after face, later over earlier.

Each line's faces, left to right, and boundaries are what the walker (ship32.s, from
src/shipspan.s) draws; ship32.inc holds the model's data and tables for it.
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
sys.path.insert(0, os.path.join(ROOT, 'tools'))
sys.path.insert(0, os.path.join(ROOT, 'proto'))
sys.path.insert(0, os.path.join(ROOT, 'ref', 'lander'))
import shipgen as SG    # noqa: E402
import ship as SH       # noqa: E402

NDIR, NPITCH, PFLAT, NF = SG.NDIR, SG.NPITCH, SG.PFLAT, SG.NF
S = SG.S
TQ = 100                                     # TANV in 256ths (0.390625)
VQ = [tuple(round(4 * S * c) for c in v) for v in SG.MV]          # quarter pixels
NQ = [tuple(round(64 * c) for c in n) for n in SG.MN[:8]]         # x 64
SINT = [round(64 * math.sin(2 * math.pi * k / NDIR)) for k in range(NDIR)]
PSIN = [round(64 * math.sin(SG.pitch(p))) for p in range(NPITCH)]
PCOS = [round(64 * math.cos(SG.pitch(p))) for p in range(NPITCH)]
assert all(abs(c) <= 127 for v in VQ for c in v)


def turn(p, k, X, Y, Z):
    """(Xr, Py, Zr) for a point (X, Y, Z) at pitch p, direction k."""
    ca, sa = PCOS[p], PSIN[p]
    sb, cb = SINT[k], SINT[(k + NDIR // 4) % NDIR]
    px = ca * X - sa * Y
    py = sa * X + ca * Y
    px8 = (px + 32) >> 6
    return cb * px8 + sb * Z, py, cb * Z - sb * px8


def orient(k, p):
    """(pts, faces): the nine vertices' (sx, sy) and the faces drawn, in order, as (f,
    swatch35 entry)."""
    pts = []
    for X, Y, Z in VQ:
        xr, py, zr = turn(p, k, X, Y, Z)
        pts.append(((xr + 128) >> 8, (py - ((zr * TQ) >> 8) + 128) >> 8))
    vis, neg, ny = [], [], []
    for X, Y, Z in NQ:
        xr, py, zr = turn(p, k, X, Y, Z)
        vis.append(-((py * TQ) >> 8) - zr > 0)
        neg.append(xr < 0)
        ny.append(py)
    faces = []
    for f in range(NF):
        g = 7 if f == 8 else f
        if vis[g]:
            br = max(0, ((4096 - ny[g]) >> 9) + neg[g] - 5)
            col = SH.FACES[f]['colour']
            faces.append((f, SG.RAMPS[SG.HUE[col]][min(15, (col >> 4 & 15) + br)]))
    return pts, faces


def lines(k, p):
    """The ship's lines: [(dy, bounds, faces)] top to bottom, dy the line's offset from
    the centre, bounds its boundaries (offsets from the centre: the first pixel, each
    change of face, one past the last), faces its faces left to right (face numbers)."""
    pts, faces = orient(k, p)
    rows = {}
    for f, _ in faces:
        (ax, ay), (bx, by), (cx, cy) = sorted((pts[v] for v in SG.FACEV[f]), key=lambda t: t[1])
        if ay == cy:
            continue
        xs = lambda x0, y0, x1, y1, y: x0 + ((x1 - x0) * (y - y0)) // (y1 - y0)
        for y in range(ay, cy):
            xa = xs(ax, ay, cx, cy, y)
            xb = xs(ax, ay, bx, by, y) if y < by else xs(bx, by, cx, cy, y)
            row = rows.setdefault(y, {})
            for x in range(min(xa, xb), max(xa, xb)):
                row[x] = f
    out = []
    for y in sorted(rows):
        r = rows[y]
        if not r:
            continue
        xs = sorted(r)
        b, fs = [], []
        for x in range(xs[0], xs[-1] + 1):
            if x not in r:
                raise ValueError(f'k {k} p {p}: a gap in line {y}')
            if x == xs[0] or r[x] != r[x - 1]:
                b.append(x)
                fs.append(r[x])
        b.append(xs[-1] + 1)
        out.append((y, b, tuple(fs)))
    return out


def check():
    """Every orientation: no gaps, consecutive lines, at most 6 faces a line, the
    walker's buffer under 256 bytes (2 a band + 8 a line + 1).  Returns the worst
    figures."""
    worst = dict(faces=0, buf=0, lines=0, bands=0)
    for p in range(NPITCH):
        for k in range(NDIR):
            ls = lines(k, p)
            assert all(ls[i + 1][0] == ls[i][0] + 1 for i in range(len(ls) - 1)), (k, p)
            bands = 1 + sum(ls[i + 1][2] != ls[i][2] for i in range(len(ls) - 1))
            worst['faces'] = max(worst['faces'], max(len(f) for _, _, f in ls))
            worst['buf'] = max(worst['buf'], 2 * bands + 8 * len(ls) + 1)
            worst['lines'] = max(worst['lines'], len(ls))
            worst['bands'] = max(worst['bands'], bands)
    return worst


def sheet(path):
    """Every orientation drawn, 32 across by 13 down, against shipgen's (left half of
    each cell: shipgen's, right: this model's)."""
    import numpy as np
    from PIL import Image
    cw = 84
    img = np.zeros((NPITCH * 44, NDIR * cw, 3), np.uint8)
    for p in range(NPITCH):
        for k in range(NDIR):
            a = np.zeros((44, 44), np.int16)
            SG.draw(a, k, p, 22, 22)
            _, faces = orient(k, p)
            pal = dict(faces)
            b = np.zeros((44, 44), np.int16)
            for y, bd, fs in lines(k, p):
                for i, f in enumerate(fs):
                    b[22 + y, 22 + bd[i]:22 + bd[i + 1]] = pal[f] + 1
            for off, m in ((0, a), (42, b)):
                for y in range(44):
                    for x in range(42):
                        e = m[y, x]
                        if e:
                            img[p * 44 + y, k * cw + off + x] = SG.SW.PHYS[SG.SW.cell(*SG.SW.ALL[e - 1])[(x & 1, y & 1)]]
    Image.fromarray(img).resize((img.shape[1] * 2, img.shape[0] * 2), Image.NEAREST).save(path)


def inc(path):
    """ship32.inc: the model and the walker's tables, ca65 data.
      VQX, VQY, VQZ + i  point i: vertices 0..8 (quarter pixels), then the faces' normals
                         (x 64), 9..16
      SINT + k           round(64 sin(k 11.25 degrees)), k 0..31
      PSIN, PCOS + p     the pitches' sines and cosines, x 64
      FV0, FV1, FV2 + f  face f's vertices
      FHUE, FGRN + f     its colour's ramp x 16 (0, 16, 32: RAMPE's rows) and green nibble
      RAMPE, RAMPO + 16 h + i   ramp h's entry i: its dither's even, odd line bytes
      KTN, BYN, LIM + w  shipspan.s's: for a boundary at w (0..47) the mask of its
                         byte's pixels before it, its byte's offset (8 (w >> 2)), the
                         byte after's first pixel"""
    import landgen as LG
    hues = ['purple', 'grey', 'orange']
    rows = []
    def emit(name, vals):
        rows.append(f'{name}:')
        for i in range(0, len(vals), 16):
            rows.append('        .byte ' + ', '.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    pts = VQ + NQ
    for c, nm in enumerate(('VQX', 'VQY', 'VQZ')):
        emit(nm, [v[c] for v in pts])
    emit('SINT', SINT)
    emit('PSIN', PSIN)
    emit('PCOS', PCOS)
    for c in range(3):
        emit(f'FV{c}', [SG.FACEV[f][c] for f in range(NF)])
    emit('FHUE', [16 * hues.index(SG.HUE[SH.FACES[f]['colour']]) for f in range(NF)])
    emit('FGRN', [SH.FACES[f]['colour'] >> 4 & 15 for f in range(NF)])
    db = [LG.dither_bytes(SG.RAMPS[h][i]) for h in hues for i in range(16)]
    emit('RAMPE', [d[0] for d in db])
    emit('RAMPO', [d[1] for d in db])
    rows.append(f'SHIP_TQ = {TQ}')
    open(path, 'w').write('; b32/tools/ship32.py\n' + '\n'.join(rows) + '\n')


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build32')
    os.makedirs(out, exist_ok=True)
    inc(os.path.join(out, 'ship32.inc'))
    if '--check' in sys.argv:
        print(check())
        sheet(os.path.join(out, 'ships32.png'))
