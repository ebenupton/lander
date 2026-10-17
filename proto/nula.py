#!/usr/bin/env python3
"""The MODE 2 builds' colours.  Three versions draw the game in MODE 2 in place of
MODE 1's 2 x 2 dithers of black, cyan, magenta and yellow:

  nula  (NULA=1, build.sh nula): MODE 2's sixteen logical colours, each given its
        own 12-bit colour through the VideoNULA palette (PAL), flat.
  cpc   (CPC=1, build.sh cpc): the "Amstrad CPC palette": every colour whose
        red, green and blue are each off, half or full, 27 of them, made on a
        plain BBC Micro as a 1 x 2 dither of MODE 2's eight colours (two MODE 2
        pixels one above the other are about square), its phase toggled on
        alternate columns: a checkerboard, one colour on even lines' left pixels
        and odd lines' right, the other on the rest.  A half channel is on in one
        pixel of the two.
  arc   (ARC=1, build.sh arc): Lander's own colours (proto/land.py's arc_tile and
        colour: a tile's kind and slope, brightened by its row), each the
        checkerboard of the pair of sixteen VideoNULA colours (ARCPAL, fit()'s)
        nearest it.

variant() names the build the environment asks for (mode1 without any) and
enabled() is true for the MODE 2 builds; the generators (landgen, gamegen,
shipgen), proto/land.py and the soak and ship tests ask and, when it is, draw
through this module.  The renderer is the MODE 1 build's: it works in its pixels, 256 across, four to a byte, at that resolution;
only its masks and colour bytes differ.  A MODE 2 byte holds two pixels, the
left in bits 7, 5, 3, 1 and the right in bits 6, 4, 2, 0 (colour bit 3 first),
so each MODE 2 pixel is two of the renderer's: it shows the even one of the
pair, which is what mask() makes of a MODE 1 mask (MODE 1 pixel 0 decides the
left pixel, pixel 2 the right).  A mask and its complement stay complements, so
boxes meeting in a byte still tile it.  Overlays placed by single pixels (game.s's
dots and map marker) take the MODE 2 pixel their pixel falls in instead (pixel()).

dither_bytes(e) is the build's even and odd line bytes for entry e.
NULA: colour(e) is e's logical colour, the entries the game uses given their
own (SLOTS' order), any other the nearest of them; both bytes solid(colour(e)).
The land and sea use fewer entries than the MODE 1 build (proto/land.py's LAND,
SEAC read nula()) so that black, three seas, the pad's grey, seven lands and the
ship's four colours fill the sixteen.  CPC: every entry the game uses (USED) is
given a different one of the 27 (cpcmap(): the assignment nearest overall in
average colour), any other its nearest; its bytes are the two colours' (pair) in
a checkerboard (pair's first colour in the even line's left pixel).  arc: the
entries go on past swatch35's 35 (entries()): LENT + 16 kind + b is Lander's
colour kind at brightness b (lrgb), which land.colour gives the tiles and
shipgen the ship's faces; every entry's bytes are its colour's pick() in a
checkerboard, as the CPC build's.
yelb(), magb() (mode2.inc's YELB, MAGB: yellow and magenta, arc's pale yellow
and orange: the letters, the fuel bar, the dots, the map's marker) are solid
bytes; the map's colours are entries (MAPSEA, MAPLAND, MAPPAD).  PIXM is the
build's mask of each MODE 1 pixel.

    python3 proto/nula.py   writes proto/nula.png (the sixteen NULA colours, each
                            labelled logical colour: entry), proto/cpc.png
                            (each entry the game uses as its CPC checkerboard,
                            labelled entry: levels) and proto/arc.png (arc_png:
                            a frame in Lander's colours and as the arc build
                            shows it, and ARCPAL)
"""
import functools
import os

import swatch35 as SW


def variant():
    """'arc', 'nula', 'cpc' or 'mode1', from the environment's ARC, NULA and CPC."""
    on = lambda k: os.environ.get(k, '0') not in ('', '0')
    return 'arc' if on('ARC') else 'nula' if on('NULA') else 'cpc' if on('CPC') else 'mode1'


