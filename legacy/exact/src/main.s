; ============================================================================
; main.s -- BAND: two rows of nine points, Bresenham-interpolated, joined by
; rungs, and the eight boxes between them filled with dithered colours, on a
; narrow MODE 1 screen, timed.  The BBC port of proto/points.py.
;
; The display: MODE 1 cut to 64 bytes a line and 20 character rows, so 256 x
; 160 MODE 1 pixels, x across and y down, at $5800-$7FFF (a character row is
; 512 bytes).  One prototype pixel is one MODE 1 pixel.  The palette is black,
; cyan, magenta and yellow; each box is one of tools/palette.py's 2x2 dithers,
; so its byte depends on the line's parity.
;
; Each frame: the rows (x fixed, from tools/gentab.py; y a random walk from 80
; and 100 in normal steps of sd 5, kept to 16..159), interpolated to a y for
; every x (`across`: TOPY, BOTY); the rungs between corresponding points, one y
; per x (`down`: RUNGY); each box a random colour, unlike its neighbour; then
; `fill`, a byte column at a time.  The three routines' cycle counts are shown
; at the top.  Any key: a new frame.
;
; Everything about the geometry but the y's is fixed, so tools/gentab.py
; writes much of the code: a routine per row and |dy| (across.inc), an
; unrolled walk per rung and direction (down.inc), and the fill's columns,
; each with its kind and boxes (fillcols.inc).
;
; Memory, all built at run time under the screen (the MOS thinks MODE 1 starts
; at $3000; nothing here prints through it):
;   $0400 LINEL, $0500 LINEH1, $0600 LINEH2  each line's address (in the
;               language's workspace, which is ours)
;   $4800 TOPY, $4900 BOTY, $4A00 RUNGY  y by x, $FF where there is none
;   $4B00 STAB1, $4F00 STAB2  STA line,Y / EOR tgl for lines 0-160: the left
;               half of the screen and the right (every address 256 on)
;   $5300 SENTL, $5400 SENTH1, $5500 SENTH2  each line's entry in them, for
;               a run starting there with A = the even lines' byte
;   $0700 SEXL, $0C00 SEXH1, $5600 SEXH2  each line's STA, where a run ends
;   $5700 PTS0, $5720 PTS1  the points, x0,y0 .. x8,y8
;   $5740 BOXC  the boxes' colours (palette entries); 8-15 black
;   $5750 CE, $5760 CO, $5770 TG  box b's byte on even and odd lines, and the
;               two EORed; box 8 black
; ============================================================================
        .setcpu "6502"

OSWRCH  = $FFEE
OSWORD  = $FFF1
OSBYTE  = $FFF4
OSRDCH  = $FFE0
CRTC_IDX = $FE00
CRTC_DAT = $FE01
SVIA_T1L = $FE44                   ; the system VIA's timer: a seed
UVIA_T2L = $FE68                   ; the user VIA's timer 2, counting at 1MHz
UVIA_T2H = $FE69

