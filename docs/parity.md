# Speed parity between the builds

The rule: no optimisation is in one build and absent from the other unless
the hardware forces it or the 32K build has no room for it. This is the audit
that holds the code to that rule. It covers two comparisons: the sideways RAM
build against the 64K program it descends from (branch `main`), and the 32K
build against the sideways RAM build. Every divergence found was ported,
measured and gated, or is listed here with the bytes it would need.

"Before" is the tree at the start of the audit. `base` is the 32K build and
`swr` the sideways RAM build. Cycles are 2 MHz cycles a frame under py65.

## Result

Cycles a frame in the gate's flight:

| Build | Before | After | Change | Free bytes before → after |
|---|---|---|---|---|
| base mode1 | 144532 | 143201 | −1331 | 284 → 222 |
| base cpc | 144576 | 143247 | −1329 | 248 → 182 |
| base nula | 143471 | 142057 | −1414 | 256 → 190 |
| base arc | 144954 | 143620 | −1334 | 294 → 228 |
| swr mode1 | 122273 | 120565 | −1708 | 1601 → 1639 |
| swr cpc | 122307 | 120600 | −1707 | 1601 → 1639 |
| swr nula | 121117 | 119420 | −1697 | 1601 → 1639 |
| swr arc | 122324 | 120653 | −1671 | 1136 → 1174 |

Final gate lines:

```
base mode1: GATE PASS 143201 cycles a frame (flight), project: 24827, strips: 185741
base cpc:   GATE PASS 143247 cycles a frame (flight), project: 24827, strips: 185972
base nula:  GATE PASS 142057 cycles a frame (flight), project: 24827, strips: 183923
base arc:   GATE PASS 143620 cycles a frame (flight), project: 23218, strips: 183401
swr mode1:  GATE PASS 120565 cycles a frame (flight), project: 6870, strips: 165734
swr cpc:    GATE PASS 120600 cycles a frame (flight), project: 6870, strips: 165973
swr nula:   GATE PASS 119420 cycles a frame (flight), project: 6870, strips: 163838
swr arc:    GATE PASS 120653 cycles a frame (flight), project: 6616, strips: 162619
```

Other scenes, mode1 (cycles a frame; strips only for the soaks):

| Scene | base before → after | swr before → after |
|---|---|---|
| `cruise.py 40` (CAME 20, fast pan) | 218622 → 216931 | 181046 → 179197 |
| soak plain (`16 2 2`), mean | 199351 → 198654 | 178004 → 176489 |
| soak cam (`16 5 3 cam`), mean | 185895 → 185741 | 167288 → 165734 |
| soak cam, slowest frame | 223377 → 224597 | 196044 → 194038 |

**One regression:** the base build's slowest frame in the raised-camera soak is 0.5% slower. It comes from run's caches (Part 2, row 1): without them that frame is 222871, but the flight is 764 cycles a frame slower and the cruise 1106. The sideways RAM build has the same caches and the same trade.

Other final figures:

- **Stack:** base 27 of 28 bytes (unchanged); swr 26 of 95.
- **Zero page:** base 3 bytes free; swr mode1 4, swr arc none.
- **Banks (swr mode1):**
  - bank 4: 834 bytes free after its code (unchanged), 305 in its table pages (314 before);
  - bank 5: 4334 (4393 before); arc 4361;
  - bank 6: unchanged;
  - bank 7: 423 after its code (463 before).

### Pads

