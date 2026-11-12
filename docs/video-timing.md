# The video timing

A television locks to a horizontal sync every 64 µs and a vertical sync every
312 lines. Both builds give it exactly that on every line of every field. The
sideways RAM build gets it for nothing; the 32K build has to work for it, and
this is the account of how, and of the measurements that say it does.

Times here are in microseconds from a line's start, or in cycles of the 2 MHz
clock (128 a line). Source: `src/video.s` (the 32K build), `src/videoswr.s`,
and the frame set-up in `src/boot.s`.

## The field

Both builds show a 312-line field of 39 character rows, eight lines each, with
the vertical sync on row 28.

| | the sideways RAM build | the 32K build |
|---|---|---|
| 6845 frames a field | one | two |
| rows 0-7 | the panel, MODE 1 or 2, from the shown screen | the panel, MODE 5 (1 MHz), from `TOP` |
| rows 8-19 | the land, MODE 1 or 2 | the land, MODE 1 or 2 (2 MHz) |
| screen memory | two of 10,240 bytes | two of 6,144 bytes and one panel of 704 |
| interrupts | the vertical sync | the vertical sync and four timer events |
| clock changes a field | none | two, each in mid-line |

The sideways RAM build has two whole screens, so its display is one ordinary
frame and its only interrupt counts fields. Every line is 64 µs because nothing
ever changes.

The 32K build cannot afford 4,096 bytes of panel in each of two screens. Its
panel is drawn once, in MODE 5, whose 1 MHz characters cover the same width in
half the bytes; and it is cut down further, to one row 32 characters wide and
seven rows 8 wide, 704 bytes in all (`TOP`). The land below it is
double-buffered at 2 MHz. That is two 6845 frames in each field (a vertical
rupture), with the video ULA's clock switched between them: once from 1 MHz to
2 MHz at the top of the land, and once back below it.

## Four lines that are not 64 µs long

The sync must come every 64 µs. The lines need not be 64 µs long, as long as
the sync's place in each makes up the difference. Four events a field, each
from timer 1 of the user VIA, use that:

| event | line | what it writes | the line's length | the sync's place |
|---|---|---|---|---|
| Ea | the last of the top's row 0 | R0 = 87; then the top's rows 1-7: R1 = 8, R2 = 21 | 88 µs | 45 µs in this line, 21 µs in the next: 88 − 45 + 21 = 64 |
| Eb | the land's first line (black) | R0 = 41, R2 = 90; the clock to 2 MHz at 38 µs; then the land's frame | 40 µs | 21 µs in this line, 45 µs (character 90) in the next: 40 − 21 + 45 = 64 |
| Ez | land line 152, below the picture | R0 = 117; the clock to 1 MHz at 54 µs; then the top's frame | 64 µs | 45 µs throughout |
| Ev | just before the vertical sync | nothing: it waits | | |

Ea makes rows 1-7 start 24 µs later than row 0, which puts their eight
characters at the right of the screen, under the end of row 0. Eb takes the 24
µs back. Ez's line is counted in two clocks: 108 characters at 2 MHz (54 µs),
then characters 108 to 117 at 1 MHz (10 µs).

