#!/usr/bin/env python3
"""Lander's ship for LAND's bank 6 (src/shipspan.s): every line of every orientation,
pre-rasterised and compressed, as shipspan.inc.

    python3 tools/shipgen.py OUTDIR [--sheet]

writes OUTDIR/shipspan.inc (ca65 data; src/shipb.s includes it after shipspan.s) and
prints a one-line summary; --sheet also writes OUTDIR/ships.png, every orientation as
the BBC shows it.  test/shipbtest.py and test/landsoak.py check the 6502's pixels
against draw(); tools/gamegen.py takes NDIR, NPITCH, PFLAT and pitch().

The model is ref/lander/ship.py's (Lander's objectPlayer): nine vertices in model
tiles (x the nose, y down, +y out through the floor, z the side) and nine triangular
faces with a normal and a 12-bit colour each: 0-4 the hull's upper faces, 5 and 6 its
rear underside, 7 its floor, 8 the exhaust (in the floor's plane, drawn over it).

Orientation: pitch then yaw, Lander's rotation_matrix(a, b).  The pitch a: NPITCH of
them, PSTEP degrees apart, from -60 (p = 0, nose up) through PFLAT (level) to +60
(nose down); pitch(p).  The direction b: NDIR equal steps of a full turn, direction k's
b = k * 360 / NDIR degrees, k = 0 the nose along +x (the screen's right), 8 towards
the camera (-z), 16 along -x, 24 away.  The camera never yaws and the model is
symmetric in its z, so the ship at (a, 180 - b) is the ship at (a, b) mirrored left to
right: only ND2 directions are stored, kk = 0..16 for b = -90..90 (k = kk - 8 mod
NDIR), and kmap() sends k = 9..23 to kk = 24 - k, mirrored.  The stored entries are
numbered e = p * ND2 + kk.

Projection: parallel, S pixels a model tile, along the camera's line of sight.  The
camera looks along +z and down at the ship with slope TANV, so a rotated offset
(x, y, z) from the ship's centre lands at
    sx = S x        sy = S (y - TANV z)
rounded to pixels, and a face shows when its rotated normal n has n . (0, -TANV, -1)
> 0 (the exhaust, face 8, with face 7: their normals are the same).  TANV is the
slope in play: game.s draws the ship SHYT[d] lines below the horizon, d the camera's
height above it, F = 256 pixels, so the slope is SHYT[d] / 256: 97 / 256 = 0.38 while
the camera follows KOFF = 79 units above the ship, 118 / 256 = 0.46 with the ship on
the ground (the camera CAMH = 96 above it); 0.39 serves throughout.  S is the ship's
own scale, not the landscape's at ZSHIP (19.7 pixels a tile).

Shading: Lander's brightness (ship.lander_brightness) from the rotated normal's y
(light from above) and + 1 if its x < 0 (and from the left).  The rotated y depends
on the pitch alone (the matrix's y row is (sin a, cos a, 0)) and only the sign of x
counts, so SHD holds a palette entry per pitch, face and sign; SNEG + e has bit f set
where face f's rotated x < 0, and a mirrored drawing inverts every bit.  Lander would
add the brightness to each channel of the face's colour; here each of the ship's three
hues has a ramp of swatch35's dithers (RAMPS), dark to light, indexed by the colour's
green channel + the brightness, at most 15.  The ramps keep off the land's and the
sea's dithers (proto/land.py's LAND and SEAC; 19, the floor's grey, is the pad's PADC).
Over the pitches drawn faces 0-4 take 30, 20 and 9, faces 5 and 6 take 8, face 7
takes 19 and face 8 takes 13; the ramps' other steps go unreached.

Lines: canvas() draws a stored entry's visible faces in face order with the reference
rasteriser tri() (the exhaust last, over the floor), and spans() reads each line of
pixels back as its boundaries, offsets from the centre: the first pixel, each change
of face, one past the last, with the faces left to right.  Lines are contiguous in y
and have no gaps.  A direction drawn mirrored is the stored entry's pixels reflected
about the centre (pixel cx + d to cx - d), its boundaries read from the line's end.

Bands and the stream: groups() cuts an entry's lines into bands of consecutive lines
sharing one pattern of faces left to right (a shortest common supersequence of the
lines' face sequences, at most 6 faces; embed() gives a face a line lacks an empty
span), and write() cuts a band again wherever a boundary moves more than a nibble's
worth (-8..7) between lines.  Each entry's stream, which shipspan.s's spdec expands:
    per band:  P (its pattern's index), L (its lines; 19 at most in the data),
               the first line's m = SPATN[P] + 1 boundaries, a byte each, u =
               offset + U0,
               then each following line as nibbles, high first, a byte a pair (an
               odd m's first high nibble 0, unused): each boundary's change from
               the same boundary of the line before, as a signed nibble, the high
               one rotated to put its sign bit lowest (bit 4 of the byte: spdec's
               carry between the pair's adds);
    then $FF.
spdec writes DBUF as the walker reads it: per band P, L, then the lines in order,
each the last m bytes of an eight-byte slot, as pixels (the u's shifted by the
centre's pixel in its byte, mirrored if the direction is); $FF after the last
band.  An entry's DBUF image is under 256 bytes (asserted).

The tables, in shipspan.inc's order (e an entry, P a pattern):
  SHIP_NDIR, SHIP_NPITCH, SHIP_ND2, SHIP_NE, SHIP_U0, SHIP_NPAT, SHIP_MAXN
                     the counts; NPAT the patterns, MAXN the most faces in one
  LIM + w            for a boundary at pixel w (from the column 5 left of shx's: w
                     = u + al normal, 41 + al - u mirrored, al = shx & 3; w in
                     3..41), the first pixel of the byte after w's, 4 * (w // 4 +
                     1): the walker's byte test against the next boundary it reads
  SPATN, SPATO + P   pattern P's faces: how many, where in SPATF
  SPATON + P         SPATO + SPATN, the pattern's end (the unmirrored walker's base)
  SPATF              the patterns' faces, left to right, in turn
  SNEG + e           bit f set where face f's rotated normal's x < 0 (face 8: bit 7)
  EYS + e            (first line + 14) | (last line - 4) << 4, offsets from the centre
  EXB + e            (leftmost pixel + 17) | (rightmost pixel - 4) << 4
  SHDE, SHDO + (p * 9 + f) * 2 + neg   face f's dither bytes at pitch p, its rotated
                     x negative (neg = 1) or not: even lines' and odd lines'
  ELO, EHI + e       entry e's stream, low and high bytes of its address in SPANS
  SPANS              the streams (segment SPANS)
  KTN, BYN + w       (segment DTAB again, after SPANS) for a boundary at pixel w:
                     KT the mask of the pixels before w in its byte ($00, $88, $CC,
                     $EE for w & 3 = 0..3), BY the byte's offset from the column 5
                     left of shx's, 8 * (w >> 2)
"""
import argparse
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
import landgen as LG    # noqa: E402

