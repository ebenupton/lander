#!/usr/bin/env python3
"""The landscape's tables, for sideways RAM (bank 4, $8000-$BFFF), from proto/land.py:

    python3 tools/landgen.py OUTDIR   -> OUTDIR/TABLES (16K, loaded to $8000)
                                         OUTDIR/TABLES2 (bank 5: the tiles' colours)
                                         OUTDIR/tables.inc (their addresses, constants)

A depth index di = (d - ZNEAR) / 16 (0..56: every row's depth is a multiple of 16) and
r = recip(d) give a row everything it needs:
  SYT    + di*16 + h      screen y of a corner of height h (0..HMAX)
  VX0/1/2 + di*16 + cxs   the first inner column's x, 8.16 with 128 << 16 added, for
                          the camera's step cxs in its tile (the column at tile
                          cxt - 3 + (cxs > 0)); each next column adds r << 8
  RLO, RHI + di           r
  PINL, PINR + di         the pinned columns' x
And:
  MAP + z*64 + x          a tile corner's height (bits 0-3) and its tile's colour pick
                          (bits 4-7: LANDT or SEAT gives the palette entry)
  LERP + (b-a+12)*16 + q  (b - a) * q / 16, rounded as land.lerp (q: 16ths of a tile)
  DE, DO + palette entry  a dither's bytes on even and odd lines (swatch35 numbering)
  DQT, DRT + a*64 + D    D div 2a, D mod 2a (a 1..31, D 0..63)
  COLO, COLQ + cxs*16 + i the camera's x step's column i: tile (from cxt) and
                          sixteenths; NPT + cxs: how many
  ROWO, ROWQ, ROWD + czs*8 + r  its z step's row r (far to near): tile (from
                          czt), sixteenths, depth index; NRT + czs: how many
  LERPQ + q*32 + d + 12   LERP by q first
  FPSL, FPSH + s          4000 / s: the readout's frames a second (tenths), s the
                          vertical syncs of the last 8 frames
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'proto'))
import land as L      # noqa: E402
import swatch35 as SW  # noqa: E402

BASE = 0x8000
ADDR = dict(MAP=0x8000, MRL=0xBC00, MRH=0xBC40, SYPL=0xBC80, SYPH=0xBCC0, SYT=0x9000, VX0=0x9400, VX1=0x9800, VX2=0x9C00, LERP=0xA000,
            PINL=0xA200, PINR=0xA240, RLO=0xA280, RHI=0xA2C0, DE=0xA300, DO=0xA340,
            LANDT=0xA380, SEAT=0xA390, FPSL=0xA400, FPSH=0xA500, DQT=0xA600, DRT=0xAE00,
            COLO=0xB600, COLQ=0xB700, ROWO=0xB800, ROWQ=0xB880, ROWD=0xB900,
            NPT=0xB980, NRT=0xB990, LERPQ=0xBA00)
NDI = (L.ZFAR - L.ZNEAR) // 16 + 1


def dither_bytes(entry):
    """MODE 1 bytes (even line, odd line) of swatch35's entry: pixel p's colour at
    (p & 1, line & 1); logical colour bits at 7-p and 3-p."""
    cl = SW.cell(*SW.ALL[entry])
    out = []
    for row in range(2):
        v = 0
        for p in range(4):
            col = cl[(p & 1, row)]
            v |= ((col >> 1) << (7 - p)) | ((col & 1) << (3 - p))
        out.append(v)
    return out


def build():
    img = bytearray(0x4000)

    def put(name, off, val):
        img[ADDR[name] - BASE + off] = val & 255

    hm, _ = L.heightmap()
    for z in range(L.MAP):
        for x in range(L.MAP):
            put('MAP', z * 64 + x, int(hm[z, x]) | (int(L.TILERND[z, x]) << 4))
    for di in range(NDI):
        d = L.ZNEAR + 16 * di
        r = L.recip(d)
        for h in range(L.HMAX + 1):
            put('SYT', di * 16 + h, L.HORIZON + (((L.CAMH - h) * r + L.HSCALE * 128) // (L.HSCALE * 256)))
        for cxs in range(16):
            xoff = (-3 + (cxs > 0)) * 256 - 16 * cxs
            v = xoff * r + 32768 + (128 << 16)
            assert 0 <= v < 1 << 24
            for k, nm in enumerate(('VX0', 'VX1', 'VX2')):
                put(nm, di * 16 + cxs, v >> (8 * k))
        put('RLO', di, r)
        put('RHI', di, r >> 8)
        put('PINL', di, 128 + ((-L.W * r + 32768) >> 16))
        put('PINR', di, 128 + ((L.W * r + 32768) >> 16))
    for d in range(-12, 13):
        for q in range(16):
            put('LERP', (d + 12) * 16 + q, L.lerp(0, d, 16 * q))
    for e in range(35):
        de, do = dither_bytes(e)
        put('DE', e, de)
        put('DO', e, do)
    for r in range(16):
        put('LANDT', r, L.LAND[r % len(L.LAND)])
        put('SEAT', r, L.SEAC[r % len(L.SEAC)])
    for a in range(1, 32):
        for d in range(64):
            put('DQT', a * 64 + d, d // (2 * a))
            put('DRT', a * 64 + d, d % (2 * a))
    for cxs in range(16):                   # the columns for the camera's x step
        xs = L.grid_lines(16 * cxs - L.W, 16 * cxs + L.W)
        put('NPT', cxs, len(xs))
        for i, x in enumerate(xs):
            put('COLO', cxs * 16 + i, x >> 8)
            put('COLQ', cxs * 16 + i, (x & 255) // 16)
    for czs in range(16):                   # the rows (far to near) for its z step
        zs = L.grid_lines(16 * czs + L.ZNEAR, 16 * czs + L.ZFAR)[::-1]
        put('NRT', czs, len(zs))
        for r, z in enumerate(zs):
            put('ROWO', czs * 8 + r, z >> 8)
            put('ROWQ', czs * 8 + r, (z & 255) // 16)
            put('ROWD', czs * 8 + r, (z - 16 * czs - L.ZNEAR) // 16)
    for di in range(NDI):
        put('SYPL', di, (ADDR['SYT'] + di * 16) & 255)
        put('SYPH', di, (ADDR['SYT'] + di * 16) >> 8)
    for z in range(64):
        put('MRL', z, (ADDR['MAP'] + z * 64) & 255)
        put('MRH', z, (ADDR['MAP'] + z * 64) >> 8)
    for q in range(16):
        for d in range(-12, 13):
            put('LERPQ', q * 32 + d + 12, L.lerp(0, d, 16 * q))
    for s in range(256):
        f = (4000 + s // 2) // s if s else 0       # frames a second, tenths, over 8 frames
        put('FPSL', s, f)
        put('FPSH', s, f >> 8)
    return img


def build2():
    """Bank 5: each tile's colour (land.colour: the sea set if both its front
    corners are at sea level), as its dither's bytes: CMAPE, CMAPO + z*64 + x."""
    img = bytearray(0x4000)
    hm = L.heightmap()
    for z in range(L.MAP):
        for x in range(L.MAP):
            de, do = dither_bytes(L.colour(hm, x, z, 0, 0))
            img[ADDR2['CMAPE'] - BASE + z * 64 + x] = de
            img[ADDR2['CMAPO'] - BASE + z * 64 + x] = do
    for di in range(NDI):                   # PXT + di*128 + cxs*8 + i: inner column
        r = L.recip(L.ZNEAR + 16 * di)      # i's x (1..7) at depth di, x step cxs
        for cxs in range(16):
            xs = L.grid_lines(16 * cxs - L.W, 16 * cxs + L.W)
            for i in range(1, len(xs) - 1):
                img[ADDR2['PXT'] - BASE + di * 128 + cxs * 8 + i] = \
                    128 + (((xs[i] - 16 * cxs) * r + 32768) >> 16)
    return img


ADDR2 = dict(CMAPE=0x8000, CMAPO=0x9000, PXT=0xA000)


def main():
    out = sys.argv[1]
    open(os.path.join(out, 'TABLES'), 'wb').write(build())
    open(os.path.join(out, 'TABLES2'), 'wb').write(build2())
    with open(os.path.join(out, 'tables.inc'), 'w') as f:
        f.write('; tools/landgen.py\n')
        for k, v in list(ADDR.items()) + list(ADDR2.items()):
            f.write(f'{k:8s}= ${v:04X}\n')
        consts = dict(MAPSZ=L.MAP, HMAX=L.HMAX, SEA=L.SEA, NDI=NDI, BLACK=34)
        for k, v in consts.items():
            f.write(f'{k:8s}= {v}\n')


if __name__ == '__main__':
    main()
