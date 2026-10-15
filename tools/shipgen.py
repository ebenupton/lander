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
import functools
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
S = 14.0                   # pixels a tile (Lander's ship on its screen, scaled to 256 wide;
                           # kept as ZSHIP went 15 -> 13: its world size S / R(ZSHIP), 13/15
                           # what it was)
TANV = 0.39                # the camera's slope down to the ship: in play shy/256 (shy the
                           # ship's line, HORIZON 0, F 256), 0.38 flying (shy 97, the
                           # camera following) to 0.45 at touchdown (116); 0.39 the
                           # least-squares fit over sampled flight (mean 0.391)
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
# lose the facets (the top's greens all land on one dither) and the landscape uses
# every green, so each of the ship's three hues has a ramp of dithers the land and sea
# never use (proto/land.py's LAND, SEAC), dark to light, indexed by the green channel
# Lander would show (its colour's green + the brightness, to 15): its top and back the two
# purples, its underside greys, its exhaust pink.
RAMPS = {'purple': [20] * 13 + [9] * 3,
         'grey': [19] * 8 + [8] * 3 + [4] * 2 + [7] * 3,
         'orange': [13] * 10 + [12] * 6}
HUE = {0x080: 'purple', 0x040: 'purple', 0x088: 'grey', 0x044: 'grey', 0xC80: 'orange'}


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


def canvas(kk, p):
    """Stored entry (kk, p) drawn unmirrored by tri() centred at (C, C) of a 2C square:
    each pixel its face + 1 (0 none; later faces over earlier: the exhaust over 7)."""
    pts, vis, _ = ENT[(kk, p)]
    img = np.zeros((2 * C, 2 * C), dtype=np.int16)
    for f in range(NF):
        if vis >> (7 if f == 8 else f) & 1:
            tri(img, [(C + pts[v][0], C + pts[v][1]) for v in FACEV[f]], f + 1)
    return img


C = 40


def draw(img, k, p, cx, cy):
    """The ship, direction k, pitch p, centred at (cx, cy): img gets palette entry + 1.
    The stored entry's faces by tri(), in order; a mirrored direction is the stored
    one's pixel mirror image about the centre (pixel cx + d to cx - d), its shades
    as the mirrored normals'."""
    kk, mir = kmap(k)
    _, faces = orient(k, p)
    pal = dict(faces)
    can = canvas(kk, p)
    ys, xs = np.nonzero(can)
    for y, x in zip(ys, xs):
        d = x - C
        img[cy + y - C, cx - d if mir else cx + d] = pal[can[y, x] - 1] + 1


def spans():
    """Each stored entry's lines (canvas()), as LAND's bank 6 draws them: [(dy, bounds,
    faces)]: the line's boundaries (pixel offsets from the centre: the first pixel,
    each change of face, one past the last) and its faces left to right."""
    out = {}
    for p in range(NPITCH):
        for kk in range(ND2):
            can = canvas(kk, p)
            ls = []
            for y in range(2 * C):
                r = can[y]
                xs = np.nonzero(r)[0]
                if not len(xs):
                    continue
                assert xs[-1] - xs[0] + 1 == len(xs)
                b, fs = [], []
                for x in range(xs[0], xs[-1] + 1):
                    if x == xs[0] or r[x] != r[x - 1]:
                        b.append(x - C)
                        fs.append(int(r[x]) - 1)
                b.append(xs[-1] + 1 - C)
                ls.append((y - C, b, tuple(fs)))
            assert all(ls[i + 1][0] == ls[i][0] + 1 for i in range(len(ls) - 1))
            out[(kk, p)] = ls
    return out


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


def scs(a, b):
    """A shortest common supersequence of face sequences a and b."""
    @functools.lru_cache(None)
    def f(i, j):
        if i == len(a):
            return b[j:]
        if j == len(b):
            return a[i:]
        if a[i] == b[j]:
            return (a[i],) + f(i + 1, j + 1)
        x, y = (a[i],) + f(i + 1, j), (b[j],) + f(i, j + 1)
        return x if len(x) <= len(y) else y
    return f(0, 0)


def embed(fs, bd, pat):
    """A line's boundaries bd (faces fs) for pattern pat (a supersequence of fs): the
    faces it lacks there with no pixels."""
    out, i = [bd[0]], 0
    for f in pat:
        if i < len(fs) and fs[i] == f:
            i += 1
        out.append(bd[i])
    assert i == len(fs)
    return out


