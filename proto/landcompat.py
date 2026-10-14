#!/usr/bin/env python3
"""Compatibility swatches for the land colours (land.LAND) and the sea's (land.SEAC): for
each, an n x n grid of 64x64 squares, the square's colour by column, a 40x40 circle in it
of the colour by row, each dithered as the BBC shows it (swatch35's 2x2 cells, pixel for
pixel); the columns' colour numbers on a black border above.

    python3 proto/landcompat.py  -> landcompat.png, seacompat.png
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont

import land as L
import swatch35 as SW

SQ, D = 64, 40
TOP = 24                   # the black border above, with the column colours' numbers


def swatch(cols, path):
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
    im = Image.new('RGB', (n * SQ, n * SQ + TOP), (0, 0, 0))   # the numbers on black above
    im.paste(Image.fromarray(out), (0, TOP))
    d = ImageDraw.Draw(im)
    font = ImageFont.load_default(size=16)
    for k, e in enumerate(cols):
        d.text((k * SQ + SQ // 2, TOP // 2), str(e), fill=(255, 255, 255), font=font, anchor='mm')
    im.save(path)
    print(f'{path}: {n} colours {cols}: squares by column, circles by row')


def main():
    swatch(L.LAND, 'landcompat.png')
    swatch(L.SEAC, 'seacompat.png')


if __name__ == '__main__':
    main()