LINEL   = $0400                    ; (the language's workspace: ours)
LINEH1  = $0500
LINEH2  = $0600
SEXL    = $0700
SEXH1   = $0C00                    ; (the user-defined characters: unused)
TOPY    = $4800
BOTY    = $4900
RUNGY   = $4A00
STAB1   = $4B00
STAB2   = $4F00
SENTL   = $5300
SENTH1  = $5400
SENTH2  = $5500
SEXH2   = $5600
PTS0    = $5700
PTS1    = $5720
BOXC    = $5740
CE      = $5750
CO      = $5760
TG      = $5770
SCREEN  = $5800
LINES   = 160

OP_STAY = $99                      ; STA abs,Y
OP_EORZP = $45                     ; EOR zp
OP_RTS  = $60
NONE    = $FF

        .rodata
        .include "tables.inc"      ; ROWn_X0/DX/Y0, NPAL, DITHE/O, NTAB, Q12, R12

        .zeropage
rng:    .res 2
tmp:    .res 2
ptr:    .res 2                     ; gentables, text
pp:     .res 2                     ; fill: the planted RTS
plant:  .res 1                     ; and its line
; across, down
stp:    .res 1                     ; a row's step: 1 or $FE
rf:     .res 1                     ; a rung's fraction step
rq:     .res 1                     ; and whole step
rr2:    .res 1                     ; or twice its remainder (width 12)
; fill
cx:     .res 1                     ; 4 * column
coff:   .res 1                     ; 8 * column, mod 256: the stores' Y
ce:     .res 1                     ; the colour being drawn: even, odd lines,
co:     .res 1
tgl:    .res 1                     ; and the two EORed
ue:     .res 1                     ; the column's box above the rung
uo:     .res 1
ut:     .res 1
de:     .res 1                     ; and below it
do:     .res 1
dt:     .res 1
xe:     .res 1                     ; and the change between them
xo:     .res 1
tmin:   .res 1                     ; the top row's (or rung's) first line in
tmax:   .res 1                     ; the column, its last, the lines where its
tl:     .res 1                     ; second and third pixels from the start
th:     .res 1                     ; begin, and $80 if it falls to the right
tdir:   .res 1
rmin:   .res 1                     ; the same for the rung
rmax:   .res 1
rl:     .res 1
rh:     .res 1
rdir:   .res 1
rlo:    .res 1                     ; and the lines its sub-runs are kept to
rhi:    .res 1
bmin:   .res 1                     ; the same for the line after the bottom row
bmax:   .res 1
bl:     .res 1
bh:     .res 1
bdir:   .res 1
b1:     .res 1                     ; bmin + 1
xt:     .res 1                     ; (xe ^ xo)
eend:   .res 1                     ; a loop's last line + 1
lp:     .res 2                     ; the walker's line (low byte 0)
cw:     .res 1                     ; and the Y where it wraps: coff + 8
tk:     .res 1                     ; and its toggle
VE:     .res 3                     ; the rung's sub-runs' bytes, from its start
VO:     .res 3
VT:     .res 3
m:      .res 1                     ; a line's pixels
gy:     .res 1                     ; gline: the line
gend:   .res 1
gu:     .res 1                     ; and its colours above and below the rung
gd:     .res 1
p2off:  .res 1                     ; gentables
; timing and text
tnull:  .res 2
tread:  .res 2
cyc:    .res 3
tx:     .res 1
ty:     .res 1
num:    .res 3

        .code
; ---------------------------------------------------------------- start
start:  ldx #0                     ; black, cyan, magenta, yellow (!BOOT sets MODE 1)
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
; A row's segment s (A = y1 - y0, C set if not negative): the routine for its
; |dy|, from x0 (X) and y0 (A), stepping by stp with the carry to match.
.macro SEG r, x0, y0
        .local pos, set, j
        bcs pos
        eor #$FF
        adc #1                     ; (C clear) |dy|
        ldx #$FE
        bne set
pos:    ldx #1
set:    stx stp
        tay
        lda .ident(.sprintf("ROW%dVL", r)),y
        sta j+1
        lda .ident(.sprintf("ROW%dVH", r)),y
        sta j+2
        lda stp
        cmp #$80                   ; C set for $FE
        lda y0
        ldx #x0
j:      jsr $FFFF
.endmacro

        .include "across.inc"

; ---------------------------------------------------------------- down
; A rung's step and starting error from |dy| (A), for width dx, walking down
; (up = 0) or up (1): see gentab.py's `down`.  Leaves Y the error, C clear.
.macro RUNGSET dx, up
.if dx = 12
        tax
        lda Q12,x
        sta rq
        lda R12,x
        sta rr2
        ldy #(244 - up)
.else
        tax
  .repeat (dx = 4) * 2 + (dx = 8) * 3 + (dx = 16) * 4
        lsr a
  .endrepeat
        sta rq
        txa
  .repeat 8 - ((dx = 4) * 2 + (dx = 8) * 3 + (dx = 16) * 4)
        asl a
  .endrepeat
        sta rf
        ldy #(128 - up * (128 / dx))
