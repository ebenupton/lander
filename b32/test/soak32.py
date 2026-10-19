#!/usr/bin/env python3
"""The renderer in py65 against the reference, byte for byte, over random pans.

    python3 b32/test/soak32.py [FRAMES] [SEED] [STEP] [cam]

    FRAMES  frames to run (default 20)
    SEED    the pans' and raises' seed (default 1)
    STEP    the most a frame pans in x and in z, in sixteenths of a tile (default 2)
    cam     about half the frames raise the camera by a random 0..EMAX

Environment: SOAKCX, SOAKCZ the first frame's camera (hex, 8.8 tiles; default 2800,
1E00); SOAKE the raise for every frame; SOAKDBG to print each frame's camera.

The machine is the loader's start-up (takeover) and nothing else: no interrupts, so the
CRTC and VIAs are plain memory and vcount is set by hand.  Each frame sets the camera,
runs project and strips, checks the rows of points against proto/land.py's projection
and the land's lines of the screen drawn against proto/frame.py's frame (in the build's
colours, proto/nula.py's), then flips.  Both screens are drawn in turn, so what a frame
leaves for the frame after next is checked too.  Prints the failures (the first three
projection errors and eight wrong bytes of each, stopping at the third), then "<n>
frames, <f> failed" and project's and strips' cycles; exits 1 on any failure.
"""
import os
import random
import sys

os.environ['LAND_MAP'] = '64'
os.environ['LAND_GEN'] = '1'
import numpy as np
from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
sys.path.insert(0, os.path.join(ROOT, 'proto'))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import land as L      # noqa: E402
import frame as F     # noqa: E402
import landgen as G   # noqa: E402
import points as P    # noqa: E402
import swr32          # noqa: E402

B = swr32.B
LAND = 0 if swr32.SWR else 0x1000                # the land buffers' first line's offset
RET = 0xFF00                                     # where a call returns to
DBG = bool(os.environ.get('SOAKDBG'))
PIXM = G.NU.PIXM                                 # each pixel's bits
DB = [G.dither_bytes(e) for e in range(G.NU.entries())]   # each colour's bytes


def labels():
    """The link's labels: {name: address}."""
    out = {}
    for ln in open(os.path.join(B, 'labels.txt')):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


def call(mpu, addr):
    """Run the routine at addr as if by JSR until it returns; its cycles, the JSR's 6
    included."""
    mpu.memory[0x1FF], mpu.memory[0x1FE] = (RET - 1) >> 8, (RET - 1) & 0xFF
    mpu.sp = 0xFD
    mpu.pc = addr
    start = mpu.processorCycles
    while mpu.pc != RET:
        mpu.step()
        if mpu.processorCycles - start > 10000000:
            raise RuntimeError(f'${addr:04X} still running at ${mpu.pc:04X}')
    return mpu.processorCycles - start + 6


def screen_bytes(img):
    """img (palette entry + 1 by pixel, 0 black) as a land buffer's virtual screen: 64
    bytes a line, 512 a character row."""
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
    """py65 after the loader's start-up, screen 0 to draw: (mpu, labels)."""
    lab = labels()
    mpu = MPU(memory=ObservableMemory())
    m = mpu.memory
    m[0:0x8000] = random.Random(32).randbytes(0x8000)   # the MOS's leftovers
    if swr32.SWR:
        swr32.attach(m)
        swr32.load(m)
        call(mpu, lab['takeover'])
        m[0x7000:0x8000] = bytes(0x1000)          # clr's work: the loader gone
    else:
        data = open(os.path.join(B, 'LANDER'), 'rb').read()
        m[0x2000:0x2000 + len(data)] = data
        call(mpu, lab['takeover'])
        m[0x5000:0x8000] = bytes(0x3000)          # clr's work: the loader gone
    m[lab['back']] = 0
    call(mpu, lab['setback'])
    return mpu, lab


def main():
    frames = int(sys.argv[1]) if len(sys.argv) > 1 else 20
    rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    step = int(sys.argv[3]) if len(sys.argv) > 3 else 2
    cam = 'cam' in sys.argv[4:]
    mpu, lab = machine()
    m = mpu.memory
    hm = L.heightmap()
    if os.environ.get('SOAKCX'):
        cx, cz = int(os.environ['SOAKCX'], 16), int(os.environ['SOAKCZ'], 16)
    else:
        cx, cz = 40 << 8, 30 << 8
    cyc = {'project': [], 'strips': []}
    fails = 0
    for f in range(frames):
        if f:
            cx += 16 * int(rng.integers(-step, step + 1))
            cz += 16 * int(rng.integers(-step, step + 1))
        cx &= 0xFFFF
        cz &= 0xFFFF
        m[lab['cxt']], m[lab['cxs']] = (cx >> 8) & 63, (cx >> 4) & 15
        m[lab['czt']], m[lab['czs']] = (cz >> 8) & 63, (cz >> 4) & 15
        scr = (lab['LAND0'] if m[lab['back']] == 0 else lab['LAND1']) - LAND
        e = int(rng.integers(0, L.EMAX + 1)) if cam and rng.integers(2) else 0
        if os.environ.get('SOAKE'):
            e = int(os.environ['SOAKE'])
        m[lab['CAME']] = e
        if DBG:
            print('f', f, f'cx {cx:04X} cz {cz:04X}', 'e', e, 'back', m[lab['back']])
        m[lab['vcount']] = (m[lab['vflip']] + 4) & 255
        for r in ('project', 'strips'):
            cyc[r].append(call(mpu, lab[r]))
        xs, rows = L.project(hm, (cx >> 8 & 63) << 8 | cx & 255, (cz >> 8 & 63) << 8 | cz & 255, e)
        np_, nr = m[lab['np']], m[lab['nr']]
        perr = []
        if np_ != len(xs) or nr != len(rows):
            perr.append(f'np {np_} nr {nr}, want {len(xs)} {len(rows)}')
        else:
            for r, (_, row) in enumerate(rows):
                got = [(m[lab['PX'] + 16 * r + i], m[lab['PY'] + 16 * r + i]) for i in range(np_)]
                want = [(sx, sy) for sx, sy, _ in row]
                if got != want:
                    perr.append(f'row {r}: {got} want {want}')
        img = np.zeros((P.H, P.W), np.uint8)
        F.draw(img, hm, cx, cz, e=e)
        want = screen_bytes(img)
        got = bytes(m[scr:scr + 10240])
        bad = [i for i in range(4096, 10240) if got[i] != want[i]]     # the land's rows
        if perr or bad:
            fails += 1
            print(f'frame {f} (cx {cx:04X} cz {cz:04X} e {e}): {len(bad)} bytes wrong')
            for pe in perr[:3]:
                print('  ', pe)
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
