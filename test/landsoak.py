#!/usr/bin/env python3
"""Soak test: LAND's renderer run in py65 over random pans, each frame checked
byte for byte against the Python reference.

    python3 test/landsoak.py [frames] [seed] [step] [ship|shipc] [cam]

    frames  frames to run (default 20)
    seed    numpy's, for the pans, the camera raise and the ship (default 1)
    step    the most a frame pans in x and in z, in steps (sixteenths of a
            tile; default 2)
    ship    each frame also draws the ship (bank 6's B6_SHIP) at a random
            direction and pitch, centred anywhere in x 18..237, y 82..140
    shipc   the same, centred near where the game keeps it (x 128, lines
            81..102): x 104..152, y 88..108
    cam     about half the frames (by the seed) raise the camera by a random
            0..EMAX (CAME)

Environment:
    SOAKCX, SOAKCZ  the first frame's camera, hex, 8.8 tiles (both or neither;
                    default 2800 and 1E00: tiles 40 and 30)
    SOAKE           the camera raise for every frame (overrides cam)
    SOAKDBG         set: print each frame's number, raise and screen first

The machine: build/LAND at $1900; TABLES, TABLES2, SHIPB and TABLES7 as
sideways banks 4..7, a write to ROMSEL ($FE30) paging one in at $8000 (the
bank paged out keeps the writes made to it).  No OS, no hardware beyond that:
the CRTC and VIA addresses are plain memory.  `init` is run once, then `back`
set to 0 and `setback` run, as LAND's start does.

A frame: the camera (cxt, cxs, czt, czs) and CAME set; vcount set to vflip + 4
(the vertical syncs the event handler would have counted: `strips` waits for
one since the flip and `flip` for FMIN); `project` and `strips` called; with
ship, bank 6 paged in, shk, shp, shx, shy written and B6_SHIP ($8003) called
(shipdraw, then the screen's TOPS and BOTS widened over the ship's box); then
the projection checked (np, nr, and each row's PX and PY at $0700 and $0800,
16 a row, against proto/land.py's project), and the screen being drawn
($3000 or $5800 by `back`) against proto/frame.py's frame with
tools/shipgen.py's ship over it, as MODE 1 bytes; then `flip`.  Both screens
are drawn in turn, so what a frame leaves for the frame after next (land gone,
the ship) is checked too.  A failing frame prints its first three projection
errors and first eight wrong bytes; the run stops at the third failure.

Prints "<frames> frames, <failed> failed" and the cycles of project, strips
and (with ship) B6_SHIP, shipdraw and the records' widening together (mean,
min, max: the call's, as if by JSR, with the bank already paged: no call6);
exit status 1 if any frame failed.
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

B = os.path.join(ROOT, 'build')
RET = 0xFF00                                     # where a call returns to
ROMSEL = 0xFE30
CAME = 0x07D6                                    # LAND's: the camera raise
B6_SHIP = 0x8003
DBG = bool(os.environ.get('SOAKDBG'))
PIXM = [0x88, 0x44, 0x22, 0x11]                  # a MODE 1 byte's pixel p
DB = [G.dither_bytes(e) for e in range(35)]      # each dither: even, odd line bytes


def labels(f='labels.txt'):
    """ld65's label file in build/ (lines "al <hex> .<name>"): {name: address}."""
    out = {}
    for ln in open(os.path.join(B, f)):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