.endif
        clc
.endmacro

        .include "down.inc"

; The rows, then the rungs.
interp: jsr across
        jmp down

; ---------------------------------------------------------------- fill
; fillcols.inc visits each byte column from the leftmost point's to the
; rightmost's with X = cx = 4 * column and coff = 8 * column (mod 256), after
; setting its boxes' colours (SETUD: ue, uo above the rung, de, do below, and
; ce, co, the colour being drawn, the box above).  Its kind:
;   one_t  one box between the top row and the bottom row
;   one_r  one box between the rung and the bottom row, black above
;   two    every pixel on the rung: box U above it, D below
;   fix    one_t, but pixel 0 is a rung's bottom point: D on its last line
;   pix    pixel 0 alone, a rung's bottom point: D on its last line
; Every row is monotonic across a byte column (each vertex is a pixel 0), and
; so is a rung.  So the top row's lines in a column run from its first pixel's
; to its last's (tmin..tmax), and between them the pixels begin in order; the
; same for the rung (rmin..rmax) and for the line after the bottom row
; (bmin+1..bmax+1, from b1).  A column is then, in order: the top row's lines,
; a pixel at a time (tedge), the box above in a run (run: STAB, from the first
; line's entry to an RTS planted at the line after the last), the rung's lines
; in up to three sub-runs of constant pixels (rsubs: run, or a line at a time
; for short ones), the box below in a run, and the bottom row's lines (bedge).
; Where these overlap -- a rung's end, or a thin band -- the lines are made a
; pixel at a time from all three records (gline).

.macro COL c
        ldx #(4 * c)
        stx cx
        lda #<(8 * c)
        sta coff
.endmacro

.macro SETUD u, d
        lda CE+u
        sta ue
        sta ce
        lda CO+u
        sta uo
        sta co
        lda TG+u
        sta ut
        sta tgl
        lda CE+d
        sta de
        eor ue
        sta xe
        lda CO+d
        sta do
        eor uo
        sta xo
        lda TG+d
        sta dt
        eor ut
        sta xt
.endmacro

; The rung's sub-runs' bytes (VE, VO, and the two EORed: VT), each a pixel more
; D than the last: from the left if it falls to the right (C set), else from
; the right.  Once per rung (RPREP), after SETUD.
.macro RPV k, S
        lda xe
        and #S
        eor ue
        sta VE+k
        lda xo
        and #S
        eor uo
        sta VO+k
        lda xt
        and #S
        eor ut
        sta VT+k
.endmacro
.macro RPREP xl, xr
        lda RUNGY+xr
        cmp RUNGY+xl
        jsr rprep
.endmacro
fill:   ldx #8                     ; each box's bytes; 8 black
:       ldy BOXC,x
        lda DITHE,y
        sta CE,x
        eor DITHO,y
        sta TG,x
        lda DITHO,y
        sta CO,x
        dex
        bpl :-
        jsr half_left
        .include "fillcols.inc"
        jmp unplant

; Lines X .. Y-1 (X < Y): ce on even lines, ce ^ tgl on odd, through STAB from
; X's entry to an RTS planted at Y's STA.  The RTS stays for the next run that
; ends there, and is moved when one ends elsewhere.
run:    cpy plant
        beq r_ent
        sty plant
        lda #OP_STAY               ; put back the last
        ldy #0
        sta (pp),y
        ldy plant
        lda SEXL,y
        sta pp
r_xh:   lda SEXH1,y
        sta pp+1
        lda #OP_RTS
        ldy #0
        sta (pp),y
r_ent:  lda SENTL,x
        sta r_j+1
r_eh:   lda SENTH1,x
        sta r_j+2
        lda ce
        ldy coff
r_j:     jmp $FFFF

; The same for X .. Y-1 if X < Y.
run_c:  stx tmp
        cpy tmp
        beq :+
        bcs run
:       rts

unplant:
        lda #OP_STAY
        ldy #0
        sta (pp),y
        lda #<dummy
        sta pp
        lda #>dummy
        sta pp+1
        lda #NONE
        sta plant
        rts
dummy:  .byte 0

; The tables for the left half of the screen, or the right (every address 256 on).
half_left:
        jsr unplant
        ldx #0
        beq half
half_right:
        jsr unplant
        ldx #1
half:   lda hsxh,x
        sta r_xh+2
        lda hseh,x
        sta r_eh+2
        lda hlh,x
        sta lh_1+2
        sta lh_2+2
        sta lh_3+2
        sta lh_4+2
        sta lh_5+2
        sta lh_6+2
        sta lh_7+2
        sta lh_8+2
        sta lh_9+2
        sta lh_10+2
        sta lh_11+2
        rts
hsxh:   .byte >SEXH1, >SEXH2
hseh:   .byte >SENTH1, >SENTH2
hlh:    .byte >LINEH1, >LINEH2

; Lines X .. Y-1 (X < Y) one at a time: ce on even lines, co on odd.  (Short
; runs: from emit.)
lines:  sty eend
lines1: lda LINEL,x
        ora coff
        sta l_s+1
lh_1:   lda LINEH1,x
        sta l_s+2
        txa
        lsr a
        lda ce
        bcc l_s
        lda co
l_s:    sta $FFFF
        inx
        cpx eend
        bne lines1
        rts

; Lines X .. Y-1 (X < Y) in ce, co: a run, or short ones a line at a time.
emit:   sty eend
        txa
        eor #$FF
        sec
        adc eend                   ; Y - X
        cmp #3
        bcc lines1
        jmp run

; An edge's lines X .. Y-1 (X < Y), from the line's pixels (p1 before line lo,
; p2 before hi, else p3) and the colour ce, co.
.macro EDGE p1, p2, p3, lo, hi, site
        .local l, v, s
        sty eend
l:      lda #p1
        cpx lo
        bcc v
        lda #p2
        cpx hi
        bcc v
        lda #p3
v:      sta m
        lda LINEL,x
        ora coff
        sta s+1
site:   lda LINEH1,x
        sta s+2
        txa
        lsr a
        lda ce
        bcc :+
        lda co
:       and m
s:      sta $FFFF
        inx
        cpx eend
        bne l
        rts
.endmacro

; The top row's (or a rung's) lines X .. Y-1, if X < Y: falling to the right,
; pixel 0 first; else pixel 3 first.
tedge_c:
        stx tmp
        cpy tmp
        beq @r
        bcc @r
        bit tdir
        bmi tinc
        jmp tdec
