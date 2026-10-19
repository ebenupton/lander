# Lander for the 32K BBC Micro

A Lander-style landscape and flight for an unexpanded Model B: no sideways RAM, the
whole program, its tables and two screens in 32K.

## Building

    sh b32/build32.sh [mode1|cpc|nula|arc]     one version: build32/lander32[-VERSION].ssd
    sh b32/build32.sh disc                     all four and a chooser: build32/lander32-all.ssd

| version | the land                                                     |
|---------|--------------------------------------------------------------|
| mode1   | MODE 1, four colours as 2 x 2 dithers                         |
| cpc     | MODE 2, the CPC's 27 colours as dithers of the eight          |
| nula    | MODE 2, the VideoNULA's sixteen colours                       |
| arc     | MODE 2, Lander's own colours as dithers of the NULA's         |

The disc boots with SHIFT+BREAK.  Its chooser (`src/menu32.bas`) tests for a VideoNULA
and offers the NULA versions only when one is fitted.  Needs cc65 (ca65, ld65, od65)
and Python 3 with numpy; the generators and the tests use the references in `proto/`
and `tools/`.

## The program

`src/lander.s` is the root; the modules, in the code's order:

| file        | contents                                                          |
|-------------|-------------------------------------------------------------------|
| `ram.s`     | the memory map: every variable and table, by address              |
| `project.s` | the camera's rows of projected corners; the tiles' colours        |
| `mapgen.s`  | the 64 x 64 map, generated as it comes into view                  |
| `strips.s`  | the frame, a strip of land at a time; the rows traced             |
| `rungs.s`   | each strip's rungs: where each pixel passes from box to box       |
| `columns.s` | the strip's byte columns; runs of lines through the parity tables |
| `game.s`    | the flight, the dots, the panel's gauge and map marker            |
| `ship.s`    | the ship, rasterised from the model when its attitude changes     |
| `video.s`   | the display's interrupt (two CRTC frames a field), the flip       |
| `boot.s`    | the loader, run once from the land buffers                        |

The display is a field of two CRTC frames: a MODE 5 panel (FUEL, the gauge and a map
of the whole terrain) above the land, double buffered.  The clock switches between
them land at exact microseconds, inside lines whose length is chosen to keep every
horizontal sync 64us after the last, as a real display needs (`video.s`).

## Memory

Data, then code, then the screen, with no interleaving:

| from      | to        |                                                               |
|-----------|-----------|---------------------------------------------------------------|
| `$0000`   |           | the data (`ram.s`), then the stored tables                    |
|           |           | free                                                          |
| computed  | `$4900`   | the code, linked to end exactly here                          |
| `$4900`   | `$4D3F`   | the four parity tables (generated), code in their pages' tails |
| `$4D40`   | `$4FFF`   | the panel: FUEL, the gauge, the map                           |
| `$5000`   | `$7FFF`   | the two land buffers                                          |

The MOS keeps `$FC`, the vectors at `$0200`, the top of the stack and the NMI's RTI at
`$0D00`.  `LANDER` loads at `$2000`; the loader copies its parts into place, makes the
generated tables and code, and clears itself away.  The build prints the free bytes.

## Testing

    [VERSION=...] sh b32/test/gate32.sh [base]

builds and checks a version: no warnings, the worst-case stack within the stack's bytes
(`tools/stackdepth.py`), a scripted flight's every frame against a baseline (`base`
writes it), the land byte for byte against `proto/` over random and jumping pans, and
the ship against its model (`tools/ship32.py`).  It prints the flight's cycles a frame.

| test               | checks                                                     |
|--------------------|------------------------------------------------------------|
| `gametest32.py`    | the game in py65, frame by frame                           |
| `soak32.py`        | the renderer against `proto/land.py` and `proto/frame.py`  |
| `shiptest32.py`    | the ship against `tools/ship32.py`                         |
| `profile32.py`     | cycles, page crossings and data accesses over a flight     |
| `cruise32.py`      | fast flight's cycles by routine                            |

## Tools

| tool              | use                                                              |
|-------------------|------------------------------------------------------------------|
| `gen32.py`        | the generated includes: constants, colours, map and game tables   |
| `ship32.py`       | the ship's model data, and the reference the ship is tested by    |
| `stackdepth.py`   | the worst-case stack, from the linked program                     |
| `padscan.sh`      | the flight's cycles for each value of a page-phase pad            |
| `zprank.py`       | the variables zero page would save most on                        |
| `hprobe.mjs`      | the hsync spacing in jsbeeb                                       |
| `eprobe.mjs`      | the display interrupt's events and writes in jsbeeb               |
| `b2probe.patch`   | a probe for b2, whose TV checks the sync timing strictly          |
| `swatchdisc.py`   | a disc of the 35 dithered colours' arrangements                   |