- **`COREPAD`** sets the renderer's place against the page boundaries: 18 for
  `swr` (21 before) and 1 for `base` (4 before). It was chosen from the
  flight's taken branches, each branch's count re-evaluated for every shift,
  then confirmed by running the flight for the neighbouring values. `base`
  links only for 0 to 5 (the rungs' one-page assert).
- **`TAILPAD`** (`base`, 7) follows `ship.s` and sets the place of `video.s`,
  whose timed branches must stay within their pages (its asserts). `units` and
  `mkad` are assembled ahead of `video.s`, and `dot0` takes the room `keys`
  left in tail T0.
- **Page-crossing penalties left** (mode1): `base` 274 cycles a frame (205
  before), `swr` 229 (504 before).

## Part 1: what main had that swr lacked

"Both" means the code is shared and the base build gains too. Gains are flight cycles a frame, from instruction counts in the profile, since totals move by ±100 with the page phase. Measured stage totals follow the table.

| # | Item | Files, labels | Outcome | Gain | Bytes |
|---|---|---|---|---|---|
| 1 | traceb's head: one value patches the fills' entry pages | `strips.s` traceb; `tabgen.s` gfill; `ram.s`; `gen.py` B4FIXED, MADE | **Ported, both.** One `TENL` serves both rows (TBLK4 and TBLK5 share a low byte); `TEN4H` and `TEN5H` sit a page apart. The head is 5 stores, as main's. | ≈ 390 (51 a strip, 7.7 strips) | swr: −51 in main RAM, −119 in bank 4. base: +61 pad between the fills, −65 (`TEN5L`), −51 code and tables |
| 3 | TNB 128; `t_one`'s own tail | `strips.s` t_one, t1_h, t1_j; `gen.py` SWR_TNB | **Ported.** swr has TNB 128 and `bmi`. Both have main's separate `t1` path. The `tf` path keeps `cpy #TNB / bcs`: main's `bmi` there needs a `clc` after it, so it gains nothing. Base keeps TNB 64. | swr ≈ 30, base ≈ 20 | +22 each |
| 2 | Table path of a shallow segment | `strips.s` t_dq, t_dj, t_dv | **Ported (swr).** The TNB test is on the `div8` path only. Base has no DQT. | ≈ 68 (10 × 6.8 a frame) | 0 |
| 4 | `jmp (jv0+1)` on the long run | | Skipped: 1 cycle a long run. | | |
| 5 | RDIV inline in the rungs | | Skipped: `divs` runs 1.5 times a frame (≈ 60 cycles for ≈ 90 bytes). | | |
| 6 | `rc_h`: one-line black by LAHSB | `columns.s` rc_t | **Not ported: a net loss in the flight.** The patch costs 4 cycles at each of 13.4 `sethalf` calls a frame (53); the one-line black happens 1.1 times a frame and would save 12 (13). In the cruise it would gain about 38. | | |
| 7 | `sp_ln`: pmask inline, `sl_h` by LAHSB | `columns.s` sp_ln | **Half ported, both:** pmask is inline. `sl_h`'s patch is not: 3 cycles on 4.7 lines against 53 for the patch. | ≈ 56 | +11 |
| 8, 9 | split2's loop inline; one-pass `run` | | Skipped: split2 runs 0.09 times a frame. | | |
| 10 | `oz_m` inline | `columns.s` oz_m | **Ported, both.** | ≈ 12 (flight), ≈ 80 (cruise) | +5 |
| 11 | Map row address by table | `projswr.s` proj4, zsh4; `gen.py` MRL, MRH | **Ported (swr).** `mrow` is gone. | ≈ 5 (flight), ≈ 80 (cruise) | 128 in bank 4's table pages; −12 code |
| 12 | Hot variables in zero page | `ram.s` | **Ported differently.** The eleven variables main had there are worth under 1 cycle a frame in the flight. The profile's hottest absolute data went in instead: see Part 2, row 14. | swr ≈ 310, base ≈ 95 (measured) | code shrinks |
| 13, 14 | `record`/`o_nr` one page; `gone` as two loops | | Skipped: no measurable gain. | | |
| 15 | `throw` | `game.s` emit, throw; `ram.s` thxs | **Cheap half ported, both:** emit's second `jsr throw` is gone (step's `tx`, `tz` stand), and so is throw's saving of X. The full tables (832 bytes) would save under 10 cycles a frame: `throw` runs on one frame in eight. | ≈ 8 a frame; 130 a thrusting frame | −9 |
| 16 | Gravity inline | `game.s` step @mv | **Ported, both.** | ≈ 90 a flying frame | +10 |
| 17 | Keys unrolled | `game.s` keys (KEY1, KEY2) | **Ported, both.** A pair sharing a bit is tested as one. In base the routine moves from tail T0 to the code. | ≈ 85 (measured) | swr +85 in bank 5; base ≈ +85 |
| — | The fsplit and c_dbl floor guards | `columns.s` fsplit, c_dbl | **Kept.** They are in both builds alike. Without them a floor in a character row above the top's sends the walker to `fr` or `fe_r` with a start below its end, and that case has not been shown impossible. | | |

Two further swr changes fell out of this work:

- **Line tables placed in their pages** (`gen.py`): `LAHSBt`, `KENL` and `KENH` started less than YSKY into their pages, so every `lda LAHSB0,y` and `lda KENL,y` crossed a page. They start YSKY or more in. About 100 cycles a frame in the flight, 170 in the cruise.
- **`np_h2`, `np_h3`** are not patched by `sethalf`: 3.5 uses a frame each against 53 cycles for each patch. They use `LAH + scrh`, as base does.

Measured stages, cycles a frame less page-crossing penalties (mode1):

| Stage | swr | base |
|---|---|---|
| Pristine | 121769 | 144327 |
| Rows 1, 2, 3, 7, 10 and the `sethalf` patches | 121385 | 143912 |
| Zero page | 121072 | 143817 |
| Rows 15, 16 | 120975 | 143720 |
| Row 17 | 120891 | 143635 |
| Row 11 | 120884 | — |
| `eyrow` and the kept EYVs (Part 2, row 2) | 120336 | — |
| run's caches (Part 2, row 1) | — | 142924 |

## Part 2: base against swr

Classes: **(a)** forced by the hardware; **(b)** memory for speed that base cannot afford (bytes needed against 182–228 free); **(c)** portable.

### Ported

