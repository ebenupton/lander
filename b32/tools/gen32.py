#!/usr/bin/env python3
"""The generated parts of the 32K build: constants and tables from the references.

    python3 b32/tools/gen32.py OUTDIR

Writes into OUTDIR (the build directory, on the assembler's include path):

    tables.inc   the renderer's and the map's constants (proto/land.py, tools/landgen.py)
    colours.inc  the tiles' dither bytes: DCE, DCO by colour index (the arc build: CTE,
                 CTO by kind * 9 + brightness)
    mapgen.inc   proto/mapgen.py's tables: SL, RA (stored), and the loader's copies of
                 the phases' steps, the quantiles, the sea's colours, the height
                 thresholds and the colour table; FUEL's letters
    neartab.inc  the near clip row's constants (its r, ends, line by height, corner 1)
    gametab.inc  tools/gamegen.py's tables, trimmed: the thrust as a quarter-table (TQ)
    pal.inc      the MODE 2 builds' palettes and dot colours (proto/nula.py)

The version comes from the environment (CPC, NULA, ARC: proto/nula.py's switches).
"""
import os
import sys

os.environ['LAND_MAP'] = '64'
os.environ.setdefault('LAND_GEN', '1')   # (LAND_GEN=0: Lander's own map, for comparisons)
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
sys.path.insert(0, os.path.join(ROOT, 'tools'))
sys.path.insert(0, os.path.join(ROOT, 'proto'))
import landgen as G   # noqa: E402
import land as L      # noqa: E402
import gamegen as GG  # noqa: E402
import mapgen as MG   # noqa: E402

NU = G.NU
ARCPAD = 7                         # the arc build's pad class (kind << 2 | slope)


def colours():
    """The palette entries the map's tiles use, in order: a tile's colour index (its
    corner's high nibble) is its entry's place here."""
    hm = L.heightmap()
    return sorted({L.colour(hm, x, z, 0, 0) for z in range(L.MAP) for x in range(L.MAP)})


def byte_rows(name, values, step=16):
    assert all(0 <= v < 256 for v in values), name
    rows = [values[i:i + step] for i in range(0, len(values), step)]
    return [f'{name + ":":8s}.byte ' + ', '.join(f'${v:02X}' for v in rows[0])] + \
        ['        .byte ' + ', '.join(f'${v:02X}' for v in r) for r in rows[1:]]


def tables_inc():
    k = dict(TNB=SWR_TNB if os.environ.get('SWR') == '1' else 64, NDI=G.NDI, NX=G.NXD, XSKIP=L.XSKIP, ZBACK=L.ZBACK, ZSKIP=L.ZSKIP,
             ZCLIP=L.ZCLIP, ZFCLIP=L.ZFCLIP, DI0=G.DI0, ZSHIP=L.ZSHIP, CAMH=L.CAMH,
             EMAX=L.EMAX, PADN=L.PADN, PADH=L.PADH, HORIZON=L.HORIZON, YSKY=G.YSKY,
             YGND=G.YGND, MAPN=L.MAP, QRAN=sum(32 - d for d in range(2, 9)))
    assert all(L.recip((G.DI0 + di) * 16) == (2 ** 21 + G.DI0 + di) // (2 * (G.DI0 + di))
               for di in range(G.NDI)), "init's R7L, R7H"
    return ['; b32/tools/gen32.py: constants'] + [f'{n:8s}= {v}' for n, v in k.items()]


def colours_inc():
    if NU.arc():
        bs = [G.dither_bytes(NU.lentry(k, 4 + t)) for k in range(6) for t in range(9)]
        return (['; b32/tools/gen32.py: by kind * 9 + brightness - 4 (black past the end)']
                + byte_rows('CTE', [b[0] for b in bs] + [0] * 7, 64)
                + byte_rows('CTO', [b[1] for b in bs] + [0] * 7, 64))
    bs = [G.dither_bytes(e) for e in colours()]
    return (['; b32/tools/gen32.py: by colour index, even and odd lines']
            + byte_rows('DCE', [b[0] for b in bs], 64) + byte_rows('DCO', [b[1] for b in bs], 64))


