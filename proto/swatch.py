#!/usr/bin/env python3
"""Preview the dither palette: each colour's 2x2 dither with MODE 1's (near-square) pixels,
its average, and its cell pattern."""
import os
import sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import palette as PL  # noqa: E402

PHYS = {0: (0, 0, 0), 1: (0, 255, 255), 2: (255, 0, 255), 3: (255, 255, 0)}
S = 4                                           # image pixels per MODE 1 pixel, square
img = Image.new('RGB', (40 * S + 260, len(PL.PALETTE) * 26 * S // 2 + 8), (40, 40, 40))
d = ImageDraw.Draw(img)
for i, (name, *_) in enumerate(PL.PALETTE):
    y0 = 4 + i * 13 * S
    for y in range(12 * S // S):
        for x in range(40):
            col = PHYS[PL.PATTERNS[i][(x & 1, y & 1)]]
            d.rectangle([x * S, y0 + y * S, x * S + S - 1, y0 + y * S + S - 1], col)
    avg = tuple(int(255 * v) for v in PL.rgb(i))
    d.rectangle([40 * S + 6, y0, 40 * S + 60, y0 + 12 * S - 1], avg)
    cells = ''.join('KCMY'[PL.PATTERNS[i][p]] for p in [(0, 0), (1, 0), (0, 1), (1, 1)])
    d.text((40 * S + 68, y0 + 10), f'{name}  {cells[:2]}/{cells[2:]}', fill=(255, 255, 255))
img.save('swatch.png')
