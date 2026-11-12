# The memory map

Lander is one source tree that builds two programs:

* **the 32K build** (`base`), for a Model B or B+ with nothing added;
* **the sideways RAM build** (`swr`, assembled with `-D SWR`), for a Model B
  or B+ with four free 16K banks of sideways RAM, and for a Master 128. It
  spends the extra 64K on tables and is the faster of the two.

Each comes in four colour versions (`mode1`, `cpc`, `nula`, `arc`), and all
eight programs go on one disc with a loader that offers what the machine can
run. This document gives the rules both layouts follow, how the programs get
from the disc to their places, and what checks the layout at each build. The
maps themselves are written by `tools/memmap.py` from the linker's output,
byte for byte:

* [map-base.md](map-base.md): the 32K build;
* [map-swr.md](map-swr.md): the sideways RAM build, with its four banks.

Every variable, table and free byte in main RAM appears in them with its
address, its size and its use.

## The two builds side by side

<!-- generated: summary -->
|  | the 32K build | the sideways RAM build |
|---|---|---|
| zero page | `$00`-`$F8`, 3 bytes free below `$FC` | `$00`-`$F7`, 4 bytes free below `$FC` |
| page 1 below the stack | 228 bytes of data | 161 bytes of data |
| the stack | 28 bytes; the worst case needs 27 | 95 bytes; the worst case needs 26 |
| page 2 | 250 bytes | 250 bytes |
| the workspace | `$0300`-`$14FC` | `$0300`-`$0CFF`, `$0E00`-`$10BC` |
| the stored tables | 890 bytes at `$14FD` | 96 bytes at `$10BD` |
| the free block | 222 bytes at `$1877` | 1639 bytes at `$111D` |
| the code | 12232 bytes, `$1B18`-`$48FF` and the pages after | 4766 bytes, `$1784`-`$27FF` and the pages after |
| code made at start-up | 1039 bytes | 1160 bytes |
| the screen | the panel, 704 bytes at `$4D40`; two land buffers of 6144, `$5000` and `$6800` | two screens of 10240 bytes, `$3000` and `$5800` |
| the start-up code (discarded) | 1683 bytes | 1190 bytes |
| free in main RAM, in all | 270 bytes | 2220 bytes |
| free in the banks | none | 4: 1905, 5: 4334, 6: 326, 7: 999 |
<!-- end -->

## The rules

1. **Data, then code, then the screen.** Main RAM is three runs in that order
   and they are never interleaved. The data starts at zero page. The code ends
   exactly at a fixed address (`$4900` in the 32K build, `$2800` in the
   sideways RAM build); the build measures the code and sets its start,
   `__PROG__`, to make it so. All the free memory is therefore one block,
   between the last byte of data and the first of code, and its size is the
   last thing each build prints.

2. **Every byte of data has a declared address.** `src/ram.s` lays the data
   out with `.org`, in address order, for both builds. What both builds hold
   is declared once. Zero page's shared part, `$00` to `$CA`, is at the same
   addresses in both, so that shared code assembles to the same bytes. The
   stored tables (segment `TABLES`: constants, and the few variables with
   initial values) follow the data.

3. **The MOS keeps what is its own.** After `takeover` the MOS never runs
   again: IRQ1V points at the program's `irq`, nothing calls the MOS, and
   BREAK is the way out. Its bytes are still left alone:
   * `$FC`, where its interrupt entry saves A before it jumps through IRQ1V,
     and `$FD` to `$FF`;
   * the vectors at `$0200` to `$0205`;
   * the top of page 1, the stack;
   * page `$0D`. On a Model B the NMI vector points at `$0D00`, and the 32K
     build keeps an `RTI` there. On a Master the page holds live NMI code and
     the extended vectors, so the sideways RAM build never writes it: its
     workspace is two runs, `$0300` to `$0CFF` and `$0E00` on, and an assert
     fails the build if the first run does not end at `$0D00`.

4. **The stack is budgeted.** `tools/stackdepth.py` walks the call graph from
   the main loop and from `irq`, following the patched jumps as they are
   assembled, and the gate fails if the main loop's deepest call, an interrupt
   on top of it and an NMI on top of that do not fit. The 32K build gives the
   stack 28 bytes and needs 27. The sideways RAM build gives it at least 64.
   What is below the stack in page 1 is data.

5. **Generated code and tables are not stored.** The fill routines, the
   division and line tables, and the tables of `STA` instructions that the
   column drawer runs are made at start-up by `src/tabgen.s`, which is then
   discarded. Only what cannot be computed cheaply is in the file.

6. **Alignment is asserted.** Where code depends on a table's place in its
   page (an index that must not carry, a pair of tables a page apart, a low
   byte that is a screen line), an `.assert` beside the declaration says so.
   The timed branches of the 32K build's interrupt handler are asserted to
   stay within their pages for the same reason
   ([video-timing.md](video-timing.md)).

7. **One layout for every version.** The four versions of a build differ in
   colour tables, palette code and, for `arc`, a few routines. The modules are
   padded so that the hot code has the same addresses in each, and one pad
   (`COREPAD`), tuned with `tools/padscan.sh`, sets the renderer's place
   against the page boundaries for all four.

8. **One bank at a time** (the sideways RAM build). Bank 4 is paged in
   whenever the renderer runs and holds its tables. The game (bank 5), the
   ship (bank 6) and the far rows' projection (bank 7) are entered through
   stubs in main RAM that page their bank in and bank 4 back. The banks are
   wherever the loader found RAM: every paging routine reads the socket from
   `BANKMAP`. Interrupts page nothing.

