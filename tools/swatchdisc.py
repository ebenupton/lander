#!/usr/bin/env python3
"""The swatch selector disc: a DFS image whose !BOOT (*EXEC) types in and runs a BASIC
program (MODE 1, black, cyan, magenta, yellow) showing, for each of proto/swatch35.py's
35 colours (k black, c cyan, m magenta, y yellow pixels in a 2 x 2 cell), a row: its
number on the left, then a 32 x 32 pixel swatch of each arrangement of its four
pixels in the cell, counted once up to a shift (a cell shifted a pixel across or down
tiles the same dither): the game's own (swatch35.cell) first, the rest after.
Swatches 4 pixels apart, rows 4 pixels apart, 6 rows a page (6 pages); SPACE turns the page.
A VideoNULA is reset first (its palette would otherwise survive BREAK; without one the
write is the ULA's, which MODE 1 then sets).

    python3 tools/swatchdisc.py [OUT]

OUT: the image; without it, swatch.ssd in build.sh's output directory (BUILD in the
environment, default build).
"""
import os
import sys
from itertools import permutations

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'proto'))
sys.path.insert(0, os.path.join(HERE, '..', 'test'))
import mkdfs            # noqa: E402
import rig              # noqa: E402  (BUILD)
import swatch35 as SW   # noqa: E402

POS = [(0, 0), (1, 0), (0, 1), (1, 1)]


def shifts(cell):
    """The four shifts of cell ({(x, y): ink}), as tuples in POS order."""
    return {tuple(cell[((x + dx) & 1, (y + dy) & 1)] for x, y in POS)
            for dx in (0, 1) for dy in (0, 1)}


def arrangements(kcmy):
    """The colour's arrangements up to a shift, as cells, the game's first."""
    inks = [SW.K] * kcmy[0] + [SW.C] * kcmy[1] + [SW.M] * kcmy[2] + [SW.Y] * kcmy[3]
    game = SW.cell(*kcmy)
    out, seen = [game], shifts(game)
    for p in sorted(set(permutations(inks))):
        c = dict(zip(POS, p))
        s = shifts(c)
        if not s & seen:
            seen |= s
            out.append(c)
    return out


def byte(cell, line):
    """MODE 1's byte for line parity `line` of the cell tiled: pixel p (0..3) takes
    the ink at (p & 1, line), logical colour c's high bit at bit 7 - p, low at 3 - p."""
    v = 0
    for p in range(4):
        c = cell[(p & 1, line)]
        v |= (c >> 1) << (7 - p) | (c & 1) << (3 - p)
    return v


PROGRAM = r'''10 VDU6:OSCLI"FX151,34,64":MODE1:VDU23,1,0;0;0;0;19,1,6;0;19,2,5;0;19,3,3;0;
20 DIM N%(34),E%(34,5),O%(34,5)
30 FORC%=0TO34:READN%(C%):FORI%=0TON%(C%)-1:READE%(C%,I%),O%(C%,I%):NEXT:NEXT
40 P%=0
50 CLS:VDU5:GCOL0,3
60 FORR%=0TO5:C%=P%*6+R%:IFC%<35 PROCrow
70 NEXT
80 MOVE0,31:PRINT"Page ";P%+1;" of 6   SPACE: next page";
90 REPEATUNTILGET=32:P%=(P%+1)MOD6:GOTO50
100 DEFPROCrow
110 Y%=4+R%*36:MOVE0,(255-Y%-12)*4:PRINT;C%;
120 FORI%=0TON%(C%)-1:X%=(6+9*I%)*8:FORL%=0TO31:Z%=Y%+L%
130 A%=&3000+(Z% DIV 8)*640+(Z% AND 7)+X%:IF Z% AND 1 THEN B%=O%(C%,I%) ELSE B%=E%(C%,I%)
140 FORJ%=0TO56STEP8:A%?J%=B%:NEXT:NEXT:NEXT
150 ENDPROC
'''


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(rig.BUILD, 'swatch.ssd')
    lines = PROGRAM.strip('\n').split('\n')
    n = 1000
    counts = []
    for e, kcmy in enumerate(SW.ALL):
        arr = arrangements(kcmy)
        assert len(arr) <= 6
        counts.append(len(arr))
        vals = [len(arr)] + [v for c in arr for v in (byte(c, 0), byte(c, 1))]
        lines.append(f'{n} DATA ' + ','.join(str(v) for v in vals))
        n += 10
    text = 'VDU21\rNEW\r' + '\r'.join(lines) + '\rRUN\r'
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    mkdfs.build(out, 'SWATCHES', [('!BOOT', text.encode(), 0, 0xFFFF)])
    print(f'{out}: 35 colours, {sum(counts)} arrangements ({counts})')


if __name__ == '__main__':
    main()