BANDC, SEGC, BYTEC = 230, 26, 20


def groups(ls):
    """An entry's lines (spans()) in bands: [(pattern, [each line's boundaries])], the
    patterns supersequences of their lines' faces (no more than 6), chosen for the
    least cost (BANDC a band, SEGC a face a line, BYTEC a byte)."""
    m = len(ls)
    best, ch = [0] + [1e18] * m, [None] * (m + 1)
    for j in range(1, m + 1):
        pat = ()
        for i in range(j - 1, -1, -1):
            pat = scs(pat, ls[i][2]) if pat else ls[i][2]
            if len(pat) > 6:
                break
            c = best[i] + BANDC + (j - i) * len(pat) * SEGC + BYTEC * (1 + (j - i) * (len(pat) + 1))
            if c < best[j]:
                best[j], ch[j] = c, (i, pat)
    out, j = [], m
    while j:
        i, pat = ch[j]
        out.append((pat, [embed(l[2], l[1], pat) for l in ls[i:j]]))
        j = i
    return out[::-1]


U0 = 20                    # a boundary's byte in bank 6's lines: its offset + U0


def asm6(out):
    """shipspan.inc: LAND's bank 6 ship (src/shipspan.s): each stored entry's lines
    (spans()), in bands of lines with the same faces left to right.
      SPATN, SPATO + P   pattern P's faces: how many, where in SPATF (SPATON:
                         where + how many)
      SPATF              the patterns' faces, left to right
      BANDP, BANDL + B   band B's pattern, lines
      ELO, EHI + e       entry e's bands: per band B, then its lines' boundaries
                         + U0 (alternate lines from the last's back, then the
                         others); $FF after the last; $FE: the rest from the next
                         page
      EYS + e            its first and last lines (offsets from the centre): 14 +
                         the first's | (the last's - 5) << 4
      EXB + e            its leftmost and rightmost pixels (offsets): 17 + the
                         leftmost's | (the rightmost's - 4) << 4
      SHDE, SHDO + (p*9 + f)*2 + neg   face f's dither bytes (as SHD's entry)"""
    sp = spans()
    pats, bands, blobs = [], [], []
    for p in range(NPITCH):
        for kk in range(ND2):
            b = []                         # its bands: [B, lines...]
            for fs, ls in groups(sp[(kk, p)]):
                if fs not in pats:
                    pats.append(fs)
                bd = (pats.index(fs), len(ls))
                if bd not in bands:
                    bands.append(bd)
                nl = len(ls)                   # (in two passes, alternate lines: the
                o = list(range(nl % 2 ^ 1, nl, 2)) + list(range(nl % 2, nl, 2))  # last's first)
                b.append([bands.index(bd)] + [x + U0 for i in o for x in ls[i]])
            blobs.append(b)
    # Pages filled in turn: whole entries (largest that fits), then the first bands
    # of one (the most that fit) and $FE (the rest from the next page's start).
    # The first page: the boundaries' tables (src/shipspan.s), by u + al (normal) or
    # u - al (mirrored, the R tables): pixel w = u + al or 41 + al - u from the column
    # 5 left of shx's: KT the pixels before w's in its byte, BY its byte's offset.
    LM = [0, 0x88, 0xCC, 0xEE]
    utab = {'KTR': [LM[(41 - k) & 3] for k in range(39)],
            'BYR': [((41 - k) >> 2) * 8 for k in range(39)],
            'KTN': [LM[i & 3] for i in range(42)],
            'BYN': [(i >> 2) * 8 for i in range(42)]}
    first, uoff = [0] * 3, {}
    for name, v in utab.items():
        uoff[name] = len(first)
        first += v
    data, where, left, cont = [], {}, set(range(len(blobs))), None
    while left or cont:
        page = list(first) if not data else []
        if cont is not None:
            e, bs = cont
            page += [x for bd in bs for x in bd] + [0xFF]
            cont = None
        while True:
            free = 256 - len(page)
            fit = [e for e in left if sum(map(len, blobs[e])) + 1 <= free]
            if not fit:
                break
            e = max(fit, key=lambda e: sum(map(len, blobs[e])))
            where[e] = len(data) + len(page)
            page += [x for bd in blobs[e] for x in bd] + [0xFF]
            left.discard(e)
        free = 256 - len(page)
        best = None
        for e in left:
            n = 0
            for i, bd in enumerate(blobs[e][:-1]):
                n += len(bd)
                if n + 1 <= free and (best is None or n > best[0]):
                    best = (n, e, i + 1)
        if best is not None:
            n, e, i = best
            where[e] = len(data) + len(page)
            page += [x for bd in blobs[e][:i] for x in bd] + [0xFE]
            left.discard(e)
            cont = (e, blobs[e][i:])
        data += page + [0] * (256 - len(page)) if (left or cont) else page
    for e in where:
        assert data[where[e]] < 0xFE
    L = ['; shipspan.inc: from tools/shipgen.py -- do not edit',
         f'SHIP_NDIR = {NDIR}', f'SHIP_NPITCH = {NPITCH}', f'SHIP_ND2 = {ND2}', f'SHIP_NE = {NE}',
         f'SHIP_U0 = {U0}', f'SHIP_NPAT = {len(pats)}',
         f'SHIP_MAXN = {max(len(f) for f in pats)}', f'SHIP_NBAND = {len(bands)}']
    assert len(bands) < 255
    def tab(name, vals):
        L.append(f'{name}:')
        for i in range(0, len(vals), 16):
            L.append('        .byte ' + ', '.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    tab('BANDL', [n for _, n in bands])
    # LIM + 36 * (al + 4 * mirrored) + u - 3: the least u in the next byte (normal),
    # or in u's byte (mirrored: w = 41 + al - u)
    tab('LIM', [((u + a) // 4 + 1) * 4 - a for a in range(4) for u in range(3, 39)] +
        [max(0, a + 38 - 4 * ((41 + a - u) // 4)) for a in range(4) for u in range(3, 39)])
    L.append('        .segment "TAIL"')
    tab('BANDP', [p for p, _ in bands])
    L.append('        .code')
    tab('SPATN', [len(f) for f in pats])
    o, po = 0, []
    for f in pats:
        po.append(o)
        o += len(f)
    tab('SPATO', po)
    tab('SPATON', [o + len(f) for o, f in zip(po, pats)])
    tab('SPATF', [x for f in pats for x in f])
    es = [ENT[(kk, p)] for p in range(NPITCH) for kk in range(ND2)]
    tab('SNEG', [e[2] for e in es])
    lss = [sp[(kk, p)] for p in range(NPITCH) for kk in range(ND2)]
    eyt, eyb = [ls[0][0] for ls in lss], [ls[-1][0] for ls in lss]
    assert all(-14 <= a <= 1 and 4 <= b <= 19 for a, b in zip(eyt, eyb))
    tab('EYS', [(a + 14) | (b - 4) << 4 for a, b in zip(eyt, eyb)])
    exl = [min(l[1][0] for l in ls) for ls in lss]
    exr = [max(l[1][-1] for l in ls) - 1 for ls in lss]
    assert all(-17 <= a <= -2 and 4 <= b <= 19 for a, b in zip(exl, exr))
    tab('EXB', [(a + 17) | (b - 4) << 4 for a, b in zip(exl, exr)])
    db = [G.dither_bytes(e) for e in range(len(SW.ALL))]
    tab('SHDE', [db[SHD[p][f][n]][0] for p in range(NPITCH) for f in range(NF) for n in range(2)])
    tab('SHDO', [db[SHD[p][f][n]][1] for p in range(NPITCH) for f in range(NF) for n in range(2)])
    L.append('ELO:')
    L.append('        .byte ' + ', '.join(f'<(SPANS+{where[e]})' for e in range(len(blobs))))
    L.append('EHI:')
    L.append('        .byte ' + ', '.join(f'>(SPANS+{where[e]})' for e in range(len(blobs))))
    L.append('        .segment "SPANS"')
    tab('SPANS', data)
    for name, o in uoff.items():
        L.append(f'{name} = SPANS + {o}')
    L.append('        .code')
    open(os.path.join(out, 'shipspan.inc'), 'w').write('\n'.join(L) + '\n')
    return len(data), (len(data) + 255) // 256


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
    print(stats(), '; bank 6 lines: %d bytes in %d pages' % asm6(out))
    if '--sheet' in sys.argv:
        sheet(os.path.join(out, 'ships.png'))
