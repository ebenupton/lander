#!/usr/bin/env python3
"""Check a frame of BAND against a model of it, from a dump of $3000-$7FFF.

    python3 test/check.py dump.bin

The rows (PTS0, PTS1): x = 20, 30 .. 100, the first y 80 and 68, each step within
10, the top row in 16..127 and the bottom 8..16 below it.  The interpolation
(OUT0, OUT1): Bresenham, err = dx/2, as bres does.  The screen below the readout's
two character rows: the fill (each byte column from the lower of the top row's
pair to the higher of the bottom row's, yellow; a lone even last x, its left
pixel), then both rows in white, then the points in red -- every byte.
"""
import sys

BASE = 0x3000
OUT0, PTS0, OUT1, PTS1, SCREEN = 0x3A00, 0x3A80, 0x3B00, 0x3B80, 0x4000

def bres(pts):
    out = {}
    for s in range(8):
        x0, y0, x1, y1 = pts[2*s], pts[2*s+1], pts[2*s+2], pts[2*s+3]
        dx, dy, sy = x1 - x0, abs(y1 - y0), (1 if y1 >= y0 else -1)
        err, y = dx // 2, y0
        for x in range(x0, x1):
            out[x] = y
            err -= dy
            if err < 0:
                y += sy
                err += dx
    out[pts[16]] = pts[17]
    return out

def addr(x, y):
    m = 127 - y
    return SCREEN + (m // 4) * 512 + (m % 4) * 2 + (x // 2) * 8

def plot(scr, x, y, colour):
    mask = 0x33 if x & 1 else 0xCC
    for a in (addr(x, y), addr(x, y) + 1):
        scr[a] = (scr.get(a, 0) & ~mask & 0xFF) | (colour & mask)

def main():
    mem = open(sys.argv[1], 'rb').read()
    rd = lambda a: mem[a - BASE]
    p0 = [rd(PTS0 + i) for i in range(18)]
    p1 = [rd(PTS1 + i) for i in range(18)]
    bad = []
    xs = list(range(20, 101, 10))
    if p0[0::2] != xs or p1[0::2] != xs: bad.append('x coordinates')
    if p0[1] != 80 or p1[1] != 68: bad.append('first points')
    for i in range(9):
        if not 16 <= p0[2*i+1] <= 127: bad.append('top row out of range at %d' % i)
        if not 8 <= p0[2*i+1] - p1[2*i+1] <= 16: bad.append('gap at %d' % i)
        if i and (abs(p0[2*i+1] - p0[2*i-1]) > 10 or abs(p1[2*i+1] - p1[2*i-1]) > 10):
            bad.append('gradient at %d' % i)
    r0, r1 = bres(p0), bres(p1)
    x0, x8 = p0[0], p0[16]
    ierr = sum(rd(OUT0 + x) != r0[x] for x in range(x0, x8 + 1)) + \
           sum(rd(OUT1 + x) != r1[x] for x in range(x0, x8 + 1))
    scr = {}
    for x in range(x0, x8 + 1, 2):
        pair = [x, x + 1] if x + 1 <= x8 else [x]
        top = min(r0[i] for i in pair)
        bot = max(r1[i] for i in pair)
        val = 0xF0 if len(pair) == 2 else 0xC0
        for y in range(bot, top + 1):
            a = addr(x, y)
            scr[a] = scr[a + 1] = val
    for r in (r0, r1):
        for x in range(x0, x8 + 1):
            plot(scr, x, r[x], 0xFF)
    for p in (p0, p1):
        for i in range(9):
            plot(scr, p[2*i], p[2*i+1], 0x0F)
    serr = sum(rd(a) != scr.get(a, 0) for a in range(SCREEN + 1024, 0x8000))
    print('rows', p0[1::2], p1[1::2])
    print('interpolation errors', ierr, ' screen byte errors', serr, ' (of %d)' % (0x8000 - SCREEN - 1024))
    for b in bad: print('constraint:', b)
    sys.exit(1 if ierr or serr or bad else 0)

main()