def enabled():
    """A MODE 2 build (arc, nula or cpc)."""
    return variant() != 'mode1'


def nula():
    return variant() == 'nula'


def cpc():
    return variant() == 'cpc'


def arc():
    return variant() == 'arc'


def check_build(b):
    """Exit unless build directory b holds the build variant() expects (build.sh's
    b/variant)."""
    want = variant()
    try:
        got = open(os.path.join(b, 'variant')).read().strip()
    except OSError:
        got = 'mode1'
    if got != want:
        arg = '' if want == 'mode1' else ' ' + want
        raise SystemExit(f'{b} holds the {got} build, the environment asks for {want} '
                         f'(sh build.sh{arg}, or set ARC=1 / NULA=1 / CPC=1 to match)')


# (swatch35 entry, use), in logical colour order 0..15
SLOTS = [(34, 'black: the sky, the margins'),
         (0, 'sea'), (15, 'sea'), (17, 'sea'),
         (19, 'the pad; the ship\'s floor'),
         (3, 'land'), (10, 'land; the fuel bar, the letters, the dots'),
         (11, 'land'), (16, 'land'), (22, 'land'), (26, 'land'), (28, 'land'),
         (30, 'the ship'), (20, 'the ship'), (9, 'the ship; the map\'s marker, old dots'),
         (8, 'the ship')]
ENTS = [e for e, _ in SLOTS]
LAND = [e for e, u in SLOTS if u.startswith('land')]   # proto/land.py's LAND and SEAC
SEAC = [e for e, u in SLOTS if u == 'sea']             # under NULA


def dist2(a, b):
    return sum((x - y) ** 2 for x, y in zip(a, b))


def avg(e):
    """Entry e's average colour, 0..255 a channel."""
    cl = SW.cell(*SW.ALL[e])
    return tuple(sum(SW.PHYS[v][ch] for v in cl.values()) / 4 for ch in range(3))


def nib(v):
    """0..255 to a NULA channel, 0..15."""
    return min(15, int(v / 17 + 0.5))


NPAL = [tuple(nib(c) for c in avg(e)) for e, _ in SLOTS]   # 4-bit r, g, b
PAL = NPAL                                                 # the build's (landgen)
YELLOW = ENTS.index(10)                                      # the HUD's and dots'
MAGENTA = ENTS.index(9)                                      # the marker's, old dots'


def colour(e):
    """Swatch35 entry e's logical colour."""
    if e in ENTS:
        return ENTS.index(e)
    return min(range(16), key=lambda c: dist2(avg(ENTS[c]), avg(e)))


def solid(c):
    """Logical colour c in both pixels of a MODE 2 byte."""
    v = 0
    for b in range(4):
        if c >> b & 1:
            v |= 3 << (2 * b)
    return v


MAPSEA, MAPLAND, MAPPAD = 0, 10, 19                        # the map's entries

# The CPC build.  A colour is its levels (r, g, b), each 0, 1 (half) or 2 (full);
# MODE 2's colours are 1 red, 2 green, 4 blue.
CPC27 = [(r, g, b) for r in range(3) for g in range(3) for b in range(3)]
USED = [34] + [3, 6, 10, 11, 16, 18, 21, 22, 26, 28] + [0, 2, 15, 17] + [19, 30, 20, 9, 8, 13]
LUMA = (0.30, 0.59, 0.11)


def rgb(lv):
    return tuple(127.5 * v for v in lv)


@functools.cache
def cpcmap():
    """{entry: levels} for USED, each a different colour, the total squared distance
    from the entries' average colours least (scipy's assignment)."""
    from scipy.optimize import linear_sum_assignment
    cost = [[dist2(avg(e), rgb(lv)) for lv in CPC27] for e in USED]
    rows, cols = linear_sum_assignment(cost)
    return {USED[r]: CPC27[c] for r, c in zip(rows, cols)}