@r:     rts
tedge:  bit tdir
        bmi tinc
        jmp tdec
tinc:   EDGE $88, $CC, $EE, tl, th, lh_2
tdec:   EDGE $11, $33, $77, tl, th, lh_3

; The bottom row's: falling to the right, pixel 0 ends first; else pixel 3.
bedge_c:
        stx tmp
        cpy tmp
        beq @r
        bcc @r
        bit bdir
        bmi binc
        jmp bdec
@r:     rts
bedge:  bit bdir
        bmi binc
        jmp bdec
binc:   EDGE $77, $33, $11, bl, bh, lh_4
bdec:   EDGE $EE, $CC, $88, bl, bh, lh_5

; A row's or rung's ends in a byte column (X = 4 * column): its first line, its
; last, the lines its middle pixels start at in order, and $80 if it falls to
; the right (else 0; level: none of these but the ends).  For the bottom row,
; the lines after (plus = 1), and b1.
.macro ENDS T, vmin, vmax, vl, vh, vdir, plus
        .local dec, lev
        lda T,x
        cmp T+3,x
        beq lev
        bcs dec
        sta vmin
        ldy T+1,x
.if plus
        iny
.endif
        sty vl
        ldy T+2,x
.if plus
        iny
.endif
        sty vh
        ldy T+3,x
        sty vmax
        lda #$80
        sta vdir
        rts
dec:    sta vmax
        ldy T+2,x
.if plus
        iny
.endif
        sty vl
        ldy T+1,x
