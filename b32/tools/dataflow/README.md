# tools/dataflow -- static analyses of a beebgame game's linked code

Two analyses of a game's 6502 code as its build linked it (ld65's debug file and the
images), for finding smaller code:

* **dataflow.py** -- liveness and constants: per source line of the game's sources,
  which registers and flags are live into and out of the line and which values are
  known; a ranked list of byte-saving opportunities that cost no cycles; and each
  JSR-entered routine's register ABI.  (The first half of this file.)
* **ranges.py** -- value ranges: an abstract interpretation of the whole program --
  every register, flag and memory byte as an interval, known bits and a small value set;
  the stack modelled, so `pha / pha / rts` dispatches resolve; an optional object model
  that keeps facts per object type.  **annotate.py** writes it out as a copy of the
  source with the state before every instruction; **patterns.py** searches it for
  mechanical savings.  (The second half: "Ranges".)

Both run from the game's root and read the game's specifics from a config file
(`--config`, see "The game's config"); a game without inline-operand helpers or an object
model needs none.

Adapted from two tools in the doom repo (github.com/ebenupton/doom, `tools/`):

* `dfscan.py`: a forward abstract interpreter (register constants, register-memory
  mirrors, memory constants, flag constants, Z/N provenance, CMP provenance,
  branch-edge refinement) plus block-local backward liveness, over a CFG seeded
  from an emulator trace of the doom engine.  JSR was full havoc.
* `zpcfg.py`: intraprocedural backward liveness of zero page, from the linked
  machine code, "poison, not optimism" for anything unresolvable.

