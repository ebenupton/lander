"""The dither palette: MODE 1 set to black, cyan, magenta, yellow (logical 0-3), and
colours made of 2x2 cells of those four.

Each colour is a count of each ink in its cell (k + c + m + y = 4; 35 such).  The
cell's positions are filled in one fixed order: cyan from the front of ORDER, yellow
or magenta from the back, black in between.  So for each of C, M and Y, the positions
one colour gives that ink are a subset of another colour's, or contain them: where two
colours meet at a pixel boundary, any 2x2 window holds each pixel of the cell from one
colour or the other, so its count of each ink lies between the two colours' counts --
no spike.  (That needs no colour to have both magenta and yellow; none here does.)

PATTERNS[i][(x & 1, y & 1)] is colour i's logical colour at a pixel.
"""
from itertools import combinations

K, C, M, Y = 0, 1, 2, 3
ORDER = [(0, 0), (1, 1), (1, 0), (0, 1)]   # the diagonals first: pairs are checkered
RGB = {K: (0, 0, 0), C: (0, 1, 1), M: (1, 0, 1), Y: (1, 1, 0)}

#         name           k  c  m  y
PALETTE = [('yellow',      0, 0, 0, 4),
           ('mustard',     1, 0, 0, 3),
           ('lime',        0, 1, 0, 3),
           ('light green', 0, 2, 0, 2),
           ('leaf green',  1, 1, 0, 2),
           ('sea green',   1, 2, 0, 1),
           ('periwinkle',  0, 2, 2, 0),
           ('sky blue',    0, 3, 1, 0),
           ('steel blue',  1, 2, 1, 0)]


def pattern(k, c, m, y):
    assert k + c + m + y == 4 and not (m and y)
    cell = {}
    for pos in ORDER[:c]:
        cell[pos] = C
    back = ORDER[::-1]
    for pos in back[:m + y]:
        cell[pos] = M if m else Y
    for pos in ORDER:
        cell.setdefault(pos, K)
    return cell


PATTERNS = [pattern(*p[1:]) for p in PALETTE]


def rgb(i):
    """The cell's average colour, 0-1 per channel."""
    cell = PATTERNS[i]
    return tuple(sum(RGB[cell[p]][ch] for p in ORDER) / 4 for ch in range(3))


def _nested():
    for a, b in combinations(PATTERNS, 2):
        for ink in (C, M, Y):
            sa = {p for p in ORDER if a[p] == ink}
            sb = {p for p in ORDER if b[p] == ink}
            assert sa <= sb or sb <= sa, (a, b, ink)


_nested()


def byte(i, row):
    """Colour i's MODE 1 byte on a line of parity row: four pixels, x parity 0101."""
    v = 0
    for p in range(4):
        col = PATTERNS[i][(p & 1, row)]
        v |= ((col >> 1) << (7 - p)) | ((col & 1) << (3 - p))
    return v