def mapgen_inc():
    assert MG.TERMS == [(2, 1, -2), (2, 4, 3), (2, -5, 3), (2, 7, 5), (1, 5, 11), (1, 10, 7)], \
        "mcl sums the phases for these terms"
    cols = None if NU.arc() else colours()
    lut = []
    if cols:
        q = MG._lut()
        for qy in range(8):
            for ql in range(0, 8, 2):
                lut.append(cols.index(q[qy][ql]) | cols.index(q[qy][ql + 1]) << 4)
    else:
        lut = [0] * 32
    ht = [t + 2560 for t in MG.HT16]
    assert all(0 < t < 65536 for t in ht)
    fuel = []                                             # FUEL: MODE 5, colour 3
    for c in 'FUEL':
        for v in NU.font_rows(c):
            fuel.append(sum(0x88 >> i for i in range(4) if v & (3 << (6 - 2 * i))))
    sea = [cols.index(L.SEAC[i % len(L.SEAC)]) if cols else 0 for i in range(4)]
    out = ['; b32/tools/gen32.py: proto/mapgen.py\'s tables',
           f'PADI    = {cols.index(L.PADC) if cols else ARCPAD}']
    out += byte_rows('SL', [(v + 256) & 255 for v in MG.SIN16])
    out += byte_rows('RA', MG.RA)
    out.append('        .segment "BOOT"')
    out += byte_rows('FUELG', fuel)
    for name, v in (('MGQ_S', [q & 63 for _, _, q in MG.TERMS] + [0]),
                    ('MGP_S', [p & 63 for _, p, _ in MG.TERMS]), ('YQT_S', MG.YQ),
                    ('LQT_S', MG.LQ), ('SEAI_S', sea),
                    ('HTL_S', [t & 255 for t in ht]), ('HTH_S', [t >> 8 for t in ht]),
                    ('LUT_S', lut)):
        out += byte_rows(name, v)
    return out + ['        .code']


def neartab_inc():
    di = L.ZCLIP * 16 - G.DI0
    k = G.DI0 + di
    r = (2 ** 21 + k) // (2 * k)
    tn = [((16 * (L.CAMH - v) * r + 32768) >> 16) + L.HORIZON for v in range(-15, 16)]
    q = 1152 * r
    b1 = []
    for cxs in range(16):
        b = (32768 + ((32768 - (1152 + 16 * cxs) * r) >> 8) + r) & 0xFFFF
        assert b + 8 * r < 65536, 'no carry over the corners'
        b1.append(b)
    return [f'; b32/tools/gen32.py: the near clip row (di {di}, r {r})',
            f'NDIN    = {di}', f'NRL     = {r & 255}', f'NRH     = {r >> 8}',
            f'NXL     = {(128 - ((q + 32767) >> 16)) & 255}',
            f'NXR     = {(128 + ((q + 32768) >> 16)) & 255}',
            '        .segment "BOOT"'] + byte_rows('TN_S', tn, 31) + \
           ['B1N_S:  .word ' + ', '.join(f'${b:04X}' for b in b1), '        .code']


def gametab_inc(out):
    """tools/gamegen.py's tables less the map and the thrust tables (TQ instead)."""
    sys.argv = [sys.argv[0], out]
    swr = os.environ.get('SWR') == '1'
    if not swr:
        GG.mapimg = lambda: bytes(1024)
    GG.main()
    path = os.path.join(out, 'gametab.inc')
    lines = open(path).read().split('\n')
    for name in ('THX:', 'THZ:', 'SHYT:') if swr else ('MAPI:', 'THX:', 'THZ:', 'SHYT:'):
        i = lines.index(name)
        j = next(k for k in range(i + 1, len(lines)) if not lines[k].startswith('        .byte'))
        lines = lines[:i] + lines[j:]
    lines = [ln for ln in lines if ln and not ln.startswith(('THXL:', 'THXH:', 'THZL:', 'THZH:'))]
    thx, _, _ = GG.thrust()
    pf = GG.SG.PFLAT
    tq = [thx[32 * (pf + p) + k] & 255 for p in range(GG.NPITCH - pf) for k in range(9)]
    return lines + byte_rows('TQ', tq, 9) + [f'RSHIP   = {L.recip(L.ZSHIP << 8)}']


