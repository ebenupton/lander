#!/usr/bin/env python3
"""The MODE 2 builds' colours.  Two versions draw the game in MODE 2 in place of
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

variant() names the build the environment asks for (mode1 without either) and
enabled() is true for both MODE 2 builds; the generators (landgen, gamegen,
shipgen), proto/land.py and the soak and ship tests ask and, when it is, draw
through this module.  The renderer is the MODE 1 build's: it works in its pixels, 256 across, four to a byte, at that resolution;
only its masks and colour bytes differ.  A MODE 2 byte holds two pixels, the
left in bits 7, 5, 3, 1 and the right in bits 6, 4, 2, 0 (colour bit 3 first),
so each MODE 2 pixel is two of the renderer's: it shows the even one of the
pair, which is what mask() makes of a MODE 1 mask (MODE 1 pixel 0 decides the
left pixel, pixel 2 the right).  A mask and its complement stay complements, so
boxes meeting in a byte still tile it.  Overlays placed by single pixels (game.s's
dots and map marker) take the MODE 2 pixel their pixel falls in instead (pixel()).

dither_bytes(e) is the build's even and odd line bytes for swatch35 entry e.
NULA: colour(e) is e's logical colour, the entries the game uses given their
own (SLOTS' order), any other the nearest of them; both bytes solid(colour(e)).
The land and sea use fewer entries than the MODE 1 build (proto/land.py's LAND,
SEAC read nula()) so that black, three seas, the pad's grey, seven lands and the
ship's four colours fill the sixteen.  CPC: every entry the game uses (USED) is
given a different one of the 27 (cpcmap(): the assignment nearest overall in
average colour), any other its nearest; its bytes are the two colours' (pair) in
a checkerboard (pair's first colour in the even line's left pixel).
yelb(), magb() (mode2.inc's YELB, MAGB: yellow and magenta, the letters, the
fuel bar, the dots, the map's marker) are solid bytes; the map's colours are
entries (MAPSEA, MAPLAND, MAPPAD).  PIXM is the build's mask of each MODE 1 pixel.

    python3 proto/nula.py   writes proto/nula.png (the sixteen NULA colours, each
                            labelled logical colour: entry) and proto/cpc.png
                            (each entry the game uses as its CPC checkerboard,
                            labelled entry: levels)
"""
import functools
import os

import swatch35 as SW


def variant():
    """'nula', 'cpc' or 'mode1', from the environment's NULA and CPC."""
    on = lambda k: os.environ.get(k, '0') not in ('', '0')
    return 'nula' if on('NULA') else 'cpc' if on('CPC') else 'mode1'


def enabled():
    """A MODE 2 build (nula or cpc)."""
    return variant() != 'mode1'


def nula():
    return variant() == 'nula'


def cpc():
    return variant() == 'cpc'


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
                         f'(sh build.sh{arg}, or set NULA=1 / CPC=1 to match)')


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


PAL = [tuple(nib(c) for c in avg(e)) for e, _ in SLOTS]    # 4-bit r, g, b
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
    if cpc():
        a, b = pair(cpc_levels(e))           # a checkerboard: even line a left, b
                                             # right; odd line b left, a right
        return [solid(a) & 0xAA | solid(b) & 0x55, solid(b) & 0xAA | solid(a) & 0x55]
    b = solid(colour(e))
    return [b, b]


def yelb():
    """The yellow byte (letters, fuel bar, dots)."""
    return solid(3) if cpc() else solid(YELLOW)


def magb():
    """The magenta byte (the map's marker, old dots)."""
    return solid(5) if cpc() else solid(MAGENTA)


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
    for c, (lv, (e, _)) in enumerate(zip(PAL, SLOTS)):
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


if __name__ == '__main__':
    main()
