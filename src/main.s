; ============================================================================
; main.s -- BAND: two rows of nine points, joined by rungs, and the eight boxes
; between them filled with dithered colours, on a narrow MODE 1 screen, timed.
; The BBC port of proto/ragged.py: shallow rows, steep rungs, and a ragged
; bottom (each byte column filled down to its lowest bottom-row point).
;
; The display: MODE 1 cut to 64 bytes a line and 20 character rows, so 256 x
; 160 MODE 1 pixels, x across and y down, at $5800-$7FFF (a character row is
; 512 bytes).  The palette is black, cyan, magenta and yellow; each box is one
; of tools/palette.py's 2x2 dithers, so its byte depends on the line's parity.
;
; Each frame: the rows (x fixed; y a random walk from 80 and 100 in normal
; steps of sd 5, kept to 16..159, each rung steep and each byte column's top
; above its bottom); `across`, the rows to what the fill needs of them (each
; byte column's top y and the shape of its top, and its lowest bottom y);
; `down`, each rung to the line where each pixel it passes changes sides; each
; box a random colour, unlike its neighbour; then `fill`.  The three routines'
; cycle counts are shown at the top.  Any key: a new frame.
;
; Everything about the geometry but the y's is fixed, so tools/gentab.py writes
; much of the code: the rows, by tables of each shape's steps (across.inc), the blitters for
; a byte column's top by its shape, an unrolled walk per rung (down.inc), and
; the fill's columns, each with its kind and boxes (fillcols.inc).
;
; Memory.  BAND loads at $1900: its code and tables, to $4C00, the tables in
; segments LOW1-3 copied down at the start.  Its own, with the language's
; workspace and the filing system's (closed once !BOOT's EXEC is), and the
; printer buffer, envelopes and soft keys, none of them used:
;   $0400 LINEL, $0500 LINEH1  each line's address
;   $0600 RT  by x: the line where a rung's pixel changes sides
;   $0700 SEXL, $0C00 SEXH1, $1800 SEXH2  each line's STA in STAB, where a run
;               ends (every line table holds lines 16-160 only)
;   $0880 TOPC, $08B0 BOTC  by byte column: its top row's first y, the line
;               after its bottom row's lowest; $08E8 SEGV, by top-row segment:
;               2 |dy| + rising
;   $0900 LOW1 (NTAB, Q12, TC1), $0B00 LOW2 (R12, TC2), $0CA1 LOW3 (TC3)
;   $0E04 PSTAB1, $1304 PSTAB2  TXA (ce in X: an even line) or LDA co /
;               STA line,Y / STA line+8,Y for lines 16-160: two neighbouring
;               columns at once, the left half of the screen and the right
;               (every address 256 on); $1240 PEL: each line's entry (low byte)
;   $1788 PTS0, $17A0 PTS1  the points, x0,y0 .. x8,y8
;   $17C0 BOXC  the boxes' colours (palette entries); 8-15 black
;   $4C00 STAB1, $4F00 STAB2  STA line,Y / EOR tgl for lines 16-160, the two
;               halves
;   $5200 SENTL, $5300 SENTH1, $5400 SENTH2  each line's entry in them, for
;               a run starting there with A = the even lines' byte
;   $5500 PL, $5600 PH1, $5700 PH2  each line's place in PSTAB
; ============================================================================
        .setcpu "6502"
        .import __LOW1_LOAD__, __LOW1_RUN__, __LOW2_LOAD__, __LOW2_RUN__
        .import __LOW3_LOAD__, __LOW3_RUN__, __LOW3_SIZE__
        .import __ZPCODE_LOAD__, __ZPCODE_RUN__, __ZPCODE_SIZE__

OSWRCH  = $FFEE
OSWORD  = $FFF1
OSBYTE  = $FFF4
OSRDCH  = $FFE0
CRTC_IDX = $FE00
CRTC_DAT = $FE01
SVIA_T1L = $FE44                   ; the system VIA's timer: a seed
UVIA_T2L = $FE68                   ; the user VIA's timer 2, counting at 1MHz
UVIA_T2H = $FE69