def cpc_levels(e):
    """Entry e's CPC colour: cpcmap()'s, or for an entry the game does not use the
    nearest of the 27."""
    m = cpcmap()
    if e in m:
        return m[e]
    return min(CPC27, key=lambda lv: dist2(avg(e), rgb(lv)))


def pair(lv):
    """Levels lv as two MODE 2 colours (even line, odd line): the full channels in
    both, each half channel in one, the brighter halves first, each to the line so
    far the darker (even on a tie)."""
    ev = od = 0
    le = lo = 0.0
    for ch in sorted((ch for ch in range(3) if lv[ch] == 1), key=lambda ch: -LUMA[ch]):
        if le <= lo:
            ev |= 1 << ch
            le += LUMA[ch]
        else:
            od |= 1 << ch
            lo += LUMA[ch]
    full = sum(1 << ch for ch in range(3) if lv[ch] == 2)
    return ev | full, od | full


def dither_bytes(e):
    """The MODE 2 build's (even, odd) bytes for entry e."""
    if cpc() or arc():
        a, b = pick(lrgb(e)) if arc() else pair(cpc_levels(e))
        # a checkerboard: even line a left, b right; odd line b left, a right
        return [solid(a) & 0xAA | solid(b) & 0x55, solid(b) & 0xAA | solid(a) & 0x55]
    b = solid(colour(e))
    return [b, b]


def yelb():
    """The yellow byte (letters, fuel bar, dots)."""
    return solid(3) if cpc() else solid(ARCYEL) if arc() else solid(YELLOW)


def magb():
    """The magenta byte (the map's marker, old dots; the arc build's orange)."""
    return solid(5) if cpc() else solid(ARCORA) if arc() else solid(MAGENTA)


# The arc build: Lander's own colours.  A colour is (kind, b): ARCK[kind]'s red,
# green and blue (0..15) each plus brightness b, held at 15, then packed as Lander
# packs it for VIDC's 256-colour mode (vidc).  Kinds 0..3 are the land (Lander's
# altitude bits 2 and 3: red 4, green 8 more), 4 the pad, 5 the sea, 6..8 the ship's
# other colours (ARCSHIP: the model's &rgb's kinds).  Entry LENT + 16 kind + b (the
# swatch35 entries, 0..34, below) is (kind, b): land.colour's and shipgen's.
ARCK = [(0, 4, 0), (4, 4, 0), (0, 8, 0), (4, 8, 0), (4, 4, 4), (0, 0, 4),
        (0, 8, 8), (0, 4, 4), (12, 8, 0)]
ARCSHIP = {0x080: 2, 0x040: 0, 0x088: 6, 0x044: 7, 0xC80: 8}
LENT = 35                                                  # the first (kind, b) entry
NENT = LENT + 16 * len(ARCK)                               # entries in all
ARCLAM = 0.1                                               # pick's dither penalty
# The sixteen colours (fit()'s, 4-bit r, g, b): black, Lander's, and an orange (the
# marker, old dots; the exhaust's nearest)
ARCPAL = [(0, 0, 0), (1, 5, 2), (0, 10, 2), (4, 8, 4), (4, 12, 4), (6, 6, 10), (6, 10, 6),
          (9, 9, 5), (8, 8, 12), (7, 15, 7), (11, 11, 7), (9, 13, 9), (10, 10, 14),
          (11, 15, 11), (14, 14, 10), (15, 8, 0)]
ARCYEL, ARCORA = 14, 15                                    # the letters', the marker's
if arc():
    PAL = ARCPAL                                           # (landgen's NULAPAL)
    MAPSEA, MAPLAND, MAPPAD = 35 + 16 * 5 + 6, 35 + 16 * 2 + 6, 35 + 16 * 4 + 6