.if plus
        iny
.endif
        sty vh
        ldy T+3,x
        sty vmin
        lda #0
        sta vdir
        rts
lev:    sta vmin
        sta vmax
        rts
.endmacro

ends_t: ENDS TOPY, tmin, tmax, tl, th, tdir, 0
ends_r: ENDS RUNGY, rmin, rmax, rl, rh, rdir, 0
ends_b: jsr ends_b0
        ldy bmin
        iny
        sty b1
        rts
ends_b0: ENDS BOTY, bmin, bmax, bl, bh, bdir, 1

; Lines X .. Y-1 (X < Y) a pixel at a time, from the column's records: black
; above the top (T), ue/uo above the rung, de/do to the bottom, black below.
.macro GLINE T, site
        .local l, odd, go, s
        sty gend
l:      stx gy
        txa
        lsr a
        bcs odd
        lda ue
        sta gu
        lda de
        sta gd
        bcc go
odd:    lda uo
        sta gu
        lda do
        sta gd
go:     lda #0
        sta m
        ldx cx
.repeat 4, p
        .scope
        lda gy
        cmp T+p,x
        bcc skip                   ; above the top
        lda BOTY+p,x
        cmp gy
        bcc skip                   ; below the bottom
        lda gy
        cmp RUNGY+p,x
        lda gu
        bcc :+
        lda gd                     ; at or below the rung
:       and #($88 >> p)
        ora m
        sta m
skip:
        .endscope
.endrepeat
        ldx gy
        lda LINEL,x
        ora coff
        sta s+1
site:   lda LINEH1,x
        sta s+2
        lda m
s:      sta $FFFF
        inx
        cpx gend
        beq :+
        jmp l
:       rts
.endmacro

gl_t_c: stx tmp
        cpy tmp
        beq :+
        bcs gl_t
:       rts
gl_t:   GLINE TOPY, lh_6
gl_r_c: stx tmp
        cpy tmp
        beq :+
        bcs gl_r
:       rts
gl_r:   GLINE RUNGY, lh_7

; The rung's sub-runs (rmin..rl, rl..rh, rh..rmax), kept to rlo..rhi-1: from
; the side it starts, one pixel more D in each.
rsubs:  bit rdir
        bmi @inc
        ldx rmin
        ldy rl
        lda #$11
        jsr sub
        ldx rl
        ldy rh
        lda #$33
        jsr sub
        ldx rh
        ldy rmax
        lda #$77
        jmp sub
@inc:   ldx rmin
        ldy rl
        lda #$88
        jsr sub
        ldx rl
        ldy rh
        lda #$CC
        jsr sub
        ldx rh
        ldy rmax
        lda #$EE
sub:    cpx rlo
        bcs :+
        ldx rlo
:       cpy rhi
        bcc :+
        ldy rhi
:       stx tmp
        cpy tmp
        beq @r
        bcc @r
        sta m                      ; D in these pixels, U in the rest
        lda xe
        and m
        eor ue
        sta ce
        lda xo
        and m
        eor uo
        sta co
        eor ce
        sta tgl
        jmp emit
@r:     rts

; The walker: lines from X down, through (lp),Y.
wstart: lda LINEL,x
        ora coff
        tay
lh_10:  lda LINEH1,x
        sta lp+1
        lda coff
        clc
        adc #8
        sta cw
        rts

; X (> 0) lines on: A, then A ^ tk, ...
wseg:   sta (lp),y
        eor tk
        iny
        cpy cw
        beq @w
@n:     dex
        bne wseg
        rts
@w:     ldy coff                   ; the next character row
        inc lp+1
        inc lp+1
        bne @n

rprep:  bcc @dec
        RPV 0, $88
        RPV 1, $CC
        RPV 2, $EE
        rts
@dec:   RPV 0, $11
        RPV 1, $33
        RPV 2, $77
        rts