What changed here: no trace (the CFG is static, from the debug info); the liveness
is global and interprocedural (registers, flags and memory bytes, through JSR
summaries computed from the callees' own code, engine included); the forward pass
uses the same summaries instead of havoc and drops edges a known flag makes
infeasible; and the input is ld65's debug file, so it knows which bytes are
instructions and which are data, and maps every instruction to its source line.

## Running

    sh build.sh                                  # (or use the build already there)
    python3 beebgame/tools/dataflow/dataflow.py --config tools/<game>_config.py
                                                 # reads build/master, writes build/dataflow

Options: `--build DIR` (another build's game.dbg + images, e.g. a private copy),
`--out DIR`, `--strict-isr` (see below), `--quiet`.  It takes about a second.

Outputs (in `build/dataflow/`):

| file | what |
|---|---|
| `report.md` | findings ranked by bytes saved: file:line, routine, instruction, source, why, evidence (live-out registers/flags, known values before it) |
| `report.json` | the same findings, the ABI table, model notes, and per-line `live_in`/`live_out`/`known` for every game source line |
| `abi.md` | per routine entered by JSR from the game: registers/flags read on entry, memory read before written, must/may-define, what callers read after the return (with per-register call-site counts), register values known at the call sites, and memory a caller stores just before the call that the routine reads (register-passing candidates, with the registers free at that site) |
| `annotated/*.s.txt` | each game source file, every code line prefixed `live-in > live-out | known` (macro lines also get one row per expanded instruction) |

Notation: registers/flags as `AXYNZCV` (`-` = none).  Known values: `A=$00`,
`X=[fc]` (X equals memory byte fc), `C=1`, `NZ~A` (N and Z currently reflect A).

## Input

`build/master/game.dbg` (ld65 `--dbgfile`) and the output images its segments name
(`b7.bin`, `b6x.bin`, `MENU`, ...).  An instruction starts exactly where a span
whose innermost source line is a mnemonic starts (macro bodies are type-2 lines,
so `mov16`, `stz`, `bge16i` ... are expanded); every other byte is data.  So data
embedded in code, inline operands after a JSR and `.byte $2C` skips are never
disassembled as code.  The source text comes from the files the dbg names; when a
file on disk no longer matches the dbg's size (someone editing), it is taken from
git (`HEAD` of this repo, the pinned commit or HEAD of the beebgame submodule)
when a version there matches, else its lines count as data.  The report's model
notes say which.

## Model and assumptions

Conservative by construction: anything unresolved is "everything live, nothing
known".

* **Unresolved exits** -- `jmp (ind)`, `jmp (a,x)` (the `jmpx` dispatch), BRK, a
  branch or fall-through into data, an opcode patched by a store -- make
  everything live at that point and stop the forward pass there.  A branch whose
  fall-through is data but whose flag the forward pass proves (`bne @xy ; always`)
  has that edge dropped and the analysis rerun.
* **Entries**: JSR targets; *address-taken* labels (any dbg reference that is not
  a direct JSR/JMP/branch: `.lobytes ob_tank-1`, `.word @t_mortar-1`, `lda #<x`,
  an equate alias such as `hook_play = level_loop`); `.word` data equal to a code
  address (or address+1); code with no predecessor.  Forward state at every entry
  is unknown.  An entry other than a pure JSR target returns with every
  register and flag live (its caller is unknown).
* **RTS**: all memory live (so a dead store is dead *within the routine*), plus
  the registers/flags any caller reads after a JSR to any routine whose body
  contains this RTS (tail jumps and shared tails included; a fixpoint).
* **JSR**: the callee's summary, computed from its code (engine routines too):
  `use` (live-in with nothing live at its RTS), must-def, may-def, memory may-read
  and may-write, and whether it may write I/O.  Live before the call =
  use + (live after - must-def) + memory it may read.  A callee whose body has
  stack games (PHA/PLA imbalance, TSX/TXS: the OPFETCH helpers, `getheight`,
  `hitscan`, rts-dispatch `@tcall`...), RTI/BRK or an unresolved exit is unknown:
  reads and clobbers everything.  Where several banks have code at the JSR's
  address, the source line's symbol picks the segment (`jsr music_tick`), else
  all candidates are joined.
* **Inline-operand helpers** (the config's INLINE_HELPERS; Commando's `add16_s`,
  `dif16_s`, `cmp16_s`, ... in its logic.s
  "16-bit helpers behind the macros") return past their operand bytes, which no
  code analysis can follow; their contract is a table in `analysis.py`
  (`INLINE_HELPERS`): X, Y preserved, A N Z C V clobbered, the operands' zero-page
  words read/written as the role says, `m_d`/`m_t` scratch.  Change the table if a
  helper's contract changes.
* **The interrupt** (`irq_handler`, and all it reaches, including `sound_tick`
  and the tune) can run between any two instructions: every byte it reads is live
  everywhere, every byte it writes is never a known constant.  Its two pointer
  reads (`SNDP`: the sfx tables, `mus_ptr`/`MUSPTR`: the tune) are assumed to
  read data, not game variables (`ISR_DATA_POINTERS`); without that assumption
  (`--strict-isr`) it reads all memory and no store anywhere can be dead.
* **Banks**: a store to paged memory ($3000-$DFFF) is never killed across an I/O
  write or a JSR whose callee may write I/O (it may leave another bank paged).
  Forward: known paged bytes are forgotten at every JSR.
* **Self-modifying code**: a direct store into an instruction's bytes (in the
  storer's bank when both are sideways) makes that instruction's operand unknown,
  or the instruction a barrier if the opcode is written; indexed stores count
  only when their base is itself inside an instruction.  Stores to BSS symbols are
  data.
* Memory liveness is tracked per byte for every address an instruction names
  directly (the "universe"); pointer reads read all of it; indexed reads read the
  256 bytes from the base.  Stack page and I/O ($FC00-$FEFF) are never dead or
  constant; I/O reads have side effects; stores to the screen ($3000-$7FFF) are
  never reported dead.
* Not modelled: NMI (disc transfers, not concurrent with game code); decimal mode
  (ADC/SBC are not folded if the game ever executes SED); cycle-exact timing
  loops (a "dead" instruction in a delay loop is still a delay).

## Findings

Each finding claims something about every modelled path.  Categories (bytes
saved; none costs a cycle):

| category | what |
|---|---|
| `dead_store` | STA/STX/STY/INC.. to a direct address rewritten before any read on every path |
| `dead_insn` | an instruction whose every result is dead |
| `dead_code` | instructions reached only through never-taken edges |
| `imm_load` / `reload` | LDr #v / LDr m when r already holds it (N, Z equal already or dead) |
| `reg_xfer` | LDA when X/Y already holds the value (TXA/TYA), or LDX/LDY when A does |
| `redundant_xfer` | TAX.. whose destination already equals the source |
| `known_store` | a store of the value the byte already holds |
| `const_operand` | an absolute operand that is a known constant: the immediate form |
| `clc_sec`, `cmp_zero`, `identity` | CLC/SEC with C known; CMP #0 with N, Z already from the register and C dead or 1; AND #$FF / ORA #0 / EOR #0 |
| `branch_never` | a conditional branch never taken |
| `branch_over_jmp` | `bxx *+5 / jmp T` with T in range: the inverted branch (3 bytes) |
| `jmp_to_branch` | JMP where a flag is known: a branch on it (in range, no page crossing) |
| `tail_call` | `jsr x / rts` -> `jmp x` (1 byte if nothing else reaches the rts) |
| `branch_always` | info: always taken (most are deliberate BRA substitutes) |
| `bit_skip_bad` | correctness: a `.byte $2C/$24` skip whose skipped instruction is not 2/1 bytes |

Findings overlap (a dead store's value-loading instruction may become dead once
the store goes); the totals are an upper bound.  Several depend on link-time
constants (`lda #<ROGUES` with A = 0 because ROGUES is page-aligned): they hold for
this build and can stop holding when the layout moves.  A finding inside a
routine with a documented contract (e.g. "X preserved") may hold only for the
current callers.  Every change still goes through the gate.

## Files

* `model.py` -- dbg parsing, decoding, symbols, source text
* `analysis.py` -- CFG, entries, interrupt, summaries, global liveness
* `forward.py` -- forward constants (dfscan's interpreter, adapted)
* `findings.py` -- the finding rules
* `dataflow.py` -- the command line and the reports


# Ranges (ranges.py, annotate.py, patterns.py)

    python3 beebgame/tools/dataflow/annotate.py --config tools/<game>_config.py
            -> build/annotated/src/<file>.s (the sources, numbered as they are) and summary.md
    python3 beebgame/tools/dataflow/patterns.py --config tools/<game>_config.py

## The domain (dom.py)
An abstract byte is an unsigned interval, the bits known (`km`, `kv`), and, while it has
at most 32 members, the exact set of values -- so `{$FF, $00}` (a `dec` on one path,
nothing on another) becomes `0..1` after an `inc`, where an interval would have gone to
`?`.  Every 6502 operation (adc/sbc with carry in and carry/overflow out, the shifts and
rotates, the logic operations, compares) is exact on the concrete level and sound on the
abstract one; `python3 dom.py` checks that against the concrete semantics.  Widening (only
at loop heads, only for a value that has kept changing there, only where the loop is not
split by its counter) goes to the next 2^k-1 bound.

## What it tracks
Before every instruction: A X Y (or one value per object type), C Z N V (0, 1, unknown)
with where Z/N/C came from (a branch refines the value it tested, and the memory byte a
register was loaded from), the memory bytes the code names (link-time content for bytes
nothing writes), the stack's pushed values, and which object types are possible.
Procedures are analysed per entry, small ones per call site; a call's return gives each
caller back its own state for whatever the callee cannot write (the bytes it names in a
store, or stored to through a pointer, recorded as it runs, to a fixpoint).  Loop heads are
split by the counter their exit test reads (`hitscan`'s bullet loop by its slot); states
are kept apart by stack height.  The interrupt's writes are never tracked.

## The object model (optional: the config's OBJECTS)
A game whose objects live in an array of fixed-size records with a type byte, processed
one at a time through a zero-page pointer and dispatched by type, can have per-type facts
(or in one array a field, the current record the one whose index a register holds, equal
to the current-record byte: `layout='soa'`):
each (type, field) has a range over every record of that type, all game long (a fixpoint
over rounds of the whole analysis, widened to converge; a run that does not converge says
so at the top of every annotated file); a record read through the current-record pointer
gives a value per type, and the dispatch (an RTS through a table indexed by the type)
splits the state, so a handler sees only its own type's fields -- as does a `jmp (ind)`
through a pointer loaded from a table by the type, or a `jmp (abs,x)` with X the type.  When the game's loader
builds the records (Commando's ld_game in the load-time program), that program is analysed
first, the type bound where the loader loads it (the config's `bind`).

## The annotations (annotate.py)
Each instruction line ends in `;| ` and the state before it:

    lda damage   ;| A={2,3,$FF}≡ohealth X=$02 Y=? C=1 Z=? N=? V=? | damage=0..80 | ty=barrel | in:YCV out:YNZCV

`$xx` one value, `lo..hi`, `{a,b}` a set, `%xx01xxxx` known bits, `?` anything,
`{type:range ...}` per type; `≡name` the register equals that memory byte; `name=` the
memory operand's range; `ty=` the object types possible (when not all); `never` /
`always` on a branch never / always taken; `dispatch->` an RTS resolved as a jump;
`in:` / `out:` the liveness (dataflow.py's).  summary.md lists the per-type record table,
the assumptions made (unbounded pointer stores, indexes clamped to their arrays, the
current-record pointer taken to stay in the records, code analysis.py calls self-modified
but analysed as written), unresolved exits and what was not reached.  A run stops after 3,000,000 steps
(`RANGES_BUDGET` sets another number); one that stops is not a fixpoint, and summary.md and
every annotated file then say the annotations are NOT sound.

## Mechanical finds (patterns.py)
`reload_via_test` (a load used only for its flags while A holds a value that is reloaded
soon after, with X or Y dead: test in the dead register), `known_and` / `known_cmp`
(results the ranges decide), `const_load` (a byte that is one known value), `const_var`
(a variable every store gives one value: its stores can go, its reads become immediates).
Each is a candidate: check it, and gate it.

## The game's config (gamecfg.py)
A Python file of assignments: `GAME_DIR`, `ISR_ROOTS`, `ISR_DATA_POINTERS`,
`INLINE_HELPERS`, `HELPER_SCRATCH`, `HELPER_CARRY_X0`, `SCREEN_POINTERS`, `VAR_SEGMENTS`,
`LOADER_DBG`, `OBJECTS` -- gamecfg.py documents each.  Commando's is
`tools/dataflow_commando.py` in its repository; Cleo's is `tools/dataflow_cleo.py` in its
(the objects one array a field, indexed by `obj`, built by level_init: `layout='soa'`,
`game_bind`).

## Using the annotations to shrink code: a suggested farm

The annotations were written to be read by an agent hunting for smaller code.  What worked
for Commando (two passes, 171 proposals, about 400 bytes accepted behind its replay gate):
cut the game's sources into overlapping windows (64 instructions at a stride of 32, never
across a routine), replace each window's text with the annotated lines, deal the windows
into batches of about eight, and give each batch a reviewer and then a skeptic.  Apply the
proposals the skeptic did not refute one small batch at a time behind the game's own
equivalence test (a step-by-step replay against a reference), bisecting failures; then have
a second skeptic audit everything accepted against a snapshot of the source, hunting paths
the replays never run -- the audit is not optional (Commando's caught two accepted rewrites
that together broke a mission no replay reached).

A reviewer's prompt, to adapt (the {braces} are the game's):

> You are one reviewer in a farm shrinking the code of {a BBC Micro game}, ca65 6502 source
> in {src/}.  Bytes are the metric; a rewrite may cost at most {2} cycles per frame for each
> byte it saves.  New code must be {plain NMOS 6502}.  Your windows are in {batch_NN.md}:
> each source line is followed by `;|` and the state before it from a whole-program range
> analysis (beebgame/tools/dataflow/README.md, "The annotations", explains the notation:
> register ranges, `≡name` a register equal to a memory byte, flags, the operand's range,
> `ty=` the object types possible, `never`/`always` branch feasibility, `in:`/`out:`
> liveness).  Look hard for what the annotations make visible: branches marked never (dead
> code); reloads of a value a register already holds (`≡`), or held a few instructions
> earlier where a dead register (absent from `out:`) could have carried the intermediate
> value instead -- e.g. `lda health / cmp #2 / bcc x / lda damage / beq y / bmi y /
> lda health / sbc damage` becomes `lda health / cmp #2 / bcc x / ldx damage / beq y /
> sbc damage` when damage is never negative and X is dead; tests the ranges decide; flags
> already known; per-type facts inside a type's handler; values that are only ever one
> constant; then the classics (staging through temporaries a dead register could carry,
> shared tails, jsr/rts -> jmp).  The ranges are sound over-approximations (summary.md
> lists the assumptions): `never` is reliable, `?` proves nothing.  Check every register
> and flag a rewrite relies on against `out:`; keep the count of anonymous `:` labels;
> keep calls with side effects in the same order with the same arguments.  Return each
> proposal as hunks {file, original (copied verbatim from the source, never from the
> annotated copy), proposal}, the byte and cycle saving, and an argument that cites the
> annotations for every fact it relies on.  Be conservative: few, solid proposals.

A skeptic's prompt: the same rules, then "for each proposal, REFUTE it if there is any
reachable path on which it changes behaviour; default to refuted when you cannot convince
yourself it is exactly equivalent; check in particular that every range a claim rests on
holds on every path into that point, flags and registers consumed after the change, every
entry point and jump target, anonymous labels, and the claimed saving".  Commando's
versions, with its Workflow scripts, are in its repository (opt/RANGES_BRIEF.md,
opt/workflows/).