| # | Item | Files, labels | Direction | Gain | Bytes |
|---|---|---|---|---|---|
| 1 | run's caches: the entries stay while X is the last run's, the planted RTS and `rodd` while Y is | `columns.s` run (rX, rY), sethalf | swr → base | 711 measured (flight), 1106 (cruise); see the regression above | +15 |
| 2 | The rows' EYVs kept while CAME and czs stand (`EHIT`, `HT+13,x`), and base's shorter `eyrow` | `prow7.s` prow7, @cam, eyrow | base → swr | 548 measured; `eyrow` falls from 5.8 to about 2.8 calls a frame and from 235 to 197 cycles | +40 in bank 7 |
| 3 | zone1's four tops unrolled | `columns.s` z1_m | swr → base | 39 a zone line after the first: 0 in the flight, more over rough land | +7 |
| 4 | Part 1's rows 1, 3, 7, 10, 15, 16, 17 | shared files | both | as above | as above |
| 14 | Zero page by the profile | `ram.s`; `shipb.s` | both | swr ≈ 310, base ≈ 95 | code shrinks |

Row 14 in detail:

- `TRB` (12 bytes; it is reached only by `abs,y` and a rare `sta zp,x`) moves out of zero page. `TRL` stays as the 16 bytes the ship's scratch needs.
- Both builds gain `su`, `dpass`, `scrg` in zero page.
- swr gains `BY`, `CE`, `CO`, `ldCLE`.
- base gains `tql`, `tqh`, `NPAT`, `edx`, `bh`, `YHI`, `fi`.
- Base cannot take `BY`, `CE`, `CO` (37 bytes): its own part of zero page holds the projection's and the ship rasteriser's scratch, about as hot per byte. This is the one zero-page divergence left.

### Left divergent

| # | Item | Files, labels | Class | Cost to base (flight) | Why not ported |
|---|---|---|---|---|---|
| 5 | Display: two CRTC frames a field and a MODE 5 top, against one frame and a panel in each screen | `video.s` / `videoswr.s`; `game.s` status, marker, gscr | (a) | — | 32K holds two 12-row land buffers, not two 20-row screens. Not a speed choice. |
| 6 | Projection: map and colours made by `mapgen.s`, rows by multiplication; swr reads stored maps and bank 7's tables | `project.s`, `mapgen.s` / `projswr.s`, `prow7.s` | (b) | ≈ 13000 against ≈ 6500 | 12K of maps and 13K of tables. |
| 7 | Ship: rasterised each frame, against bank 6's spans | `ship.s` / `shipb.s`, `shipspan.s` | (b) | ≈ 12000 against ≈ 6000 | 16K. |
| 8 | Two-pass runs through eight store pages, inline in the column loop | `columns.s` run2, sethalf; RUNT / STAB | (b) | ≈ 2000, with row 9 | +1460 bytes of pages. The cheap half is row 1. |
| 9 | Black runs by `runk` | `columns.s` runk; BLKT, KENL, KENH | (b) | in row 8's figure | 1360 bytes of tables. |
| 10 | Rungs by TRk/TLk | `rungs.s` rfastr, rfastl, FR0, FL0 | (b) | ≈ 3500 | 1440 bytes of tables, 280 of code. |
| 11 | setup's strip unrolled | `strips.s` su_l4 | (b) | ≈ 900 | +385 bytes. See the note below. |
| 12 | DQT, DRT for shallow segments and `divs` | `strips.s` t_dq, divs | (b) | ≈ 450 | 4160 bytes. |
| 13 | `DIV4`, `CLMP1`, `RSMT`, `LAHSBt` | `columns.s` record, recordc, np_*, fs_c, fs_h, z1_h, s2_l, mktr | (b) | ≈ 360, 140, 60, 180 | 256, 256, 99 and 388 bytes. |
| 15 | `s2v`: two rungs under a level top | `columns.s` s2v | (b) | under 5 (0.09 columns a frame); more in the cruise | 186 bytes. |
| 16 | TNB 128 against 64 | `gen.py` tables_inc | (b) | ≈ 450 (`t_flo` chains twice as often) | +576 bytes (fills and entries). |
| 17 | The arc colour tables: `(cte),y` against patched operands | `strips.s` setup | (a) | 0 | swr's loop is in bank 4, unrolled; neither form is faster for its loop. |

Notes on the (b) rows:

- **Row 11, a cheaper half not done:** two points a pass would save about 270 cycles a frame for about 50 bytes. It doubles four operands that `project.s` and `setup` patch, so it is left.
- **Row 13, a way out not done:** the column records could be indexed by x4 (stride 4, the six sets interleaved in the same 384 bytes). That removes the `>> 2` in both builds for no memory, but touches `gone`, `ship.s`, `shipb.s` and `game.s`.

The generators have one SWR switch, in `tools/gen.py` (TNB, the bank images, the game's map image). `landgen.py`, `gamegen.py`, `shipmodel.py` and `shipgen.py` have none.

## Open points

- **The display.** The gate runs under py65, which has no 6845 and no
  interrupts in the soaks. The video timing of the final disc is proved
  separately, on b2 and jsbeeb ([video-timing.md](video-timing.md)).
- **`t_flo`'s entry sum** (`asl a / adc tfn / adc tfb+1`) drops a carry when
  fewer than 43 pixels are left; it then enters the fill 85 stores early, over
  pixels the chain has just written with the same line. It is harmless and is
  left as it is.
