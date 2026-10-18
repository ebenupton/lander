#!/usr/bin/env python3
"""The 32K build's tables (b32/src/land.s), from tools/landgen.py's, for a 32-tile map
(LAND_MAP=32, set here before proto/land.py is imported).

    python3 b32/tools/gen32.py OUTDIR  ->  OUTDIR/TABLES    bank 4's image (dev: at $8000)
                                           OUTDIR/TABLES7   bank 7's image (dev: at $C000)
                                           OUTDIR/MAP32     the map (1K, at MAP32)
                                           OUTDIR/tables.inc
                                           OUTDIR/b32tab.inc DCE, DCO (ca65 data)

The development stage: the sideways banks' tables are kept whole above $8000, where
only py65 has memory (bank 4's at $8000, bank 7's moved to $C000), while they are cut
one by one; the land buffers are the 32K build's.  The land is drawn into one of two
buffers of 12 character rows (lines YSKY..YGND), LAND0 and LAND1, addressed as if each
were a 20-row screen starting 8 rows earlier (SCR0, SCR1: line y's byte for pixel x at
SCRn*256 + (y >> 3) * 512 + (x >> 2) * 8 + (y & 7)).
"""
import os
import sys

os.environ['LAND_MAP'] = '64'
os.environ['LAND_GEN'] = '1'
ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
sys.path.insert(0, os.path.join(ROOT, 'tools'))
sys.path.insert(0, os.path.join(ROOT, 'proto'))
import landgen as G   # noqa: E402
import land as L      # noqa: E402
import gamegen as GG  # noqa: E402
import mapgen as MG   # noqa: E402
MAPIMG = GG.mapimg    # (gametab stubs it out: panel's reference keeps it)

LAND0, LAND1 = 0x5000, 0x6800
SCR = (LAND0 - 0x1000, LAND1 - 0x1000)      # the buffers' virtual screen starts
B7SHIFT = 0x4000                            # bank 7's tables at $C000 (dev)
MAP32 = 0x3800                              # 32 bytes a map row