def call(mpu, addr):
    """Run the routine at addr as if by JSR (a return to RET pushed) until it
    returns; its cycles, the JSR's 6 included.  Raises after 3M cycles."""
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
    """img (palette entry + 1 by pixel, 0 black) as the narrow screen's 10K:
    64 bytes a line, 512 a character row."""
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
    """py65 with LAND loaded, the four banks behind ROMSEL and bank 4 paged in,
    `init` run and the screen being drawn set to 0: (mpu, labels)."""
    lab = labels()
    banks = {4: open(os.path.join(B, 'TABLES'), 'rb').read(),
             5: open(os.path.join(B, 'TABLES2'), 'rb').read(),
             6: open(os.path.join(B, 'SHIPB'), 'rb').read().ljust(0x4000, b'\0'),
             7: open(os.path.join(B, 'TABLES7'), 'rb').read()}
    mem = ObservableMemory()
    cur = [4]

    def romsel(addr, value):
        if value in banks and value != cur[0]:
            banks[cur[0]] = bytes(mem._subject[0x8000:0xC000])
            mem._subject[0x8000:0xC000] = banks[value]
            cur[0] = value
        return value
    mem.subscribe_to_write([ROMSEL], romsel)
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
    cam = 'cam' in sys.argv[4:]

    mpu, lab = machine()
    lab6 = labels('shipb_labels.txt')
    hm = L.heightmap()
    if os.environ.get('SOAKCX'):
        cx, cz = int(os.environ['SOAKCX'], 16), int(os.environ['SOAKCZ'], 16)
    else:
        cx, cz = 40 << 8, 30 << 8
    cyc = {'project': [], 'strips': []}
    if ship:
        cyc['ship'] = []
    fails = 0
    m = mpu.memory
    for f in range(frames):
        if f:
            cx += 16 * int(rng.integers(-step, step + 1))
            cz += 16 * int(rng.integers(-step, step + 1))
        cx &= 0xFFFF
        cz &= 0xFFFF
        m[lab['cxt']], m[lab['cxs']] = (cx >> 8) & 63, (cx >> 4) & 15
        m[lab['czt']], m[lab['czs']] = (cz >> 8) & 63, (cz >> 4) & 15
        scr = 0x3000 if m[lab['back']] == 0 else 0x5800
        e = int(rng.integers(0, L.EMAX + 1)) if cam and rng.integers(2) else 0
        if os.environ.get('SOAKE'):
            e = int(os.environ['SOAKE'])
        m[CAME] = e
        if DBG:
            print('f', f, 'e', e, 'back', m[lab['back']])
        m[lab['vcount']] = (m[lab['vflip']] + 4) & 255
        for r in ('project', 'strips'):
            cyc[r].append(call(mpu, lab[r]))
        if ship:
            k, p = int(rng.integers(SG.NDIR)), int(rng.integers(SG.NPITCH))
            if near:
                sx, sy = 128 + int(rng.integers(-24, 25)), 98 + int(rng.integers(-10, 11))
            else:
                sx, sy = int(rng.integers(18, 238)), int(rng.integers(F.YSKY + 18, F.YGND - 18))
            m[ROMSEL] = 6
            for n, v in (('shk', k), ('shp', p), ('shx', sx), ('shy', sy)):
                m[lab6[n]] = v
            cyc['ship'].append(call(mpu, B6_SHIP))
            m[ROMSEL] = 4
        # the projection: the counts, then each row's points
        xs, rows = L.project(hm, (cx >> 8 & 63) << 8 | cx & 255, (cz >> 8 & 63) << 8 | cz & 255, e)
        np_, nr = m[lab['np']], m[lab['nr']]
        perr = []
        if np_ != len(xs) or nr != len(rows):
            perr.append(f'np {np_} nr {nr}, want {len(xs)} {len(rows)}')
        else:
            for r, (_, row) in enumerate(rows):
                got = [(m[0x0700 + 16 * r + i], m[0x0800 + 16 * r + i]) for i in range(np_)]
                want = [(sx, sy) for sx, sy, _ in row]
                if got != want:
                    perr.append(f'row {r}: {got} want {want}')
        # the screen
        img = np.zeros((P.H, P.W), np.uint8)
        F.draw(img, hm, cx, cz, e=e)
        if ship:
            SG.draw(img, k, p, sx, sy)
        want = screen_bytes(img)
        got = bytes(m[scr:scr + 10240])
        bad = [i for i in range(10240) if got[i] != want[i]]
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
