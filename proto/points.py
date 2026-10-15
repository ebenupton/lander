#!/usr/bin/env python3
"""The pixel geometry the models share: the screen, line tracing and PNG output.

The screen is W x H = 256 x 160 pixels: the narrow MODE 1 screen (64 bytes a line,
four pixels a byte, so byte column c is pixels 4c..4c+3), of which the land uses
lines YSKY..YGND (frame.py).  A point is (x, y) in pixels, y down, integers
throughout.

A row of points is traced into a line by pixel: one y for each x from the row's
first point to its last (trace), each segment by bresenham_ys.  That is only a
line if every segment is shallow, |dy| < dx (or has no length: the two points the
same), which land.project's rows are and strip.ok checks; land.s's traceb steps the
same algorithm, one y a pixel, and relies on it.  A rung (a top row point to the
bottom row point under it) is stepped the other way, one x a line, by the same
routine with x and y swapped (ragged.boundary).

N and SD are strip.py's random rows: nine points (eight boxes) and the normal step
of their y walk.  SCALE is save's enlargement.  DIR is this directory: every model's
main writes its PNGs here.
"""
import os

W, H = 256, 160
N = 9
SD = 5
SCALE = 4
DIR = os.path.dirname(os.path.abspath(__file__))


def bresenham_ys(x0, y0, x1, y1):
    """One y for each x from x0 to x1 inclusive, x1 >= x0 (x1 == x0: [y0] alone).

    The nearest y to the line at each x, a half rounding towards y1; the last is
    y1.  A steep segment steps y several times in a column and keeps one y, so a
    row's trace is only a line when its segments are shallow."""
    dx = x1 - x0
    dy = y1 - y0
    sy = 1 if dy >= 0 else -1
    ady = abs(dy)
    y = y0
    err = dx                                  # (the error in 1/2dx: half a step)
    ys = [y]
    for _ in range(dx):
        err += 2 * ady
        while err >= 2 * dx:
            y += sy
            err -= 2 * dx
        ys.append(y)
    return ys


def trace(points):
    """The row's line: {x: y} over every consecutive pair of its points, which must
    have non-decreasing x.  A shared x takes the later segment's y (the same point
    when the segments meet there)."""
    line = {}
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        for i, y in enumerate(bresenham_ys(x0, y0, x1, y1)):
            line[x0 + i] = y
    return line


def save(img, name):
    """img, an (H, W, 3) RGB array, to DIR/name.png and, SCALE times larger with
    square pixels, DIR/name_x4.png."""
    from PIL import Image
    im = Image.fromarray(img, mode='RGB')
    im.save(os.path.join(DIR, f'{name}.png'))
    im.resize((W * SCALE, H * SCALE), Image.NEAREST).save(os.path.join(DIR, f'{name}_x4.png'))