The fifth event, E0, is the vertical sync itself (the system VIA's CA1). It
restarts timer 1, so the four events are timed from the sync of their own
field. Each event loads the latch for the event after next, so the timer runs
free between them and no event's latency moves the next.

## Placing a write on its cycle

A clock switch has to land on one of two adjacent cycles, or its line comes out
a cycle long or short. Three things put it there.

**The latency is measured and padded.** An interrupt is taken at the end of
whatever instruction is running, so an event's handler starts between 32 and 35
µs after the timer's zero in flight. The handler reads the timer, and `dejit`
pads what it finds out to 39 µs (`DJK`) with a slide of NOPs entered at a
computed point. From there on the handler is counted in cycles. Asserts keep
its timed branches inside their pages, so the count holds wherever the module
is linked.

**The restart is fixed.** A chain that ran free would drift, because a switch
line's length depends on where the switch lands. Ev therefore arrives just
before the vertical sync and executes 20 NOPs with interrupts on. E0 always
interrupts a NOP, so its latency is constant, and it rewrites timer 1 a fixed
163 µs (`RSL`) after the sync.

**The half microsecond is tied down by the order of events.** This is the
subtle one.

At 1 MHz the 6845 counts on the ticks of the 1 MHz clock, which are a line's
even cycles. At 2 MHz it counts on every cycle, so a 2 MHz line can start on a
tick or on the cycle after. Ez's line can be 128 cycles only if it starts on a
tick. The timer counts microseconds and the processor cannot read which half
of a microsecond it is in, so nothing the handlers measure can tell the two
cases apart.

With the vertical sync raised in the land, at 2 MHz, there are two stable
states. In one the land's lines start on ticks and every line is 128 cycles. In
the other they start a cycle off; E0's restart inherits the offset from the
sync, both switches inherit it from E0, and the display settles into one line
of 127 cycles and one of 129 in every field, for ever. Which state a boot fell
into depended on the cycle on which start-up first changed the clock. With
Ez on line 164, below the sync, b2 found the second state in 6 to 15 of every
20 boots, depending on the version, and its television lost lock on about
700,000 lines a run.

The fix is to move Ez above the vertical sync, from line 164 to line 152. The
sync is then raised at 1 MHz, which can only happen on a tick. E0 restarts the
chain from a tick, and Eb, timed from E0, lands on its cycle of a line that
began on a tick. The land's lines therefore start on ticks whatever they did
before, and the second state cannot be reached. With p the last cycle at the
old clock:

| switch | the line is right for | lands at (b2, jsbeeb phase 1) | lands at (jsbeeb phase 0) |
|---|---|---|---|
| Eb, to 2 MHz | p = 75 or 76 | 75 | 76 |
| Ez, to 1 MHz | p = 107 or 108 | 107 | 108 |

The two columns are the two possible relations between the processor's 1 MHz
bus and the 6845's 1 MHz clock: on the same ticks, or half a microsecond apart.
A real machine has one of them, fixed by its video ULA. Ev's `LDA` is the
four-cycle form so that its NOPs fall on the odd cycles, which is what puts
both cases inside the one two-cycle window.

## Start-up

`takeover` holds the ULA at 1 MHz with the MOS's MODE 7 timing until the
frame's registers are written, so the lines stay 64 µs up to the mode change
itself. `chst` then waits for a vertical sync by polling, starts timer 1 for
Ez, and clears the sync's flag so that E0 first fires on the following sync.

The polling loop is 4 µs a pass, so the first Ez is placed to within 2 µs and
its one line is up to 2 µs long or short. Every line from the first Eb onwards
is exact. The mode change costs one short field, as any mode change does.

## The proof

### b2

`tools/b2/b2drive.cpp` drives Tom Seddon's b2 core with no window, as Elite's
harness does. It boots `build/lander.ssd`, picks a build and a version at the
loader's menu, flies a scripted flight with keys held for 100 emulated
seconds, and reports:

* every interval between rising edges of the 6845's horizontal sync, in 2 MHz
  cycles;
* the lines in every field;
* what b2's television does with them, by a mirror of its state machine: lines
  ended by a sync against lines ended by its own timeout, syncs it ignored,
  vertical syncs accepted and rejected;
* every write to the ULA's control register, by line and cycle.

`tools/b2/b2sweep.sh` runs that at 20 boot phases: 16 warm boots, SHIFT+BREAK
after 0 to 987 further cycles, so that the program takes the display at a
different point in the MOS's field and line each time; and 4 cold boots, one
for each starting value of b2's cycle count modulo four, which covers every
power-on b2 can make. A sweep passes only if every run has every interval at
128, every field at 312, and a television that never timed out or ignored a
sync.

`sh tools/b2/all.sh` runs the whole matrix. On the disc as built, 13 sweeps of
20 boots each, 260 boots in all:

| build | machine | versions | result |
|---|---|---|---|
| 32K | Model B, no sideways RAM | all four | every interval 128, every field 312, in all 80 boots |
| 32K | Model B, RAM in sockets 4-7 | MODE 1 | the same, in all 20 |
| sideways RAM | Model B, RAM in sockets 4-7 | all four | the same, in all 80 |
| sideways RAM | Master 128 | all four | the same, in all 80 |

A 32K run measures about 1.4 million intervals over 4,490 fields (MODE 1:
1,401,585 to 1,401,775 intervals a run, every one of them 128). The television
never timed out, never ignored a sync and accepted every vertical sync. In
every boot of every version Ez's write lands on cycle 108 of line 152 and Eb's
on cycle 76 of line 0, which is p = 107 and p = 75. The picture at the first
snapshot is the same, byte for byte, in all 20 boots of a version.

### jsbeeb

jsbeeb keeps the processor's 1 MHz bus and the 6845's 1 MHz clock as separate
counters, and a hard reset zeroes one of them only. Resetting on an odd or an
even cycle therefore gives the two phases, which b2 cannot do.
`tools/b2/jhsync.mjs` makes the same measurement there and prints the phase;
`tools/b2/jsweep.sh` runs 16 reset cycles, which fall 6 in phase 0 and 10 in
phase 1.

All four versions pass all 16 runs, about 937,500 intervals each:

| phase | runs | Ez's write | Eb's write |
|---|---|---|---|
| 0 | 6 of 16 | line 152, cycle 109 (p = 108) | line 0, cycle 77 (p = 76) |
| 1 | 10 of 16 | line 152, cycle 108 (p = 107) | line 0, cycle 76 (p = 75) |

### Negative control

A check that cannot fail proves nothing. `-D ZTRIM=n` and `-D BTRIM=n` move
one switch by n cycles. MODE 1 version, 20 s runs:

| trim | b2, warm and cold | jsbeeb phase 0 | jsbeeb phase 1 |
|---|---|---|---|
| Ez −2 | fail (130) | fail (130) | fail (130) |
| Ez −1 | fail (130) | pass | fail (130) |
| Ez +1 | pass | fail (126) | pass |
| Ez +2 | fail (126) | fail (126) | fail (126) |
| Eb −2 | fail (127) | fail (127) | fail (127) |
| Eb −1 | fail (127) | pass | fail (127) |
| Eb +1 | pass | fail (129) | pass |
| Eb +2 | fail (129) | fail (129) | fail (129) |

The window is two cycles wide for each switch in both emulators, and zero is
the only trim that passes all three columns.

### Interrupt hold-off

The game never disables interrupts outside `irq`; the keyboard scan and the
sound run with them on. Latency at every event measures 32 to 35 µs, against
the 39 that `dejit` covers. With 0 to 8 extra cycles injected at every timer
event the build still passes in both phases; with 14 it fails, as it should,
since `dejit` wraps at 16.

## What an emulator cannot show

Two things about a real Model B are not known from here: which half
microsecond its processor bus sits on against the 6845's clock, and how long
CA1 takes to reach the processor after the sync. The build passes in the three
cases the emulators offer, and they span the first. If a machine differs:

* a whole microsecond in E0's latency moves both switches two cycles: change
  `RSL` by one;
* otherwise `ZTRIM` and `BTRIM` move one switch each, a cycle at a time.

On an oscilloscope, lines 152 and 0 of the land's frame should each measure
64 µs from sync to sync.
