#!/usr/bin/env python3
"""The landscape's tables, for sideways RAM (bank 4, $8000-$BFFF), from proto/land.py:

    python3 tools/landgen.py OUTDIR   -> OUTDIR/TABLES (16K, loaded to $8000)
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
  FPSL, FPSH + s          4000 / s: the readout's frames a second (tenths), s the
                          vertical syncs of the last 8 frames
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'proto'))
import land as L      # noqa: E402
import swatch35 as SW  # noqa: E402

BASE = 0x8000
ADDR = dict(MAP=0x8000, SYT=0x9000, VX0=0x9400, VX1=0x9800, VX2=0x9C00, LERP=0xA000,
            PINL=0xA200, PINR=0xA240, RLO=0xA280, RHI=0xA2C0, DE=0xA300, DO=0xA340,
            LANDT=0xA380, SEAT=0xA390, FPSL=0xA400, FPSH=0xA500, DQT=0xA600, DRT=0xAE00)
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
    for s in range(256):
        f = (4000 + s // 2) // s if s else 0       # frames a second, tenths, over 8 frames
        put('FPSL', s, f)
        put('FPSH', s, f >> 8)
    return img


def main():
    out = sys.argv[1]
    open(os.path.join(out, 'TABLES'), 'wb').write(build())
    with open(os.path.join(out, 'tables.inc'), 'w') as f:
        f.write('; tools/landgen.py\n')
        for k, v in ADDR.items():
            f.write(f'{k:8s}= ${v:04X}\n')
        consts = dict(MAPSZ=L.MAP, HMAX=L.HMAX, SEA=L.SEA, NDI=NDI, BLACK=34)
        for k, v in consts.items():
            f.write(f'{k:8s}= {v}\n')


if __name__ == '__main__':
    main()
