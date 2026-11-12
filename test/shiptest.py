#!/usr/bin/env python3
"""The 32K build's ship (src/ship.s) in py65 against tools/shipmodel.py's model: every
direction and pitch (or a sample), drawn over random bytes in land buffer 0 at a random
centre, every byte checked.

    [VERSION=v] [BUILD=dir] python3 test/shiptest.py [STEP] [SEED]

STEP: every STEP'th orientation (default 1, all 416); SEED the centres' and bytes' seed
(default 1).  The centre's x is 128 (the game's) for half the orientations, else
anywhere its box stays on the screen; its line anywhere the box stays on the land's
lines.  The build is test/rig.py's (VERSION, BUILD, BDIR; the sideways RAM build's ship
is test/shipswr.py's).  Prints the first five orientations that fail, "<n> orientations,
<f> failed" and the cycles of a drawing that rasterises and of one that redraws what
the last left; exits 1 on any failure.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import soak as S         # noqa: E402  (its machine; the paths to tools/ and proto/)
import shipmodel as M    # noqa: E402


def main():
    if S.rig.SWR:
        sys.exit('shiptest.py: the 32K build\'s ship (SWR=1: test/shipswr.py)')
    step = int(sys.argv[1]) if len(sys.argv) > 1 else 1
    rng = np.random.default_rng(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
    mpu, lab = S.machine()
    GSHK, GSHP, GSHX, GSHY = (lab[n] for n in ('GSHK', 'GSHP', 'GSHX', 'GSHY'))
    m = mpu.memory
    scr = lab['LAND0'] - S.LAND
    fails = 0
    cyc = {}
    n = 0
    for i in range(0, M.NDIR * M.NPITCH, step):
        k, p = i % M.NDIR, i // M.NDIR
        cx = 128 if rng.integers(2) else int(rng.integers(24, 232))
        cy = int(rng.integers(64 + 16, 160 - 18))
        rnd = bytes(rng.integers(0, 256, 6144, dtype=np.uint8))
        m[scr + 4096:scr + 10240] = rnd
        for a, v in ((GSHK, k), (GSHP, p), (GSHX, cx), (GSHY, cy)):
            m[a] = v
        m[lab['back']] = 0
        S.call(mpu, lab['setback'])
        c = S.call(mpu, lab['shipdraw'])
        cyc.setdefault('rasterised', []).append(c)
        c2 = S.call(mpu, lab['shipdraw'])            # again: from DBUF as it is
        cyc.setdefault('kept', []).append(c2)
        want = bytearray(rnd)
        _, faces = M.orient(k, p)
        pal = dict(faces)
        for y, bd, fs in M.lines(k, p):
            yy = cy + y
            for j, f in enumerate(fs):
                for x in range(cx + bd[j], cx + bd[j + 1]):
                    o = ((yy >> 3) - 8) * 512 + (x >> 2) * 8 + (yy & 7)
                    pm = S.PIXM[x & 3]
                    want[o] = (want[o] & ~pm & 255) | (S.DB[pal[f]][yy & 1] & pm)
        got = bytes(m[scr + 4096:scr + 10240])
        n += 1
        if got != bytes(want):
            fails += 1
            bad = [o for o in range(6144) if got[o] != want[o]]
            print(f'k {k} p {p} at ({cx}, {cy}): {len(bad)} bytes wrong, first at line '
                  f'{(bad[0] // 512 + 8) * 8 + (bad[0] & 7)} column {(bad[0] % 512) // 8}')
            if fails >= 5:
                break
    print(f'{n} orientations, {fails} failed')
    for r, c in cyc.items():
        print(f'{r}: mean {sum(c) // len(c)}, max {max(c)}')
    sys.exit(1 if fails else 0)


if __name__ == '__main__':
    main()