NDIR = 32                  # directions in a full turn
NPITCH = 13                # pitches
PSTEP = 10                 # degrees between pitches
PFLAT = NPITCH // 2        # the level pitch
ND2 = NDIR // 2 + 1        # stored directions: b = -90..90 degrees
NE = ND2 * NPITCH          # stored entries
NF = 9                     # faces
S = 14.0                   # pixels a model tile
TANV = 0.39                # the camera's slope down to the ship
C = 40                     # canvas(): the centre of a 2C-square canvas
U0 = 20                    # a boundary's byte in the stream: its offset + U0

FACEV = [f['verts'] for f in SH.FACES]
MV = [tuple(c / SH.TILE for c in v) for v in SH.VERTICES]       # vertices, tiles
MN = [tuple(c / SH.ONE for c in f['normal']) for f in SH.FACES]  # unit normals

# Each hue's ramp of swatch35 entries, dark to light, by Lander's green channel +
# brightness (0..15); HUE: the model's colours' hues.
RAMPS = {'purple': [30] * 13 + [20] + [9] * 2,
         'grey': [19] * 8 + [8] * 3 + [4] * 2 + [7] * 3,
         'orange': [13] * 10 + [12] * 6}
HUE = {0x080: 'purple', 0x040: 'purple', 0x088: 'grey', 0x044: 'grey', 0xC80: 'orange'}


def rnd(v):
    """v rounded to the nearest integer, halves up."""
    return int(math.floor(v + 0.5))


def pitch(p):
    """Pitch p's angle in radians, Lander's sense (positive nose down): (p - PFLAT)
    * PSTEP degrees."""
    return math.radians((p - PFLAT) * PSTEP)


