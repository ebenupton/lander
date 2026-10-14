#!/usr/bin/env python3
"""A compatibility swatch for the land colours (land.LAND): an n x n grid of 64x64 squares,
the square's colour by column, a 40x40 circle in it of the colour by row, each dithered as
the BBC shows it (swatch35's 2x2 cells, pixel for pixel).

    python3 proto/landcompat.py  -> landcompat.png
"""
import numpy as np
from PIL import Image

import land as L
import swatch35 as SW

SQ, D = 64, 40


def main():
    cols = L.LAND
    n = len(cols)
    idx = np.zeros((n * SQ, n * SQ), dtype=int)
    yy, xx = np.mgrid[0:SQ, 0:SQ]
    c = (SQ - 1) / 2
    disc = (xx - c) ** 2 + (yy - c) ** 2 <= (D / 2) ** 2
    for r in range(n):
        for k in range(n):
            idx[r * SQ:(r + 1) * SQ, k * SQ:(k + 1) * SQ] = np.where(disc, cols[r], cols[k])
    cells = [SW.cell(*t) for t in SW.ALL]
    out = np.zeros(idx.shape + (3,), dtype=np.uint8)
    for y in range(idx.shape[0]):
        for x in range(idx.shape[1]):
            out[y, x] = SW.PHYS[cells[idx[y, x]][(x & 1, y & 1)]]
    Image.fromarray(out).save('landcompat.png')
    print(f'{n} colours {cols}: squares by column, circles by row')


if __name__ == '__main__':
    main()
