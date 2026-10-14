#!/usr/bin/env python3
"""The landscape's tables, for sideways RAM, from proto/land.py and proto/frame.py:

    python3 tools/landgen.py OUTDIR   -> OUTDIR/TABLES (bank 4, 16K, loaded to $8000)
                                         OUTDIR/TABLES2 (bank 5: the tiles' colours)
                                         OUTDIR/TABLES7 (bank 7: the projection)
                                         OUTDIR/tables.inc (their addresses, constants)

Bank 7, by a row's depth index di = d/16 - DI0 (d its depth, 8.8 tiles: (20 - j)*256
- 16*czs, so di 0..NDI-1) and r = land.recip(d) (pixels a tile, 8.8):
  R7L, R7H + di           r
  SYT7 + di*16 + h        screen y of a corner of height h (0..HMAX), YLIM at most
  B0L, B0H, B0X + di*16 + cxs  the row's first corner's x * 256 (24 bits, signed),
                          XC on: corner i's x is (B0 + i*r) >> 8
  CLP + di*16 + cxs       1 if the row overhangs the screen (corner 0 left of 0, or
                          12 right of XR): clipped
Bank 4:
  MAP + z*64 + x          a tile corner's height (bits 0-3) and its tile's colour pick
                          (bits 4-7: LANDT or SEAT gives the palette entry)
  MRL, MRH + z            map row z's address
  DE, DO + palette entry  a dither's bytes on even and odd lines (swatch35 numbering)
  DQT, DRT + a*64 + D    D div a, 2 (D mod a) (a 1..31, D 0..63); DVH, DVR, DVL + a:
                          its row's pages and offset
  FPSL, FPSH + s          4000 / s: the readout's frames a second (tenths), s the
                          vertical syncs of the last 8 frames
  run2's store tables (TPE, TPO pages, from R2OFF), EIN, RSMT: by line, YSKY..YGND+2
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'proto'))
import land as L      # noqa: E402
import frame as FR    # noqa: E402
import swatch35 as SW  # noqa: E402

BASE = 0x8000
YSKY, YGND = FR.YSKY, FR.YGND
ADDR = dict(MAP=0x8000, MRL=0xBC00, MRH=0xBC40, DE=0xA300, DO=0xA340,
            LANDT=0xA380, SEAT=0xA390, FPSL=0xA400, FPSH=0xA500, DQT=0xA600, DRT=0xAE00,
            DVH=0xBD00, DVR=0xBD20, DVL=0xBD40, CLMP1=0xBE00, DIV4=0xBF00,
            TBLK4=0x9B00, TBLK5=0x9D00, TENL=0x9F00, TENH4=0xA000, TENH5=0xA100,
            RSMT=0xBA00 - YSKY, EIN=0xBB00 - (YSKY - 1))
# run2's store tables: by t (2 screen + half), the even lines' on page TPE[t], the odd
# lines' on TPO[t], from R2OFF, the end line's slot (an RTS) at $FF
TPE = (0x90, 0x91, 0x92, 0x93)
TPO = (0xB6, 0xB7, 0xB8, 0xB9)
R2N = (YGND + 1 - YSKY) // 2                # each table's lines
R2OFF = 255 - 3 * R2N
TNB = 128
DI0 = (L.ZBACK - L.NZ + 1) * 16 - 15        # the least depth / 16: the near row, fz 15
NDI = L.ZBACK * 16 - DI0 + 1
ADDR7 = dict(R7L=0x8000, R7H=0x8100, SYT7=0x8200, B0L=0x8D00, B0H=0x9800, B0X=0xA300,
             CLP=0xAE00)
assert YSKY % 2 == 0 and YGND % 2 == 1 and R2OFF > 0 and NDI <= 176


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
    for e in range(35):
        de, do = dither_bytes(e)
        put('DE', e, de)
        put('DO', e, do)
    for r in range(16):
        put('LANDT', r, L.LAND[r % len(L.LAND)])
        put('SEAT', r, L.SEAC[r % len(L.SEAC)])
    for a in range(1, 32):
        for d in range(64):
            put('DQT', a * 64 + d, d // a)
            put('DRT', a * 64 + d, 2 * (d % a))    # 2r: r2 directly
        put('DVH', a, (ADDR['DQT'] + a * 64) >> 8)
        put('DVR', a, (ADDR['DRT'] + a * 64) >> 8)
        put('DVL', a, (a * 64) & 255)
    for z in range(64):
        put('MRL', z, (ADDR['MAP'] + z * 64) & 255)
        put('MRH', z, (ADDR['MAP'] + z * 64) >> 8)
    for s in range(256):
        f = (4000 + s // 2) // s if s else 0       # frames a second, tenths, over 8 frames
        put('FPSL', s, f)
        put('FPSH', s, f >> 8)
    for d in range(256):                    # fsplit's: d + 1 (signed) clamped to 0..4
        v = (d + 1) & 255
        put('CLMP1', d, 0 if v >= 128 else min(v, 4))
    for d in range(256):                    # record's, nearpost's: x4's column
        put('DIV4', d, d >> 2)
    for blk, pg, enh in (('TBLK4', 4, 'TENH4'), ('TBLK5', 5, 'TENH5')):
        # traceb's fills: STA page*256-k,X for k = TNB..1, then JMP (init: t_back);
        # entered at L stores before the JMP: X - L .. X - 1
        for k in range(TNB, 0, -1):
            a = pg * 256 - k
            o = 3 * (TNB - k)
            put(blk, o, 0x9D)
            put(blk, o + 1, a & 255)
            put(blk, o + 2, a >> 8)
        put(blk, 3 * TNB, 0x4C)
        for n in range(TNB + 1):
            e = ADDR[blk] + 3 * (TNB - n)
            put('TENL', n, e & 255)
            put(enh, n, e >> 8)
    for y in range(YSKY, YGND + 3):         # fsplit's: each line's row's first line - 1
        put('RSMT', y, (y & 0xF8) - 1)
    # run2's: STA addr(y),Y for the even lines YSKY..YGND-1, then YGND+1's slot (RTS);
    # the odd lines YSKY+1..YGND, then YGND+2's; EIN by line y: the low byte of the
    # first even line's at or after y (EIN - 1 by y: the first odd line's at or after y)
    for t in range(4):
        for y in range(YSKY, YGND + 1):
            a = 0x3000 + 0x2800 * (t >> 1) + 256 * (t & 1) + 512 * (y >> 3) + (y & 7)
            pg = TPE[t] if y % 2 == 0 else TPO[t]
            o = pg * 256 + R2OFF + 3 * ((y - YSKY) // 2) - BASE
            assert not any(img[o:o + 3])
            img[o:o + 3] = bytes([0x99, a & 255, a >> 8])
        for pg in (TPE[t], TPO[t]):
            assert not img[pg * 256 + 255 - BASE]
            img[pg * 256 + 255 - BASE] = 0x60
    for y in range(YSKY - 1, YGND + 3):
        put('EIN', y, R2OFF + 3 * ((y + 1) // 2 - YSKY // 2))
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
    return img


ADDR2 = dict(CMAPE=0x8000, CMAPO=0x9000)


def build7():
    """Bank 7: the projection, by depth index (the docstring's)."""
    img = bytearray(0x4000)

    def put(name, off, val):
        img[ADDR7[name] - BASE + off] = val & 255

    for di in range(NDI):
        d = (DI0 + di) * 16
        r = L.recip(d)
        put('R7L', di, r)
        put('R7H', di, r >> 8)
        for h in range(L.HMAX + 1):
            put('SYT7', di * 16 + h, min(L.YLIM, L.HORIZON + (((L.CAMH - h) * r + L.HSCALE * 128) // (L.HSCALE * 256))))
        for cxs in range(16):
            dx0 = (L.XSKIP - 5) * 256 - cxs * 16 - 128        # (the first drawn corner)
            b0 = ((dx0 * r + 32768) >> 8) + L.XC * 256
            put('B0L', di * 16 + cxs, b0)
            put('B0H', di * 16 + cxs, b0 >> 8)
            put('B0X', di * 16 + cxs, b0 >> 16)
            x12 = (b0 + (L.NX - 2 * L.XSKIP - 1) * r) >> 8     # (the last)
            put('CLP', di * 16 + cxs, 1 if (b0 >> 8) < L.XL or x12 > L.XR else 0)
    return img


def main():
    out = sys.argv[1]
    open(os.path.join(out, 'TABLES'), 'wb').write(build())
    open(os.path.join(out, 'TABLES2'), 'wb').write(build2())
    open(os.path.join(out, 'TABLES7'), 'wb').write(build7())
    with open(os.path.join(out, 'tables.inc'), 'w') as f:
        f.write('; tools/landgen.py\n')
        for k, v in list(ADDR.items()) + list(ADDR2.items()) + list(ADDR7.items()):
            f.write(f'{k:8s}= ${v:04X}\n')
        consts = dict(TNB=TNB, MAPSZ=L.MAP, HMAX=L.HMAX, SEA=L.SEA, NDI=NDI, BLACK=34,
                      NX=L.NX - 2 * L.XSKIP, XSKIP=L.XSKIP, NZ=L.NZ, ZBACK=L.ZBACK, ZSKIP=L.ZSKIP, DI0=DI0, XC=L.XC, XL=L.XL, XR=L.XR, YLIM=L.YLIM,
                      YSKY=YSKY, YGND=YGND, R2OFF=R2OFF,
                      TPE0=TPE[0], TPE1=TPE[1], TPE2=TPE[2], TPE3=TPE[3],
                      TPO0=TPO[0], TPO1=TPO[1], TPO2=TPO[2], TPO3=TPO[3])
        for k, v in consts.items():
            f.write(f'{k:8s}= {v}\n')


if __name__ == '__main__':
    main()