def vidc(r, g, b):
    """Lander's colour (r, g, b, each held at 15) as VIDC's 256-colour mode shows it:
    bits 3 and 2 of each channel kept, bits 1 and 0 of all three the OR of theirs
    (the tint)."""
    r, g, b = min(15, r), min(15, g), min(15, b)
    t = (r | g | b) & 3
    return (r & 12 | t, g & 12 | t, b & 12 | t)


def entries():
    """The build's entries: swatch35's, and in the arc build Lander's colours."""
    return NENT if arc() else LENT


def lentry(kind, b):
    return LENT + 16 * kind + b


def lrgb(e):
    """Entry e's colour, 0..15 a channel: Lander's for e >= LENT, else the average of
    swatch35 dither e."""
    if e < LENT:
        return tuple(v / 17 for v in avg(e))
    k, b = divmod(e - LENT, 16)
    return vidc(*(c + b for c in ARCK[k]))


def _lin(v):
    """0..15 (an array) to linear light."""
    import numpy as np
    return (np.asarray(v, float) / 15) ** 2.2


def _oklab(x):
    """Linear RGB (rows) to Oklab."""
    import numpy as np
    m1 = np.array([[0.4122214708, 0.5363325363, 0.0514459929],
                   [0.2119034982, 0.6806995451, 0.1073969566],
                   [0.0883024619, 0.2817188376, 0.6299787005]])
    m2 = np.array([[0.2104542553, 0.7936177850, -0.0040720468],
                   [1.9779984951, -2.4285922050, 0.4505937099],
                   [0.0259040371, 0.7827896400, -0.8086757660]])
    return np.cbrt(np.asarray(x) @ m1.T) @ m2.T


def _pairs(pal):
    """Every pair (a <= b) of pal's colours: (a's, b's, the pair's Oklab, its
    penalty), the pair seen as the average of its two in linear light, the penalty
    ARCLAM times the two's own distance (a coarse checkerboard costs)."""
    import numpy as np
    a, b = np.triu_indices(len(pal))
    lp = _lin(pal)
    ok = _oklab(lp)
    return a, b, _oklab((lp[a] + lp[b]) / 2), ARCLAM * np.linalg.norm(ok[a] - ok[b], axis=1)


@functools.cache
def pick(rgb):
    """The pair of ARCPAL's colours (a, b) nearest colour rgb (0..15 a channel), its
    penalty added."""
    import numpy as np
    a, b, ok, pen = _pairs(ARCPAL)
    d = np.linalg.norm(ok - _oklab(_lin(rgb)), axis=1) + pen
    i = int(d.argmin())
    return int(a[i]), int(b[i])


def fit():
    """ARCPAL afresh: black, orange (15, 8, 0) and fourteen more, chosen to bring the
    colours the game shows nearest their pairs (pick).  The colours: every tile's at
    each row (land.arc_tile; rows 4..10 a weight (20 - j)^-2, near rows' tiles being
    larger, the pad's three times), and the ship's faces' at every pitch, a weight
    0.2% each; the weights to the power 0.25 (rare colours count for more), the sum
    of each colour's weight times its distance (with the pair's penalty) least, by
    stepping each colour's channels from six random starts."""
    import collections
    import math
    import sys
    import numpy as np
    import land as L
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'ref', 'lander'))
    import ship as SH
    hm = L.heightmap()
    w = collections.Counter()
    for z in range(L.MAP):
        for x in range(L.MAP):
            k, s = L.arc_tile(hm, x, z)
            for j in range(4, 11):
                w[lrgb(lentry(k, j + s))] += (20 - j) ** -2 * (3 if k == 4 else 1)
    tot = sum(w.values())
    for p in range(13):
        a = math.radians((p - 6) * 10)
        for f in SH.FACES:
            ny = math.sin(a) * f['normal'][0] / SH.ONE + math.cos(a) * f['normal'][1] / SH.ONE
            for nx in (1, -1):
                br = SH.lander_brightness(nx, int(ny * SH.ONE))
                w[lrgb(lentry(ARCSHIP[f['colour']], min(15, br)))] += 0.002 * tot
    tg = list(w)
    wt = np.array([w[t] for t in tg]) ** 0.25
    wt /= wt.sum()
    tl = _oklab(_lin(tg))

    def cost(pal):
        _, _, ok, pen = _pairs(pal)
        return (wt * (np.linalg.norm(tl[:, None] - ok[None], axis=2) + pen).min(1)).sum()
    rng = np.random.default_rng(1)
    best = None
    for _ in range(6):
        pal = np.array(tg)[rng.choice(len(tg), 16, replace=False, p=wt)]
        pal[0], pal[15] = (0, 0, 0), (15, 8, 0)
        c = cost(pal)
        better = True
        while better:
            better = False
            for s in range(1, 15):
                for ch in range(3):
                    for dv in (-1, 1, -2, 2):
                        q = pal.copy()
                        q[s, ch] += dv
                        if 0 <= q[s, ch] <= 15 and cost(q) < c - 1e-9:
                            pal, c, better = q, cost(q), True
        if best is None or c < best[0]:
            best = (c, pal)
    pal = sorted(map(tuple, best[1][1:15].tolist()), key=lambda t: (sum(t), t))
    return [(0, 0, 0)] + pal + [(15, 8, 0)]