; The rung's k'th sub-run, from line `from` to `to`, walked.
.macro SUBW from, to, k
        .local l, w, n, skip
        lda to
        sec
        sbc from
        beq skip
        tax
        lda VT+k
        sta tk
        lda from
        lsr a
        lda VE+k
        bcc l
        lda VO+k
l:      sta (lp),y
        eor tk
        iny
        cpy cw
        beq w
n:      dex
        bne l
        beq skip
w:      ldy coff                   ; the next character row
        inc lp+1
        inc lp+1
        bne n
skip:
.endmacro

; The rung's lines rmin .. rmax-1, when nothing else is there: its three
; sub-runs, walked.
rwalk:  ldx rmin
        cpx rmax
        bne :+
        rts
:       jsr wstart
        SUBW rmin, rl, 0
        SUBW rl, rh, 1
        SUBW rh, rmax, 2
        rts

; Below the rung: the bottom row's lines, and the box below in a run.
dpart:  lda de
        sta ce
        lda do
        sta co
        lda dt
        sta tgl
        ldx cx
        lda BOTY,x
        cmp BOTY+3,x
        bne :+
        tay                        ; level
        iny
        ldx rmax
        jmp run_c
:       jsr botedge
        tay
        ldx rmax
        jmp run_c

; From the rung's lines on (rlo = the first not yet made): its sub-runs, where
; it overlaps the bottom row's lines a pixel at a time, the box below, and the
; bottom row's lines.
.macro RBODY GL
        lda rmax                   ; sub-runs to the first bottom row line
        cmp b1
        bcc :+
        lda b1
:       sta rhi
        jsr rsubs
        ldx b1                     ; the overlap
        cpx rlo
        bcs :+
        ldx rlo
:       ldy rmax
        jsr GL
        lda de                     ; the box below
        sta ce
        lda do
        sta co
        lda dt
        sta tgl
        ldx rmax
        ldy b1
        jsr run_c
        ldx b1                     ; the bottom row
        cpx rmax
        bcs :+
        ldx rmax
:       ldy bmax
        iny
        jmp bedge_c
.endmacro

; Line Y's pixels A in ce or co, by its parity.  Keeps X.
pst:    sta m
        lda LINEL,y
        ora coff
        sta ps_s+1
lh_11:  lda LINEH1,y
        sta ps_s+2
        tya
        lsr a
        lda ce
        bcc :+
        lda co
:       and m
ps_s:   sta $FFFF
        rts

; The top row's lines in the column (X = cx), its ends unlike: made, and tmax
; (also in A).  Mostly one line, of the pixels level with the higher end.
topedge:
        lda TOPY,x
        cmp TOPY+3,x
        bcs @dec
        adc #1                     ; (C clear) falling to the right
        cmp TOPY+3,x
        bne @gen
        ldy TOPY,x                 ; one line: from pixel 0 (monotonic, so
        lda TOPY,x                 ; level with it is no lower)
        cmp TOPY+2,x
        lda #$EE
        bcs @one
        lda TOPY,x
        cmp TOPY+1,x
        lda #$CC
        bcs @one
        lda #$88
@one:   jsr pst
        lda TOPY+3,x
        cmp TOPY,x
        bcs :+
        lda TOPY,x
:       sta tmax
        rts
@dec:   sbc #1                     ; (C set) rising to the right
        cmp TOPY+3,x
        bne @gen
        ldy TOPY+3,x               ; one line: from pixel 3
        lda TOPY+3,x
        cmp TOPY+1,x
        lda #$77
        bcs @one
        lda TOPY+3,x
        cmp TOPY+2,x
        lda #$33
        bcs @one
        lda #$11
        bne @one
@gen:   jsr ends_t
        ldx tmin
        ldy tmax
        jsr tedge
        ldx cx
        lda tmax
        rts

; The bottom row's, the same: and b1 (also in A).
botedge:
        lda BOTY,x
        cmp BOTY+3,x
        bcs @dec
        adc #1                     ; (C clear) falling to the right
        sta b1
        cmp BOTY+3,x
        bne @gen
        tay                        ; one line: to pixel 3
        lda BOTY+1,x
        cmp BOTY+3,x
        lda #$77
        bcs @one
        lda BOTY+2,x
        cmp BOTY+3,x
        lda #$33
        bcs @one
        lda #$11