def bank4():
    """landgen's bank 4 image with run2's stores retargeted at the land buffers."""
    img = G.build()
    for t in range(4):
        for y in range(G.YSKY, G.YGND + 1):
            a = SCR[t >> 1] + 256 * (t & 1) + 512 * (y >> 3) + (y & 7)
            pg = G.TPE[t] if y % 2 == 0 else G.TPO[t]
            o = pg * 256 + G.R2OFF + 3 * ((y - G.YSKY) // 2) - G.BASE
            assert img[o] == 0x99
            img[o + 1:o + 3] = bytes([a & 255, a >> 8])
    return img


def bank7():
    """landgen's bank 7 image, its pointer tables (SYH7, LQHI) moved with it."""
    img = G.build7()
    for name, n in (('SYH7', G.NDI), ('LQHI', 16)):
        o = G.ADDR7[name] - G.BASE
        for i in range(n):
            img[o + i] = (img[o + i] + (B7SHIFT >> 8)) & 255
    return img


ARCSEA, ARCPAD = 3, 7           # the arc build's tile classes (kind << 2 | slope, slope 0..2)


def arc_class(i, j):
    """Tile (i, j)'s class in the arc build (mapgen.s's mtl)."""
    k, s = MG.arc_tile(i, j)
    return ARCPAD if k == 4 else ARCSEA if k == 5 else k << 2 | s


def arc_tables():
    """b32tab.inc's arc tables: CTE, CTO by kind * 9 + (brightness - 4), 0..8: the even
    and odd line bytes of proto/nula.py's colour (kind, brightness).  A box holds kind * 9
    + slope (crow), setup adds the strip's brightness less 4, 7 - nr + ns (su_l)."""
    bs = [G.dither_bytes(G.NU.lentry(k, 4 + t)) for k in range(6) for t in range(9)]
    return [b[0] for b in bs] + [0] * 7, [b[1] for b in bs] + [0] * 7   # (54 + brightness: black)


def colours():
    """The palette entries the map's tiles use (L.colour's), in order: a tile's colour
    index (its corner's MAP32 byte's high nibble) is its entry's place here."""
    hm = L.heightmap()
    return sorted({L.colour(hm, x, z, 0, 0) for z in range(L.MAP) for x in range(L.MAP)})


def mapgen():
    """mapgen.inc: proto/mapgen.py's tables for b32/src/mapgen.s.  MGP, MGQ: the six
    terms' x and z cycles (mod 64), the four k = 2 terms first; SL: SIN16 + 256's low
    byte (its high bit set for i <= 32); HTL, HTH: the height thresholds + 2560 (the
    sum is kept as S + 2560 = the terms' SIN16 + 256s); YQT, LQT: the colour axes'
    quantiles; LUT: the colour index by (qy, ql), two a byte (qy << 3 | ql >> 1, the
    odd ql's in the high nibble); RA; SEAI: the sea's colour indices by R1 & 3; PADI
    the pad's."""
    if G.NU.arc():      # (no quantile tables: a tile's class is its kind << 2 | slope; sea 3, pad 7)
        cols = None
    else:
        cols = colours()
    assert MG.TERMS == [(2, 1, -2), (2, 4, 3), (2, -5, 3), (2, 7, 5), (1, 5, 11), (1, 10, 7)], \
        "mapgen.s's mcl sums the phases for these terms"
    lut = MG._lut() if cols else None
    lb = []
    for qy in range(8):
        for ql in range(0, 8, 2):
            lb.append(cols.index(lut[qy][ql]) | cols.index(lut[qy][ql + 1]) << 4 if cols else 0)
    ht = [t + 2560 for t in MG.HT16]
    assert all(0 < t < 65536 for t in ht)
    code = [('SL', [(v + 256) & 255 for v in MG.SIN16]), ('RA', MG.RA)]
    # (the rest the loader copies to holes: mapgen.s's .res for each, these as _S)
    held = [('MGQ', [q & 63 for _, _, q in MG.TERMS] + [0]),
            ('MGP', [p & 63 for _, p, _ in MG.TERMS]), ('YQT', MG.YQ),
            ('LQT', MG.LQ), ('SEAI', [cols.index(L.SEAC[i % len(L.SEAC)]) if cols else 0 for i in range(4)]),
            ('HTL', [t & 255 for t in ht]), ('HTH', [t >> 8 for t in ht]), ('LUT', lb)]
    out = ['; b32/tools/gen32.py: proto/mapgen.py\'s tables (b32/src/mapgen.s)',
           f'PADI    = {cols.index(L.PADC) if cols else ARCPAD}', f'SEAN    = {ARCSEA}']
    for name, v in code:
        assert all(0 <= b < 256 for b in v), name
        out.append(f'{name + ":":8s}.byte ' + ', '.join(f'${b:02X}' for b in v))
    out.append('        .segment "BOOT"            ; (copied to their holes by the loader)')
    fuelg = []                                            # FUEL in the MODE 2 build's narrow
    for c in 'FUEL':                                      # letters (proto/nula.py), MODE 5:
        for v in G.NU.font_rows(c):                       # pixel i lit (colour 3: $88 >> i)
            fuelg.append(sum(0x88 >> i for i in range(4) if v & (3 << (6 - 2 * i))))
    out.append('FUELG:  .byte ' + ', '.join(f'${b:02X}' for b in fuelg))
    grey = GG.SW.cell(*GG.SW.ALL[L.PADC])                 # (gpanel's pad: gamegen's mapimg)
    out.append('PADG:   .byte ' + ', '.join(str(grey[(px, ln)]) for ln in (0, 1) for px in (0, 1)))
    for name, v in held:
        assert all(0 <= b < 256 for b in v), name
        out.append(f'{name + "_S:":8s}.byte ' + ', '.join(f'${b:02X}' for b in v))
    out.append('        .code')
    return '\n'.join(out) + '\n'


def panel():
    """The panel's map: its first 8 rows, MODE 5 (64 bytes a row of 8 characters, 4
    pixels a byte), the 64 x 64 tiles two across a pixel, one a line (square): line
    y, pixel t the tile x = 2t - MAPX, z = MAPZ - y (mod 64); sea colour 1, land 3,
    the pad black.  Line y, pixel t's byte: 64 (y >> 3) + 8 (t >>
    2) + (y & 7), its bits $88 >> (t & 3) (as MODE 1's)."""
    mapx, mapz = GG.MAPX, GG.MAPZ
    img = bytearray(8 * 64)
    for y in range(64):
        for t in range(32):
            if G.NU.arc():
                c = arc_class((2 * t - mapx) & 63, (mapz - y) & 63)
                v = 0x00 if c == ARCPAD else 0x0F if c == ARCSEA else 0xFF
            else:
                e = MG.colour((2 * t - mapx) & 63, (mapz - y) & 63)
                v = 0x00 if e == L.PADC else 0x0F if e in L.SEAC else 0xFF
            mask = 0x88 >> (t & 3)
            o = 64 * (y >> 3) + 8 * (t >> 2) + (y & 7)
            img[o] = img[o] & ~mask & 255 | v & mask
    return img


# The readout's characters (gchars's order: "0123456789. FPS"), 3 pixels by 7 lines
# in a 4-pixel MODE 5 cell (the 4th pixel and the top line blank), colour 3.
FONT = {
    '0': '.#. #.# #.# #.# #.# #.# .#.', '1': '.#. ##. .#. .#. .#. .#. ###',
    '2': '.#. #.# ..# .#. #.. #.. ###', '3': '##. ..# ..# .#. ..# ..# ##.',
    '4': '#.# #.# #.# ### ..# ..# ..#', '5': '### #.. #.. ##. ..# ..# ##.',
    '6': '.## #.. #.. ##. #.# #.# .#.', '7': '### ..# ..# .#. .#. .#. .#.',
    '8': '.#. #.# #.# .#. #.# #.# .#.', '9': '.#. #.# #.# .## ..# ..# ##.',
    '.': '... ... ... ... ... ... .#.', ' ': '... ... ... ... ... ... ...',
    'F': '### #.. #.. ##. #.. #.. #..', 'P': '##. #.# #.# ##. #.. #.. #..',
    'S': '.## #.. #.. .#. ..# ..# ##.',
}


def glyphs():
    """GLY: 8 bytes a character (its lines), gchars's order."""
    out = bytearray()
    for c in '0123456789. FPS':
        rows = ['...'] + FONT[c].split()   # (a blank line on top: off the map)
        for r in rows:
            out.append(sum(0x88 >> i for i in range(3) if r[i] == '#'))
    return out


def qrtab():
    """qrtab.inc: div8's table: for divisor d 2..15 and dividend D d..31, (D div d)
    << 4 | D mod d (both under 16).  QRA rows d 2..8, QRB rows 9..15, each row D = d..31
    in order; QOA + d - 2 (QOB + d - 9): row d's start less d (QOB's less 1 more: its
    ADC has C set), so the entry is at QRA + (QOA[d] + D) mod 256."""
    rows = {}
    for lo, hi, name in ((2, 8, 'QRA'), (9, 15, 'QRB')):
        t, off = [], []
        for d in range(lo, hi + 1):
            off.append((len(t) - d - (1 if name == 'QRB' else 0)) & 255)
            t += [(D // d) << 4 | (D % d) for D in range(d, 32)]
        assert len(t) <= 256
        rows[name] = (t, off)
    return rows


def gametab(out):
    """gametab.inc: tools/gamegen.py's tables less MAPI (the panel's map is drawn at
    the start by the loader, from the generator)."""
    sys.argv = [sys.argv[0], out]
    GG.mapimg = lambda: bytes(1024)
    GG.main()
    path = os.path.join(out, 'gametab.inc')
    lines = open(path).read().split('\n')
    for name in ('MAPI:', 'THX:', 'THZ:', 'SHYT:'):         # (TQ, RSHIP instead)
        i = lines.index(name)
        j = next(k for k in range(i + 1, len(lines)) if not lines[k].startswith('        .byte'))
        lines = lines[:i] + lines[j:]
    lines = [ln for ln in lines if not ln.startswith(('THXL:', 'THXH:', 'THZL:', 'THZH:'))]
    thx, _, _ = GG.thrust()
    pf = GG.SG.PFLAT
    tq = [thx[32 * (pf + p) + k] for p in range(GG.NPITCH - pf) for k in range(9)]
    lines.append('TQ:     .byte ' + ', '.join(f'${v & 255:02X}' for v in tq))
    lines.append(f'RSHIP = {L.recip(L.ZSHIP << 8)}')
    open(path, 'w').write('\n'.join(lines) + '\n')


def neartab():
    """proj32's near clip row (di = ZCLIP*16 - DI0, its r a constant): TN + 15 + v, the
    line less EYV for a corner v = h - hg above the ship's ground (ytab's: HORIZON +
    ((CAMH - v) r + 2048) >> 12); B1N + 2 cxs, corner 1's 8.8 x (xrow's B1); NXL, NXR
    the ends (xrow's)."""
    di = L.ZCLIP * 16 - G.DI0
    k = G.DI0 + di
    r = (2 ** 21 + k) // (2 * k)
    tn = [((16 * (L.CAMH - v) * r + 32768) >> 16) + L.HORIZON for v in range(-15, 16)]
    assert all(0 <= t < 256 for t in tn)
    q = 1152 * r
    nxr = (128 + ((q + 32768) >> 16)) & 255
    nxl = (128 - ((q + 32767) >> 16)) & 255
    b1 = []
    for cxs in range(16):
        m = (1152 + 16 * cxs) * r
        b = (32768 + ((32768 - m) >> 8) + r) & 0xFFFF
        assert b + 8 * r < 65536, 'no carry out over the corners'
        b1.append(b)
    out = ['; b32/tools/gen32.py: proj32\'s near clip row (di %d, r %d)' % (di, r),
           f'NDIN    = {di}', f'NRL     = {r & 255}', f'NRH     = {r >> 8}',
           f'NXL     = {nxl}', f'NXR     = {nxr}',
           '        .segment "BOOT"            ; (copied to their holes by the loader)',
           'TN_S:   .byte ' + ', '.join(f'{t}' for t in tn),
           'B1N_S:  .word ' + ', '.join(f'${b:04X}' for b in b1),
           '        .code']
    return '\n'.join(out) + '\n'


def palettes():
    """pal.inc (the MODE 2 builds': proto/nula.py): YELB, MAGB, the dots' bytes, and the
    ULA's palette writes for the two modes the screen alternates between, (entry << 4) |
    (colour ^ 7), colour bit 3 (VideoNULA: its sixteenth) kept.  The top is MODE 5, its
    logical colour c (0 black, 1 the sea, 2 the marker's magenta, 3 yellow: the land,
    the letters, the gauge) in the four entries with c's high bit at bit 3 and its low
    at bit 1; the land MODE 2, entry e colour e (CPC: e & 7: the steady colours; NULA:
    the sixteen).  P5PAL, P2PAL: 16 bytes each; NULAPAL: the VideoNULA's palette."""
    NU = G.NU
    if NU.arc():                                     # ARCPAL: the sea's nearest of the sixteen
        sea = min(range(16), key=lambda c: NU.dist2(NU.ARCPAL[c], NU.lrgb(NU.lentry(5, 7))))
        top = [0, sea, NU.ARCORA, NU.ARCYEL]
        land = list(range(16))
    elif NU.nula():
        top = [0, NU.colour(NU.MAPSEA), NU.MAGENTA, NU.YELLOW]
        land = list(range(16))
    else:                                            # the nearest of MODE 2's eight to the sea
        sea = min(range(8), key=lambda c: NU.dist2(NU.avg(NU.MAPSEA), tuple(255 * (c >> i & 1) for i in range(3))))
        top = [0, sea, 5, 3]
        land = [e & 7 for e in range(16)]
    p5 = [e << 4 | (top[(e >> 3 & 1) * 2 + (e >> 1 & 1)] ^ 7) for e in range(16)]
    p2 = [e << 4 | (land[e] ^ 7) for e in range(16)]
    out = ['; b32/tools/gen32.py: the MODE 2 build\'s colours (proto/nula.py)',
           f'YELB    = ${NU.yelb():02X}', f'MAGB    = ${NU.magb():02X}',
           '.macro P5PAL', '        .byte ' + ', '.join(f'${b:02X}' for b in p5), '.endmacro',
           '.macro P2PAL', '        .byte ' + ', '.join(f'${b:02X}' for b in p2), '.endmacro']
    if NU.nula() or NU.arc():
        out.append('.macro NULAPAL')
        for c, (r, g, b) in enumerate(NU.PAL):
            out.append(f'        .byte ${c << 4 | r:02X}, ${g << 4 | b:02X}')
        out.append('.endmacro')
    return '\n'.join(out) + '\n'


def main():
    out = sys.argv[1]
    if G.NU.enabled():
        open(os.path.join(out, 'pal.inc'), 'w').write(palettes())
    gametab(out)
    open(os.path.join(out, 'mapgen.inc'), 'w').write(mapgen())
    open(os.path.join(out, 'PANELMAP'), 'wb').write(panel())   # (the tests' reference)
    with open(os.path.join(out, 'qrtab.inc'), 'w') as f:
        # (the loader makes the tables: here only their sizes, checked against qrtab(),
        # and the panel's colour byte for each colour index, for its map)
        qa, qb = qrtab()['QRA'][0], qrtab()['QRB'][0]
        f.write('; b32/tools/gen32.py: the loader-made tables\' sizes, the panel map\'s colours\n')
        f.write(f'QRAN = {len(qa)}\nQRBN = {len(qb)}\n')
        if G.NU.arc():
            cls = [0x00 if n == ARCPAD else 0x0F if n == ARCSEA else 0xFF for n in range(16)]
        else:
            cls = [0x00 if e == L.PADC else 0x0F if e in L.SEAC else 0xFF for e in colours()]
        f.write('.macro MAPCLS_DATA\n        .byte ' + ', '.join(f'${v:02X}' for v in cls + [0] * (16 - len(cls))) + '\n.endmacro\n')
    with open(os.path.join(out, 'b32tab.inc'), 'w') as f:
        f.write('; b32/tools/gen32.py: a colour index\'s dither bytes, even and odd lines\n')
        if G.NU.arc():
            ce, co = arc_tables()
            f.write('CTE:    .byte ' + ', '.join(f'${v:02X}' for v in ce) + '\n')
            f.write('CTO:    .byte ' + ', '.join(f'${v:02X}' for v in co) + '\n')
        else:
            bs = [G.dither_bytes(e) for e in colours()]
            f.write('DCE:    .byte ' + ', '.join(f'${b[0]:02X}' for b in bs) + '\n')
            f.write('DCO:    .byte ' + ', '.join(f'${b[1]:02X}' for b in bs) + '\n')
        assert all(L.recip((G.DI0 + di) * 16) == (2 ** 21 + G.DI0 + di) // (2 * (G.DI0 + di))
                   for di in range(G.NDI))           # (init's R7L, R7H)
    with open(os.path.join(out, 'neartab.inc'), 'w') as f:
        f.write(neartab())
    EYS = 255 - max(L.HORIZON + (((L.CAMH + L.HMAX) * L.recip((G.DI0 + di) * 16) + L.HSCALE * 128)
                                  // (L.HSCALE * 256)) for di in range(G.NDI))
    with open(os.path.join(out, 'tables.inc'), 'w') as f:
        f.write('; b32/tools/gen32.py\n')
        addr = {}
        addr.update(LAND0=LAND0, LAND1=LAND1)
        for k, v in addr.items():
            f.write(f'{k:8s}= ${v:04X}\n')
        consts = dict(TNB=64, HMAX=L.HMAX, NDI=G.NDI, NX=G.NXD, XSKIP=L.XSKIP, NZ=L.NZ,
                      ZBACK=L.ZBACK, ZSKIP=L.ZSKIP, ZCLIP=L.ZCLIP, ZFCLIP=L.ZFCLIP, DI0=G.DI0,
                      NCLP=G.NCLP, XL=L.XL, XR=L.XR, LQOFF=G.LQOFF, ZSHIP=L.ZSHIP, CAMH=L.CAMH,
                      EMAX=L.EMAX, PADN=L.PADN, PADH=L.PADH, HORIZON=L.HORIZON, YSKY=G.YSKY,
                      YGND=G.YGND, R2OFF=G.R2OFF, RFA=G.RFA, EYS=EYS, MAPN=L.MAP,
                      SCR0=SCR[0] >> 8, SCR1=SCR[1] >> 8,
                      TPE0=G.TPE[0], TPE1=G.TPE[1], TPE2=G.TPE[2], TPE3=G.TPE[3],
                      TPO0=G.TPO[0], TPO1=G.TPO[1], TPO2=G.TPO[2], TPO3=G.TPO[3])
        for k, v in consts.items():
            f.write(f'{k:8s}= {v}\n')


if __name__ == '__main__':
    main()
