#!/usr/bin/env python3
"""Run LAND's own code in py65 for many frames, panning, and check each frame's screen
against proto/frame.py's (the frame alone on black), byte for byte.

    python3 test/landsoak.py [frames] [seed]

build/land/LAND at $1900 and TABLES at $8000 (bank 4, as LAND pages it); init once,
then each frame: the camera set, project, strips, flip (both screens in turn, so
what a frame leaves for the one after next is checked too).  Prints the cycles.
"""
import os
import sys

import numpy as np
from py65.devices.mpu6502 import MPU

ROOT = os.path.join(os.path.dirname(__file__), '..')
sys.path.insert(0, os.path.join(ROOT, 'proto'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import land as L      # noqa: E402
import frame as F     # noqa: E402
import landgen as G   # noqa: E402
import points as P    # noqa: E402

B = os.path.join(ROOT, 'build', 'land')
RET = 0xFF00
PIXM = [0x88, 0x44, 0x22, 0x11]
DB = [G.dither_bytes(e) for e in range(35)]


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
        if mpu.processorCycles - start > 3000000:
            raise RuntimeError(f'${addr:04X} still running at ${mpu.pc:04X}')
    return mpu.processorCycles - start + 6


def screen_bytes(img):
    """img (palette entry + 1 by pixel, 0 black) as the narrow screen's 10K."""
    out = bytearray(10240)
    for y in range(P.H):
        for c in range(64):
            v = 0
            for p in range(4):
                e = img[y, 4 * c + p]
                if e:
                    v |= DB[e - 1][y & 1] & PIXM[p]
            out[(y >> 3) * 512 + (y & 7) + 8 * c] = v
    return out


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    lab = labels()
    mpu = MPU()
    code = open(os.path.join(B, 'LAND'), 'rb').read()
    mpu.memory[0x1900:0x1900 + len(code)] = code
    mpu.memory[0x8000:0xC000] = open(os.path.join(B, 'TABLES'), 'rb').read()
    call(mpu, lab['init'])
    mpu.memory[lab['back']] = 0
    call(mpu, lab['setback'])
    hm = L.heightmap()
    cx, cz = 40 << 8, 30 << 8
    cyc = {'project': [], 'strips': []}
    fails = 0
    for f in range(frames):
        if f:
            cx += 16 * int(rng.integers(-2, 3))
            cz += 16 * int(rng.integers(-2, 3))
        cx &= 0xFFFF
        cz &= 0xFFFF
        m = mpu.memory
        m[lab['cxt']], m[lab['cxs']] = (cx >> 8) & 63, (cx >> 4) & 15
        m[lab['czt']], m[lab['czs']] = (cz >> 8) & 63, (cz >> 4) & 15
        scr = 0x3000 if m[lab['back']] == 0 else 0x5800
        for r in cyc:
            cyc[r].append(call(mpu, lab[r]))
        # the projection
        xs, rows = L.project(hm, (cx >> 8 & 63) << 8 | cx & 255, (cz >> 8 & 63) << 8 | cz & 255)
        np_, nr = m[lab['np']], m[lab['nr']]
        perr = []
        if np_ != len(xs) or nr != len(rows):
            perr.append(f'np {np_} nr {nr}, want {len(xs)} {len(rows)}')
        else:
            for r, (_, row) in enumerate(rows):
                got = [(m[0x0900 + 16 * r + i], m[0x0950 + 16 * r + i]) for i in range(np_)]
                want = [(sx, sy) for sx, sy, _ in row]
                if got != want:
                    perr.append(f'row {r}: {got} want {want}')
        img = np.zeros((P.H, P.W), np.uint8)
        F.draw(img, hm, cx, cz)
        want = screen_bytes(img)
        got = bytes(m[scr:scr + 10240])
        bad = [i for i in range(10240) if got[i] != want[i]]
        if perr or bad:
            fails += 1
            print(f'frame {f} (cx {cx:04X} cz {cz:04X}): {len(bad)} bytes wrong')
            for e in perr[:3]:
                print('  ', e)
            for i in bad[:8]:
                y = (i // 512) * 8 + (i & 7)
                c = (i % 512) // 8
                print(f'   line {y} column {c}: ${got[i]:02X}, want ${want[i]:02X}')
            if fails >= 3:
                break
        call(mpu, lab['flip'])
    n = len(cyc['strips'])
    print(f'{n} frames, {fails} failed')
    for r, c in cyc.items():
        print(f'{r + ":":10s} mean {sum(c) // n:6d}, min {min(c):6d}, max {max(c):6d}')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