@one:   jsr pst
        lda b1
        rts
@dec:   lda BOTY+3,x               ; rising to the right
        adc #0                     ; (C set) + 1
        sta b1
        cmp BOTY,x
        bne @gen
        tay                        ; one line: to pixel 0
        lda BOTY+2,x
        cmp BOTY,x
        lda #$EE
        bcs @one
        lda BOTY+1,x
        cmp BOTY,x
        lda #$CC
        bcs @one
        lda #$88
        bne @one
@gen:   jsr ends_b
        ldx b1
        ldy bmax
        iny
        jsr bedge
        ldx cx
        lda b1
        rts

; One box, between the top row and the bottom row.
one_t:  lda TOPY,x
        cmp TOPY+3,x
        bne @tn
        sta tmax                   ; the top level
        lda BOTY,x
        cmp BOTY+3,x
        bne @bn
        tay                        ; both level: one run
        iny
        ldx tmax
        jmp run
@bn:    jsr botedge                ; the bottom row's lines, and the box
        tay
        ldx tmax
        jmp run
@tn:    lda BOTY,x
        cmp BOTY+3,x
        bne @both
        tay                        ; the bottom level: the top row's lines,
        iny                        ; and the box
        sty b1
        jsr topedge
        tax
        ldy b1
        jmp run
@both:  lda TOPY,x                 ; neither: unless the rows come close,
        cmp TOPY+3,x               ; the same
        bcs :+
        lda TOPY+3,x
:       sta tmp
        lda BOTY,x
        cmp BOTY+3,x
        bcc :+
        lda BOTY+3,x
:       cmp tmp                    ; bmin < tmax
        bcc @slow
        jsr topedge
        jsr botedge
        tay
        ldx tmax
        jmp run
@slow:  jsr ends_t
        jsr ends_b
        ldx tmin                   ; the top row, to the bottom row's first line
        ldy tmax
        cpy b1
        bcc :+
        ldy b1
:       jsr tedge_c
        ldx b1                     ; where they overlap
        ldy tmax
        jsr gl_t_c
        ldx tmax                   ; the box
        ldy b1
        jsr run_c
        ldx b1                     ; the bottom row
        cpx tmax
        bcs :+
        ldx tmax
:       ldy bmax
        iny
        jmp bedge_c

; One box between the rung and the bottom row, black above: SETUD 8, box.
one_r:  jsr ends_r
        lda BOTY,x                 ; the rung clear of the bottom row
        cmp BOTY+3,x
        bcc :+
        lda BOTY+3,x
:       cmp rmax                   ; bmin + 1 < rmax
        bcs :+
        adc #1
        cmp rmax
        bcc @gen
:       jsr rwalk
        jmp dpart
@gen:   jsr ends_b
        lda rmin
        sta rlo
        RBODY gl_r_c

; Two boxes, every pixel on the rung.
two:    lda ue
        sta ce
        lda uo
        sta co
        lda ut
        sta tgl
        jsr ends_r
        lda TOPY,x                 ; the rung clear of both rows
        cmp TOPY+3,x
        bcs :+
        lda TOPY+3,x
:       cmp rmin
        beq :+
        bcs @gen
:       lda BOTY,x
        cmp BOTY+3,x
        bcc :+
        lda BOTY+3,x
:       cmp rmax                   ; bmin + 1 < rmax
        bcs :+
        adc #1
        cmp rmax
        bcc @gen
:       lda TOPY,x                 ; the top row's lines
        cmp TOPY+3,x
        bne :+
        sta tmax
        beq :++
:       jsr topedge
:       ldx tmax                   ; the box above
        ldy rmin
        jsr run_c
        jsr rwalk
        jmp dpart
@gen:   jsr ends_t
        jsr ends_b
        ldx tmin                   ; the top row, to the rung's first line
        ldy tmax
        cpy rmin
        bcc :+
        ldy rmin
