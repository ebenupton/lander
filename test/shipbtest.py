#!/usr/bin/env python3
"""Bank 6's `shipdraw` run in py65 for every orientation, each drawing checked
byte for byte against tools/shipgen.py's rasteriser.

    python3 test/shipbtest.py [centres]

    centres  the centres drawn at (default 4): the first of (128, 98),
             (127, 99), (17, 87), (238, 124), (19, 86), (236, 125), then
             random ones in x 17..238, y 86..125 for any beyond six.  Fewer
             than six: screen 0 ($3000) only; six or more: both screens.

The machine: build/SHIPB at $8000 on a plain py65 memory (no bank switching:
nothing else is loaded), LAND's `scrb` (zero page, from build/labels.txt)
set to the screen's high byte.  For each screen, centre, pitch (0..NPITCH-1)
and direction (0..NDIR-1): the screen's 10K filled with random bytes; shk,
shp, shx, shy written (bank 6's, from build/shipb_labels.txt); `shipdraw`
called.  Checked: every byte of the screen equals the random fill with the
ship's pixels (shipgen.draw: palette entry + 1) replaced by their dither
bytes, so each pixel outside the ship is untouched; and the box bxl, bxr, byt,
byb equals the ship's pixel extent.  The first five failures are described
(the differing bytes' lines and columns).

Prints "<drawings> drawings, <failed> failed" and shipdraw's cycles (mean,
min, max: the call's, as if by JSR); exit status 1 if any drawing failed.
"""
import os
import random
import sys

import numpy as np
from py65.devices.mpu6502 import MPU

ROOT = os.path.join(os.path.dirname(__file__), '..')
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import shipgen as G   # noqa: E402
import landgen as LG  # noqa: E402

B = os.path.join(ROOT, 'build')
RET = 0xFF00                                     # where a call returns to
PIXM = LG.NU.PIXM                                # each pixel's mask (proto/nula.py)
LG.NU.check_build(B)
DB = [LG.dither_bytes(e) for e in range(LG.NU.entries())]  # each entry's even, odd line bytes
FIXED = [(128, 98), (127, 99), (17, 87), (238, 124), (19, 86), (236, 125)]


def labels(f):
    """ld65's label file in build/ (lines "al <hex> .<name>"): {name: address}."""
    out = {}
    for ln in open(os.path.join(B, f)):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


def call(mpu, addr):
    """Run the routine at addr as if by JSR (a return to RET pushed) until it
    returns; its cycles, the JSR's 6 included.  Raises after 200K cycles."""
    mpu.memory[0x1FF], mpu.memory[0x1FE] = (RET - 1) >> 8, (RET - 1) & 0xFF
    mpu.sp = 0xFD
    mpu.pc = addr
    start = mpu.processorCycles
    while mpu.pc != RET:
        mpu.step()
        if mpu.processorCycles - start > 200000:
            raise RuntimeError(f'${addr:04X} still running at ${mpu.pc:04X}')
    return mpu.processorCycles - start + 6


def main():
    ncen = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    lab, lab6 = labels('labels.txt'), labels('shipb_labels.txt')
    mpu = MPU()
    mem = mpu.memory
    code = open(os.path.join(B, 'SHIPB'), 'rb').read()
    mem[0x8000:0x8000 + len(code)] = list(code)
    rng = random.Random(1)
    cens = FIXED + [(rng.randint(17, 238), rng.randint(86, 125)) for _ in range(max(0, ncen - 6))]
    cyc, bad, n = [], 0, 0
    for scr0 in (0x3000, 0x5800):
        for cx, cy in cens[:max(ncen, 1)]:
            for p in range(G.NPITCH):
                for k in range(G.NDIR):
                    scr = [rng.randrange(256) for _ in range(10240)]
                    mem[scr0:scr0 + 10240] = scr
                    for name, v in (('shk', k), ('shp', p), ('shx', cx), ('shy', cy)):
                        mem[lab6[name]] = v
                    mem[lab['scrb']] = scr0 >> 8
                    cyc.append(call(mpu, lab6['shipdraw']))
                    img = np.zeros((160, 256), dtype=np.int16)
                    G.draw(img, k, p, cx, cy)
                    exp = list(scr)
                    ys, xs = np.nonzero(img)
                    for y, x in zip(ys, xs):
                        a = (y >> 3) * 512 + (y & 7) + (x >> 2) * 8
                        m = PIXM[x & 3]
                        exp[a] = (exp[a] & ~m & 255) | (DB[img[y, x] - 1][y & 1] & m)
                    got = mem[scr0:scr0 + 10240]
                    box = [mem[lab6[v]] for v in ('bxl', 'bxr', 'byt', 'byb')]
                    want = [xs.min(), xs.max(), ys.min(), ys.max()]
                    n += 1
                    if list(got) != exp or box != want:
                        bad += 1
                        if bad <= 5:
                            d = [i for i in range(10240) if got[i] != exp[i]]
                            print(f'centre ({cx},{cy}) k {k} p {p}: {len(d)} bytes differ, box {box} want {want}')
                            for i in d[:4]:
                                y = (i // 512) * 8 + (i & 7)
                                print(f'   line {y} column {(i % 512) // 8}: ${got[i]:02X}, want ${exp[i]:02X}')
        if ncen < 6:
            break
    print(f'{n} drawings, {bad} failed')
    print(f'shipdraw: mean {sum(cyc) / len(cyc):.0f}, min {min(cyc)}, max {max(cyc)} cycles')
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
