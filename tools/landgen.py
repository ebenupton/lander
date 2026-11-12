#!/usr/bin/env python3
"""The renderer's constants, the dithers' bytes and the projection's tables, from
proto/land.py's model.  A module, not a program: tools/gen.py takes the constants (DI0,
NDI, NXD, NCLP, LQOFF, RFA, YSKY, YGND) and build7(), the sideways RAM build's bank 7
(the 32K build has no such bank: its start makes R7L and R7H, src/tabgen.s);
tools/gen.py, tools/shipgen.py, tools/shipmodel.py and the tests take dither_bytes()
and NU (proto/nula.py, the version's colours: CPC, NULA, ARC in the environment).

Bank 7's tables (ADDR7), by a row's depth index di.  Corner row j (0..NZ-1, far to
near: map row czt + ZBACK - j) is at depth d = 256 (ZBACK - j) - 16 czs, 8.8 tiles; di =
d/16 - DI0, DI0 the nearest (j NZ-1, czs 15), NDI of them; r = land.recip(d), pixels a
tile, 8.8.
  R7L, R7H + di           r's low and high bytes.
  SYT7 + 32 di + v        screen y of a corner at height h = v - HMAX + hg, hg the ground
                          under the ship, v 0..2 HMAX: HORIZON + ((CAMH + hg - h) r + 2048)
                          / 4096 (land.project's sy, the camera at CAMH; raised, EYV is
                          added).  src/prow7.s points syp at SYT7 + 32 di + HMAX - hg and
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
                          A row overhangs the screen (PINL7 < XL or PINR7 > XR) exactly
                          when di < NCLP (asserted; src/prow7.s tests di).
  LERPQ7 + 32 q + d + LQOFF  land.lerp(0, d, 16 q) - 1, q 0..15, d -15..15: adding a with
                          C set to the entry at d = b - a gives lerp(a, b, 16 q); prow7.s
                          indexes by (b | 16) - a - 1 (b < 16).  The edges' heights (q cxs),
                          the clip rows' (16 - czs), the ground's (hgnd).
  LQLO, LQHI + q          LERPQ7 + 32 q, low byte and page.
  PXF7, PXN7 + 11 cxs + i the x's of the far clip plane's row (di 16 ZFCLIP - DI0) and the
                          near's (16 ZCLIP - DI0), fixed but for cxs: PINL7, corners 1..NX-2
                          by B1T, PINR7; i 0..NX-1.  Neither overhangs the screen (asserted).
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'proto'))
import land as L      # noqa: E402
import frame as FR    # noqa: E402
import swatch35 as SW  # noqa: E402
import nula as NU     # noqa: E402

BASE = 0x8000                               # a bank's address
YSKY, YGND = FR.YSKY, FR.YGND
ADDR7 = dict(R7L=0x8000, R7H=0x8100, SYT7=0x8200, B1T=0x9800,
             PINL7=0xAF00, PINR7=0xB000, LERPQ7=0xB100, SYL7=0xB300, SYH7=0xB3B0,
             LQLO=0xB460, LQHI=0xB470, PXF7=0xBEA0, PXN7=0xBF50)
RFA = 9                                     # the rungs' fast way: rungs of up to RFA pixels
DI0 = (L.ZBACK - L.NZ + 1) * 16 - 15        # the nearest row's d/16
NDI = L.ZBACK * 16 - DI0 + 1                # depth indices: to the farthest (j 0, czs 0)
SIZE7 = {}                                  # each of ADDR7's tables' bytes (build7 fills it)
NCLP = 4                                    # the rows that overhang the screen: di < NCLP
NXD = L.NX - 2 * L.XSKIP                    # the corners drawn in a row (tables.inc's NX)
LQOFF = 15                                  # LERPQ7's offset for d = -15
assert YSKY % 2 == 0 and YGND % 2 == 1 and NDI <= 176


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


def build7():
    """Bank 7's image, 16K: the projection by depth index, at ADDR7 (the module
    docstring); fills SIZE7."""
    img = bytearray(0x4000)

    def put(name, off, val):
        img[ADDR7[name] - BASE + off] = val & 255
        SIZE7[name] = max(SIZE7.get(name, 0), off + 1)

    b1s, clp = {}, []
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
        clp.append(1 if pl < L.XL or pr > L.XR else 0)
        for row, dic in (('PXF7', L.ZFCLIP * 16 - DI0), ('PXN7', L.ZCLIP * 16 - DI0)):
            if di == dic:
                assert not (pl < L.XL or pr > L.XR)
                for cxs in range(16):
                    b1 = b1s[di, cxs]
                    xs = [pl] + [(b1 + (i - 1) * r) >> 8 for i in range(1, NXD - 1)] + [pr]
                    for i, x in enumerate(xs):
                        put(row, 11 * cxs + i, x)
    assert clp == [1] * NCLP + [0] * (NDI - NCLP), 'a row overhangs the screen exactly when di < NCLP'
    for q in range(16):
        put('LQLO', q, ADDR7['LERPQ7'] + 32 * q)
        put('LQHI', q, (ADDR7['LERPQ7'] + 32 * q) >> 8)
        for d in range(-15, 16):
            put('LERPQ7', q * 32 + d + LQOFF, L.lerp(0, d, 16 * q) - 1)
    return img