LINEL   := $0403                   ; (3 on: a TOP's LINEL-3..-1,x crosses no page)
LINEH1  := $0503
RT      := $0600
SEXL    := $0700
TOPC    := $0878                   ; (columns 8-55)
BOTC    := $08AC                   ; (columns 4-59)
SEXH1   := $0C00
PSTAB1  := $0E04                   ; (line 16's entry: no line's load and STA straddle a page)
PSTAB2  := $1304
PEL     := $1240                   ; each line's entry (its load) in PSTAB, low byte (by PL's high)
PTS0    := $1788
PTS1    := $17A0
BOXC    := $17C0
SEXH2   := $1800                   ; (as SEXH1, for the self-modified half)
STAB1   := $4C00                   ; (line 16's place)
STAB2   := $4F00
SENTL   := $5200
SENTH1  := $5300
SENTH2  := $5400
PL      := $5500
PH1     := $5600
PH2     := $5700
SCREEN  := $5800
LINES   = 160

OP_STAY = $99                      ; STA abs,Y
OP_EORZP = $45                     ; EOR zp
OP_RTS  = $60
OP_LDAZP = $A5
OP_TXA  = $8A
NONE    = $FF

        .rodata
        .include "tables.inc"
        .assert >DITHE = >(DITHO + 15), ldwarning, "DITHE/DITHO cross a page (SETC/SETUD's abs,X)"

        .zeropage
rng:    .res 2
tmp:    .res 2
wp:     .res 2                     ; WLINES' line address
ptr     = wp                       ; gentables, text (not in fill)
; across, down
rq:     .res 1                     ; and whole step
; fill
        .globalzp pp               ; fill: the planted STAB RTS (run_d's put-back operand)
        .globalzp coff, pplant     ; prun's operands (coff: 8 * column, mod 256: the stores' Y)
half:   .res 1                     ; 0 for the left half of the screen, 1 the right
        .globalzp ce               ; the colour being drawn (prun's LDX # operand): even, odd lines,
co:     .res 1
tgl:    .res 1                     ; and the two EORed
ue      = ce                       ; the column's box above the rung: its bytes
uo      = co                       ; stay in ce, co through its group (gentab.py)
ut:     .res 1
de:     .res 1                     ; and below it
do:     .res 1
dt:     .res 1
b1:     .res 1                     ; the line after a column's last
lp:     .res 2                     ; the walker's line (low byte 0)
r0:     .res 4                     ; a column's rung lines, in order
SEGV:   .res 8                     ; by top-row segment: 2 |dy| + rising
m:      .res 1
gu:     .res 1                     ; and its colours above and below the rung
gd:     .res 1
tp:     .res 4                     ; and each pixel's top
rp:     .res 4                     ; and rung line
gs:     .res 1                     ; genrows

        .code
; ---------------------------------------------------------------- start
start:  lda #119                   ; close !BOOT (an EXEC file): the filing
        jsr OSBYTE                 ; system's workspace is then ours
        ldx #0                     ; LOW1-3 down
:       lda __LOW1_LOAD__,x
        sta __LOW1_RUN__,x
        lda __LOW1_LOAD__+256,x
        sta __LOW1_RUN__+256,x
        lda __LOW2_LOAD__,x
        sta __LOW2_RUN__,x
        inx
        bne :-
        ldx #<__LOW3_SIZE__
:       lda __LOW3_LOAD__-1,x
        sta __LOW3_RUN__-1,x
        dex
        bne :-
        ldx #0                     ; black, cyan, magenta, yellow (!BOOT has
                                   ; set MODE 1: a mode change would clear
                                   ; $3000 up, where this program is)
:       lda vdu_init,x
        jsr OSWRCH
        inx
        cpx #vdu_end-vdu_init
        bne :-
        ldx #0                     ; then narrow it: 64 bytes by 20 rows at $5800
:       lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne :-
        lda SVIA_T1L
        ora #1                     ; never zero
        sta rng
        lda #$A5
        sta rng+1
        jsr gentables

frame:  jsr cls
        jsr genrows
        jsr timenull
        jsr timeacross
        jsr timedown
        jsr timefill
        jsr readout
        jsr OSRDCH
        bcc frame
        lda #126                   ; ESCAPE: acknowledge it, carry on
        jsr OSBYTE
        jmp frame

vdu_init:
        .byte 19, 1, 6, 0, 0, 0
        .byte 19, 2, 5, 0, 0, 0
        .byte 19, 3, 3, 0, 0, 0
vdu_end:

crtc_regs:
        .byte 1, 64                ; displayed characters
        .byte 2, 90                ; hsync, to centre the 64
        .byte 6, 20                ; displayed rows
        .byte 7, 28                ; vsync, to centre the 20
        .byte 12, >(SCREEN/8)      ; screen start
        .byte 13, <(SCREEN/8)
        .byte 10, $20              ; cursor off
crtc_end:

; ---------------------------------------------------------------- across
; A top-row column's line X+d in its pixels m: ce or co by its parity.
.macro PART m, d
        lda LINEL+d,x              ; (line X+d; Y: 8 * the column)
        sta wp
        lsr a                      ; C: the line's parity
        lda LINEH1+d,x
        ora half
        sta wp+1
        lda ce
        bcc :+
        lda co
:       and #m
        sta (wp),y
.endmacro

; The rows (across.inc): each segment straight-line, its shape (y0 - y1 mod 256 by
; TOPVT: SEGV, 2 |dy| + rising) indexing a table per column of its steps.
        .include "across.inc"

; ---------------------------------------------------------------- down
; A rung of width a, |dy| in A, its top point's y at yt: A its first pixel's
; line (yt + ceil(dy / 2a)), C clear; rq its step dy div a, and the carries to
; add to that at each later pixel, which depend only on r = dy mod 2a (gentab.py's
; `carryregs`): X = PIa[r] (cpx #TPIa: one set of pixels'), Y = PYa[X] (cpy #1:
; another's), the rest's each its own table by X (CRa_j: adc CRa_j,x, C clear).
.macro RUNGSET wid, yt
.if wid = 12
        tay
        lda Q12,y                  ; dy div 12
        sta rq
        lsr a                      ; dy div 24
        ldx R12,y                  ; PI12[dy mod 24]
        ldy PY12,x
        cpx #1
.else
        K .set (wid = 4) * 2 + (wid = 8) * 3 + (wid = 16) * 4
        tax
        and #(2 * wid - 1)         ; dy mod 2a
        tay
        txa
  .repeat K
        lsr a
  .endrepeat
        sta rq
        lsr a                      ; dy div 2a
        ldx .ident(.sprintf("PI%d", wid)),y
        ldy .ident(.sprintf("PY%d", wid)),x
        cpx #1                     ; (PIa[r] = 0 iff r = 0)
.endif
        adc yt                     ; and 1 more unless dy mod 2a = 0
.endmacro

        .include "down.inc"
        .res ($74 - (* - start)) & $FF  ; (what follows where it was, mod 256: its page crossings)

; The rows, then the rungs.
interp: jsr across
        jmp down

; ---------------------------------------------------------------- fill
; fillcols.inc visits each byte column, setting coff = 8 * column (mod 256)
; and, where they change, its boxes' colours (SETUD: ue, uo above the rung,
; de, do below; ce, co, the colour being drawn, the box above) and the rung's
; sub-runs' (RPREP).  Its kind:
;   ONE   one box, from the top row: its top by shape (a TOP, from SEGV and
;         TBLj: the lines above its first full line), then a run to its bottom
;   TWO   every pixel on a rung: its top, the box above in a run to the rung's
;         first line, the rung's lines in three sub-runs (rwalk: a pixel more
;         of the box below in each, walked through (lp),Y), the box below in a
;         run to the bottom
;   ONER  the band's ends: black above the rung, its sub-runs, the box below
; A run is STAB from its first line's entry to an RTS planted at the line
; after its last.  Where the rung's lines meet the top's, or the bottom, the
; column is made a line at a time (gtwo, gone_r).

