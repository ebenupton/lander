#!/usr/bin/env python3
"""The game's tables (src/game.s, bank 5): build/land/gametab.inc.

  NPITCH            the ship's pitches (shipgen's)
  THX, THZ + 32 p + k   full thrust's x and z for pitch p (THXL/H, THZL/H: its row),
                    direction k (shipgen's: k 0
                    faces +x, 8 towards the camera (-z), 16 -x, 24 away), 127 a unit
  THY + p           and its y (up)
  SHYT + d          the ship's line below the horizon for the camera d height units above
                    it: d R / 16 rounded (R = recip at ZSHIP: the landscape's projection)
  MAPI              the map, 64 x 64 MODE 1 pixels (a tile each, z up): 16 bytes a
                    line, 64 lines: sea cyan, land yellow, the pad grey (its dither,
                    PADC's), turned round the torus so the pad's middle is the map's:
                    tile x at column (x + MAPX) & 63, z at line (MAPZ - z) & 63
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, '..', 'proto'))
sys.path.insert(0, HERE)
import land as L     # noqa: E402
import shipgen as SG  # noqa: E402
import swatch35 as SW  # noqa: E402

NDIR, NPITCH = SG.NDIR, SG.NPITCH
MAPX = 32 - L.PADN // 2   # the pad's middle (tile PADN/2) to the map's (column 32,
MAPZ = 31 + L.PADN // 2   # line 31; game.s's marker likewise)


def tables():
    thx, thz = [], []
    for p in range(NPITCH):
        a = SG.pitch(p)
        for k in range(NDIR):
            t = k * 2 * math.pi / NDIR
            thx.append(round(127 * math.sin(a) * math.cos(t)))
            thz.append(round(-127 * math.sin(a) * math.sin(t)))
    thy = [round(127 * math.cos(SG.pitch(p))) for p in range(NPITCH)]
    return thx, thz, thy


def mapimg():
    hm = L.heightmap()[0]
    out = bytearray(1024)
    grey = SW.cell(*SW.ALL[L.PADC])
    for line in range(64):
        z = (MAPZ - line) % 64
        for px in range(64):
            x = (px - MAPX) % 64
            if x < L.PADN and z < L.PADN:
                c = grey[(px & 1, line & 1)]   # the pad: grey
            elif all(hm[(z + dz) % L.MAP, (x + dx) % L.MAP] == L.SEA for dz in (0, 1) for dx in (0, 1)):
                c = 1                     # sea: cyan
            else:
                c = 3                     # land: yellow
            p = px & 3
            v = ((c >> 1) << (7 - p)) | ((c & 1) << (3 - p))
            out[line * 16 + (px >> 2)] |= v
    return out


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'build', 'land')
    thx, thz, thy = tables()
    lines = ['; tools/gamegen.py: the game\'s tables (generated)']

    def emit(name, vals):
        lines.append(f'{name}:')
        for i in range(0, len(vals), 16):
            lines.append('        .byte ' + ', '.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    lines.append(f'NPITCH = {NPITCH}')
    lines.append(f'NDIR = {NDIR}')
    lines.append(f'PFLAT = {SG.PFLAT}')
    for name in ('THX', 'THZ'):                # (each pitch's row: game.s's throw)
        lines.append(f'{name}L: .byte ' + ', '.join(f'<({name}+{32 * p})' for p in range(NPITCH)))
        lines.append(f'{name}H: .byte ' + ', '.join(f'>({name}+{32 * p})' for p in range(NPITCH)))
    emit('THX', thx)
    emit('THZ', thz)
    emit('THY', thy)
    r = L.recip(L.ZSHIP << 8)
    emit('SHYT', [min(255, (d * r + 2048) // 4096) for d in range(256)])
    emit('MAPI', list(mapimg()))
    lines.append(f'MAPX = {MAPX}')
    lines.append(f'MAPZ = {MAPZ}')
    open(os.path.join(out, 'gametab.inc'), 'w').write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
