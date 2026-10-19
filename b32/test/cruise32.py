#!/usr/bin/env python3
"""Fast level flight's cost by routine: the camera moved DX, DZ sixteenths of a tile a
frame at the raise CAME, project, strips and flip each frame (soak32's machine), every
instruction's cycles summed by routine (the first frame not counted).

    python3 b32/test/cruise32.py [FRAMES] [DX] [DZ] [CAME]      (default 60 7 9 20)"""
import bisect, collections, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import soak32 as S
n = int(sys.argv[1]) if len(sys.argv) > 1 else 60
dx = int(sys.argv[2]) if len(sys.argv) > 2 else 7
dz = int(sys.argv[3]) if len(sys.argv) > 3 else 9
came = int(sys.argv[4]) if len(sys.argv) > 4 else 20
mpu, lab = S.machine(); m = mpu.memory
names = sorted((a, k) for k, a in lab.items() if not k.startswith(('__', '@')))
ks = [a for a, _ in names]
by = collections.Counter()
cx, cz = 40 << 4, 30 << 4                    # sixteenths
tot = 0
for f in range(n):
    m[lab['cxt']], m[lab['cxs']] = (cx >> 4) & 63, cx & 15
    m[lab['czt']], m[lab['czs']] = (cz >> 4) & 63, cz & 15
    m[lab['CAME']] = came
    m[lab['vcount']] = (m[lab['vflip']] + 4) & 255
    for r in ('project', 'strips', 'flip'):
        m[0x1FF], m[0x1FE] = (S.RET - 1) >> 8, (S.RET - 1) & 255
        mpu.sp = 0xFD; mpu.pc = lab[r]
        while mpu.pc != S.RET:
            pc = mpu.pc; c0 = mpu.processorCycles; mpu.step()
            if f: by[names[bisect.bisect_right(ks, pc) - 1][1]] += mpu.processorCycles - c0
    cx += dx; cz += dz
F = n - 1
t = sum(by.values()) / F
print(f'{F} frames at ({dx}, {dz})/16 a frame, CAME {came}: {t:.0f} cycles a frame (project, strips, flip)')
for k, v in by.most_common(400):
    print(f'  {v / F:7.0f} {k}')
