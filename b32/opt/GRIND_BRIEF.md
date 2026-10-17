# Brief: the micro-optimisation grind (Lander, the 32K Model B build)

Work from files only.  Do NOT edit any file.  Do not run builds or emulators: reading is all
you need.

## The program
Lander for a 32K BBC Model B (6502 at 2 MHz, no sideways RAM, the MOS killed after
loading).  ca65 source in /Users/ebenupton/bandfill/b32/src: `land.s` (the frame: the
projection driver, the land renderer -- strips, rungs, columns, fills -- flip, the
interrupt; it `.include`s the others), `proj32.s` (the computed projection), `game.s` (the
game: physics, dots, sound, keys, the map marker), `ship32.s` (the ship's run-time
rasteriser and span walker), `boot32.s` (the loader).  The memory map is in
`b32/src/b32.cfg`'s comment.  Each frame the main loop (`loop` in land.s) calls gstep,
project, strips, gpre, ship, gpost, readout, flip.

## The goal: CYCLES a frame, paid for in BYTES
Cycles a frame are what we are buying.  Bytes are the currency: everything that grows the
program comes out of ONE free block (about 1100 bytes, all the memory left).  The going
rate, measured on the first round's accepted rewrites: about 40 cycles a frame per byte.
A speed rewrite that spends bytes should beat that; a size rewrite that costs cycles should
cost well under it per byte saved.  So every proposal must state both honestly:
- `cycles_saved_per_frame`: per-execution saving x executions a frame.  Your window
  shows each line's measured cycles a frame (the profile of a 129-frame scripted flight);
  divide by the instruction's cycles to get its executions.  Negative if slower.
- `bytes_delta`: the change in code/data size (negative = smaller).

Both kinds of proposal are wanted:
1. **Speed** (hot code): fewer cycles; may cost bytes (an unrolled loop, a table, a
   specialised path).  We are measuring the going rate of cycles saved per byte spent
   across all speed proposals; a good one saves many cycles a frame per byte it costs.
2. **Size** (cold code: lines showing `-` or a few cycles a frame): fewer bytes; may cost
   a few cycles a frame (a subroutine shared instead of duplicated, a loop instead of
   straight-line code).  Worth it when the bytes saved could buy more cycles elsewhere.
Changes that save both are best.

**Free work**: the loader (`boot32.s`, `init` and `shtab` in land.s and ship32.s, `ginit`
in game.s: segment BOOT) runs once and is then discarded -- its bytes and cycles cost
nothing.  Moving run-time work into it (precomputing a table it fills in a hole or the
free block) costs only the table's run-time bytes.  Do not optimise the loader itself.

## Second round
This code has had one round already (about 110 rewrites).  What is left is harder: look
for structural savings (work that is repeated across calls, values recomputed that could
be kept, loops that could carry state in registers, tests that could be hoisted) as well as
local ones.  Do not undo a first-round change.  Page phase: code addresses shift with any
size change; a rewrite that only moves code to dodge a page crossing is not wanted.

## The instruction set: plain NMOS 6502
No `stz`, `bra`, `phx`/`plx`/`phy`/`ply`, `inc a`, `bit #`, `(zp)` without an index,
`jmp (abs,x)`, `trb`/`tsb`, no illegal opcodes.  `.byte $2C` (BIT abs) skips exactly 2 bytes.

