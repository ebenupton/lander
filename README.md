# Lander for the BBC Micro

A port of David Braben's *Lander* (the 1987 Archimedes demo that became *Zarch*) to
the BBC Micro Model B: a 3D landscape you fly over in Lander's ship, with Lander's
flight model, a landing pad, fuel, a map and sound, at about ten frames a second on
a 2 MHz 6502.

The disc image is `lander.ssd` (also built to `build/lander.ssd`).  It needs a Model B
with 64K of sideways RAM (four writable 16K banks in any sockets, written through
ROMSEL or a Watford or Solidisk write-select board) and a DFS.  In jsbeeb choose
"BBC B with 8271 (DFS 1.2)" and load the disc; SHIFT+BREAK boots it.

## Playing

| Key | Action |
|---|---|
| Z / X (or cursor left / right) | yaw left / right |
| K / M (or cursor up / down) | pitch nose down / nose up |
| SPACE or SHIFT | thrust |
| F | frame-rate readout on / off |

With a mouse at &FCAC-&FCAF (found at start; the movement since the last read, as
some Master upgrades provide) the mouse flies the ship as in Lander, and the
keys above no longer steer.  The pointer's offset from where it was when the
ship last spawned sets the target heading (its direction) and how far the nose
tips that way (its distance: level near the centre, the full 60 degrees about
160 mouse units out).  The ship moves halfway to each target every step.  Left
button: full thrust.  Middle: hover, a quarter of the thrust for a bit over half
the fuel (Lander's buttons; the right, Lander's fire, does nothing).

You start level on the pad, the grey square in the middle of the map.  Thrust pushes
the ship along its roof, so tip the nose the way you want to go.  Land slowly and
within one pitch step of level, anywhere on the pad, to refuel; touch the ground
anywhere else, or the pad too fast or too tilted, and the ship is destroyed and, four
seconds later, back on the pad.  The engines cut out once the landscape has sunk off
the bottom of the screen; the ship then coasts up and falls back.

## The VideoNULA version

`lander-nula.ssd` is the same game in MODE 2 for a BBC Micro or Master fitted with a
VideoNULA: sixteen flat
12-bit colours in place of MODE 1's dithers (black, three seas, the pad's grey, seven
lands and four for the ship; each the average of the dither it replaces).  Without a
NULA it runs with MODE 2's standard colours.  The renderer is unchanged: it still
works in MODE 1's pixels, 256 across, and each MODE 2 pixel shows the even one of the
two it covers, which only its masks and colour bytes have to know about.  The
palette, the colours' assignments and the 3 x 7 letters are in `proto/nula.py`.

```sh
sh build.sh nula               # build/lander.ssd, the NULA version
NULA=1 sh test/run.sh          # its tests (the same reference, MODE 2's bytes)
```

## The CPC-palette version

`lander-cpc.ssd` is MODE 2 on any BBC Micro or Master, no NULA needed: the "Amstrad
CPC palette", the 27 colours whose red, green and blue are each off, half or full,
made as 1 x 2 dithers of MODE 2's eight colours (two MODE 2 pixels one above the
other are about square), the phase toggled on alternate columns so each is a
checkerboard, a half channel lit on one pixel of the two.  Every colour the game uses gets a different one of the 27, the nearest
assignment overall (`proto/nula.py`); the renderer is the NULA version's.

```sh
sh build.sh cpc                # build/lander.ssd, the CPC-palette version
CPC=1 sh test/run.sh           # its tests
```

## Building and testing