:       jsr tedge_c
        ldx rmin                   ; where they overlap
        ldy tmax
        jsr gl_t_c
        ldx tmax                   ; the box above
        ldy rmin
        jsr run_c
        lda rmin                   ; the rung from the box above's end
        cmp tmax
        bcs :+
        lda tmax
:       sta rlo
        RBODY gl_t_c

; one_t, then pixel 0's last line in D: SETUD U, D.
fix:    lda ue                     ; (after a two, ce is D)
        sta ce
        lda uo
        sta co
        lda ut
        sta tgl
        jsr one_t
        ldx cx
        ldy BOTY,x
        lda LINEL,y
        ora coff
        sta f_r+1
        sta f_w+1
lh_8:   lda LINEH1,y
        sta f_r+2
        sta f_w+2
        tya
        lsr a
        lda xe
        bcc :+
        lda xo
:       and #$88
f_r:    eor $FFFF
f_w:    sta $FFFF
        rts

; Pixel 0's last line in D: SETUD 8, D.
pix:    ldy BOTY,x
        lda LINEL,y
        ora coff
        sta p_w+1
lh_9:   lda LINEH1,y
        sta p_w+2
        tya
        lsr a
        lda de
        bcc :+
        lda do
:       and #$88
p_w:    sta $FFFF
        rts

; ---------------------------------------------------------------- the tables
; STAB1: for each line y to 160, STA y's address,Y / EOR tgl; STAB2 the same 4
; pages on, for the right half (every address 256 on).  SEXL, SEXH1, SEXH2: each
; line's STA; SENTL, SENTH1, SENTH2: where a run from it starts with A = the even
; lines' byte (an odd line: the last line's EOR).  LINEL, LINEH1, LINEH2: each
; line's address.
gentables:
        ldx #0
@pg:    lda #NONE                  ; TOPY, BOTY, RUNGY: none
        sta TOPY,x
        sta BOTY,x
        sta RUNGY,x
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
        ora #1
        sta LINEH2,x
        inx
        bne @pg
        lda #>(STAB2-STAB1)
        sta p2off
        lda #<STAB1
        sta ptr
        lda #>STAB1
        sta ptr+1
        ldx #0
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
        lda #OP_EORZP
        jsr gput
        lda #tgl
        jsr gput
        lda #5                     ; ptr += 5
        clc
        adc ptr
        sta ptr
        bcc :+
        inc ptr+1
:       inx
        cpx #LINES+1
        bne @st
        jmp unplant

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

; A frame's points and colours.  Rows that cross, or a rung that leaves the
; band, are thrown away and the frame made again: fill needs the top row, rung
; and bottom row in that order at every x (equal is fine).
genrows:
        ROW PTS0, ROW0_X0, ROW0_DX, ROW0_Y0
        ROW PTS1, ROW1_X0, ROW1_DX, ROW1_Y0
        jsr interp
        jsr inorder
        bcs genrows
        ; the boxes' colours: each a palette entry, unlike the last
        lda #$FF
        sta tmp
        ldx #0
@box:   jsr rnd
        and #15
        cmp #NPAL
        bcs @box
        cmp tmp
        beq @box
        sta tmp
        sta BOXC,x
        inx
        cpx #8
        bne @box
        lda #15                    ; 8-15: black
:       sta BOXC,x
        inx
        cpx #16
        bne :-
        rts

; C set unless top <= rung <= bottom wherever they are.
inorder:
        ldx #0
@x:     lda TOPY,x
        cmp #NONE
        beq @notop
        cmp BOTY,x
        beq :+
        bcs @bad                   ; top below bottom
:       lda RUNGY,x
        cmp #NONE
        beq @next
        cmp TOPY,x
        bcc @bad                   ; rung above top
        bcs @bot
@notop: lda RUNGY,x
        cmp #NONE
        beq @next
@bot:   cmp BOTY,x
        beq @next
        bcs @bad                   ; rung below bottom
@next:  inx
        bne @x
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