def mask(m):
    """A MODE 1 pixel mask (pixel p in bits 7 - p and 3 - p) as MODE 2's: the left
    pixel if MODE 1 pixel 0 is in it, the right if pixel 2 is."""
    return (0xAA if m & 0x88 else 0) | (0x55 if m & 0x22 else 0)


def pixel(x):
    """The MODE 2 mask (left 0xAA, right 0x55) of the pixel renderer pixel x falls
    in: x & 3 0, 1 left; 2, 3 right."""
    return 0xAA if x & 2 == 0 else 0x55


PIXM = [mask(m) if enabled() else m for m in (0x88, 0x44, 0x22, 0x11)]


# The MODE 2 builds' letters: 3 x 7 pixels in a 4 x 8 cell (a MODE 2 character is two
# bytes, four pixels), for the characters the game shows (land.s's gchars, lchars).
FONT = {
    '0': ['###', '#.#', '#.#', '#.#', '#.#', '#.#', '###'],
    '1': ['.#.', '##.', '.#.', '.#.', '.#.', '.#.', '###'],
    '2': ['###', '..#', '..#', '###', '#..', '#..', '###'],
    '3': ['###', '..#', '..#', '.##', '..#', '..#', '###'],
    '4': ['#.#', '#.#', '#.#', '###', '..#', '..#', '..#'],
    '5': ['###', '#..', '#..', '###', '..#', '..#', '###'],
    '6': ['###', '#..', '#..', '###', '#.#', '#.#', '###'],
    '7': ['###', '..#', '..#', '.#.', '.#.', '.#.', '.#.'],
    '8': ['###', '#.#', '#.#', '###', '#.#', '#.#', '###'],
    '9': ['###', '#.#', '#.#', '###', '..#', '..#', '###'],
    '.': ['...', '...', '...', '...', '...', '...', '.#.'],
    ' ': ['...'] * 7,
    'F': ['###', '#..', '#..', '##.', '#..', '#..', '#..'],
    'P': ['##.', '#.#', '#.#', '##.', '#..', '#..', '#..'],
    'S': ['.##', '#..', '#..', '.#.', '..#', '..#', '##.'],
    'U': ['#.#', '#.#', '#.#', '#.#', '#.#', '#.#', '###'],
    'E': ['###', '#..', '#..', '##.', '#..', '#..', '###'],
    'L': ['#..', '#..', '#..', '#..', '#..', '#..', '###'],
    'A': ['.#.', '#.#', '#.#', '###', '#.#', '#.#', '#.#'],
    'N': ['#.#', '###', '###', '###', '#.#', '#.#', '#.#'],
    'D': ['##.', '#.#', '#.#', '#.#', '#.#', '#.#', '##.'],
    'C': ['.##', '#..', '#..', '#..', '#..', '#..', '.##'],
    'R': ['##.', '#.#', '#.#', '##.', '#.#', '#.#', '#.#'],
    'H': ['#.#', '#.#', '#.#', '###', '#.#', '#.#', '#.#'],
}


