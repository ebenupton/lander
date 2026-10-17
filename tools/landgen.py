#!/usr/bin/env python3
"""The landscape renderer's sideways RAM tables (src/land.s), from proto/land.py's model.

    python3 tools/landgen.py OUTDIR  ->  OUTDIR/TABLES      bank 4 (16K, at $8000)
                                         OUTDIR/TABLES2     bank 5: the tiles' colours
                                         OUTDIR/TABLES7     bank 7: the projection
                                         OUTDIR/tables.inc  the addresses and constants
                                         OUTDIR/mode2.inc   (MODE 2 builds) YELB, MAGB,
                                                            NULAPAL, NFONTCH, NFONT

Every table is a 16K image's bytes at its bank address; build.sh then merges land.s's
bank code segments into the space the tables leave.  Also imported by tools/shipgen.py
and the tests for dither_bytes.

Bank 4 (TABLES), by address:
  MAP + 64 z + x          corner (x, z)'s height, 0..HMAX, in bits 0-3 (land.heightmap);
                          bits 4-7 a random nibble (land.TILERND) that nothing reads.  land.s
                          reads a row through MRL, MRH and masks to the height.
  TPE[t], TPO[t] pages    run2's store tables, by t = 2 screen + half (the screens at
                          $3000, $5800; a half the left or right 32 of a row's 64 byte
                          columns): at page*256 + R2OFF + 3 k the entry for even line YSKY
                          + 2 k (TPE) or odd line YSKY + 1 + 2 k (TPO), k 0..R2N-1: STA
                          addr,Y with addr the line's screen address ($3000 + $2800 screen
                          + $100 half + $200 (y >> 3) + (y & 7); Y = (8 column) & 255, the
                          column's byte in the half); at page*256 + 255 (k = R2N) an RTS,
                          the slot after the last line's (YGND+1's in TPE, YGND+2's in
                          TPO).  Entered at line X's entry it stores to every line of X's
                          parity up to an RTS the code plants at line Y's.  The first
                          R2OFF bytes of each page are free (build.sh's code segments,
                          TL6, TL7).
  RSMT + y                (y & ~7) - 1: the line before y's character row (fsplit's);
                          y YSKY..YGND+2.
  TBLK4, TBLK5            traceb's fills into ROWA ($0400) and ROWB ($0500): TNB stores
                          STA page*256-k,X for k = TNB down to 1 (3 bytes each), then a
                          JMP whose operand (t_back) land.s's init writes.  Entered at its
                          n'th store from the end it fills X-n .. X-1.
  TENL, TENH4, TENH5 + n  the entry for n stores, n 0..TNB: TBLK + 3 (TNB - n), its low
                          byte and its page (TBLK4's, TBLK5's).
  FPSL, FPSH + s          (4000 + s/2) / s (0 at s 0): the readout's frames a second in
                          tenths, s the vertical syncs of the last 8 frames.
  DQT, DRT + 64 a + D     D div a, and 2 (D mod a); a 1..31, D 0..63 (row 0 free: TR5, TL5).
  DVH, DVR, DVL + a       DQT's and DRT's row a: its page in each, and 64 a's low byte
                          (ORed with D).
  MRL, MRH + z            MAP + 64 z, low byte and page; z 0..63.
  CLMP1 + d               d + 1 as a signed byte, clamped to 0..4 (a rung's position in
                          its byte column: d = TX - x4 - 1).
  DIV4 + x                x >> 2: pixel x's byte column.
  TRk, TLk                the rungs' fast way: a rung of a pixels (a <= RFA) spanning D
                          lines (D < 16) from its top line yt; at + 16 (RFA - a) + D the
                          transition of its k'th pixel (k < a), lines below yt:
                          ceil(D (2 j - 1) / (2 a)), j = k + 1 leaning right (TRk) or a - k
                          leaning left (TLk).  TRk and TLk hold 16 (RFA - k) bytes, in gaps
                          between the tables.

Bank 5 (TABLES2):
  CMAPE, CMAPO + 64 z + x tile (x, z)'s colour (land.colour: sea if its four corners are
                          at sea level, the pad PADC, else land, lit) as its dither's even
                          and odd bytes (pcol5's: the strips' boxes' bytes).
  The arc build's instead, its colours Lander's, brightened by the row (land.colour):
  CMAPE + 64 z + x        16 kind + slope (land.arc_tile), CMAPO not made.
  CTE, CTO + 16 kind + b  (kind, b)'s bytes, even and odd lines (proto/nula.py's entry
                          LENT + 16 kind + b); kind 0..8, b 0..15.  At $9100 - ZBACK and
                          $9300 - ZBACK: crow indexes CTE by the class from the page's
                          start plus j - ZBACK (j the row, 3..13), a byte below 256.

Bank 7 (TABLES7), by a row's depth index di.  Corner row j (0..NZ-1, far to near: map
row czt + ZBACK - j) is at depth d = 256 (ZBACK - j) - 16 czs, 8.8 tiles; di = d/16 - DI0,
DI0 the nearest (j NZ-1, czs 15), NDI of them; r = land.recip(d), pixels a tile, 8.8.
  R7L, R7H + di           r's low and high bytes.
  SYT7 + 32 di + v        screen y of a corner at height h = v - HMAX + hg, hg the ground
                          under the ship, v 0..2 HMAX: HORIZON + ((CAMH + hg - h) r + 2048)
                          / 4096 (land.project's sy, the camera at CAMH; raised, EYV is
                          added).  land.s points syp at SYT7 + 32 di + HMAX - hg and
                          indexes by h.
  SYL7, SYH7 + di         32 di's low byte, and SYT7 + 32 di's page.
  B1T + 32 di + 2 cxs     the row's x's.  Corner i (0..NX-1) is at map column cxt - 4 + i;
                          corners 1..NX-2 are drawn, 0 and NX-1 replaced by the clip
                          planes' points.  B_i = B_1 + (i - 1) r is 256 times corner i's
                          screen x (B_0 = 256 XC + ((dx0 r + 32768) >> 8), dx0 = -1152 -
                          16 cxs: corner 0's x from the camera, 8.8 tiles; B_1 = B_0 + r).
                          Byte 1: B_1 >> 8, corner 1's x.  Byte 0: bit k set if B_{k+1}'s
                          low byte carries when r's is added, so corner k+2's x is corner
                          k+1's + (r >> 8) + bit k, k 0..NX-4.  B_1 + (i - 1) r < 65536
                          for i to NX-2 (asserted: no carry out of the high byte).
  PINL7, PINR7 + di       x of the clip planes XCLIP tiles left and right of the camera:
                          XC + ((-+XCLIP r + 32768) >> 16); corners 0 and NX-1's.
  CLP7 + di               1 if that row overhangs the screen (PINL7 < XL or PINR7 > XR):
                          exactly di < NCLP (asserted).  Nothing reads it; NCLP is in a
                          land.s assert.
  LERPQ7 + 32 q + d + LQOFF  land.lerp(0, d, 16 q) - 1, q 0..15, d -15..15: adding a with
                          C set to the entry at d = b - a gives lerp(a, b, 16 q); land.s
                          indexes by (b | 16) - a - 1 (b < 16).  The edges' heights (q cxs),
                          the clip rows' (16 - czs), the ground's (hgnd).
  LQLO, LQHI + q          LERPQ7 + 32 q, low byte and page.
  PXF7, PXN7 + 11 cxs + i the x's of the far clip plane's row (di 16 ZFCLIP - DI0) and the
                          near's (16 ZCLIP - DI0), fixed but for cxs: PINL7, corners 1..NX-2
                          by B1T, PINR7; i 0..NX-1.  Neither overhangs the screen (asserted).

tables.inc: every address above (CTE, CTO in the arc build alone), then TNB, HMAX,
NDI, NX (the drawn corners: land.NX less 2 XSKIP), XSKIP, NZ, ZBACK, ZSKIP, ZCLIP,
ZFCLIP, DI0, NCLP, XL, XR, LQOFF, ZSHIP, CAMH, EMAX, PADN, PADH, HORIZON, YSKY, YGND,
R2OFF, RFA, EYS (255 less the greatest SYT7 entry: the least camera raise EYV at which
a corner's y could pass 254, satrow's), TPE0-3, TPO0-3.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'proto'))
import land as L      # noqa: E402
import frame as FR    # noqa: E402
import swatch35 as SW  # noqa: E402
import nula as NU     # noqa: E402

BASE = 0x8000
YSKY, YGND = FR.YSKY, FR.YGND
ADDR = dict(MAP=0x8000, MRL=0xBC00, MRH=0xBC40, FPSL=0xA400, FPSH=0xA500, DQT=0xA600, DRT=0xAE00,
            DVH=0xBD00, DVR=0xBD20, DVL=0xBD40, CLMP1=0xBE00, DIV4=0xBF00,
            TBLK4=0x9B00, TBLK5=0x9D00, TENL=0x9F00, TENH4=0xA000, TENH5=0xA100,
            RSMT=0x9A00 + 97 - YSKY,
            TR0=0xBA62, TR1=0xBC80, TR2=0xBD60, TR3=0x9C83, TR4=0x9F81, TR5=0xA600,
            TR6=0xBDD0, TR7=0x9FD1, TR8=0xA2F0,
            TL0=0xBB63, TL1=0xA200, TL2=0xA280, TL3=0x9E83, TL4=0xA3A0, TL5=0xAE00,
            TL6=0x9300, TL7=0x9330, TL8=0xA3F0)
ADDR2 = dict(CMAPE=0x8000, CMAPO=0x9000)
ADDRA = dict(CTE=0x9100 - L.ZBACK, CTO=0x9300 - L.ZBACK)     # the arc build's (CMAPO's room)
ADDR7 = dict(R7L=0x8000, R7H=0x8100, SYT7=0x8200, B1T=0x9800,
             CLP7=0xAE00, PINL7=0xAF00, PINR7=0xB000, LERPQ7=0xB100, SYL7=0xB300, SYH7=0xB3B0,
             LQLO=0xB460, LQHI=0xB470, PXF7=0xBEA0, PXN7=0xBF50)
RFA = 9                                     # the rungs' fast way: rungs of up to RFA pixels
TPE = (0x90, 0x91, 0x92, 0x93)              # run2's store-table pages: the even lines' by t,
TPO = (0xB6, 0xB7, 0xB8, 0xB9)              # and the odd lines'
R2N = (YGND + 1 - YSKY) // 2                # lines in each
R2OFF = 255 - 3 * R2N                       # the first entry's offset: the RTS at 255
TNB = 128                                   # traceb's longest fill
DI0 = (L.ZBACK - L.NZ + 1) * 16 - 15        # the nearest row's d/16
NDI = L.ZBACK * 16 - DI0 + 1                # depth indices: to the farthest (j 0, czs 0)
NCLP = 4                                    # the rows that overhang the screen: di < NCLP
NXD = L.NX - 2 * L.XSKIP                    # the corners drawn in a row (tables.inc's NX)
LQOFF = 15                                  # LERPQ7's offset for d = -15
assert YSKY % 2 == 0 and YGND % 2 == 1 and R2OFF > 0 and NDI <= 176


def dither_bytes(entry):
    """The MODE 1 bytes (even line, odd line) of swatch35 dither `entry`: pixel p (0..3)
    takes the cell's ink at (p & 1, line & 1); its colour's high bit is bit 7 - p of the
    byte, its low bit 3 - p.  A MODE 2 build's: proto/nula.py's dither_bytes."""
    if NU.enabled():
        return NU.dither_bytes(entry)
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
    """Bank 4's image (TABLES): the module docstring's tables, at ADDR."""
    img = bytearray(0x4000)

    def put(name, off, val):
        img[ADDR[name] - BASE + off] = val & 255

    hm, _ = L.heightmap()
    for z in range(L.MAP):
        for x in range(L.MAP):
            put('MAP', z * 64 + x, int(hm[z, x]) | (int(L.TILERND[z, x]) << 4))
    for a in range(1, 32):
        for d in range(64):
            put('DQT', a * 64 + d, d // a)
            put('DRT', a * 64 + d, 2 * (d % a))
        put('DVH', a, (ADDR['DQT'] + a * 64) >> 8)
        put('DVR', a, (ADDR['DRT'] + a * 64) >> 8)
        put('DVL', a, (a * 64) & 255)
    for z in range(64):
        put('MRL', z, (ADDR['MAP'] + z * 64) & 255)
        put('MRH', z, (ADDR['MAP'] + z * 64) >> 8)
    for s in range(256):
        f = (4000 + s // 2) // s if s else 0
        put('FPSL', s, f)
        put('FPSH', s, f >> 8)
    for d in range(256):
        v = (d + 1) & 255
        put('CLMP1', d, 0 if v >= 128 else min(v, 4))
    for d in range(256):
        put('DIV4', d, d >> 2)
    for blk, pg, enh in (('TBLK4', 4, 'TENH4'), ('TBLK5', 5, 'TENH5')):
        for k in range(TNB, 0, -1):
            a = pg * 256 - k
            o = 3 * (TNB - k)
            put(blk, o, 0x9D)                           # STA abs,X
            put(blk, o + 1, a & 255)
            put(blk, o + 2, a >> 8)
        put(blk, 3 * TNB, 0x4C)                         # JMP (operand: land.s's init)
        for n in range(TNB + 1):
            e = ADDR[blk] + 3 * (TNB - n)
            put('TENL', n, e & 255)
            put(enh, n, e >> 8)
    for y in range(YSKY, YGND + 3):
        put('RSMT', y, (y & 0xF8) - 1)
    for t in range(4):
        for y in range(YSKY, YGND + 1):
            a = 0x3000 + 0x2800 * (t >> 1) + 256 * (t & 1) + 512 * (y >> 3) + (y & 7)
            pg = TPE[t] if y % 2 == 0 else TPO[t]
            o = pg * 256 + R2OFF + 3 * ((y - YSKY) // 2) - BASE
            assert not any(img[o:o + 3])
            img[o:o + 3] = bytes([0x99, a & 255, a >> 8])    # STA abs,Y
        for pg in (TPE[t], TPO[t]):
            assert not img[pg * 256 + 255 - BASE]
            img[pg * 256 + 255 - BASE] = 0x60               # RTS
    for k in range(RFA):
        for side in 'RL':
            o = ADDR[f'T{side}{k}'] - BASE
            n = 16 * (RFA - k)
            assert not any(img[o:o + n]) and (o & 255) + n <= 256, (side, k)
            for a in range(k + 1, RFA + 1):
                j = k + 1 if side == 'R' else a - k
                for d in range(16):
                    img[o + 16 * (RFA - a) + d] = -(-d * (2 * j - 1) // (2 * a))
    return img


def build2():
    """Bank 5's image (TABLES2): CMAPE, CMAPO, each tile's colour as its dither's bytes;
    the arc build's CMAPE, CTE, CTO (the module docstring)."""
    img = bytearray(0x4000)
    hm = L.heightmap()
    if NU.arc():
        for z in range(L.MAP):
            for x in range(L.MAP):
                k, s = L.arc_tile(hm, x, z)
                img[ADDR2['CMAPE'] - BASE + z * 64 + x] = 16 * k + s
        for e in range(NU.LENT, NU.NENT):
            de, do = dither_bytes(e)
            img[ADDRA['CTE'] - BASE + e - NU.LENT] = de
            img[ADDRA['CTO'] - BASE + e - NU.LENT] = do
        return img
    for z in range(L.MAP):
        for x in range(L.MAP):
            de, do = dither_bytes(L.colour(hm, x, z, 0, 0))
            img[ADDR2['CMAPE'] - BASE + z * 64 + x] = de
            img[ADDR2['CMAPO'] - BASE + z * 64 + x] = do
    return img