## The annotations (USE THEM)
Each code line ends in `;|` and the state BEFORE its instruction over every path a
whole-program analysis found (beebgame's range analysis):

    ;| A=0..3 X=? Y=$0B C=1 Z=? N=0 V=? | dvd=0..31 | never | in:AXC out:A

`A=`, `X=`, `Y=`: possible values (`$xx` one, `lo..hi`, `{a,b}`, `%xx01xxxx` known bits,
`?` anything); `≡name`: the register equals that memory byte; `C= Z= N= V=` 0/1/?; after
the first `|` the memory operand's range; `never`/`always` on a branch; `in:`/`out:` the
registers and flags live into / out of the instruction (a register absent from `out:` is
dead after it: free to clobber).  The ranges over-approximate (never narrower than the
truth): `never` is reliable, `?` proves nothing.  Liveness is reliable.  Self-modified
operands (see below) are analysed as written: their real values are whatever the patching
code stores, so treat any fact derived through a patched operand with suspicion.

## Correctness: exactly equivalent (hard rules)
The gate checks, byte for byte: the land as drawn against a Python reference (many frames,
a moving camera), the ship's pixels at every orientation, and the game's state every frame
of a scripted flight.  Paths it never runs are your responsibility.
1. **Flags and registers** live after the rewrite (out:, and at every jump target and after
   every JSR return) must hold what they did.  Many routines here return values in flags
   (C, V, N, Z) and registers: check every caller.
2. **Self-modifying code is everywhere.**  Patched operands (`sta c_lo+1`, `sta r_j+1`,
   `sta fl_e+1`, `sta sh_b+1`, `pT3+2`, ...), patched opcodes (`ob_st`, `zb_st`: a STA or a
   BNE; `t_inc`/`tr_inc`: INC or DEC), planted RTS (run plants an RTS opcode in the STABs,
   init's generated code in $0E00-$11FF, and puts the STA back; run2 likewise), patched
   jump targets (`jmp $FFFF` placeholders), the ship's walker chains (seg1..seg7, rd1..: their
   operands' high bytes patched, PNH/CNH/FLH).  An instruction another instruction patches
   must keep its encoding and its offset from its label; every patch site must still hit
   it; a label used as a patch target must stay on the same byte.  Search the source for
   `label+1`, `label+2` and `#<label`/`#>label` before touching any labelled instruction.
3. **The interrupt** (`irq` in land.s) runs between any two instructions: it saves A (the
   MOS stub stores it in $FC) and X (pushed), writes vcount, evn, the CRTC, the ULA, the
   VIAs, and reads lfront.  Main code must not use the stack below S as storage, nor $FC.
4. **Anonymous labels**: ca65 counts `:` lines across the file -- keep the number of `:`
   label lines in the replaced text exactly the same.
5. **Layout**: code moves when any size changes, so do not claim savings from page
   alignment (indexed reads crossing a page +1, taken branches into another page +1)
   unless the rewrite asserts the alignment it relies on (`.assert`); keep every existing
   `.assert` true.  Tables in fixed low memory (land.s's equates: ROWA, RTBUF, PX, CLE,
   TOPS... and the variables b32.cfg packs into holes) do not move.
6. **Zero page** is full ($00-$FB used, $FC the MOS's).  Do not add zero-page variables.
7. **Order of effects**: the sound chip writes (psg), the keyboard scan, the dots' random
   numbers (rand) happen in the same order with the same values.
8. **Every entry point** into the replaced text (labels jumped or branched to from outside,
   fall-throughs, address-taken labels) behaves as before.

## Output
Structured output: a list of candidates (empty when nothing is safe -- most windows will
have little; few solid proposals beat many doubtful ones).  Each: `file`, `first_line`,
`last_line` (the replaced lines, inclusive), `old_text` (those lines EXACTLY as they are in
the CURRENT file in b32/src, comments and indentation included -- never copied from the
window's annotated text: no `;|` and no line numbers), `new_text` (their replacement, in
the file's style: tab-free, comments where the reasoning is not obvious), `extra_edits`
(other hunks the change needs elsewhere, e.g. callers or a patch site: a list of
{file, old_text, new_text}, or empty), `cycles_saved_per_frame`, `bytes_delta`, `kind`
("speed" or "size"), `rationale` (instruction by instruction: cycles, bytes, and the
liveness/range evidence for every register and flag you rely on being dead or known, and
every caller you checked), `risk` (low/medium/high).
