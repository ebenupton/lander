#!/usr/bin/env python3
"""Run LAND's own code in py65 for many frames, panning, and check each frame's screen
against proto/frame.py's (the frame alone on black), byte for byte.

    python3 test/landsoak.py [frames] [seed] [step] [ship]   (step: the most a frame pans,
                                     in sixteenths of a tile; default 2.  ship: each frame
                                     also draws the ship (bank 6's B6_SHIP), at a random
                                     orientation and place, and the screen must be the
                                     land with tools/shipgen.py's ship over it; shipc:
                                     the same, the ship near where LAND keeps it)

build/land/LAND at $1900 and TABLES at $8000 (bank 4, as LAND pages it); init once,
then each frame: the camera set, project, strips, flip (both screens in turn, so
what a frame leaves for the one after next is checked too).  Prints the cycles.
"""
import os
import sys

import numpy as np
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROOT = os.path.join(os.path.dirname(__file__), '..')
sys.path.insert(0, os.path.join(ROOT, 'proto'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import land as L      # noqa: E402
import frame as F     # noqa: E402
import landgen as G   # noqa: E402
import shipgen as SG  # noqa: E402
import points as P    # noqa: E402

B = os.path.join(ROOT, 'build', 'land')
RET = 0xFF00
PIXM = [0x88, 0x44, 0x22, 0x11]
DB = [G.dither_bytes(e) for e in range(35)]


def labels(f='labels.txt'):
    out = {}
    for ln in open(os.path.join(B, f)):
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


def machine():
    """py65 with LAND at $1900, TABLES in bank 4 and TABLES2 in bank 5 (a write
    to ROMSEL, $FE30, pages one in at $8000), init run: (mpu, labels)."""
    lab = labels()
    banks = {4: open(os.path.join(B, 'TABLES'), 'rb').read(),
             5: open(os.path.join(B, 'TABLES2'), 'rb').read(),
             6: open(os.path.join(B, 'SHIPB'), 'rb').read().ljust(0x4000, b'\0')}
    mem = ObservableMemory()

    cur = [4]

    def romsel(addr, value):                         # (writes to the bank kept)
        if value in banks and value != cur[0]:
            banks[cur[0]] = bytes(mem._subject[0x8000:0xC000])
            mem._subject[0x8000:0xC000] = banks[value]
            cur[0] = value
        return value
    mem.subscribe_to_write([0xFE30], romsel)
    mpu = MPU(memory=mem)
    code = open(os.path.join(B, 'LAND'), 'rb').read()
    mpu.memory[0x1900:0x1900 + len(code)] = code
    mem._subject[0x8000:0xC000] = banks[4]
    call(mpu, lab['init'])
    mpu.memory[lab['back']] = 0
    call(mpu, lab['setback'])
    return mpu, lab


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    step = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    ship = 'ship' in sys.argv[4:] or 'shipc' in sys.argv[4:]
    near = 'shipc' in sys.argv[4:]
    mpu, lab = machine()
    lab6 = labels('shipb_labels.txt')
    hm = L.heightmap()
    cx, cz = 40 << 8, 30 << 8
    cyc = {'project': [], 'strips': []}
    if ship:
        cyc['ship'] = []
    fails = 0
    for f in range(frames):
        if f:
            cx += 16 * int(rng.integers(-step, step + 1))
            cz += 16 * int(rng.integers(-step, step + 1))
        cx &= 0xFFFF
        cz &= 0xFFFF
        m = mpu.memory
        m[lab['cxt']], m[lab['cxs']] = (cx >> 8) & 63, (cx >> 4) & 15
        m[lab['czt']], m[lab['czs']] = (cz >> 8) & 63, (cz >> 4) & 15
        scr = 0x3000 if m[lab['back']] == 0 else 0x5800
        m[lab['vcount']] = (m[lab['vflip']] + 1) & 255     # (a vertical sync since the flip)
        for r in ('project', 'strips'):
            cyc[r].append(call(mpu, lab[r]))
        if ship:
            k, p = int(rng.integers(SG.NDIR)), int(rng.integers(SG.NPITCH))
            if near:                                 # (about where LAND keeps it)
                sx, sy = 128 + int(rng.integers(-24, 25)), 98 + int(rng.integers(-10, 11))
            else:
                sx, sy = int(rng.integers(18, 238)), int(rng.integers(F.YSKY + 18, F.YGND - 18))
            m[0xFE30] = 6
            for n, v in (('shk', k), ('shp', p), ('shx', sx), ('shy', sy)):
                m[lab6[n]] = v
            cyc['ship'].append(call(mpu, 0x8003))
            m[0xFE30] = 4
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
        if ship:
            SG.draw(img, k, p, sx, sy)
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