def build7():
    """Bank 7's image (TABLES7): the projection by depth index, at ADDR7."""
    img = bytearray(0x4000)

    def put(name, off, val):
        img[ADDR7[name] - BASE + off] = val & 255

    b1s = {}
    for di in range(NDI):
        d = (DI0 + di) * 16
        r = L.recip(d)
        put('R7L', di, r)
        put('R7H', di, r >> 8)
        for v in range(2 * L.HMAX + 1):
            put('SYT7', di * 32 + v, L.HORIZON + (((L.CAMH - (v - L.HMAX)) * r + L.HSCALE * 128) // (L.HSCALE * 256)))
        put('SYL7', di, di * 32)
        put('SYH7', di, (ADDR7['SYT7'] + di * 32) >> 8)
        for cxs in range(16):
            dx0 = (L.XSKIP - 5) * 256 - cxs * 16 - 128
            b0 = ((dx0 * r + 32768) >> 8) + L.XC * 256
            b1 = (b0 + r) & 0xFFFF
            assert all(b1 + (i - 1) * r < 65536 for i in range(1, NXD - 1))
            cm = sum((((b1 & 255) + (k - 1) * (r & 255)) & 255) + (r & 255) > 255 and 1 << (k - 1) or 0
                     for k in range(1, NXD - 2))
            assert all(((b1 >> 8) + (i - 1) * (r >> 8) + bin(cm & ((1 << (i - 1)) - 1)).count('1')) == (b1 + (i - 1) * r) >> 8
                       for i in range(1, NXD - 1))
            b1s[di, cxs] = b1
            put('B1T', di * 32 + 2 * cxs, cm)
            put('B1T', di * 32 + 2 * cxs + 1, b1 >> 8)
        pl = L.XC + ((-L.XCLIP * r + 32768) >> 16)
        pr = L.XC + ((L.XCLIP * r + 32768) >> 16)
        put('PINL7', di, pl)
        put('PINR7', di, pr)
        put('CLP7', di, 1 if pl < L.XL or pr > L.XR else 0)
        for row, dic in (('PXF7', L.ZFCLIP * 16 - DI0), ('PXN7', L.ZCLIP * 16 - DI0)):
            if di == dic:
                assert not (pl < L.XL or pr > L.XR)
                for cxs in range(16):
                    b1 = b1s[di, cxs]
                    xs = [pl] + [(b1 + (i - 1) * r) >> 8 for i in range(1, NXD - 1)] + [pr]
                    for i, x in enumerate(xs):
                        put(row, 11 * cxs + i, x)
    clp = [img[ADDR7['CLP7'] - BASE + di] for di in range(NDI)]
    assert clp == [1] * NCLP + [0] * (NDI - NCLP), 'CLP7: di < NCLP'
    for q in range(16):
        put('LQLO', q, ADDR7['LERPQ7'] + 32 * q)
        put('LQHI', q, (ADDR7['LERPQ7'] + 32 * q) >> 8)
        for d in range(-15, 16):
            put('LERPQ7', q * 32 + d + LQOFF, L.lerp(0, d, 16 * q) - 1)
    return img


def main():
    """Write the three images, tables.inc and, in a MODE 2 build, mode2.inc to the
    directory named on the command line."""
    out = sys.argv[1]
    open(os.path.join(out, 'TABLES'), 'wb').write(build())
    open(os.path.join(out, 'TABLES2'), 'wb').write(build2())
    open(os.path.join(out, 'TABLES7'), 'wb').write(build7())
    EYS = 255 - max(L.HORIZON + (((L.CAMH + L.HMAX) * L.recip((DI0 + di) * 16) + L.HSCALE * 128)
                                  // (L.HSCALE * 256)) for di in range(NDI))
    with open(os.path.join(out, 'tables.inc'), 'w') as f:
        f.write('; tools/landgen.py\n')
        for k, v in list(ADDR.items()) + list(ADDR2.items()) + list(ADDR7.items()) + (list(ADDRA.items()) if NU.arc() else []):
            f.write(f'{k:8s}= ${v:04X}\n')
        consts = dict(TNB=TNB, HMAX=L.HMAX, NDI=NDI, NX=NXD, XSKIP=L.XSKIP, NZ=L.NZ, ZBACK=L.ZBACK,
                      ZSKIP=L.ZSKIP, ZCLIP=L.ZCLIP, ZFCLIP=L.ZFCLIP, DI0=DI0, NCLP=NCLP, XL=L.XL, XR=L.XR,
                      LQOFF=LQOFF, ZSHIP=L.ZSHIP, CAMH=L.CAMH, EMAX=L.EMAX, PADN=L.PADN, PADH=L.PADH,
                      HORIZON=L.HORIZON, YSKY=YSKY, YGND=YGND, R2OFF=R2OFF, RFA=RFA, EYS=EYS,
                      TPE0=TPE[0], TPE1=TPE[1], TPE2=TPE[2], TPE3=TPE[3],
                      TPO0=TPO[0], TPO1=TPO[1], TPO2=TPO[2], TPO3=TPO[3])
        for k, v in consts.items():
            f.write(f'{k:8s}= {v}\n')
    if NU.enabled():                # mode2.inc: the MODE 2 builds' colour bytes, letters
        with open(os.path.join(out, 'mode2.inc'), 'w') as f:      # and NULA palette
            f.write('; tools/landgen.py: proto/nula.py\'s colours\n')
            f.write(f'YELB    = ${NU.yelb():02X}\nMAGB    = ${NU.magb():02X}\n')
            f.write('.macro NULAPAL\n')
            for c, (r, g, b) in enumerate(NU.PAL):
                f.write(f'        .byte ${c << 4 | r:02X}, ${g << 4 | b:02X}\n')
            f.write('.endmacro\n')
            chars = ''.join(NU.FONT)
            f.write('.macro NFONTCH\n        .byte ' + ', '.join(f'${ord(c):02X}' for c in chars) + '\n.endmacro\n')
            f.write('.macro NFONT\n')
            for c in chars:
                f.write('        .byte ' + ', '.join(f'${v:02X}' for v in NU.font_rows(c)) + f'  ; {c!r}\n')
            f.write('.endmacro\n')


if __name__ == '__main__':
    main()
