#!/usr/bin/env python3
"""Run SHIP's `shipdraw` in py65 for every orientation (and a few centres) over a random
screen, and check every byte against tools/shipgen.py's reference rasteriser: the
ship's pixels in their dithers, every other pixel untouched.  Prints the cycles.

    python3 test/shiptest.py [centres]
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

B = os.path.join(ROOT, 'build', 'ship')
RET = 0xFF00
PIXM = [0x88, 0x44, 0x22, 0x11]
DB = [LG.dither_bytes(e) for e in range(35)]
SCR = 0x3000


def labels():
    out = {}
    for ln in open(os.path.join(B, 'labels.txt')):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


def call(mpu, addr):
    mpu.memory[0x1FF], mpu.memory[0x1FE] = (RET - 1) >> 8, (RET - 1) & 0xFF
    mpu.sp = 0xFD
    mpu.pc = addr
    start = mpu.processorCycles
    while mpu.pc != RET:
        mpu.step()
        if mpu.processorCycles - start > 200000:
            raise RuntimeError(f'${addr:04X} still running at ${mpu.pc:04X}')
    return mpu.processorCycles - start + 6


def addr(x, y):
    return SCR + (y >> 3) * 512 + (y & 7) + (x >> 2) * 8


def main():
    ncen = int(sys.argv[1]) if len(sys.argv) > 1 else 4
    lab = labels()
    mpu = MPU()
    mem = mpu.memory
    code = open(os.path.join(B, 'SHIP'), 'rb').read()
    mem[0x1900:0x1900 + len(code)] = list(code)
    tabs = open(os.path.join(ROOT, 'build', 'land', 'TABLES'), 'rb').read()
    mem[0x8000:0xC000] = list(tabs)            # (LAND's: DQT, DRT, as bank 4)
    rng = random.Random(1)
    cens = [(128, 80), (127, 81), (30, 40), (226, 130)] + \
           [(rng.randint(20, 235), rng.randint(20, 140)) for _ in range(max(0, ncen - 4))]
    cyc, bad, n = [], 0, 0
    for cx, cy in cens[:max(ncen, 1)]:
        for p in range(G.NPITCH):
            for k in range(G.NDIR):
                scr = [rng.randrange(256) for _ in range(10240)]
                mem[SCR:SCR + 10240] = scr
                for name, v in (('shk', k), ('shp', p), ('shx', cx), ('shy', cy), ('scrb', SCR >> 8)):
                    mem[lab[name]] = v
                cyc.append(call(mpu, lab['shipdraw']))
                img = np.zeros((160, 256), dtype=np.int16)
                G.draw(img, k, p, cx, cy)
                exp = list(scr)
                ys, xs = np.nonzero(img)
                for y, x in zip(ys, xs):
                    a = addr(x, y) - SCR
                    m = PIXM[x & 3]
                    exp[a] = (exp[a] & ~m & 255) | (DB[img[y, x] - 1][y & 1] & m)
                got = mem[SCR:SCR + 10240]
                n += 1
                if list(got) != exp:
                    bad += 1
                    if bad <= 5:
                        d = [i for i in range(10240) if got[i] != exp[i]]
                        print(f'centre ({cx},{cy}) k {k} p {p}: {len(d)} bytes differ, first at +${d[0]:04X}')
    print(f'{n} drawings, {bad} failed')
    print(f'shipdraw: mean {sum(cyc) / len(cyc):.0f}, min {min(cyc)}, max {max(cyc)} cycles')


if __name__ == '__main__':
    main()