; Box b's bytes straight from its palette entry (no per-frame table), or (src,
; from gentab.py, which knows which box each holds) from where they are
; already: 1 ce, co; 4 ce, co, ut; 2 ue, uo; 3 de, do (only SETC/SETUD
; write these, and rrun ce).
.macro SETC b, t, src
  .if src = 0
        ldx BOXC+b
        lda DITHE,x
        sta ce
        lda DITHO,x
        sta co
  .elseif src = 1
    .if t
        lda co
    .endif
  .elseif src = 4                  ; ce, co and ut: a SETUD's box above
    .if t
        lda ut
        sta tgl
    .endif
  .elseif src = 2
        lda ue
        sta ce
        lda uo
        sta co
  .else
        lda de
        sta ce
        lda do
        sta co
  .endif
  .if t && src <> 4                ; tgl only for a ONE's run (not PONE's, nor tops)
        eor ce
        sta tgl
  .endif
.endmacro

; cu, cd: box u's (d's) bytes already in ce, co.
.macro SETUD u, d, cu, cd
  .if u = 8                        ; black above (ONE_R only, which read
    .if cd                         ; no ut or dt): ue, uo (ce, co) 0, and tgl
        lda ce                     ; dt at once (every ONER td)
        sta de                     ; (before ce is spoilt)
        tay                        ; Y = xe, X = A = xo for RPREP
        lda co
        sta do
        eor de
        sta tgl
        lda #0
        sta ce
        sta co
        lda do
    .else
        lda #0
        sta ce
        sta co
        ldx BOXC+d
        lda DITHE,x
        sta de
        tay                        ; Y = xe, X = A = xo for RPREP
        lda DITHO,x
        sta do
        eor de
        sta tgl
        eor de
    .endif
  .elseif cd
        lda ce                     ; d first (before ce is spoilt)
        sta de
        lda co
        sta do
        eor de
        sta dt
        ldx BOXC+u
        lda DITHE,x
        sta ce                     ; (ue, uo)
        eor de
        tay                        ; Y = xe, X = A = xo for RPREP
        lda DITHO,x
        sta co
        eor ue
        sta ut
        sta tgl
        eor ue
        eor do
  .else
    .if cu
        lda co                     ; (ue, uo: ce, co already)
    .else
        ldx BOXC+u
        lda DITHE,x
        sta ce                     ; (ue, uo)
        lda DITHO,x
        sta co
    .endif
        eor ue
        sta ut
        sta tgl
        ldx BOXC+d
        lda DITHE,x
        sta de
        eor ue
        tay                        ; Y = xe, X = A = xo for RPREP
        lda DITHO,x
        sta do
        eor de
        sta dt
        eor de
        eor uo
  .endif
        tax
.endmacro

; The rung's sub-runs' bytes, each a pixel more of the box below than the
; last: from the right if the rung leans left (its bottom to the left), else
; from the left.  Straight into the walk's LDA #s (nm: rwalk_l or rwalk_r).
; blk: the box above is black (ue = uo = 0: no EORs).
.macro RPV nm, k, S, blk
  .if k
        txa                        ; xo (A already, for k = 0)
  .endif
        and #S
  .if !blk
        eor uo
  .endif
        sta .ident(.sprintf("%s_od%d", nm, k))+1
        tya                        ; xe
        and #S
  .if !blk
        eor ue
  .endif
        sta .ident(.sprintf("%s_ev%d", nm, k))+1
.endmacro
.macro RPREP lean, wide, blk
        .assert wide, error, "every rung is walked"
  .if .xmatch({lean}, L)
        RPV "rwalk_l", 0, $11, blk
        RPV "rwalk_l", 1, $33, blk
        RPV "rwalk_l", 2, $77, blk
  .else
        RPV "rwalk_r", 0, $88, blk
        RPV "rwalk_r", 1, $CC, blk
        RPV "rwalk_r", 2, $EE, blk
  .endif
.endmacro

; The rung's line in pixel 4c+RMIN comes first in the column, 4c+RMAX's last.
.macro RENDS lean
  .if .xmatch({lean}, L)
        RMIN .set 3
        RMAX .set 0
  .else
        RMIN .set 0
        RMAX .set 3
  .endif
.endmacro

