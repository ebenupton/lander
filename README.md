# bandfill

Two rows of nine points on random walks, joined by rungs between corresponding
points, and the eight boxes between them filled with 2x2 dithers of black, cyan,
magenta and yellow (MODE 1), on a narrow screen (256 x 160 MODE 1 pixels, 64 bytes a
line, 10K at $5800).  The BBC port of the prototype in `proto/ragged.py`, which it
matches pixel for pixel:

- the rows are shallow (every segment's |dy| < its width);
- each rung is steep (its bottom point more than its width below its top point) and
  stepped in y, one x per line, the boundary between two boxes;
- the bottom is ragged: each byte column is filled down to its lowest bottom-row
  point.

The three routines' cycle counts are printed at the top: `across` (the rows),
`down` (the rungs) and `fill`; any key draws a new frame.

| 300 random frames, mean cycles | across | down | fill |
|---|---|---|---|
| first port (`proto/points.py`, exact bottom, rungs stepped in x) | 23.6k (both) | | 50.1k |
| same semantics, optimised (`legacy/exact/`) | 3.3k | 2.0k | 34.6k |
| shape codes, ragged bottom | 1.8k | 2.0k | 27.9k |
| this version: two-column table, MOS workspace reclaimed, then four rounds of an agent farm over beebgame's dataflow annotations | 1.15k | 1.0k | 20.2k |

This version is specialised for the fixed geometry above (byte-aligned vertices, black
around the strip, the rows' first points fixed).  The next design (`proto/strip.py`:
free perspective x geometry, stackable strips, nothing outside a strip touched)
replaces it.

## Building

You need [cc65](https://cc65.github.io) (`ca65`, `ld65`) and Python 3 (with numpy, and
`py65` for the soak test).

```sh
sh build.sh                   # build/band.ssd: SHIFT+BREAK runs BAND
python3 test/check.py dump    # check a frame, from a dump of $3000-$7FFF
python3 test/soak.py 300      # run BAND's own code for 300 frames in py65, check each
python3 proto/ragged.py       # the prototype: proto/ragged.png, ragged_outline.png
```

`!BOOT` sets MODE 1 before loading BAND: BAND runs from $1900 past $3000, which a
mode change would clear.  `tools/gentab.py` writes the code and tables the fixed
geometry allows (`build/*.inc`); `tools/mkdfs.py` is beebgame's disc builder.
`src/main.s` describes the method and the memory layout.  `legacy/` holds the
earlier versions.
