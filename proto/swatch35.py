#!/usr/bin/env python3
"""All 35 2x2 dithers of MODE 1's black, cyan, magenta and yellow (k + c + m + y = 4),
numbered, for picking a landscape palette: each shown as its dither (MODE 1's pixels,
2:1 wide... drawn square here) beside its average colour.

    python3 proto/swatch35.py  -> swatch35.png
"""
from itertools import product
from PIL import Image, ImageDraw

K, C, M, Y = 0, 1, 2, 3
PHYS = {K: (0, 0, 0), C: (0, 255, 255), M: (255, 0, 255), Y: (255, 255, 0)}
ORDER = [(0, 0), (1, 1), (1, 0), (0, 1)]       # the diagonals first: pairs are checkered


def cell(k, c, m, y):
    """The 2x2 cell: cyan from the front of ORDER, yellow then magenta from the back,
    black in between; SHEARED cells with their odd line's two pixels swapped (a shear
    by a pixel: their one ink filling a column becomes a diagonal, no vertical strips)."""
    out, back = {}, ORDER[::-1]
    for pos in ORDER[:c]:
        out[pos] = C
    for pos in back[:y]:
        out[pos] = Y
    for pos in back[y:y + m]:
        out[pos] = M
    for pos in ORDER:
        out.setdefault(pos, K)
    if (k, c, m, y) in SHEARED:
        out[(0, 1)], out[(1, 1)] = out[(1, 1)], out[(0, 1)]
    return out


ALL = [(k, c, m, y) for k, c, m, y in product(range(5), repeat=4) if k + c + m + y == 4]
ALL.sort(key=lambda t: (t[0], -t[1], -t[3], -t[2]))      # by darkness, then hue
SHEARED = {ALL[i] for i in (23, 26, 27)}                  # (vertical strips otherwise)


def main():
    S, cols = 6, 5
    w, h = 220, 70
    img = Image.new('RGB', (cols * w + 10, ((len(ALL) + cols - 1) // cols) * h + 10), (60, 60, 60))
    d = ImageDraw.Draw(img)
    for n, t in enumerate(ALL):
        x0, y0 = 10 + (n % cols) * w, 10 + (n // cols) * h
        cl = cell(*t)
        for yy in range(8):
            for xx in range(12):
                c = PHYS[cl[(xx & 1, yy & 1)]]
                d.rectangle([x0 + xx * S, y0 + yy * S, x0 + xx * S + S - 1, y0 + yy * S + S - 1], c)
        avg = tuple(sum(PHYS[v][ch] for v in cl.values()) // 4 for ch in range(3))
        d.rectangle([x0 + 12 * S + 4, y0, x0 + 12 * S + 44, y0 + 8 * S - 1], avg)
        d.text((x0 + 12 * S + 50, y0 + 8), f'{n:2d}', fill=(255, 255, 255))
        d.text((x0 + 12 * S + 50, y0 + 26), 'K%dC%dM%dY%d' % t, fill=(220, 220, 220))
    img.save('swatch35.png')


if __name__ == '__main__':
    main()
