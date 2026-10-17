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

os.environ['LAND_MAP'] = '32'
ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
sys.path.insert(0, os.path.join(ROOT, 'tools'))
sys.path.insert(0, os.path.join(ROOT, 'proto'))
import landgen as G   # noqa: E402
import land as L      # noqa: E402
import gamegen as GG  # noqa: E402

LAND0, LAND1, PANEL = 0x5000, 0x6800, 0x4800
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


def colours():
    """The palette entries the map's tiles use (L.colour's), in order: a tile's colour
    index (its corner's MAP32 byte's high nibble) is its entry's place here."""
    hm = L.heightmap()
    return sorted({L.colour(hm, x, z, 0, 0) for z in range(L.MAP) for x in range(L.MAP)})


def map32():
    """MAP32 + 32 z + x: corner (x, z)'s height (bits 0-3) and tile (x, z)'s colour
    index (bits 4-7)."""
    hm = L.heightmap()
    cols = colours()
    assert len(cols) <= 16
    out = bytearray(0x400)
    for z in range(L.MAP):
        for x in range(L.MAP):
            out[z * 32 + x] = int(hm[0][z, x]) | cols.index(L.colour(hm, x, z, 0, 0)) << 4
    return out


def gametab(out):
    """gametab.inc: tools/gamegen.py's tables less MAPI (the panel's map is drawn at
    the start from MAP32), MAPX, MAPZ for the 32-tile map."""
    GG.main.__globals__['MAPX'] = 16 - L.PADN // 2
    GG.main.__globals__['MAPZ'] = 15 + L.PADN // 2
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


def main():
    out = sys.argv[1]
    gametab(out)
    open(os.path.join(out, 'MAP32'), 'wb').write(map32())
    with open(os.path.join(out, 'b32tab.inc'), 'w') as f:
        f.write('; b32/tools/gen32.py: a colour index\'s dither bytes, even and odd lines\n')
        bs = [G.dither_bytes(e) for e in colours()]
        f.write('DCE:    .byte ' + ', '.join(f'${b[0]:02X}' for b in bs) + '\n')
        f.write('DCO:    .byte ' + ', '.join(f'${b[1]:02X}' for b in bs) + '\n')
        rs = [L.recip((G.DI0 + di) * 16) for di in range(G.NDI)]
        assert max(rs) < 8192
        for nm, sh in (('R7L', 0), ('R7H', 8)):
            f.write(f'{nm}:\n')
            for i in range(0, len(rs), 16):
                f.write('        .byte ' + ', '.join(f'${(r >> sh) & 255:02X}' for r in rs[i:i + 16]) + '\n')
    EYS = 255 - max(L.HORIZON + (((L.CAMH + L.HMAX) * L.recip((G.DI0 + di) * 16) + L.HSCALE * 128)
                                  // (L.HSCALE * 256)) for di in range(G.NDI))
    with open(os.path.join(out, 'tables.inc'), 'w') as f:
        f.write('; b32/tools/gen32.py\n')
        addr = {}
        addr.update(LAND0=LAND0, LAND1=LAND1, PANEL=PANEL)
        for k, v in addr.items():
            f.write(f'{k:8s}= ${v:04X}\n')
        consts = dict(TNB=G.TNB, HMAX=L.HMAX, NDI=G.NDI, NX=G.NXD, XSKIP=L.XSKIP, NZ=L.NZ,
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