; The top of column c (segment s, j'th in it): its lines above the first full
; one, which is left in X.
; In a pair (side L or R), no X out.  Y = 8 * c for PART (TOPPG routines keep Y).
.macro TOP c, s, j, side
        .local lev, js
  .if .xmatch({side}, "")
        ldy SEGV+s
        ldx TOPC+c                 ; X out when level
        lda .ident(.sprintf("TBL%dL", j)),y
        beq lev                    ; level across the column
        sta js+1                   ; (every TOP's entry is in TOPPG)
        ldy #<(8 * (c))            ; (PART's column)
js:     jsr TOPPG
  .elseif .xmatch({side}, "L")     ; (Y = 8 * c already: prun's)
        ldx SEGV+s
        lda .ident(.sprintf("TBLL%dL", j)),x
        beq lev
        sta js+1
        ldx TOPC+c
js:     jsr TOPPG
        ldx SEGV+s                 ; (for R)
  .else                            ; (X = SEGV+s already)
        lda .ident(.sprintf("TBLR%dL", j)),x
        beq lev
        sta js+1
        ldy #<(8 * (c))
        ldx TOPC+c
js:     jsr TOPPG
  .endif
lev:
.endmacro

.macro ONE c, s, j
        lda #<(8 * c)
        sta coff
        TOP c, s, j, ""
        ldy BOTC+c
        jsr run
.endmacro

; Two one-box columns, c and c+1, j and j+1 in segment s: the lower one's
; lines below the other's bottom (WLINES); one run from their first full line (the
; earlier one's, by PMINj) to the higher bottom, two columns at a time (prun);
; then each its top, which overwrites the run's lines above the later one's
; first full line, and puts back the black line above that one's top if the
; top row steps between them (TBLLj, TBLRj).
; Lines X .. to-1 (X < to) of column off/8, a line at a time (Y, wp: spoilt).
.macro WLINES to, off
        .local l, e
        ldy #<(off)
l:      lda LINEL,x                ; y mod 8: no carry into the high byte
        sta wp
        lsr a                      ; C: the line's parity
        lda LINEH1,x
        ora half
        sta wp+1
        lda ce
        bcc e
        lda co
e:      sta (wp),y
        inx
        cpx to
        bne l
.endmacro

.macro PONE c, s, j
        .local lo, gy
        lda #<(8 * c)
        sta coff
        ldy BOTC+c+1
        cpy BOTC+c
        beq gy                     ; Y: the higher bottom (equal: either)
        bcs lo
        tya                        ; c the lower
        tax
        WLINES BOTC+c, 8 * c
        ldy BOTC+c+1
        jmp gy
lo:     ldx BOTC+c                 ; c+1 the lower
        WLINES BOTC+c+1, 8 * c + 8
        ldy BOTC+c
gy:     ldx SEGV+s
        lda TOPC+c                 ; C = 1 here (cpx/wcol's equal exit): PMINj holds PMIN - 1
        adc .ident(.sprintf("PMIN%d", j)),x
        tax
        jsr prun
        TOP c, s, j, "L"
        TOP c+1, s, j+1, "R"           ; (sets coff = 8 * c + 8)
.endmacro

; Column c's rung (rwalk_l/r: v "p" from the box above's line Y).
.macro RUNG c, lean, v
        lda #<(8 * c + 8)          ; (lp's low byte)
        ldx #(4 * c)
  .if .xmatch({lean}, L)
        jsr .ident(.concat("rwalk_l", v))
  .else
        jsr .ident(.concat("rwalk_r", v))
  .endif
.endmacro

; tu: tgl is ut already (the group's first column, after SETUD); td: tgl is dt
; already (ONER after another).  Either leaves tgl = dt.
.macro TWO c, s, j, lean, wide, tu, pre, suf
        .local messy, done, nu, ok, below
        RENDS lean
        lda #<(8 * c)
        sta coff
  .if suf                          ; (C: the rung done by the bottom; A: the
        lda BOTC+c                 ; box below's lines, for the walk)
        sec
        sbc RT+4*c+RMAX
  .else
        ldy BOTC+c
        cpy RT+4*c+RMAX            ; the rung done by the bottom,
  .endif
        bcs ok
messy:
  .if suf
        lda #0                     ; (rwalk's r0+3: none)
        sta r0+3
  .endif
        lda BOTC+c                 ; (rare: out of the way of the rest)
        sta b1
        lda #c
        ldx #j
        ldy #s
        jsr gtwo
        lda dt
        sta tgl
        jmp done
  .if pre
nu:     RUNG c, lean, ""           ; (no box above)
        jmp below
  .endif
ok:
  .if suf
        sta r0+3
  .endif
        TOP c, s, j, ""
        cpx RT+4*c+RMIN            ; and the top by the rung's first line
        beq nu
        bcs messy
  .if pre
        txa                        ; the box above, walked with the rung
        tay
        RUNG c, lean, "p"
  .else
    .if !tu
        lda ut
        sta tgl
    .endif
        ldy RT+4*c+RMIN            ; the box above
        jsr run
        sec                        ; (rwalk's C: set by beq nu's way too)
nu:     RUNG c, lean, ""           ; the rung (and the box below if suf)
  .endif
below:
  .if !suf
        lda dt
        sta tgl
        ldy BOTC+c                 ; the box below (none if the rung ends
        ldx RT+4*c+RMAX            ; there: run_d's X = Y run is empty)
        jsr run_d
  .endif
done:
.endmacro

.macro ONER c, lean, wide, td, suf
        .local ok, done
        RENDS lean
  .if !suf                         ; (coff: for run_d and gone_r only)
        lda #<(8 * c)
        sta coff
  .endif
  .if !td
        lda dt
        sta tgl
  .endif
  .if suf                          ; (C: the rung by the bottom; A: the box
        lda BOTC+c                 ; below's lines)
        sec
        sbc RT+4*c+RMAX
        bcs ok
        lda BOTC+c                 ; (rare: out of the way of the rest)
        sta b1
        lda #<(8 * c)
        sta coff
  .else
        ldy BOTC+c
        cpy RT+4*c+RMAX            ; the rung by the bottom
        bcs ok
        sty b1                     ; (rare: out of the way of the rest)
  .endif
        lda #c
        jsr gone_r
        jmp done
ok:
  .if suf
        sta r0+3                   ; the box below's lines
        RUNG c, lean, ""           ; the rung and the box below, walked
  .else                            ; the box below first (Y = BOTC+c still;
        ldx RT+4*c+RMAX            ; none if the rung ends there: run_d's
        jsr run_d                  ; X = Y run is empty), then the rung
        RUNG c, lean, ""           ; (lines RMIN .. RMAX-1: no line in common)
  .endif
done:
.endmacro

; The tables for the left half of the screen (h = 0, A = 0 already), or the
; right (h = 1): every address 256 on.  prun: nothing planted in this half's
; PSTAB (the other half's plant is put back by the next prun as before).
.macro SETHALF h
  .if h
        lda #1
  .endif
        sta half
        lda #NONE
        sta pplant
        lda #>(SEXH1 + h * (SEXH2 - SEXH1))
        sta r_xh+2
        sta z:d_xh+2
        lda #>(SENTH1 + h * (SENTH2 - SENTH1))
        sta r_eh+2
        sta z:d_eh+2                 ; (r_eh2, d_eh2: the same bytes)
        lda #>(PH1 + h * (PH2 - PH1))
        sta z:p_xh+2
        sta z:p_eh+2
.endmacro

fill:   lda #0
        sta r0+3                   ; (rwalk: no box below unless set)
        SETHALF 0                  ; the left half (no PSTAB plant; the STAB
                                   ; one is put back by the next run)
        .include "fillcols.inc"
        rts                        ; (the plants stay: each run first puts back the last)
        .res 292                   ; (the left end's columns' code, now in fixedrung's
                                   ; RODATA: the code after keeps the reference's
                                   ; addresses, so no loop of rwalk's crosses a page)



; Lines X .. Y-1 (X < Y): ce on even lines (STA / EOR tgl), ce ^ tgl on odd
; (STA / TXA: X = ce), through STAB from
; X's entry to an RTS planted at Y's STA.  The RTS stays for the next run that
; ends there, and is moved when one ends elsewhere (each way its own JMP).
; run_d: the same in de.
.macro RUN col, xh, eh, eh2
        .local j2
        eh = eh2                   ; (no same-line shortcut: replanting is harmless)
        lda SENTL,x
        sta j2+1
eh2:    lda SENTH1,x
        sta j2+2
        ldx #0
        lda #OP_STAY               ; put back the last
        sta (pp,x)
        lda SEXL,y
        sta pp
xh:     lda SEXH1,y
        sta pp+1
        lda #OP_RTS
        sta (pp,x)
        lda col                    ; (X: the even lines' byte, for the odd lines' TXA)
        tax
        ldy coff
j2:     jmp $FFFF
.endmacro
run:    RUN ce, r_xh, r_eh, r_eh2

; Lines X .. Y-1 (X <= Y) of columns coff/8 and the next, through PSTAB, the
; same way: an RTS planted at Y's LDA.  It runs in zero page (copied there by
; gentables): its own operands are zero-page stores, and the planted RTS's
; address (pq, pr_r's operand) the pointer that plants it.
        .segment "ZPCODE": zeropage
prun:   cpy #NONE                  ; (its operand is pplant)
        beq pr_go
        sty pplant
        lda #OP_STAY               ; put back the last
pr_r:   sta dummy                  ; (pq: unplant first puts back here)
        lda PL,y
        sta z:pq
p_xh:   lda PH1,y
        sta z:pq+1
        ldy #0
        lda #OP_RTS
        sta (pq),y
pr_go:  lda PEL,x                   ; (a line's load and STA share a page)
        sta z:pr_j+1
p_eh:   lda PH1,x
        sta z:pr_j+2
pr_x:   ldx #0                     ; (its operand is ce: PSTAB's even lines TXA)
pr_y:   ldy #0                     ; (its operand is coff)
pr_j:   jmp $FFFF
pq      = pr_r+1
; run_d: as run, in de, in zero page: the put-back's operand is pp.
run_d:  lda SENTL,x
        sta z:dj+1
d_eh:   lda SENTH1,x
        sta z:dj+2
        lda #OP_STAY               ; put back the last
d_r:    sta dummy
        lda SEXL,y
        sta z:pp
d_xh:   lda SEXH1,y
        sta z:pp+1
        ldy #0
        lda #OP_RTS
        sta (pp),y
        ldx de
        txa
        ldy coff
dj:     jmp $FFFF
pp      = d_r+1
d_eh2   = d_eh
pplant  = prun+1
ce      = pr_x+1
coff    = pr_y+1
        .code




.macro UNPLANT
        lda #OP_STAY
        ldy #0
        sta (pp),y
        sta (pq),y
        lda #<dummy
        sta pp
        sta pq
        lda #>dummy
        sta pp+1
        sta pq+1
        lda #NONE
        sta pplant
.endmacro
unplant:
        UNPLANT
        rts
dummy:  .byte 0



        .align 256                 ; (rwalk_l/r's branches cross no page; any
                                   ; other such .align before the walks: the same)
; A sub-run of a column's walk (X lines, at least one): e an even line's
; byte, o an odd's, unrolled by line parity: ev an even line's entry, od an
; odd's.  Only an odd line can end a character row (Y = $FF), so only it tests
; for the wrap.  Its end after an even line goes to xo (the next sub-run's odd
; entry, out of line), after an odd line falls through with the next sub-run's
; count (nx) in X.  up: X counts up from minus the count instead.
.macro SUBW e, o, ev, od, w, n, xo, nx, up, nd
ev:     lda e
        sta (lp),y
        iny
  .ifblank up
        dex
  .else
        inx
  .endif
        beq xo
od:     lda o
        sta (lp),y
        iny
        beq w
  .ifblank up
n:      dex
  .else
n:      inx
  .endif
        bne ev
  .ifnblank nd
nd:
  .endif
  .ifnblank nx
        ldx nx
  .endif
.endmacro

; SUBW's next character row, out of line (after RWALK's rts) so that the
; sub-run's end falls through.  C = 0 throughout the walk (RWALK's last
; subtraction borrows; nothing in SUBW touches C), and lp+1 < $FE.
.macro SUBWW w, ev, nd, up
w:      ldy #$F8                   ; the next character row
        lda lp+1
        adc #2
        sta lp+1
  .ifblank up                      ; SUBW's n, in line
        dex
  .else
        inx
  .endif
        bne ev
        beq nd
.endmacro

; The rung's lines in column X/4, its pixels taken in order p0..p3, walked
; through (lp),Y from the first, then the box below's: r0+3 lines (none if 0,
; left 0: it is 0 at every call that does not set it).  A: lp's low byte,
; 8 * column + 8 (mod 256); half: the screen's half, fixed by the lean.
.macro RWALK nm, p0, p1, p2, p3, half
        .local w0, w1, w2, n0, n1, n2, nd0, nd1, nd2, xo0, xo1, xo2, wb, nb, evb, odb, fin
        sta lp                     ; lp: the column in its character row less
        ldy RT+p0,x                ; 248, Y: 248 + the line in it, so that
        lda RT+p2,x                ; INY wraps at the row's end
                                   ; r0+k: sub-run k's line count (each
        sbc RT+p1,x                ; at least one, so C stays set; the
                                   ; caller sets C)
        sta r0+1
        lda RT+p3,x
        sbc RT+p2,x
        sta r0+2
        lda LINEH1,y               ; lp+1: LINEH1 + half - 1 (the half is
  .if !half                        ; fixed by the lean: gentab.py)
        sbc #1                     ; (C set, and stays set)
  .endif
        sta lp+1
        tya                        ; X: minus sub-run 0's count (it counts
        sbc RT+p1,x                ; up), and C = 0 (a borrow) for SUBWW
        tax
        tya                        ; LINEL = y AND 7
        ora #$F8
        tay
        and #1                     ; the first line's parity (C kept)
        bne .ident(.concat(nm, "_od0"))
        SUBW #0, #0, .ident(.concat(nm, "_ev0")), .ident(.concat(nm, "_od0")), w0, n0, xo0, r0+1, up, nd0
        SUBW #0, #0, .ident(.concat(nm, "_ev1")), .ident(.concat(nm, "_od1")), w1, n1, xo1, r0+2, , nd1
        SUBW #0, #0, .ident(.concat(nm, "_ev2")), .ident(.concat(nm, "_od2")), w2, n2, xo2, r0+3, , nd2
        bne evb
        rts                        ; (no box below)
        SUBW de, do, evb, odb, wb, nb, fin
fin:    stx r0+3                   ; (X = 0: none for the next call)
        rts
xo2:    ldx r0+3
        bne odb
        rts
xo0:    ldx r0+1                   ; (at least one line: always taken)
        bne .ident(.concat(nm, "_od1"))
xo1:    ldx r0+2
        bne .ident(.concat(nm, "_od2"))
        SUBWW w0, .ident(.concat(nm, "_ev0")), nd0, up
        SUBWW w1, .ident(.concat(nm, "_ev1")), nd1
        SUBWW w2, .ident(.concat(nm, "_ev2")), nd2
        SUBWW wb, evb, fin
.endmacro

; The same from the box above's line Y (at least one line before the rung's
; first) in ue/uo.
.macro RWALKP nm, p0, p1, p2, p3, half
        .local wa, na, eva, oda, xoa, nda
        sta lp
        lda RT+p2,x
        sec
        sbc RT+p1,x
        sta r0+1
        lda RT+p3,x
        sbc RT+p2,x
        sta r0+2
        lda LINEH1,y
  .if !half
        sbc #1                     ; (C set, and stays set)
  .endif
        sta lp+1
        lda RT+p0,x
        sbc RT+p1,x
        sta r0                     ; (r0: minus sub-run 0's; X: minus the
        sec                        ; box above's, Y less the rung's first
        tya                        ; line; C = 0 for SUBWW: a borrow)
        sbc RT+p0,x
        tax
        tya
        ora #$F8
        tay
        and #1
        bne oda
        SUBW ue, uo, eva, oda, wa, na, xoa, r0, up, nda
        jmp .ident(.concat(nm, "_ev0"))
xoa:    ldx r0                     ; (at least one line)
        jmp .ident(.concat(nm, "_od0"))
        SUBWW wa, eva, nda, up
.endmacro
        .res 168               ; (rwalk where it was: its branches stay in their pages)
        .align 256                 ; (rwalk_l+rwalk_lp, rwalk_r+rwalk_rp: a page
                                   ; each, so that no walk branch crosses one)
        .align 256                 ; (rwalk_l+rwalk_lp, rwalk_r+rwalk_rp: a page
                                   ; each, so that no walk branch crosses one)
rwalk_l: RWALK "rwalk_l", 3, 2, 1, 0, 0
rwalk_lp: RWALKP "rwalk_l", 3, 2, 1, 0, 0
rwalk_r: RWALK "rwalk_r", 0, 1, 2, 3, 1
rwalk_rp: RWALKP "rwalk_r", 0, 1, 2, 3, 1


; A column a line at a time, lines X .. b1-1, each pixel p from its top tp+p
; (black above), ue/uo above its rung line rp+p and de/do from it.
gl:     cpx b1
        bcc gl_l
        rts
gl_l:   txa                        ; X = the line throughout
        lsr a
        bcs gl_o
        lda ue
        sta gu
        lda de
        sta gd
        bcc gl_g
gl_o:   lda uo
        sta gu
        lda do
        sta gd
gl_g:   lda #0
        sta m
.repeat 4, p
        .scope
        cpx tp+p
        bcc skip                   ; above its top
        cpx rp+p
        lda gu
        bcc :+
        lda gd                     ; at or below its rung line
:       and #($88 >> p)
        ora m
        sta m
skip:
        .endscope
.endrepeat
        lda LINEL,x
        ora coff
        sta gl_s+1
        lda LINEH1,x
        ora half
        sta gl_s+2
        lda m
gl_s:   sta $FFFF
        inx
        cpx b1
        beq :+
        jmp gl_l
:       rts

; A two column's rung lines from its column (rp).
.macro RPS
        asl a
        asl a
        tax
        lda RT,x
        sta rp
        lda RT+1,x
        sta rp+1
        lda RT+2,x
        sta rp+2
        lda RT+3,x
        sta rp+3
.endmacro

; A TWO column whose rung meets its top or its bottom: A = column, X = its
; place in its segment, Y = the segment.  Its pixels' tops from its first, by
; the segment's shape.
gtwo:   sta gs
        lda JMUL,x
        sta tmp
        lda SEGV,y
        lsr a                      ; |dy|, C: rising
        php
        clc
        adc tmp
        tay
        ldx gs
        lda TOPC,x
        sta tp
        plp
        bcs @rise
        clc
        adc TC1,y
        sta tp+1
        lda tp
        clc
        adc TC2,y
        sta tp+2
        lda tp
        clc
        adc TC3,y
        sta tp+3
        jmp @rp
@rise:  sec
        sbc TC1,y
        sta tp+1
        lda tp
        sec
        sbc TC2,y
        sta tp+2
        lda tp
        sec
        sbc TC3,y
        sta tp+3
@rp:    lda gs
        RPS
        ldx tp                     ; from its highest top
        cpx tp+3
        bcc :+
        ldx tp+3
:       jmp gl

; A ONER column the same: A = column.  No top but the rung.
gone_r: RPS
        lda #0
        sta tp
        sta tp+1
        sta tp+2
        sta tp+3
        ldx rp                     ; from its first rung line
        cpx rp+3
        bcc :+
        ldx rp+3
:       jmp gl

JMUL:   .repeat ROW0_DX / 4, j
        .byte j * (MAXDY + 1)
        .endrepeat

; ---------------------------------------------------------------- the tables
; STAB1: for each line y to 160, STA y's address,Y / EOR tgl; STAB2 the same 4
; pages on, for the right half (every address 256 on).  SEXL, SEXH1, SEXH2: each
; line's STA; SENTL, SENTH1, SENTH2: where a run from it starts with A = the even
; lines' byte (an odd line: the last line's EOR).  LINEL, LINEH1: each
; line's address.
gentables:
        ldx #<__ZPCODE_SIZE__      ; prun to zero page
:       lda __ZPCODE_LOAD__-1,x
        sta <(__ZPCODE_RUN__-1),x
        dex
        bne :-
@pg:    lda #NONE                  ; RT: none
        sta RT,x
        txa                        ; SCREEN + (y/8)*512 + y mod 8
        and #7
        sta LINEL,x
        txa
        lsr a
        lsr a
        lsr a
        asl a                      ; (C clear)
        adc #>SCREEN
        sta LINEH1,x
        inx
        bne @pg
        lda #NONE                  ; (LINEH1+253..255 ran into RT)
        sta RT
        sta RT+1
        sta RT+2
        lda #>(STAB2-STAB1)
        sta p2off
        lda #<STAB1
        sta ptr
        lda #>STAB1
        sta ptr+1
        ldx #16
@st:    lda ptr
        sta SEXL,x
        lda ptr+1
        sta SEXH1,x
        clc
        adc #>(STAB2-STAB1)
        sta SEXH2,x
        txa
        lsr a
        lda ptr
        ldy ptr+1
        bcc :+                     ; an odd line: 2 back
        sec
        sbc #2
        bcs :+
        dey
:       sta SENTL,x
        tya
        sta SENTH1,x
        clc
        adc #>(STAB2-STAB1)
        sta SENTH2,x
        ldy #0
        lda #OP_STAY
        jsr gput
        lda LINEL,x
        jsr gput
        lda LINEH1,x
        jsr gputlr
        txa                        ; an even line: EOR tgl (the odd byte);
        lsr a                      ; an odd: TXA (the even, in X)
        lda #$8A                   ; (TXA)
        bcs :+
        lda #OP_EORZP
        jsr gput
        lda #tgl
:       jsr gput
        tya                        ; ptr += 5 or 4
        clc
        adc ptr
        sta ptr
        bcc :+
        inc ptr+1
:       inx
        cpx #LINES+1
        bne @st
        lda #>(PSTAB2-PSTAB1)      ; PSTAB1, PSTAB2, PEL, PL, PH1, PH2: each line
        sta p2off                  ; its load (TXA: ce in X, or LDA co), then
        lda #<PSTAB1               ; STA line,Y / STA line+8,Y; PEL the load,
        sta ptr                    ; PL/PH the first STA (the plant)
        lda #>PSTAB1
        sta ptr+1
        ldx #16
@ps:    lda ptr
        sta PEL,x
        ldy #0
        txa
        lsr a
        lda #OP_TXA
        bcc :+
        lda #OP_LDAZP
        jsr gput
        lda #co
:       jsr gput
        jsr padv
        lda ptr
        sta PL,x
        lda ptr+1
        sta PH1,x
        clc
        adc #>(PSTAB2-PSTAB1)
        sta PH2,x
        lda #OP_STAY
        jsr gput
        lda LINEL,x
        jsr gput
        lda LINEH1,x
        jsr gputlr
        lda #OP_STAY
        jsr gput
        lda LINEL,x
        ora #8
        jsr gput
        lda LINEH1,x
        jsr gputlr
        jsr padv
        inx
        cpx #LINES+1
        bne @ps
        jmp unplant

; ptr += Y, Y = 0
padv:   tya
        clc
        adc ptr
        sta ptr
        bcc :+
        inc ptr+1
:       ldy #0
        rts

; Into the left-half table at (ptr),Y and the right half's p2off pages on: A
; into both (gput), or A and A+1 (gputlr); Y on
gput:   sta (ptr),y
        pha
        jsr g_right
        pla
        sta (ptr),y
        jsr g_left
        iny
        rts
gputlr: sta (ptr),y
        pha
        jsr g_right
        pla
        clc
        adc #1
        sta (ptr),y
        jsr g_left
        iny
        rts
g_right: lda ptr+1
        clc
        adc p2off
        sta ptr+1
        rts
g_left: lda ptr+1
        sec
        sbc p2off
        sta ptr+1
        rts

; ---------------------------------------------------------------- the rows
rnd:    lda rng+1                  ; 16-bit xorshift (7,9,8); A = a new byte
        lsr a
        lda rng
        ror a
        eor rng+1
        sta rng+1
        ror a
        eor rng
        sta rng
        eor rng+1
        sta rng+1
        rts

; A row's points: x from x0 by dx, y from y0 in normal steps, kept to 16..159.
.macro ROW pts, x0, ddx, y0
        .local px, py
        ldx #0
        lda #x0
px:     sta pts,x
        clc
        adc #ddx
        inx
        inx
        cpx #18
        bne px
        lda #y0
        sta pts+1
        ldx #2
py:     jsr rnd
        tay
        lda NTAB,y
        clc
        adc pts-1,x
        cmp #16
        bcc py
        cmp #LINES
        bcs py
        sta pts+1,x
        inx
        inx
        cpx #18
        bne py
.endmacro

; A frame's points and colours.  Each rung must be steep (its bottom point
; more than its width below its top point), and each byte column's top no
; lower than its bottom; else the frame is made again.
genrows:
        ROW PTS0, ROW0_X0, ROW0_DX, ROW0_Y0
        ROW PTS1, ROW1_X0, ROW1_DX, ROW1_Y0
        ldx #0
        ldy #0
@steep: lda PTS1+1,x
        sec
        sbc PTS0+1,x
        bcc @again                 ; rising
        cmp RUNGA,y
        beq @again
        bcc @again                 ; no steeper than 45 degrees
        inx
        inx
        iny
        cpy #9
        bne @steep
        jsr interp
        jsr tops_ok
        bcc @box
@again: jmp genrows
        ; the boxes' colours: each a palette entry, unlike the last
@box:   lda #$FF
        sta tmp
        ldx #0
@bx:    jsr rnd
        and #15
        cmp #NPAL
        bcs @bx
        cmp tmp
        beq @bx
        sta tmp
        sta BOXC,x
        inx
        cpx #8
        bne @bx
        lda #15                    ; 8-15: black
:       sta BOXC,x
        inx
        cpx #16
        bne :-
        rts

; C set if a byte column's top row is anywhere below its bottom: its lowest
; top pixel is its first, or (falling) its first + its offset at pixel 3.
tops_ok:
        lda #(ROW0_X0 / 4)
        sta m                      ; the column
        lda #0
        sta gs                     ; the segment
@s:     lda #0
        sta gj                     ; and the column in it
@j:     ldy gs
        lda SEGV,y
        lsr a
        ldx m
        bcs @t0
        ldy gj
        clc
        adc JMUL,y
        tay
        lda TC3,y
        clc
        adc TOPC,x
        jmp @c
@t0:    lda TOPC,x
@c:     cmp BOTC,x                 ; (the line after the bottom)
        bcs @bad
        inc m
        inc gj
        lda gj
        cmp #(ROW0_DX / 4)
        bne @j
        inc gs
        lda gs
        cmp #8
        bne @s
        clc
        rts
@bad:   sec
        rts

; ---------------------------------------------------------------- timing
; The user VIA's timer 2 counts down at 1MHz from $FFFF; a routine's reading
; less an empty run's, doubled, is its 2MHz cycles (to 2), JSR and RTS included.
.macro TIMED routine, dest
        sei
        lda #$FF
        sta UVIA_T2L
        sta UVIA_T2H
.ifnblank routine
        jsr routine
.endif
:       lda UVIA_T2H
        sta dest+1
        lda UVIA_T2L
        sta dest
        lda UVIA_T2H
        cmp dest+1
        bne :-
        cli
.endmacro

.macro TIMEIT routine, out
        TIMED routine, tread
        jsr elapsed
        lda cyc
        sta out
        lda cyc+1
        sta out+1
        lda cyc+2
        sta out+2
        rts
.endmacro

timenull:
        TIMED , tnull
        rts
timeacross:
        TIMEIT across, acyc
timedown:
        TIMEIT down, dcyc
timefill:
        TIMEIT fill, fcyc
elapsed:                           ; cyc = 2 * (tnull - tread), 17 bits
        sec
        lda tnull
        sbc tread
        sta cyc
        lda tnull+1
        sbc tread+1
        asl cyc
        rol a
        sta cyc+1
        lda #0
        rol a
        sta cyc+2
        rts
acyc:   .res 3
tnull:  .res 2                     ; (timing and text, gentables, genrows: not zero page)
tread:  .res 2
cyc:    .res 3
tx:     .res 1
ty:     .res 1
num:    .res 3
p2off:  .res 1
gj:     .res 1
dcyc:   .res 3
fcyc:   .res 3

; ---------------------------------------------------------------- drawing
cls:    lda #0
        sta ptr
        lda #>SCREEN
        sta ptr+1
        ldx #>($8000-SCREEN)       ; 10K
        lda #0
        tay
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        dex
        bne :-
        rts

; ---------------------------------------------------------------- text
; Characters from the MOS's font (OSWORD 10), at character position (tx, ty)
; of the narrow screen: 32 across, each 16 bytes (two MODE 1 bytes a line), ty
; the character row; logical colour 3 (yellow).
putc:   sta oswblk
        lda #10
        ldx #<oswblk
        ldy #>oswblk
        jsr OSWORD
        lda tx
        asl a
        asl a
        asl a
        asl a
        sta ptr                    ; 16 * tx, mod 256
        lda ty
        asl a
        adc #>SCREEN
        sta ptr+1
        lda tx
        cmp #16
        bcc :+
        inc ptr+1
:       ldx #0
@line:  txa
        tay
        lda oswblk+1,x
        and #$F0
        sta tmp
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp
        sta (ptr),y                ; the left four pixels
        lda oswblk+1,x
        and #$0F
        sta tmp
        asl a
        asl a
        asl a
        asl a
        ora tmp
        pha
        txa
        clc
        adc #8
        tay
        pla
        sta (ptr),y                ; the right four
        inx
        cpx #8
        bne @line
        inc tx
        rts
oswblk: .res 9

puts:   stx @ld+1                  ; the string at (X low, Y high), zero-ended
        sty @ld+2
        ldy #0
@ld:    lda $FFFF,y
        beq @end
        sty num
        jsr putc
        ldy num
        iny
        bne @ld
@end:   rts

putdec: ldx #0                     ; num (24 bits), unsigned, without leading zeros
        stx tmp+1                  ; (non-zero once a digit is out)
@pow:   ldy #'0'
@sub:   lda num
        sec
        sbc pow10lo,x
        sta tmp
        lda num+1
        sbc pow10mi,x
        pha
        lda num+2
        sbc pow10hi,x
        bcc @dig
        sta num+2
        pla
        sta num+1
        lda tmp
        sta num
        iny
        bne @sub
@dig:   pla
        tya
        cpx #5
        beq @out                   ; the units always
        cmp #'0'
        bne @out
        lda tmp+1
        beq @next
        lda #'0'
@out:   sta tmp+1
        stx gtmp
        jsr putc
        ldx gtmp
@next:  inx
        cpx #6
        bne @pow
        rts
gtmp:   .byte 0
pow10lo: .byte <100000, <10000, <1000, <100, <10, <1
pow10mi: .byte >100000, >10000, >1000, >100, >10, >1
pow10hi: .byte ^100000, ^10000, ^1000, ^100, ^10, ^1

; The string at s, then the number at n (3 bytes).
.macro SAYNUM s, n
        ldx #<s
        ldy #>s
        jsr puts
        lda n
        sta num
        lda n+1
        sta num+1
        lda n+2
        sta num+2
        jsr putdec
.endmacro

readout:
        lda #0
        sta tx
        sta ty
        SAYNUM s_across, acyc
        SAYNUM s_down, dcyc
        lda #0
        sta tx
        inc ty
        SAYNUM s_fill, fcyc
        rts

        .rodata
s_across: .asciiz "Across "
s_down:   .asciiz "  Down "
s_fill:   .asciiz "Fill "
code_end:
        .assert code_end <= STAB1, error, "code over STAB1"
