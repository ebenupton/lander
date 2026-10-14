#!/usr/bin/env python3
"""Run BAND's own code for many frames in py65 and check each against the prototype.

    python3 test/soak.py [frames] [seed]

build/BAND is loaded at $1900 and its routines called directly (labels from
build/labels.txt), without the MOS: gentables once, then for each frame cls,
genrows, across (the rows), down (the rungs) and fill, each frame checked by
check.py.  Prints their cycle counts (including JSR and RTS), as the BBC's
readout would.
"""
import os
import random
import sys

from py65.devices.mpu6502 import MPU

sys.path.insert(0, os.path.dirname(__file__))
from check import check  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), '..')
RET = 0xFF00                       # a routine's RTS lands here


def labels():
    out = {}
    for ln in open(os.path.join(ROOT, 'build', 'labels.txt')):
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
        if mpu.processorCycles - start > 2000000:
            raise RuntimeError(f'${addr:04X} still running at ${mpu.pc:04X}')
    return mpu.processorCycles - start + 6   # and the JSR


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    random.seed(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    lab = labels()
    mpu = MPU()
    code = open(os.path.join(ROOT, 'build', 'BAND'), 'rb').read()
    mpu.memory[0x1900:0x1900 + len(code)] = code
    zp_rng = lab['rng']
    mpu.memory[zp_rng] = random.randrange(1, 256) | 1
    mpu.memory[zp_rng + 1] = 0xA5
    for seg in ('LOW1', 'LOW2', 'LOW3'):           # start's copy
        ld, run = lab[f'__{seg}_LOAD__'], lab[f'__{seg}_RUN__']
        n = lab[f'__{seg}_SIZE__']
        mpu.memory[run:run + n] = mpu.memory[ld:ld + n]
    call(mpu, lab['gentables'])
    cyc = {'across': [], 'down': [], 'fill': []}
    fails = 0
    for f in range(frames):
        call(mpu, lab['cls'])
        call(mpu, lab['genrows'])
        mpu.memory[lab['RT']:lab['RT'] + 256] = [0xFF] * 256    # interp's own work,
        mpu.memory[lab['TOPC']:lab['BOTC'] + 60] = [0xFF] * (lab['BOTC'] + 60 - lab['TOPC'])
        mpu.memory[lab['SEGV']:lab['SEGV'] + 8] = [0xFF] * 8
        for r in cyc:
            cyc[r].append(call(mpu, lab[r]))
        pts, boxc, terr, bad = check(lambda a: mpu.memory[a])
        if terr or bad:
            fails += 1
            print(f'frame {f}: table errors {terr}, screen byte errors {len(bad)}')
            print('  rows', [y for _, y in pts[0]], [y for _, y in pts[1]], 'boxes', boxc)
            for c, y, got, want in bad[:6]:
                print(f'  column {c} line {y}: ${got:02X}, want ${want:02X}')
            if fails >= 3:
                break
    n = len(cyc['fill'])
    print(f'{n} frames, {fails} failed')
    for r, c in cyc.items():
        print(f'{r + " cycles:":14s} mean {sum(c)//n:6d}, min {min(c):6d}, max {max(c):6d}')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
