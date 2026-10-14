#!/usr/bin/env python3
"""The game's tables (src/game.s, bank 5): build/land/gametab.inc.

  ATQ + 16 a + b    the virtual mouse's angle in its quadrant, 32nds of a turn from the
                    x axis (0..8), |mx| >> 2 = a, |mz| >> 2 = b
  MAGT + 16 a + b   its distance as a target pitch (0..NPITCH-1)
  THX, THZ + 32 p + k   full thrust's x and z for pitch p, direction k (shipgen's: k 0
                    faces +x, 8 towards the camera (-z), 16 -x, 24 away), 127 a unit
  THY + p           and its y (up)
  MAPI              the map, 64 x 64 MODE 1 pixels (a tile each, z up): 16 bytes a
                    line, 64 lines: sea cyan, land yellow, the pad magenta
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'proto'))
sys.path.insert(0, HERE)
import land as L     # noqa: E402
import shipgen as SG  # noqa: E402

NDIR, NPITCH = SG.NDIR, SG.NPITCH


def tables():
    atq, mag = [], []
    for a in range(16):
        for b in range(16):
            x, z = 4 * a, 4 * b
            atq.append(round(math.atan2(z, x) * NDIR / (2 * math.pi)) if a or b else 0)
            d = math.hypot(4 * a, 4 * b)
            mag.append(0 if d < 6 else min(NPITCH - 1, int(d / 8)))
    thx, thz = [], []
    for p in range(NPITCH):
        a = p * math.pi / 2 / NPITCH
        for k in range(NDIR):
            t = k * 2 * math.pi / NDIR
            thx.append(round(127 * math.sin(a) * math.cos(t)))
            thz.append(round(-127 * math.sin(a) * math.sin(t)))
    thy = [round(127 * math.cos(p * math.pi / 2 / NPITCH)) for p in range(NPITCH)]
    return atq, mag, thx, thz, thy


def mapimg():
    hm = L.heightmap()[0]
    out = bytearray(1024)
    for line in range(64):
        z = 63 - line
        for x in range(64):
            if x < L.PADN and z < L.PADN:
                c = 2                     # the pad: magenta
            elif all(hm[(z + dz) % L.MAP, (x + dx) % L.MAP] == L.SEA for dz in (0, 1) for dx in (0, 1)):
                c = 1                     # sea: cyan
            else:
                c = 3                     # land: yellow
            p = x & 3
            v = ((c >> 1) << (7 - p)) | ((c & 1) << (3 - p))
            out[line * 16 + (x >> 2)] |= v
    return out


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'build', 'land')
    atq, mag, thx, thz, thy = tables()
    lines = ['; tools/gamegen.py: the game\'s tables (generated)']

    def emit(name, vals):
        lines.append(f'{name}:')
        for i in range(0, len(vals), 16):
            lines.append('        .byte ' + ', '.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    emit('ATQ', atq)
    emit('MAGT', mag)
    emit('THX', thx)
    emit('THZ', thz)
    emit('THY', thy)
    emit('MAPI', list(mapimg()))
    open(os.path.join(out, 'gametab.inc'), 'w').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