You need [cc65](https://cc65.github.io) (`ca65`, `ld65`) and Python 3 with `numpy`.
The tests need [`py65`](https://github.com/mnaberez/py65); the optional renders need
Pillow.

```sh
sh build.sh          # build/lander.ssd
sh test/run.sh       # the test suite (a few minutes)
```

The build is deterministic: the disc images it produces are byte for byte the ones
checked in (`test/identical.sh` checks all three).

The tests run the game's own 6502 code in py65; the first two compare its output byte
for byte with the Python reference model:

- `test/landsoak.py` renders random pans of the landscape (one run with the ship
  drawn, another with the camera raised at random) and checks every frame's
  projected rows against `proto/land.py` and every byte of its screen against
  `proto/frame.py`;
- `test/shipbtest.py` draws every one of the ship's 416 orientations (13 pitches by
  32 directions) over a random screen and checks every byte against
  `tools/shipgen.py`'s reference rasteriser;
- `test/gametest.py` runs the whole game loop with scripted keys and prints the
  ship's state each frame: a check that it runs, and a harness for poking at the
  flight model.

## Layout

| Path | What |
|---|---|
| `src/land.s` | the renderer, the main loop, start-up and the sideways-RAM loader |
| `src/game.s` | the game: controls, flight model, pad, dots, camera, map, sound (bank 5) |
| `src/shipb.s`, `src/shipspan.s` | the ship: the bank's entries, the span walker and the decoder (bank 6) |
| `src/land.cfg`, `src/shipb.cfg` | ld65 configurations |
| `tools/landgen.py` | the renderer's tables for banks 4, 5 and 7 |
| `tools/shipgen.py` | the ship: pre-rotated, pre-rasterised, compressed orientations |
| `tools/gamegen.py` | the game's tables: thrust, the ship's screen line, the map, the crash's sound |
| `proto/nula.py` | the MODE 2 versions' palettes, colours, masks and letters |
| `tools/mergebank.py`, `tools/mkdfs.py` | code segments into the bank images; the DFS disc |
| `build.sh`, `lander.ssd`, `lander-nula.ssd`, `lander-cpc.ssd` | the build, and the disc images it makes |
| `proto/` | the Python reference model the 6502 matches pixel for pixel |
| `test/` | the test suite (`test/run.sh` runs it) |
| `ref/lander/` | what was taken from Lander: the ship blueprint, the flight model, notes |

## How it works

**The landscape.** Lander's height map (its six-sine altitude formula, rescaled to a
wrapping 64 x 64 tile map with 16 height units a tile) is seen from a camera 13 tiles
behind the ship and six tiles above the ground under it, looking along z with no yaw,
so the grid projects to rows of points at fixed depths.  `tools/landgen.py` bakes the
projection into tables in sideways bank 7, by a row's depth: its y for every height,
its corners' x for every fraction of the camera's x, and its ends on the side clip
planes, so projecting a frame is table lookups and additions with no multiplies.  The
near and far clip planes replace the rows they cut by interpolated ones, the rows end
on clip planes 4.5 tiles either side of the line of sight, and a row pushed below the
screen (the camera raised) is held just off it.

**Filling.** Each pair of adjacent rows bounds a strip, drawn far to near.  A strip's
rows are traced into a line-per-pixel table, its rungs (the segments joining
corresponding points) into transition tables, and then each byte column of the strip
is filled from its top to its floor: as one box (a single tile colour) where no rung
crosses the column, split at the rung otherwise (two or more rungs in one column take
slower ways).  Fills are runs through unrolled store tables entered at the first line
and ended by an RTS planted at the line after the last, so a run costs its stores and
little else.  The screen is double buffered; for each screen and column, the highest
and lowest lines the landscape reached the last time that screen was drawn are kept,
so the next frame on it blacks exactly what has gone.  Tiles are coloured from the 35
2 x 2 dithers of MODE 1's four colours: ten for land, picked by height and by slope
(lit from the left) with a per-tile scatter, four for sea and a grey for the pad.

**The ship.** Lander's ship is pre-rotated and pre-projected for 13 pitches (60
degrees nose up to 60 nose down, 10 apart) by 32 directions, 17 of them stored and
the rest drawn mirrored.  Each stored orientation is rasterised line by line into the
boundaries between its faces and compressed, in bands, to 4-bit deltas; bank 6
decodes the current orientation into a buffer when it changes and draws it with a
span walker that reads the boundaries forwards or backwards.  The ship is always
drawn at the same depth, so one view angle serves.

**The game.** Lander's flight model (gravity, thrust along the roof, drag, fuel) runs
one step per frame, with the constants scaled for ten frames a second; the frame rate
is held to 12.5 at most.  The camera rises with the ship once the ship comes within
79 height units of it, up to a limit past which the landscape is drawn below the
screen and the ship holds its line.  The exhaust dots are single pixels moved by the
same rule in coarser units.  Sound is the SN76489's noise channel: a quiet roar while
thrusting and, for the crash, a crack that drops to a rumble and fades.

**Memory.** The program loads at $1900; the two screens are at $3000 and $5800
(256 x 160 pixels, with a 64-line panel for the fuel bar, the readout and the map).
Bank 4 holds the height map, the renderer's tables and some of its code, bank 5 the
tile colours and the game, bank 6 the ship, bank 7 the projection's tables and code.
The loader finds four writable banks in whichever sockets hold RAM (free ones first);
every bank switch in play goes through a map of their sockets, and on a Watford or
Solidisk board the loader patches the board's write-select store into the paging
routines.

## Credits

Lander is by David Braben; the source studied is Mark Moxon's annotated reconstruction
of it at [lander.bbcelite.com](https://lander.bbcelite.com).  The sideways-RAM loader and
the disc builder come from [beebgame](https://github.com/ebenupton/beebgame).  Built
with [cc65](https://cc65.github.io); tested with [py65](https://github.com/mnaberez/py65).