def pal_inc():
    """The ULA's palette writes for the two modes the field alternates between, (entry
    << 4) | (colour ^ 7): the top (MODE 5: logical colour c in the four entries with
    c's bits at 3 and 1: black, the sea, magenta, yellow) and the land (MODE 2: entry e
    colour e; CPC: e & 7); the dots' bytes; the VideoNULA's palette."""
    if NU.arc():
        sea = min(range(16), key=lambda c: NU.dist2(NU.ARCPAL[c], NU.lrgb(NU.lentry(5, 7))))
        top, land = [0, sea, NU.ARCORA, NU.ARCYEL], list(range(16))
    elif NU.nula():
        top, land = [0, NU.colour(NU.MAPSEA), NU.MAGENTA, NU.YELLOW], list(range(16))
    else:
        sea = min(range(8), key=lambda c: NU.dist2(NU.avg(NU.MAPSEA), tuple(255 * (c >> i & 1) for i in range(3))))
        top, land = [0, sea, 5, 3], [e & 7 for e in range(16)]
    p5 = [e << 4 | (top[(e >> 3 & 1) * 2 + (e >> 1 & 1)] ^ 7) for e in range(16)]
    p2 = [e << 4 | (land[e] ^ 7) for e in range(16)]
    out = ['; b32/tools/gen32.py: the MODE 2 build\'s colours',
           f'YELB    = ${NU.yelb():02X}', f'MAGB    = ${NU.magb():02X}',
           '.macro P5PAL', '        .byte ' + ', '.join(f'${b:02X}' for b in p5), '.endmacro',
           '.macro P2PAL', '        .byte ' + ', '.join(f'${b:02X}' for b in p2), '.endmacro']
    if NU.nula() or NU.arc():
        out.append('.macro NULAPAL')
        out += [f'        .byte ${c << 4 | r:02X}, ${g << 4 | b:02X}' for c, (r, g, b) in enumerate(NU.PAL)]
        out.append('.endmacro')
    return out


B7CODE = 0xB480
SWR_TNB = 127                      # the fills' longest (TEN4H, TEN5H share a page)
B4FIXED = dict(B4MAP=0x8000, DQT=0x9000, DRT=0x9800, CLMP1=0xA000, DIV4=0xA100,
               LAHS=0xA200, TENH=0xA600, TENL=0xA700, TBLK4=0xA800, TBLK5=0xA980)
B5CMAPE, B5CMAPO, B5CODE = 0x8000, 0x9000, 0xA000
BLKT = 0xB800                      # bank 4: the black runs' tables (to $BFFF)


