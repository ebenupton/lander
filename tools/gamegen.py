#!/usr/bin/env python3
"""The game's tables (src/game.s, bank 5): OUTDIR/gametab.inc, ca65 data game.s .includes.

    python3 tools/gamegen.py [OUTDIR]       (OUTDIR: build/ by default)

Labels and constants, in the file's order:
  EXNL, EXNH, EXA + t   the crash's sound, step t of the 40 (game.s's CRASHT) at 10 a
                        second: the noise channel clocked by tone 2, whose period is
                        N = min(1023, round(10 * 1.15^t)), 10 (12.5 kHz: a crack) rising
                        15% a step (a falling rumble).  EXNL: tone 2's latch byte, $C0 |
                        (N & 15); EXNH: its data byte, N >> 4; EXA: the attenuation, 0
                        (full) for t < 2, then round((t - 2) 15 / 22), 15 (silence) from
                        step 24.
  NPITCH, NDIR, PFLAT   shipgen's: 13 pitches, 32 directions, the level pitch (6).
  THXL, THXH, THZL, THZH + p   THX + 32 p and THZ + 32 p, low bytes and high bytes.
  THX, THZ + 32 p + k   full thrust's x and z for pitch p, direction k, 127 a unit:
                        127 sin a cos t and -127 sin a sin t, a = shipgen.pitch(p) (nose
                        down positive), t = 2 pi k / NDIR (k 0 faces +x, 8 -z, towards the
                        camera, 16 -x, 24 +z).  Signed bytes; game.s's step adds 1.25 of them,
                        shifted by gt5, to the velocities a step (throw, tadd).
  THY + p               its y: 127 cos a.
  SHYT + d              the ship's line below the horizon with the camera d height units
                        above it, d 0..255: round(d R / 4096), at most 255; R =
                        land.recip(ZSHIP * 256), the landscape's pixels a tile (8.8) at
                        the ship's depth, so R / 4096 is pixels a height unit.
  MAPI + 16 line + byte the map, 64 x 64 MODE 1 pixels, 16 bytes a line (pixel p of a byte
                        in bits 7 - p and 3 - p): a tile each; line (MAPZ - z) & 63, pixel
                        (x + MAPX) & 63 is tile (x, z), so the pad's middle is the map's
                        (column 32, line 31) and z runs up the screen.  Sea (all four
                        corners at sea level, as land.colour) logical colour 1 (cyan), land
                        3 (yellow), the pad (x, z < PADN) its dither (land.PADC: a grey).
  MAPX, MAPZ            the offsets above: 32 - PADN/2, 31 + PADN/2.
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
MAPX = 32 - L.PADN // 2
MAPZ = 31 + L.PADN // 2
CRASHT = 40                                 # the crash's steps (game.s's CRASHT)


def thrust():
    """(THX, THZ, THY): the thrust tables, THX and THZ by 32 p + k, THY by p."""
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
    """MAPI's 1024 bytes: the map's tiles as MODE 1 pixels, 16 bytes a line."""
    hm = L.heightmap()[0]
    out = bytearray(1024)
    grey = SW.cell(*SW.ALL[L.PADC])
    for line in range(64):
        z = (MAPZ - line) % 64
        for px in range(64):
            x = (px - MAPX) % 64
            if x < L.PADN and z < L.PADN:
                c = grey[(px & 1, line & 1)]
            elif all(hm[(z + dz) % L.MAP, (x + dx) % L.MAP] == L.SEA for dz in (0, 1) for dx in (0, 1)):
                c = 1
            else:
                c = 3
            p = px & 3
            out[line * 16 + (px >> 2)] |= ((c >> 1) << (7 - p)) | ((c & 1) << (3 - p))
    return out


def main():
    """Write gametab.inc to the directory named on the command line, or build/."""
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', 'build')
    thx, thz, thy = thrust()
    lines = ['; tools/gamegen.py: the game\'s tables (generated)']

    def emit(name, vals):
        lines.append(f'{name}:')
        for i in range(0, len(vals), 16):
            lines.append('        .byte ' + ', '.join(f'${v & 255:02X}' for v in vals[i:i + 16]))
    ns = [min(1023, round(10 * 1.15 ** t)) for t in range(CRASHT)]
    emit('EXNL', [0xC0 | (n & 15) for n in ns])
    emit('EXNH', [(n >> 4) & 63 for n in ns])
    emit('EXA', [0 if t < 2 else min(15, round((t - 2) * 15 / 22)) for t in range(CRASHT)])
    lines.append(f'NPITCH = {NPITCH}')
    lines.append(f'NDIR = {NDIR}')
    lines.append(f'PFLAT = {SG.PFLAT}')
    for name in ('THX', 'THZ'):
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