def font_rows(ch):
    """Character ch's 8 rows as land.s's glyph code takes a definition: pixel i of
    the cell (0..3) in bits 7 - 2 i and 6 - 2 i (the two pixels a MODE 2 pixel is
    made from)."""
    out = []
    for r in FONT[ch] + ['...']:
        v = 0
        for i, c in enumerate(r):
            if c == '#':
                v |= 3 << (6 - 2 * i)
        out.append(v)
    return out


def main():
    from PIL import Image, ImageDraw
    im = Image.new('RGB', (16 * 60, 90), 'white')
    d = ImageDraw.Draw(im)
    for c, (lv, (e, _)) in enumerate(zip(NPAL, SLOTS)):
        d.rectangle([c * 60, 0, c * 60 + 59, 59], fill=tuple(17 * v for v in lv))
        d.text((c * 60 + 2, 62), f'{c}: {e}', fill='black')
    im.save(os.path.join(os.path.dirname(__file__), 'nula.png'))
    phys = [(255 * (c & 1), 255 * (c >> 1 & 1), 255 * (c >> 2 & 1)) for c in range(8)]
    m = cpcmap()
    im = Image.new('RGB', (len(USED) * 50, 90), 'white')
    d = ImageDraw.Draw(im)
    for i, e in enumerate(USED):
        a, b = pair(m[e])
        for y in range(60):
            for x in range(0, 50, 2):
                d.rectangle([i * 50 + x, y, i * 50 + x + 1, y], fill=phys[(a, b)[(x >> 1 ^ y) & 1]])
        d.text((i * 50 + 2, 62), f'{e}: {m[e]}', fill='black')
    im.save(os.path.join(os.path.dirname(__file__), 'cpc.png'))
    arc_png(os.path.join(os.path.dirname(__file__), 'arc.png'))


def arc_png(path, cx=40 << 8, cz=30 << 8):
    """The arc build's palette, and a frame's land (camera (cx, cz)) twice: in
    Lander's colours exactly (lrgb), and as the build shows it, MODE 2's pixels in
    ARCPAL's pairs (pick) as checkerboards; each 3 x 3."""
    import numpy as np
    from PIL import Image
    import land as L
    import strip as S
    hm = L.heightmap()
    xs, rows = L.project(hm, cx, cz)
    h, w = 160, 256
    exact = np.zeros((h, w, 3))
    bbc = np.zeros((h, w, 3))
    pal = np.array(ARCPAL) * 17
    nr = len(rows) - 1
    for k, ((_, top), (z, bot)) in enumerate(zip(rows, rows[1:])):
        m = S.mask([p[:2] for p in top], [p[:2] for p in bot])
        for i, x in enumerate(xs[:-1]):
            kd, sl = L.arc_tile(hm, x, z)
            e = lentry(kd, 10 - nr + k + 1 + sl)
            ys, xx = np.nonzero(m == i)
            exact[ys, xx] = np.array(lrgb(e)) * 17
            a, b = pick(lrgb(e))
            bbc[ys, xx] = pal[np.where(((xx >> 1) ^ ys) & 1, b, a)]
    bbc[:, 1::2] = bbc[:, 0::2]
    sw = np.zeros((16, w, 3))
    for c in range(16):
        sw[:, c * 16:c * 16 + 15] = pal[c]
    out = np.concatenate([np.concatenate([exact, np.zeros((h, 8, 3)), bbc], 1),
                          np.zeros((8, 2 * w + 8, 3)),
                          np.concatenate([sw, np.zeros((16, w + 8, 3))], 1)], 0).astype(np.uint8)
    Image.fromarray(out).resize((out.shape[1] * 3, out.shape[0] * 3), Image.NEAREST).save(path)


if __name__ == '__main__':
    main()
