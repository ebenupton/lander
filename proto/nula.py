#!/usr/bin/env python3
"""The NULA build's colours: MODE 2's sixteen logical colours, each given its own
12-bit colour through the VideoNULA palette, in place of MODE 1's 2 x 2 dithers.

Every tool and test asks enabled() (the environment's NULA set and not "0") and,
when it is, draws through this module.  The renderer itself is unchanged: it still
works in the MODE 1 build's pixels, 256 across, four to a byte; only its masks and
colour bytes differ.  A MODE 2 byte holds two pixels, the left in bits 7, 5, 3, 1
and the right in bits 6, 4, 2, 0 (colour bit 3 first), so each MODE 2 pixel is two
of the renderer's: it shows the even one of the pair, which is what mask() makes
of a MODE 1 mask (MODE 1 pixel 0 decides the left pixel, pixel 2 the right).  A
mask and its complement stay complements, so boxes meeting in a byte still tile
it.  Overlays placed by single pixels (the dots, the map's marker) take the MODE 2
pixel their pixel falls in instead (near()).

colour(e) is swatch35 entry e's logical colour: the entries the game uses are
given their own (PAL's order below), any other the nearest of them by average
colour.  solid(c) is colour c's byte (both pixels c); dither_bytes(e) the NULA
build's even and odd bytes for entry e (both solid(colour(e))).  The land and sea
use fewer entries than the MODE 1 build (proto/land.py's LAND, SEAC, which read
enabled()), so that black, three seas, the pad's grey, seven lands and the ship's
four colours fill the sixteen.

    python3 proto/nula.py   writes proto/nula.png: the sixteen colours with their
                            numbers and the entries they stand for
"""
import os

import swatch35 as SW


def enabled():
    return os.environ.get('NULA', '0') not in ('', '0')


def check_build(b):
    """Exit unless build directory b holds the build enabled() expects (build.sh's
    b/variant: nula or mode1)."""
    want = 'nula' if enabled() else 'mode1'
    try:
        got = open(os.path.join(b, 'variant')).read().strip()
    except OSError:
        got = 'mode1'
    if got != want:
        raise SystemExit(f'{b} holds the {got} build; NULA={int(enabled())} tests the {want} one '
                         f'(sh build.sh{" nula" if enabled() else ""}, or set NULA)')


# (swatch35 entry, use), in logical colour order 0..15
SLOTS = [(34, 'black: the sky, the margins'),
         (0, 'sea'), (15, 'sea'), (17, 'sea'),
         (19, 'the pad; the ship\'s floor'),
         (3, 'land'), (10, 'land; the fuel bar, the letters, the dots'),
         (11, 'land'), (16, 'land'), (22, 'land'), (26, 'land'), (28, 'land'),
         (30, 'the ship'), (20, 'the ship'), (9, 'the ship; the map\'s marker, old dots'),
         (8, 'the ship')]
LAND = [3, 10, 11, 16, 22, 26, 28]       # proto/land.py's LAND and SEAC under NULA
SEAC = [0, 15, 17]


def avg(e):
    """Entry e's average colour, 0..255 a channel."""
    cl = SW.cell(*SW.ALL[e])
    return tuple(sum(SW.PHYS[v][ch] for v in cl.values()) / 4 for ch in range(3))


def nib(v):
    """0..255 to a NULA channel, 0..15."""
    return min(15, int(v / 17 + 0.5))


PAL = [tuple(nib(c) for c in avg(e)) for e, _ in SLOTS]    # 4-bit r, g, b
YELLOW = [e for e, _ in SLOTS].index(10)                     # the HUD's and dots'
MAGENTA = [e for e, _ in SLOTS].index(9)                     # the marker's, old dots'
SEA, LANDC, PADC = 1, YELLOW, 4                              # the map's


def colour(e):
    """Swatch35 entry e's logical colour."""
    ents = [s for s, _ in SLOTS]
    if e in ents:
        return ents.index(e)
    a = avg(e)
    return min(range(16), key=lambda c: sum((x - y) ** 2 for x, y in zip(avg(ents[c]), a)))


def solid(c):
    """Logical colour c in both pixels of a MODE 2 byte."""
    v = 0
    for b in range(4):
        if c >> b & 1:
            v |= 3 << (2 * b)
    return v


def dither_bytes(e):
    """The NULA build's (even, odd) bytes for entry e."""
    b = solid(colour(e))
    return [b, b]


def mask(m):
    """A MODE 1 pixel mask (pixel p in bits 7 - p and 3 - p) as MODE 2's: the left
    pixel if MODE 1 pixel 0 is in it, the right if pixel 2 is."""
    return (0xAA if m & 0x88 else 0) | (0x55 if m & 0x22 else 0)


def near(m):
    """A MODE 1 pixel mask as the MODE 2 pixels its pixels fall in."""
    return (0xAA if m & 0xCC else 0) | (0x55 if m & 0x33 else 0)


def pixel(x):
    """The MODE 2 mask of the pixel virtual pixel x shows in (x & 3: 0, 1 left)."""
    return 0xAA if x & 2 == 0 else 0x55


def byte_of(img_row, c, enc):
    """Byte column c of a line: img_row (palette entry + 1 by virtual pixel, 0
    black), enc(entry) its colour byte."""
    v = 0
    for p, m in ((0, 0xAA), (2, 0x55)):
        e = img_row[4 * c + p]
        if e:
            v |= enc(e - 1) & m
    return v


# The NULA build's letters: 3 x 7 pixels in a 4 x 8 cell (a MODE 2 character is two
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
    for c, (rgb, (e, use)) in enumerate(zip(PAL, SLOTS)):
        d.rectangle([c * 60, 0, c * 60 + 59, 59], fill=tuple(17 * v for v in rgb))
        d.text((c * 60 + 2, 62), f'{c}: {e}', fill='black')
    im.save(os.path.join(os.path.dirname(__file__), 'nula.png'))


if __name__ == '__main__':
    main()