def entry(kk, p):
    """Stored entry (kk, p) projected: (pts, vis, neg).  pts the nine vertices'
    (dx, dy) in pixels from the centre; vis bit f (f = 0..7) set where face f shows;
    neg bit f set where face f's rotated normal's x < 0."""
    a, b = pitch(p), (kk - NDIR // 4) * 2 * math.pi / NDIR
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


def shade(p, f, ng):
    """Face f's swatch35 entry at pitch p, its rotated normal's x negative (ng) or not:
    Lander's brightness through the face's hue's ramp."""
    a = pitch(p)
    ny = math.sin(a) * MN[f][0] + math.cos(a) * MN[f][1]
    br = SH.lander_brightness(-1 if ng else 1, int(ny * SH.ONE))
    col = SH.FACES[f]['colour']
    return RAMPS[HUE[col]][min(15, (col >> 4 & 15) + br)]


ENT = {(kk, p): entry(kk, p) for p in range(NPITCH) for kk in range(ND2)}
SHD = [[[shade(p, f, ng) for ng in range(2)] for f in range(NF)] for p in range(NPITCH)]


def kmap(k):
    """Direction k (0..NDIR-1): (its stored direction kk, whether drawn mirrored)."""
    kk = (k + NDIR // 4) % NDIR
    if kk < ND2:
        return kk, False
    return (NDIR // 2 - k + NDIR // 4) % NDIR, True


def orient(k, p):
    """Direction k, pitch p as the 6502 reads the tables: (pts, faces), pts the
    vertices' (dx, dy) (mirrored if k is) and faces the [(f, swatch35 entry)] to draw,
    in face order."""
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
    """The reference rasteriser: fill the triangle pts (three (x, y)) with val in
    img[y, x].  Corners sorted by y (a top, b, c bottom); lines a.y .. c.y - 1; on
    each, the long edge's x (a to c) and the short edge's (a to b above b.y, b to c
    from it), each x0 + floor(dx * t / dy) at t lines down from its upper end; the
    pixels xl <= x < xr between them.  Two faces sharing an edge split its pixels
    exactly."""
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
    """Stored entry (kk, p) drawn unmirrored by tri(), centred at (C, C) of a
    2C-square int16 array: each pixel its face + 1 (0 none), later faces over earlier
    (the exhaust over the floor)."""
    pts, vis, _ = ENT[(kk, p)]
    img = np.zeros((2 * C, 2 * C), dtype=np.int16)
    for f in range(NF):
        if vis >> (7 if f == 8 else f) & 1:
            tri(img, [(C + pts[v][0], C + pts[v][1]) for v in FACEV[f]], f + 1)
    return img


def draw(img, k, p, cx, cy):
    """The ship, direction k, pitch p, centred at (cx, cy) in img: each of its pixels
    gets its swatch35 entry + 1, the rest untouched.  A mirrored direction is the
    stored entry's pixels reflected about the centre, shaded by its mirrored
    normals."""
    kk, mir = kmap(k)
    _, faces = orient(k, p)
    pal = dict(faces)
    can = canvas(kk, p)
    ys, xs = np.nonzero(can)
    for y, x in zip(ys, xs):
        d = x - C
        img[cy + y - C, cx - d if mir else cx + d] = pal[can[y, x] - 1] + 1


def spans():
    """Every stored entry's lines: {(kk, p): [(dy, bounds, faces)]}, dy the line's
    offset from the centre, bounds its boundaries (offsets from the centre: the first
    pixel, each change of face, one past the last) and faces its faces left to right.
    Asserts each line has no gaps and the lines are consecutive."""
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


def scs(a, b):
    """A shortest common supersequence of the face sequences a and b (tuples)."""
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
    """A line's boundaries bd (its faces fs) as the boundaries of pattern pat, a
    supersequence of fs: a face the line lacks gets an empty span (its boundary
    repeated)."""
    out, i = [bd[0]], 0
    for f in pat:
        if i < len(fs) and fs[i] == f:
            i += 1
        out.append(bd[i])
    assert i == len(fs)
    return out


BANDC, SEGC, BYTEC = 230, 26, 20      # groups()'s weights: a band, a face on a line, a byte


def groups(ls):
    """An entry's lines (spans()'s) cut into bands: [(pattern, [each line's boundaries
    for it])], consecutive lines sharing a pattern (a supersequence of their faces, at
    most 6), the cut minimising BANDC a band + SEGC a face a line + BYTEC a byte
    (1 + (faces + 1) a line) by dynamic programming over the lines."""
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


def write(out):
    """OUTDIR/shipspan.inc (the module docstring's tables).  Returns (the streams'
    bytes, the pages they span)."""
    sp = spans()
    pats, blobs = [], []           # the patterns; each entry's [(P, [each line's u's])]
    for p in range(NPITCH):
        for kk in range(ND2):
            b = []
            for fs, ls in groups(sp[(kk, p)]):
                if fs not in pats:
                    pats.append(fs)
                cut = [0] + [i for i in range(1, len(ls))
                             if any(not -8 <= c - a <= 7 for a, c in zip(ls[i - 1], ls[i]))] + [len(ls)]
                for i0, i1 in zip(cut, cut[1:]):
                    b.append((pats.index(fs), [[x + U0 for x in l] for l in ls[i0:i1]]))
            blobs.append(b)
    data, where, dmax = [], {}, 0
    for e, b in enumerate(blobs):
        where[e] = len(data)
        dmax = max(dmax, sum(2 + len(ls) * 8 for _, ls in b) + 1)
        for P, lines in b:
            data += [P, len(lines)]
            data += lines[0]
            for i in range(1, len(lines)):
                d = [(c - a) & 15 for a, c in zip(lines[i - 1], lines[i])]
                d = [0] * (len(d) & 1) + d
                data += [((d[j] & 7) << 1 | d[j] >> 3) << 4 | d[j + 1] for j in range(0, len(d), 2)]
        data.append(0xFF)
    assert dmax < 256, dmax
    L = ['; shipspan.inc: from tools/shipgen.py -- do not edit',
         f'SHIP_NDIR = {NDIR}', f'SHIP_NPITCH = {NPITCH}', f'SHIP_ND2 = {ND2}', f'SHIP_NE = {NE}',
         f'SHIP_U0 = {U0}', f'SHIP_NPAT = {len(pats)}',
         f'SHIP_MAXN = {max(len(f) for f in pats)}']

    def tab(name, vals):
        L.append(f'{name}:')
        for i in range(0, len(vals), 16):
            L.append('        .byte ' + ', '.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    tab('LIM', [(w // 4 + 1) * 4 for w in range(42)])
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
    db = [LG.dither_bytes(e) for e in range(len(SW.ALL))]
    tab('SHDE', [db[SHD[p][f][n]][0] for p in range(NPITCH) for f in range(NF) for n in range(2)])
    tab('SHDO', [db[SHD[p][f][n]][1] for p in range(NPITCH) for f in range(NF) for n in range(2)])
    L.append('ELO:')
    L.append('        .byte ' + ', '.join(f'<(SPANS+{where[e]})' for e in range(len(blobs))))
    L.append('EHI:')
    L.append('        .byte ' + ', '.join(f'>(SPANS+{where[e]})' for e in range(len(blobs))))
    L.append('        .segment "SPANS"')
    tab('SPANS', data)
    L.append('        .segment "DTAB"')
    LM = [0, 0x88, 0xCC, 0xEE]
    if LG.NU.enabled():            # the NULA build: MODE 2's masks (proto/nula.py)
        LM = [LG.NU.mask(m) for m in LM]
    tab('KTN', [LM[i & 3] for i in range(42)])
    tab('BYN', [(i >> 2) * 8 for i in range(42)])
    L.append('        .code')
    open(os.path.join(out, 'shipspan.inc'), 'w').write('\n'.join(L) + '\n')
    return len(data), (len(data) + 255) // 256


def sheet(path, scale=3):
    """Every orientation by draw(), in its dithers, to the PNG at path: a 64 x 56
    cell each, directions 0..15 across the top NPITCH rows (a pitch a row) and 16..31
    across the next, scaled up by scale."""
    from PIL import Image
    cw, ch = 64, 56
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
    """The summary line: the entries, the vertices' furthest offsets and the most hull
    faces (0-7) showing at once (+1: the exhaust)."""
    w = max(max(abs(x) for x, _ in e[0]) for e in ENT.values())
    h = max(max(abs(y) for _, y in e[0]) for e in ENT.values())
    nf = max(bin(e[1]).count('1') for e in ENT.values())
    return f'{NE} entries ({NDIR * NPITCH} orientations by mirroring), |dx| <= {w}, |dy| <= {h}, <= {nf}(+1) faces'


if __name__ == '__main__':
    ap = argparse.ArgumentParser(description="LAND's ship: shipspan.inc for bank 6.")
    ap.add_argument('outdir', nargs='?', default='.', help='where shipspan.inc goes')
    ap.add_argument('--sheet', action='store_true', help='also write OUTDIR/ships.png, every orientation')
    args = ap.parse_args()
    os.makedirs(args.outdir, exist_ok=True)
    print(stats(), '; bank 6 lines: %d bytes in %d pages' % write(args.outdir))
    if args.sheet:
        sheet(os.path.join(args.outdir, 'ships.png'))