9. **A bank's image is tables first, code in the gaps.** `tools/gen.py`
   places the tables each bank needs at the page alignments they need.
   `tools/mergebank.py` then puts the bank's code (segments `B4CODE`,
   `B5CODE`, `B7CODE`) into the image at its linked address and fails if the
   two overlap. Bank 6 is linked on its own (`src/shipb.s`).

## From the disc to memory

SHIFT+BREAK runs `!BOOT`, the loader (`src/loader.s`), at `$7000`. It reads
the machine type, looks for four sockets of sideways RAM and for a VideoNuLA,
and shows a MODE 7 menu of the versions this machine can run. While files load
the layout is:

| from | to | contents |
|---|---|---|
| `$0000` | `$1FFF` | the MOS's and the filing system's |
| `$2000` | `$59FF` | `BASE`, the 32K build's one file (at most) |
| `$3000` | `$6FFF` | `STAGE`: a bank's image, then `MAIN` (the sideways RAM build) |
| `$7000` | `$76FF` | the loader |
| `$7C00` | `$7FFF` | the MODE 7 screen |

**The 32K build.** `d.BASE` loads at `$2000` and is entered at its execution
address, `start`. The file holds the stored parts in address order (`TABLES`,
`CODE`, the tails of the parity pages) and the start-up code (`BOOT`) last.
`takeover` disables interrupts for good, zeroes the data, and copies each
stored part down to where it runs; every destination is below every later
source, so a forward copy is safe. The start-up code runs where it was loaded,
which the link places inside land buffer 0. It builds the tables, sets the
6845 and the palette, shows land buffer 1 (black), and leaves through a
22-byte stub copied to `RTBUF` that blacks its own pages and jumps to the main
loop. Nothing of the loader or the start-up code survives the first frame.

**The sideways RAM build.** A filing system loads into main RAM only, so each
bank's image loads at `STAGE` and is copied into its bank: `$.BANK7`,
`$.BANK6`, `d.BANK5`, `$.BANK4`. Then `d.MAIN` loads at `STAGE` and is entered
with X and Y pointing at five bytes: the four sockets and the board's write
select (plain, Watford or Solidisk). Its start-up is the same code as the 32K
build's with three more steps: it patches the paging routines for the board's
write select, applies the version's patch records to banks 4, 6 and 7, and
pages bank 4 in.

**Shared banks and patch records.** Banks 4, 6 and 7 are nearly the same in
all four versions, so the disc holds the MODE 1 version's images once. Each
other version's differences (colour patterns, and the `arc` version's set-up
code) are a list of records at the end of its `MAIN`: a bank, an address, a
length and the bytes. `tools/mkdisc.py` computes them and rebuilds every
version's banks from the shared images and its records, byte for byte, before
it writes the disc.

<!-- generated: disc -->
The disc is an 80-track single-sided DFS image, boot option 2 (`*RUN !BOOT`):

| file | load | exec | bytes | sectors |
|---|---|---|---|---|
| `$.!BOOT` | `$7000` | `$7000` | 1686 | 7 |
| `$.BANK4` | `$3000` | `$3000` | 16161 | 64 |
| `$.BANK6` | `$3000` | `$3000` | 16271 | 64 |
| `$.BANK7` | `$3000` | `$3000` | 16384 | 64 |
| `M.BASE` | `$2000` | `$545B` | 14805 | 58 |
| `M.MAIN` | `$3000` | `$42FE` | 6052 | 24 |
| `M.BANK5` | `$3000` | `$3000` | 12049 | 48 |
| `C.BASE` | `$2000` | `$5483` | 14825 | 58 |
| `C.MAIN` | `$3000` | `$42FE` | 6578 | 26 |
| `C.BANK5` | `$3000` | `$3000` | 12049 | 48 |
| `N.BASE` | `$2000` | `$547B` | 14862 | 59 |
| `N.MAIN` | `$3000` | `$42FE` | 6623 | 26 |
| `N.BANK5` | `$3000` | `$3000` | 12049 | 48 |
| `A.BASE` | `$2000` | `$5455` | 14823 | 58 |
| `A.MAIN` | `$3000` | `$438C` | 7328 | 29 |
| `A.BANK5` | `$3000` | `$3000` | 12022 | 47 |

16 files in 730 of the disc's 800 sectors (two are the catalogue), 70 free.
The patch records are 2110 bytes in all.
<!-- end -->

## What checks the layout

At assembly and link:

* `ram.s`'s asserts: zero page ends below `$FC`; page 2 ends at `$0300`; the
  workspace meets page `$0D` exactly; the stack's size; every alignment in
  rule 6;
* the linker's memory areas: any overflow of data into code, code into the
  screen, or a store page's code into its table is a link error;
* `boot.s`: the start-up code lies wholly inside the pages its stub clears.

At build:

* `tools/mergebank.py`: no bank's code overlaps its tables;
* `tools/mkdisc.py`: the patch records rebuild every bank exactly; `MAIN`
  ends below the second screen; the catalogue and the disc's 800 sectors.

At the gate (`test/gate.sh`, once for each of the eight programs):

* `tools/stackdepth.py`: the stack budget of rule 4;
* `tools/memmap.py check`: the maps in `docs/` are the ones this build
  produces, so a change to the layout cannot be committed without its map;
* the flight, the soak and the ship tests, which run the linked image under
  a 6502 emulator and compare every frame with the reference.
