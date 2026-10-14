#!/usr/bin/env python3
"""Prototype: 256x160 bitmap with rows of 9 points on random walks in y."""
import sys
import numpy as np
from PIL import Image

W, H = 256, 160
N = 9
SD = 5
# Each row: (centre x, spacing, starting y). Rows are centred on x = 128.
ROWS = [
    (128, 24, 80),   # x 32..224
    (128, 28, 100),  # x 16..240
]
SCALE = 4


def make_points(rng, cx, spacing, y0):
    xs = cx + spacing * (np.arange(N) - (N - 1) // 2)
    steps = np.rint(rng.normal(0, SD, N - 1)).astype(int)
    ys = np.concatenate([[y0], y0 + np.cumsum(steps)])
    return list(zip(xs.tolist(), ys.tolist()))


def bresenham_ys(x0, y0, x1, y1):
    """One y per x from x0 to x1 inclusive (x1 > x0).

    Always steps in x; for steep segments the inner loop advances y several
    times per column, so only one y (the nearest to the true line) is kept.
    """
    dx = x1 - x0
    dy = y1 - y0
    sy = 1 if dy >= 0 else -1
    ady = abs(dy)
    y = y0
    err = dx  # start at half a pixel (scaled by 2*dx) to round to nearest
    ys = [y]
    for _ in range(dx):
        err += 2 * ady
        while err >= 2 * dx:
            y += sy
            err -= 2 * dx
        ys.append(y)
    return ys


def line_ys(x0, y0, x1, y1):
    """Map x -> y for a segment in either x direction.

    Endpoints are swapped so Bresenham always steps in +x. A vertical
    segment (x0 == x1) keeps only the first endpoint's y.
    """
    if x1 == x0:
        return {x0: y0}
    if x1 < x0:
        x0, y0, x1, y1 = x1, y1, x0, y0
    return {x0 + i: y for i, y in enumerate(bresenham_ys(x0, y0, x1, y1))}


def trace(points):
    """Map x -> y across all consecutive point pairs."""
    line = {}
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        for i, y in enumerate(bresenham_ys(x0, y0, x1, y1)):
            line[x0 + i] = y
    return line


def span_box(x, below, rungs):
    """Box index for a span in column x, either below or above rung records.

    Counts the rungs the span lies to the right of. Only a rung that has a
    record in this column needs its slant consulted: below a '/' rung (or a
    vertical one) is to its right, above a '\\' rung is to its right.
    """
    right = 0
    for rung, x_top, x_bot in rungs:
        lo, hi = min(x_top, x_bot), max(x_top, x_bot)
        if x > hi:
            right += 1
        elif x >= lo:
            slash = x_bot <= x_top
            if (below and slash) or (not below and not slash):
                right += 1
    return min(max(right - 1, 0), len(rungs) - 2)


def fill(top, bot, rungs, colours):
    """Fill each column between its records; a rung record splits two boxes."""
    img = np.zeros((H, W, 3), dtype=np.uint8)
    spans = {}
    for x in range(W):
        recs = [line[x] for line in (top, bot) if x in line]
        rung_y = next((r[x] for r, _, _ in rungs if x in r), None)
        if rung_y is not None:
            recs.append(rung_y)
        recs.sort()
        if len(recs) == 2:
            # One record must be a rung or both rows; either way one box.
            below = rung_y is not None and rung_y == recs[0]
            b = span_box(x, below, rungs)
            img[recs[0]:recs[1] + 1, x] = colours[b]
            spans[x] = [(recs[0], recs[1], b)]
        elif len(recs) == 3:
            y0, y1, y2 = recs
            b_up = span_box(x, False, rungs)
            b_dn = span_box(x, True, rungs)
            img[y0:y1, x] = colours[b_up]
            img[y1:y2 + 1, x] = colours[b_dn]
            spans[x] = [(y0, y1, b_up), (y1, y2, b_dn)]
    return img, spans


def outline(img, rows, rungs):
    img = img.copy()
    for rung, _, _ in rungs:
        for x, y in rung.items():
            img[y, x] = (80, 80, 80)
    for points, line in rows:
        for x, y in line.items():
            img[y, x] = (40, 40, 40)
        for x, y in points:
            img[y, x] = (0, 0, 0)
    return img


def save(img, name):
    im = Image.fromarray(img, mode="RGB")
    im.save(f"{name}.png")
    im.resize((W * SCALE, H * SCALE), Image.NEAREST).save(f"{name}_x4.png")


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else None
    rng = np.random.default_rng(seed)
    rows = []
    for r, (cx, spacing, y0) in enumerate(ROWS):
        points = make_points(rng, cx, spacing, y0)
        line = trace(points)
        rows.append((points, line))
        print(f"row {r}: " + " ".join(f"({x},{y})" for x, y in points))
    # Rungs: join corresponding points on the two rows.
    (top_pts, top), (bot_pts, bot) = rows
    rungs = []
    for (x0, y0), (x1, y1) in zip(top_pts, bot_pts):
        rungs.append((line_ys(x0, y0, x1, y1), x0, x1))
    # Pastel: each channel in the upper part of the range.
    colours = [tuple(int(c) for c in rng.integers(150, 256, 3))
               for _ in range(len(rungs) - 1)]
    for b, c in enumerate(colours):
        print(f"box {b}: #{c[0]:02x}{c[1]:02x}{c[2]:02x}")
    img, spans = fill(top, bot, rungs, colours)
    three = [x for x, s in spans.items() if len(s) == 2]
    print(f"columns filled: {len(spans)} ({len(three)} split by a rung)")
    for x in (20, 32, 50, 128, 154, 230):
        print(f"  x={x}: " + ", ".join(f"y {a}..{b} box {k}" for a, b, k in spans[x]))
    save(img, "fill")
    save(outline(img, rows, rungs), "fill_outline")


if __name__ == "__main__":
    main()
