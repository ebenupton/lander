# Lander for the BBC Micro

A Lander-style landscape and flight: a filled patchwork of land, a ship, fuel
and a map. One source tree builds two programs, and one disc carries both:

| build | machine | the frame |
|---|---|---|
| `base`, the 32K build | a Model B or B+ with nothing added | about 143,000 cycles in the reference flight |
| `swr`, the sideways RAM build | a Model B or B+ with four free 16K banks of sideways RAM; a Master 128 | about 120,500 |

The two are the same game drawn by the same renderer. The sideways RAM build
keeps in its banks the tables that 32K has no room for, and takes about a
sixth fewer cycles a frame. [docs/parity.md](docs/parity.md) lists every difference between them
and why it stands.

Each build comes in four colour versions:

| version | the land |
|---|---|
| `mode1` | MODE 1, four colours as 2 x 2 dithers |
| `cpc` | MODE 2, the CPC's 27 colours as dithers of the eight |
| `nula` | MODE 2, the VideoNuLA's sixteen colours |
| `arc` | MODE 2, Lander's own colours as dithers of the NuLA's |

## Running

`lander.ssd` boots with SHIFT+BREAK. The loader names the machine, looks for
sideways RAM (in any four sockets, written through ROMSEL or a Watford or
Solidisk board) and for a VideoNuLA, and offers what the machine can run. On a
Model B with sideways RAM, B switches between the two builds.

## Building

    sh build.sh                    everything: build/lander.ssd, copied to lander.ssd
    sh build.sh base|swr VERSION   one program, into build/base-VERSION or build/swr-VERSION
    sh build.sh loader             the disc's !BOOT
    sh build.sh disc               the disc, from the builds as they stand

Needs cc65 (ca65, ld65, od65) and Python 3 with numpy. The whole build takes
about ten seconds. Each program's build ends by printing its free block.

## The source

`src/lander.s` is the root of both programs; `-D SWR` selects the sideways RAM
build.

| file | contents | build |
|---|---|---|
| `ram.s` | the memory map of main RAM below the code: every variable and table, by address | both |
| `strips.s` | the frame, a strip of land at a time; the rows traced | both |
| `rungs.s` | each strip's rungs: where each pixel passes from box to box | both |
| `columns.s` | the strip's byte columns; runs of lines through generated store tables | both |
| `game.s` | the flight, the dots, the panel's gauge and map marker | both |
| `tabgen.s` | the tables and code made at start-up | both |
| `boot.s` | the start-up: takes the machine, puts the program in place | both |
| `project.s`, `mapgen.s` | the projection by multiplication; the map generated as it comes into view | `base` |
| `ship.s` | the ship, rasterised from its model | `base` |
| `video.s` | two 6845 frames a field, the clock switched in mid-line | `base` |
| `projswr.s`, `prow7.s` | the projection from stored maps and bank 7's tables | `swr` |
| `shipb.s`, `shipspan.s` | the ship, every orientation pre-rasterised, in bank 6 | `swr` |
| `videoswr.s` | one frame a field; the banks' paging | `swr` |
| `loader.s` | the disc's `!BOOT` | the disc |

## Documents

* [docs/memory-map.md](docs/memory-map.md): the rules of the layout, loading,
  the disc; with the generated maps [map-base.md](docs/map-base.md) and
  [map-swr.md](docs/map-swr.md), which account for every byte.
* [docs/video-timing.md](docs/video-timing.md): how the 32K build keeps every
  horizontal sync 64 µs from the last across two clock changes a field, and
  the b2 and jsbeeb measurements that prove it.
* [docs/parity.md](docs/parity.md): the optimisations of each build against
  the other's.

## Testing

    [SWR=1] [VERSION=mode1|cpc|nula|arc] sh test/gate.sh

builds one program and checks it. It prints `GATE PASS` with the flight's
cycles a frame, or `GATE FAIL` and the step.

| step | checks |
|---|---|
| the build | no errors or warnings; every assert in the source |
| `tools/stackdepth.py` | the worst-case stack fits; every bank's code runs with its bank paged in |
| `test/gametest.py` | a scripted flight under py65, every frame's state against `test/flight.txt`: both builds against the one baseline |
| `test/soak.py` | the land, byte for byte against the reference renderer in `proto/`, over random pans, a raised camera and jumps |
| `test/shiptest.py`, `test/shipswr.py` | the ship against its model |
| `tools/memmap.py check` | the maps in `docs/` are this build's |

The video timing is checked on the disc itself, in two emulators:

    sh tools/b2/build.sh     builds the headless b2 driver (once)
    sh tools/b2/all.sh       every build on every machine, at 20 boot phases each

## Tools

| tool | use |
|---|---|
| `gen.py`, `landgen.py`, `gamegen.py` | the generated includes; the sideways RAM build's bank images |
| `shipmodel.py`, `shipgen.py` | the ship's model; its pre-rasterised orientations |
| `mergebank.py` | a bank's code into its image |
| `mkdisc.py` | the disc, and the patch records that turn the shared bank images into each version's |
| `mkdfs.py` | a DFS disc image from files |
| `memmap.py` | the memory maps, from the linker's output |
| `stackdepth.py` | the worst-case stack, from the linked program |
| `padscan.sh` | the flight's cycles for each value of the renderer's page-phase pad |
| `zprank.py` | the variables zero page would save most on |
| `test/flightprof.py`, `test/cruise.py` | cycles by routine over a flight |
| `swatchdisc.py` | a disc of the 35 dithered colours' arrangements |
| `tools/b2/` | the video timing harness: b2 (`b2drive.cpp`, `b2sweep.sh`) and jsbeeb (`jhsync.mjs`, `jsweep.sh`) |