def rfast_tables():
    """landgen's TRk, TLk (the rungs' fast way): {name: bytes}.  Entry 16 (RFA - a) + D
    of TRk is pixel k's transition for a rung of a pixels leaning right, D lines deep:
    ceil(D (2j - 1) / 2a), j = k + 1 (TLk: j = a - k)."""
    rfa = G.RFA
    out = {}
    for k in range(rfa):
        for side in 'RL':
            v = bytearray(16 * (rfa - k))
            for a in range(k + 1, rfa + 1):
                j = k + 1 if side == 'R' else a - k
                for d in range(16):
                    v[16 * (rfa - a) + d] = -(-d * (2 * j - 1) // (2 * a))
            out[f'T{side}{k}'] = bytes(v)
    return out


def bank4_tables():
    """Bank 4's tables: {name: (address, bytes or None)} (None: made by the loader's init)
    and the code's start.  Fixed: the map's heights (64 a row), DQT, DRT (D div a, 2 (D
    mod a), 64 a + D: a 1..31, D 0..63), CLMP1 (d + 1, signed, clamped to 0..4), DIV4 (x
    >> 2), the four line-page tables LAHSBt (a page each from LAHS, one low byte for all:
    sethalf patches the page), the fills' entries (TENxH by n in one page, TENxL in the
    next) and the fills TBLK4, TBLK5 (init's).  Then, first fit into the gaps: RSMT ((y &
    ~7) - 1), DVH, DVL (DQT's row a: its page, its low byte), the rungs' tables.  The
    code follows on the next page."""
    t = {}
    hm = L.heightmap()
    t['B4MAP'] = (B4FIXED['B4MAP'], bytes(int(hm[0][z, x]) for z in range(64) for x in range(64)))
    dq, dr = bytearray(2048), bytearray(2048)
    for a in range(1, 32):
        for d in range(64):
            dq[64 * a + d], dr[64 * a + d] = d // a, 2 * (d % a)
    t['DQT'], t['DRT'] = (B4FIXED['DQT'], bytes(dq)), (B4FIXED['DRT'], bytes(dr))
    t['CLMP1'] = (B4FIXED['CLMP1'], bytes(0 if ((d + 1) & 255) >= 128 else min((d + 1) & 255, 4)
                                          for d in range(256)))
    t['DIV4'] = (B4FIXED['DIV4'], bytes(x >> 2 for x in range(256)))
    lines = range(G.YSKY, G.YGND + 2)
    for q in range(4):                             # q = 2 screen + half
        page = (0x30 if q < 2 else 0x58) + (q & 1)
        t[f'LAHS{q}'] = (B4FIXED['LAHS'] + 256 * q, bytes(page + 2 * (y >> 3) for y in lines))
    t['TENH'] = (B4FIXED['TENH'], None)
    t['TENL'] = (B4FIXED['TENL'], None)
    t['TBLK4'] = (B4FIXED['TBLK4'], None)
    t['TBLK5'] = (B4FIXED['TBLK5'], None)
    used = [(B4FIXED['B4MAP'], 0x8000 + 0x1000), (0x9000, 0xA200)]
    used += [(a, a + len(v)) for n, (a, v) in t.items() if n.startswith('LAHS')]
    used += [(0xA600, 0xAB00)]
    gaps = []
    for pg in range(0xA2, 0xC0):                   # free bytes by page
        lo = pg * 256
        taken = [(max(a, lo), min(b, lo + 256)) for a, b in used if a < lo + 256 and b > lo]
        top = max([b for _, b in taken], default=lo)
        if top < lo + 256:
            gaps.append([top, lo + 256])
    items = {'RSMT': bytes(((y & 0xF8) - 1) & 255 for y in range(G.YSKY, G.YGND + 3)),
             'DVH': bytes(((B4FIXED['DQT'] + 64 * a) >> 8) for a in range(32)),
             'DVL': bytes((64 * a) & 255 for a in range(32))}
    items.update(rfast_tables())
    for name, v in sorted(items.items(), key=lambda kv: -len(kv[1])):
        g = next(g for g in gaps if g[1] - g[0] >= len(v))
        t[name] = (g[0], v)
        g[0] += len(v)
    end = max(a + (len(v) if v else 0) for a, v in t.values() if a >= 0xAB00)
    assert end <= 0xB000, 'bank 4: the tables over its code ($B000, landerswr.cfg)'
    # the black runs' store tables (runk): table q at BLKT + $200 q, a slot of STA
    # line,Y for each line YSKY .. YGND+1 (line YGND+1's an RTS, the end); KENL, KENH
    # (the slot's low byte, and its page less the table's) by line, YSKY .. YGND+2
    # (YGND+2's the end slot too), in the tables' second pages' spare
    n = G.YGND + 2 - G.YSKY
    for q in range(4):
        v = bytearray()
        for y in range(G.YSKY, G.YGND + 2):
            a = (0x3000 if q < 2 else 0x5800) + 256 * (q & 1) + 512 * (y >> 3) + (y & 7)
            v += bytes([0x99, a & 255, a >> 8]) if y <= G.YGND else bytes([0x60, 0, 0])
        t[f'BLK{q}'] = (BLKT + 0x200 * q, bytes(v))
    lines = list(range(G.YSKY, G.YGND + 3))
    slot = [3 * (min(y, G.YGND + 1) - G.YSKY) for y in lines]
    t['KENL'] = (BLKT + 3 * n, bytes(o & 255 for o in slot))
    t['KENH'] = (BLKT + 0x200 + 3 * n, bytes(o >> 8 for o in slot))
    assert 256 <= 3 * n and 3 * n - 256 + len(lines) <= 256, 'KENL, KENH: in the tables\' second pages'
    return t, 0xB000


def bank4():
    """Bank 4's image (bank4_tables'); the code follows."""
    img = bytearray(0x4000)
    tabs, _ = bank4_tables()
    for a, v in tabs.values():
        if v:
            assert not any(img[a - 0x8000:a - 0x8000 + len(v)]), 'bank 4: tables overlap'
            img[a - 0x8000:a - 0x8000 + len(v)] = v
    return img


def bank5():
    """Bank 5's image: each tile's colour bytes (CMAPE, CMAPO; the arc build's CMAPE its
    class, 9 kind + slope) by 64 z + x; the code (the game, pcol5) follows at B5CODE."""
    img = bytearray(0x4000)
    hm = L.heightmap()
    for z in range(64):
        for x in range(64):
            o = 64 * z + x
            if NU.arc():
                k, s = MG.arc_tile(x, z) if L.GEN else L.arc_tile(hm, x, z)
                img[B5CMAPE - 0x8000 + o] = 9 * k + s
            else:
                e, d = G.dither_bytes(L.colour(hm, x, z, 0, 0))
                img[B5CMAPE - 0x8000 + o] = e
                img[B5CMAPO - 0x8000 + o] = d
    return img


def swrtab_inc():
    """The sideways RAM build's addresses and constants: banks 4, 5 and 7's tables."""
    eys = 255 - max(L.HORIZON + (((L.CAMH + L.HMAX) * L.recip((G.DI0 + di) * 16) + L.HSCALE * 128)
                                 // (L.HSCALE * 256)) for di in range(G.NDI))
    tabs, code = bank4_tables()
    k = {n: a for n, (a, _) in tabs.items()}
    for q in range(4):                             # (line tables: base + y)
        k[f'LAHSB{q}'] = k.pop(f'LAHS{q}') - G.YSKY
    k['RSMT'] -= G.YSKY
    k['KENL'] -= G.YSKY
    k['KENH'] -= G.YSKY
    k['BLKT'] = k.pop('BLK0')
    for q in (1, 2, 3):
        k.pop(f'BLK{q}')
    k['TEN4H'], k['TEN5H'] = k['TENH'], k.pop('TENH') + SWR_TNB + 1
    k['TEN4L'], k['TEN5L'] = k['TENL'], k.pop('TENL') + SWR_TNB + 1
    k.update(B4CODE=code, CMAPE=B5CMAPE, CMAPO=B5CMAPO, B5CODE=B5CODE, B7CODE=B7CODE)
    k.update(G.ADDR7)
    out = ['; b32/tools/gen32.py: the sideways RAM banks\' tables']
    out += [f'{n:8s}= ${v:04X}' for n, v in k.items()]
    out += [f'{n:8s}= {v}' for n, v in dict(RFA=G.RFA, NCLP=G.NCLP, LQOFF=G.LQOFF, EYS=eys,
                                            XL=L.XL, XR=L.XR, HMAX=L.HMAX).items()]
    return out


def panel_inc():
    """The sideways RAM build's panel: FUELI, FUEL's letters as the bytes of row 0's
    first eight byte columns (16 a letter: two columns of 8 lines, proto/nula.py's
    letters, MODE 1's pixels doubled), and BARB, the gauge's byte by pixels lit."""
    fuel = bytearray(64)
    for n, c in enumerate('FUEL'):
        for line, v in enumerate(NU.font_rows(c)):
            for i in range(4):
                if not v & (3 << (6 - 2 * i)):
                    continue
                if NU.enabled():
                    fuel[16 * n + 8 * (i >> 1) + line] |= NU.yelb() & NU.pixel(2 * i)
                else:
                    fuel[16 * n + 8 * (i >> 1) + line] |= 0xCC >> (2 * (i & 1))
    if NU.enabled():
        barb = [0, NU.yelb() & 0xAA, NU.yelb() & 0xAA, NU.yelb(), NU.yelb()]
        pixg = [0xAA, 0xAA, 0x55, 0x55]
    else:
        barb = [0x00, 0x88, 0xCC, 0xEE, 0xFF]
        pixg = [0x88, 0x44, 0x22, 0x11]
    return (['; b32/tools/gen32.py: the panel'] + byte_rows('FUELI', list(fuel))
            + byte_rows('BARB', barb) + byte_rows('PIXG', pixg))


def main():
    out = sys.argv[1]
    swr = os.environ.get('SWR') == '1'
    files = {'tables.inc': tables_inc(), 'colours.inc': colours_inc(),
             'gametab.inc': gametab_inc(out)}
    if swr:
        files.update({'swrtab.inc': swrtab_inc(), 'panel.inc': panel_inc()})
        open(os.path.join(out, 'B4'), 'wb').write(bank4())
        open(os.path.join(out, 'B5'), 'wb').write(bank5())
        open(os.path.join(out, 'B7'), 'wb').write(G.build7())
    else:
        files.update({'mapgen.inc': mapgen_inc(), 'neartab.inc': neartab_inc()})
    if NU.enabled():
        files['pal.inc'] = pal_inc()
    for name, lines in files.items():
        open(os.path.join(out, name), 'w').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
