; ============================================================================
; land.s -- LAND: a Lander-style landscape on a narrow, double-buffered MODE 1
; screen, panned with the arrow keys.  The BBC port of proto/land.py, as
; proto/frame.py draws it (and proto/bbc.py fills it), pixel for pixel.
;
; The display: MODE 1 cut to 64 bytes a line and 20 character rows (256 x 160
; MODE 1 pixels, 10K), two of them, at $3000 and $5800: one shown while the
; other is drawn.  Black, cyan, magenta and yellow; each tile one of
; proto/swatch35.py's 2x2 dithers of them.
;
; Each frame: the keys move the camera a step (a sixteenth of a tile); the
; grid's corners are projected (`project`, by tools/landgen.py's tables in
; sideways RAM); then the strips, top to bottom (`strips`): the sky (black, from
; line YSKY down to the far row), the land's (each between two rows), the
; ground (black, from the near row down to line YGND), each with a black margin
; box either side out to a byte boundary; then the frame rate; then the screens
; swap at the next vertical sync.  Nothing outside the strips is drawn, and
; they cover all a frame two frames back can have left (proto/frame.py).
;
; A strip: its top row traced into a line by pixel (the last strip's bottom
; row, widened), its bottom row too; each rung's transitions (the line where
; each pixel it crosses changes box); then each byte column, from its top-row
; pixels' highest line down to its floor (its bottom-row pixels' lowest line):
;   - one box: the top zone (the lines down to its top-row pixels' lowest, a
;     line at a time, read-modify-write), then a run to the floor;
;   - a rung splits it: the same, the bytes split at the rung's position in the
;     column (bpos: its pixels left of the rung), a run between transitions;
;   - two rungs split it (rare): a line at a time, each pixel by itself.
; A run is STAB (STA line,Y / EOR tgl a line, for the screen and half being
; drawn) from its first line's entry to an RTS planted at the line after it.
;
; Memory.  LAND loads at $1900 and loads TABLES (tools/landgen.py) into
; sideways RAM bank 4, paged in throughout; then it closes !BOOT and takes the
; filing system's workspace:
;   $0400, $0500  ROWA, ROWB: a row's line by pixel (a strip's top and bottom)
;   $0600         RTBUF: the rungs' transition lines
;   $0900         the frame's rows and columns, $0A40 the strip's, $0B00 the
;                 slow way's
;   $0C00 ENTH, $1700 ENTL: each line's entry in STAB (high, low); $1600
;                 LAH: each line's address (high, less the screen's); $1800
;                 GLY: the readout's characters
;   $0E00, $1000, $1200, $1400  STAB for screen 0 left half, right half,
;                 screen 1 left, right (lines YSKY-YGND+1)
;   $1900         the code
; ============================================================================
        .setcpu "6502"
        .include "tables.inc"

OSWRCH  = $FFEE
OSWORD  = $FFF1
OSBYTE  = $FFF4
OSCLI   = $FFF7
EVNTV   = $0220
ROMSEL  = $FE30
ROMCOPY = $F4
CRTC_IDX = $FE00
CRTC_DAT = $FE01
BANK    = 4

YSKY    = 68                       ; proto/frame.py's
YGND    = 143
MARGIN  = 8
ZFARDI  = NDI - 1

ROWA    = $0400
ROWB    = $0500
RTBUF   = $0600
PX      = $0900                    ; the rows', far to near: 16 a row
PY      = $0950
CLE     = $09A0                    ; the land strips' box bytes: 16 a strip
CLO     = $09E0
CT      = $0A20                    ; the columns': tile, sixteenths
CQ      = $0A30
TX      = $0A40                    ; the strip's: top row (margins at 0, np+1)
TY      = $0A50
BX      = $0A60                    ; bottom row
BY      = $0A70
LO      = $0A80                    ; each rung's pixels: LO..HI-1 (HI = LO if none)
HI      = $0A90
RTPL    = $0AA0                    ; and its transitions: (RTP),x for pixel x
RTPH    = $0AB0
CE      = $0AC0                    ; each box's bytes, even and odd lines
CO      = $0AD0
SPB     = $0B00                    ; the slow way: each pixel's box at the top
STL     = $0B10                    ; and transitions (4 a pixel: line, step)
STD     = $0B20
GLY     = $1800                    ; the readout's characters: 16 bytes each
ENTH    = $0C00
STAB    = $0E00
LAH     = $1600
ENTL    = $1700
RZT     = $0B30                    ; the rows': tile, sixteenths, depth index
RZQ     = $0B38
RDI     = $0B40

OP_STAY = $99
OP_EORZ = $45
OP_RTS  = $60

        .zeropage
cxt:    .res 1                     ; the camera: tile and step (0-15), x and z
cxs:    .res 1
czt:    .res 1
czs:    .res 1
back:   .res 1                     ; the screen being drawn: 0 ($3000), 1 ($5800)
scrb:   .res 1                     ; its high byte
stb0:   .res 1                     ; its STAB's (left half)
np:     .res 1                     ; points a row (8 or 9)
nr:     .res 1                     ; rows (4 or 5)
vcount: .res 1                     ; vertical syncs (the event handler's)
vflip:  .res 1                     ; at the last flip
ptr:    .res 2
tmp:    .res 2
; project
pr:     .res 1
zq:     .res 1
hp0:    .res 2
hp1:    .res 2
syp:    .res 2
lp:     .res 2
vx:     .res 3
rl:     .res 1
rh:     .res 1
ha:     .res 1
hb:     .res 1
xq:     .res 1
xt:     .res 1
; strips
ns:     .res 1                     ; the strip (0 sky, nr ground)
np1:    .res 1                     ; np + 1: the right margin's index
xl:     .res 1                     ; the strip's margins: its columns xl/4 .. xr/4-1
xr:     .res 1
xlp:    .res 1                     ; the last strip's
xrp:    .res 1
topa:   .res 2                     ; its top row's line by pixel, and its bottom's
bota:   .res 2
; trace
tdx2:   .res 1
tdy2:   .res 1
terr:   .res 1
tyy:    .res 1
tx1:    .res 1
tj:     .res 1
; rungs
rD:     .res 1
ra2:    .res 1
rq:     .res 1
rrem:   .res 1
rq2:    .res 1
rr2:    .res 1
alloc:  .res 2
rtp:    .res 2
; columns
x4:     .res 1                     ; the column's first pixel
x4p4:   .res 1
coff:   .res 1                     ; 8 * column, mod 256 (STAB's Y)
half:   .res 1
scrh:   .res 1                     ; the screen's high byte, and the half
stbh:   .res 1                     ; STAB's page for the screen and half
ri:     .res 1                     ; the first rung not wholly left of the column
ys:     .res 4                     ; each pixel's top-row line
mn:     .res 1
mx:     .res 1
flr:    .res 1                     ; the floor, and the line after it
flr1:   .res 1
ve:     .res 1                     ; the bytes being drawn: even and odd lines
vo:     .res 1
tgl:    .res 1                     ; the two EORed (STAB's EOR operand)
re:     .res 1                     ; a split column: the right box's bytes
ro:     .res 1
xe:     .res 1                     ; and the two boxes' EORed
xo:     .res 1
bpos:   .res 1
p0:     .res 1
p1:     .res 1
yy:     .res 1
kk:     .res 1
msk:     .res 1
zv:     .res 1
zp_:    .res 2
rA:     .res 1
rp:     .res 2
TRL:    .res 12                    ; a split column's transitions: line, bpos after
TRB:    .res 12                    ; (a second rung's from 6)
kb:     .res 1
bpos2:  .res 1
le:     .res 1                     ; split2: the boxes' bytes
lo2:    .res 1
me:     .res 1
mo:     .res 1
; readout
fps10:  .res 2
dvs:    .res 8
dvi:    .res 1
vlast:  .res 1
tcol:   .res 1

        .code
; ---------------------------------------------------------------- start
start:  ldx #<cmd_load              ; TABLES to $3000, then to bank 4
        ldy #>cmd_load
        jsr OSCLI
        lda #119                   ; close !BOOT (an EXEC file): the filing
        jsr OSBYTE                 ; system's workspace is then ours
        sei
        lda #BANK
        sta ROMCOPY
        sta ROMSEL
        cli
        lda #$30
        sta ptr+1
        lda #$80
        sta tmp+1
        ldy #0
        sty ptr
        sty tmp
        ldx #$40
:       lda (ptr),y
        sta (tmp),y
        iny
        bne :-
        inc ptr+1
        inc tmp+1
        dex
        bne :-
        ldx #0                     ; the palette (!BOOT has set MODE 1)
:       lda vdu_init,x
        jsr OSWRCH
        inx
        cpx #vdu_end-vdu_init
        bne :-
        jsr glyphs
        ldx #0                     ; narrow the screen: 64 bytes by 20 rows
:       lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne :-
        jsr init
        sei                        ; count vertical syncs (event 4)
        lda #<vsync
        sta EVNTV
        lda #>vsync
        sta EVNTV+1
        cli
        lda #14
        ldx #4
        jsr OSBYTE
        lda #0
        sta back
        jsr setback
        lda vcount
        sta vflip
        sta vlast

loop:   jsr keys
        jsr project
:       lda vcount                 ; the screen to draw shown no more
        cmp vflip
        beq :-
        jsr strips
        jsr readout
        jsr flip
        jmp loop

vsync:  php
        inc vcount
        plp
        rts

cmd_load: .byte "LOAD TABLES 3000", 13

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
        .byte 12, >($3000/8)
        .byte 13, <($3000/8)
        .byte 10, $20              ; cursor off
crtc_end:

; Show the screen just drawn (from the next frame), and draw the other.
flip:   lda #12
        sta CRTC_IDX
        lda back
        beq :+
        lda #>($5800/8) - >($3000/8)
:       clc
        adc #>($3000/8)
        sta CRTC_DAT
        lda vcount
        sta vflip
        sec                        ; the frame's vertical syncs, for the readout
        sbc vlast
        ldx dvi
        sta dvs,x
        inx
        txa
        and #7
        sta dvi
        lda vflip
        sta vlast
        lda back
        eor #1
        sta back
setback:
        lda back                   ; scrb, stb0 for back
        beq :+
        lda #$28
:       clc
        adc #$30
        sta scrb
        lda back
        asl a
        asl a
        adc #>STAB
        sta stb0
        rts

; ---------------------------------------------------------------- init
; (no OS calls: the soak test runs it.)  Both screens black; STAB; ENTL, ENTH;
; LAH; the camera.
init:   lda #0
        tay
        sta ptr
        ldx #$30
        stx ptr+1
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        bpl :-                     ; ($3000-$7FFF)
        ; STAB: four tables, t = 2 * screen + half
        lda #0
        sta tmp                    ; t
@tab:   lda tmp
        asl a
        adc #>STAB
        sta ptr+1
        lda #0
        sta ptr
        ldx #YSKY
@line:  ldy #0
        lda #OP_STAY
        cpx #YGND+1
        bne :+
        lda #OP_RTS
:       sta (ptr),y
        txa
        and #7
        iny
        sta (ptr),y                ; the line's address, low
        txa
        lsr a
        lsr a
        and #$FE                   ; 2 * (y >> 3)
        sta tmp+1
        lda tmp
        and #1                     ; + the half
        ora tmp+1
        sta tmp+1
        lda tmp
        and #2                     ; + the screen
        beq :+
        lda #$28
:       clc
        adc #$30
        adc tmp+1
        iny
        sta (ptr),y
        lda #OP_EORZ
        iny
        sta (ptr),y
        lda #tgl
        iny
        sta (ptr),y
        lda ptr
        clc
        adc #5
        sta ptr
        bcc :+
        inc ptr+1
:       inx
        cpx #YGND+2
        bne @line
        inc tmp
        lda tmp
        cmp #4
        bne @tab
        ldx #0                     ; ENTL, ENTH: 5 * (y - YSKY); LAH
@ent:   txa
        lsr a
        lsr a
        and #$FE
        sta LAH,x
        txa
        sec
        sbc #YSKY
        sta tmp
        lda #0
        sta tmp+1
        lda tmp
        asl a
        rol tmp+1
        asl a
        rol tmp+1
        clc
        adc tmp
        sta ENTL,x
        lda tmp+1
        adc #0
        and #1
        sta ENTH,x
        inx
        bne @ent
        lda #40                    ; the camera
        sta cxt
        lda #30
        sta czt
        lda #0
        sta cxs
        sta czs
        ldx #7
:       lda #0
        sta dvs,x
        dex
        bpl :-
        rts

; ---------------------------------------------------------------- keys
; Arrows: left and right in x, up and down (away and towards) in z.
.macro KEY inkey, routine
        .local no
        lda #129
        ldx #<(256 - inkey)
        ldy #$FF
        jsr OSBYTE
        cpx #$FF
        bne no
        jsr routine
no:
.endmacro
keys:   KEY 26, left
        KEY 122, right
        KEY 58, away
        KEY 42, towards
        rts
left:   dec cxs
        bpl :+
        lda #15
        sta cxs
        dec cxt
:       rts
right:  inc cxs
        lda cxs
        cmp #16
        bne :+
        lda #0
        sta cxs
        inc cxt
:       rts
towards:
        dec czs
        bpl :+
        lda #15
        sta czs
        dec czt
:       rts
away:   inc czs
        lda czs
        cmp #16
        bne :+
        lda #0
        sta czs
        inc czt
:       rts

; ---------------------------------------------------------------- project
; The columns (CT, CQ: tile, sixteenths; np of them), the rows far to near
; (RZT, RZQ, RDI), then each row's points (PX, PY: 16 a row) and each land
; strip's boxes' bytes (CLE, CLO: 16 a strip).
project:
        ldx #0
        lda cxs                    ; the left pinned column: cx - 3.5 tiles
        cmp #8
        bcs :+
        adc #8
        sta CQ
        lda cxt
        sbc #3                     ; (C clear: - 4)
        jmp @lp
:       sbc #8
        sta CQ
        lda cxt
        sbc #3                     ; (C set)
@lp:    sta CT
        inx
        lda #<-3                   ; the inner columns: cxt - 3 + (cxs > 0) .. cxt + 3
        ldy cxs
        beq :+
        lda #<-2
:       sta tmp
@in:    lda tmp
        clc
        adc cxt
        sta CT,x
        lda #0
        sta CQ,x
        inx
        inc tmp
        lda tmp
        cmp #4
        bne @in
        lda cxs                    ; the right pinned column: cx + 3.5
        clc
        adc #8
        cmp #16
        and #15
        sta CQ,x
        lda cxt
        adc #3                     ; (+ 1 if cxs >= 8: C)
        sta CT,x
        inx
        stx np
        ; rows: far pinned (cz + 7.5), inner (czt + 7 down to czt + 5 + (czs > 8)), near pinned (cz + 4)
        ldx #0
        lda czs
        clc
        adc #8
        cmp #16
        and #15
        sta RZQ
        lda czt
        adc #7
        sta RZT
        lda #ZFARDI
        sta RDI
        inx
        lda #5                     ; the inner rows: czt + 7 down to czt + 5 + (czs > 8)
        ldy czs
        cpy #9
        bcc :+
        lda #6
:       sta ha                     ; (the last)
        lda #7
        sta tmp
@rin:   lda tmp
        clc
        adc czt
        sta RZT,x
        lda #0
        sta RZQ,x
        lda tmp                    ; di = 16k - czs - 64
        asl a
        asl a
        asl a
        asl a
        sec
        sbc czs
        sec
        sbc #64
        sta RDI,x
        inx
        dec tmp
        lda tmp
        cmp ha
        bcs @rin
@rnear: lda czs
        sta RZQ,x
        lda czt
        clc
        adc #4
        sta RZT,x
        lda #0
        sta RDI,x
        inx
        stx nr
        ; each row's points
        lda #0
        sta pr
@row:   ldx pr
        lda RZQ,x
        sta zq
        lda RZT,x
        jsr maprow
        stx hp0
        sty hp0+1
        ldx pr
        lda RZT,x
        clc
        adc #1
        jsr maprow
        stx hp1
        sty hp1+1
        ldx pr
        lda RDI,x
        tay                        ; di
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #>SYT
        sta syp+1
        sta lp+1                   ; (lp: VX's)
        tya
        asl a
        asl a
        asl a
        asl a
        sta syp
        ora cxs
        sta lp
        lda RLO,y
        sta rl
        lda RHI,y
        sta rh
        lda lp+1                   ; vx from VX0/1/2 + di*16 + cxs
        clc
        adc #>(VX0-SYT)
        sta lp+1
        ldy #0
        lda (lp),y
        sta vx
        lda lp+1
        adc #>(VX1-VX0)
        sta lp+1
        lda (lp),y
        sta vx+1
        lda lp+1
        adc #>(VX2-VX1)
        sta lp+1
        lda (lp),y
        sta vx+2
        ; the points
        lda pr
        asl a
        asl a
        asl a
        asl a
        sta tmp                    ; 16 * row
        ldx #0
@pt:    stx tmp+1
        lda CT,x
        sta xt
        lda CQ,x
        sta xq
        jsr height
        tay
        lda (syp),y
        ldy tmp
        sta PY,y
        ldx tmp+1
        bne :+
        ldy pr                     ; the left pinned column
        ldx RDI,y
        lda PINL,x
        jmp @px
:       inx
        cpx np
        bne :+
        ldy pr                     ; the right
        ldx RDI,y
        lda PINR,x
        jmp @px
:       lda vx+1                   ; an inner one: vx's top byte, then add r << 8
        clc
        adc rl
        sta vx+1
        lda vx+2
        tax
        adc rh
        sta vx+2
        txa
@px:    ldy tmp
        sta PX,y
        inc tmp
        ldx tmp+1
        inx
        cpx np
        bne @pt
        inc pr
        lda pr
        cmp nr
        beq :+
        jmp @row
:       ; each land strip's boxes: the tile row of its bottom row
        lda #1
        sta pr
@cs:    ldx pr
        lda RZT,x
        jsr maprow
        stx hp0
        sty hp0+1
        lda pr
        sec
        sbc #1
        asl a
        asl a
        asl a
        asl a
        sta tmp                    ; 16 * strip
        ldx #0
@box:   stx tmp+1
        lda CT,x
        and #63
        tay
        lda (hp0),y
        sta ha
        iny
        tya
        and #63
        tay
        lda (hp0),y
        and #15
        cmp #SEA
        bne @land
        lda ha
        and #15
        cmp #SEA
        bne @land
        lda ha
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        lda SEAT,x
        jmp @pal
@land:  lda ha
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        lda LANDT,x
@pal:   tax
        ldy tmp
        lda DE,x
        sta CLE,y
        lda DO,x
        sta CLO,y
        inc tmp
        ldx tmp+1
        inx
        txa
        clc
        adc #1
        cmp np
        bne @box
        inc pr
        lda pr
        cmp nr
        bne @cs
        rts

; The map's row A (mod 64): its address in (X, Y).
maprow: and #63
        pha
        lsr a
        lsr a
        clc
        adc #>MAP
        tay
        pla
        and #3
        lsr a
        ror a
        ror a                      ; (A & 3) << 6
        tax
        rts

; The height at column (xt, xq) of the row (hp0, hp1, zq), as land.corner.
height: lda xt
        and #63
        tay
        lda xq
        ora zq
        bne :+
        lda (hp0),y                ; a whole corner
        and #15
        rts
:       lda (hp0),y                ; across, in the row
        and #15
        sta ha
        iny
        tya
        and #63
        tay
        lda (hp0),y
        and #15
        ldx xq
        jsr lerp
        sta hb
        lda zq
        bne :+
        lda hb
        rts
:       lda xt                     ; and in the row after, then down
        and #63
        tay
        lda (hp1),y
        and #15
        sta ha
        iny
        tya
        and #63
        tay
        lda (hp1),y
        and #15
        ldx xq
        jsr lerp
        pha
        lda hb
        sta ha
        pla
        ldx zq
        ; fall into lerp
; ha to A by X/16 (land.lerp): ha + LERP[(A - ha + 12) * 16 + X].
lerp:   sec
        sbc ha
        clc
        adc #12
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #>LERP
        sta lp+1
        pla
        asl a
        asl a
        asl a
        asl a
        sta lp
        txa
        tay
        lda (lp),y
        clc
        adc ha
        rts

; ---------------------------------------------------------------- strips
; The sky (ns = 0), the land's (ns = 1 .. nr-1: rows ns-1 and ns), the ground
; (ns = nr).  A strip's points: 0 its left margin, 1..np the rows', np+1 its
; right margin.
strips: lda #>ROWA
        sta topa+1
        lda #>ROWB
        sta bota+1
        lda #0
        sta topa
        sta bota
        sta ns
        ldx np
        inx
        stx np1
@strip: jsr setup
        jsr rungs
        jsr cols
        lda topa+1                 ; the bottom row the next's top
        ldx bota+1
        sta bota+1
        stx topa+1
        lda xl
        sta xlp
        lda xr
        sta xrp
        inc ns
        lda ns
        cmp nr
        beq @strip
        bcc @strip
        rts

; The strip's points (TX..BY) and boxes (CE, CO), its top row's line (the
; last strip's bottom row's, widened, or the sky's) and its bottom row's.
setup:  lda ns                     ; the top row: row ns-1 (the sky: row 0)
        beq :+
        sec
        sbc #1
        asl a
        asl a
        asl a
        asl a
:       sta tmp
        lda ns                     ; the bottom row: row ns (the ground: nr-1)
        cmp nr
        bne :+
        sbc #1                     ; (C set)
:       asl a
        asl a
        asl a
        asl a
        sta tmp+1
        ldx #1
@p:     ldy tmp
        lda PX,y
        sta TX,x
        lda PY,y
        ldy ns
        bne :+
        lda #YSKY
:       sta TY,x
        ldy tmp+1
        lda PX,y
        sta BX,x
        lda PY,y
        ldy ns
        cpy nr
        bne :+
        lda #YGND
:       sta BY,x
        inc tmp
        inc tmp+1
        inx
        cpx np1
        bcc @p
        ; the margins: a byte boundary MARGIN or more beyond the bottom row
        lda BX+1
        sec
        sbc #MARGIN
        and #$FC
        sta xl
        sta TX
        sta BX
        ldx np
        lda BX,x
        clc
        adc #MARGIN+3
        and #$FC
        sta xr
        lda TY,x
        sta TY+1,x
        lda BY,x
        sta BY+1,x
        lda xr
        sta TX+1,x
        sta BX+1,x
        lda TY+1
        sta TY
        lda BY+1
        sta BY
        ; the boxes: 0 and np black, 1..np-1 the strip's (all black: sky, ground)
        lda #0
        sta CE
        sta CO
        ldx np
        sta CE,x
        sta CO,x
        lda ns                     ; CLE + 16 * (ns - 1) + box - 1
        asl a
        asl a
        asl a
        asl a
        sec
        sbc #16
        tay
        ldx #1
@c:     lda #0
        sta ve
        sta vo
        lda ns
        beq :+
        cmp nr
        beq :+
        lda CLE,y
        sta ve
        lda CLO,y
        sta vo
:       lda ve
        sta CE,x
        lda vo
        sta CO,x
        iny
        inx
        cpx np
        bcc @c
        ; the top row's line
        lda ns
        bne @widen
        ldx xl                     ; the sky's: flat
        ldy #YSKY
        lda xr
        clc
        adc #1
        jsr flatt
        jmp @bot
@widen: ldx xl                     ; the last strip's bottom row, widened
        ldy TY
        lda xlp
        jsr flatt
        ldx np1
        ldy TY,x
        ldx xrp
        lda xr
        clc
        adc #1
        jsr flatt
@bot:   lda ns                     ; the bottom row's line
        cmp nr
        bne :+
        ldx xl                     ; the ground's: flat
        ldy #YGND
        lda xr
        clc
        adc #1
        jmp flatb
:       jmp traceb

; (topa) from X up to (not including) A: Y.  flatb: (bota).
flatt:  sta tj
        cpx tj
        bcs @d
        stx tmp
        tya
        ldy tmp
:       sta (topa),y
        iny
        cpy tj
        bne :-
@d:     rts
flatb:  sta tj
        cpx tj
        bcs @d
        stx tmp
        tya
        ldy tmp
:       sta (bota),y
        iny
        cpy tj
        bne :-
@d:     rts

; The bottom row (BX, BY 0..np+1) into (bota): each segment as points.py's
; bresenham_ys, one y a pixel.
traceb: ldx #0
@seg:   stx tj
        lda BX+1,x
        sta tx1
        sec
        sbc BX,x
        asl a
        sta tdx2                   ; 2 dx
        lsr a
        sta terr                   ; dx
        lda BY,x
        sta tyy
        ldy BX,x
        sta (bota),y
        lda BY+1,x
        sec
        sbc BY,x
        bcs @down
        eor #$FF                   ; rising: |dy|
        adc #1
        asl a
        sta tdy2
@ul:    iny
        lda terr
        clc
        adc tdy2
:       cmp tdx2
        bcc :+
        sbc tdx2
        dec tyy
        jmp :-
:       sta terr
        lda tyy
        sta (bota),y
        cpy tx1
        bne @ul
        jmp @next
@down:  asl a
        sta tdy2
@dl:    iny
        lda terr
        clc
        adc tdy2
:       cmp tdx2
        bcc :+
        sbc tdx2
        inc tyy
        jmp :-
:       sta terr
        lda tyy
        sta (bota),y
        cpy tx1
        bne @dl
@next:  ldx tj
        inx
        cpx np1
        bcc @seg
        rts

; ---------------------------------------------------------------- rungs
; Each rung's pixels (LO..HI-1) and transitions: rung (xt, yt) - (xb, yb), D =
; yb - yt, a = |xb - xt|: its j'th pixel from xt (xt + j - 1 leaning right, xt
; - j left) changes box at line yt + ceil(D (2j - 1) / 2a) (ragged.transitions).
; Kept at RTBUF on, (RTP),x for pixel x.  The margins: none.
rungs:  lda xl
        sta LO
        sta HI
        ldx np1
        lda xr
        sta LO,x
        sta HI,x
        lda #<RTBUF
        sta alloc
        lda #>RTBUF
        sta alloc+1
        ldx #1
@r:     stx tj
        lda BY,x
        sec
        sbc TY,x
        sta rD
        lda BX,x
        cmp TX,x
        bne :+
        sta LO,x                   ; upright: none
        sta HI,x
        jmp @nx
:       bcs @right
        sta LO,x                   ; leaning left: pixels xb .. xt-1
        lda TX,x
        sta HI,x
        sec
        sbc BX,x
        jmp @a
@right: lda TX,x                   ; leaning right: xt .. xb-1
        sta LO,x
        lda BX,x
        sta HI,x
        sec
        sbc TX,x
@a:     sta rq                     ; (a)
        asl a
        sta ra2                    ; 2a
        lda alloc                  ; RTP = alloc - LO
        sec
        sbc LO,x
        sta RTPL,x
        sta rtp
        lda alloc+1
        sbc #0
        sta RTPH,x
        sta rtp+1
        lda alloc                  ; alloc += a
        clc
        adc rq
        sta alloc
        bcc :+
        inc alloc+1
:       lda rD                     ; q, rem = D div 2a, mod; q2, r2 = 2D's
        ldy #0
:       cmp ra2
        bcc :+
        sbc ra2
        iny
        bne :-
:       sty rq
        sta rrem
        lda rD
        asl a
        ldy #0
:       cmp ra2
        bcc :+
        sbc ra2
        iny
        bne :-
:       sty rq2
        sta rr2
        ldy TX,x                   ; the pixels, from xt out
        lda BX,x
        cmp TX,x
        bcc @left
@rl:    lda rrem                   ; line yt + q + (rem > 0)
        cmp #1
        lda TY,x
        adc rq
        sta (rtp),y
        jsr @step
        iny
        tya
        cmp HI,x
        bne @rl
        beq @nx
@left:  dey
        lda rrem
        cmp #1
        lda TY,x
        adc rq
        sta (rtp),y
        jsr @step
        tya
        cmp LO,x
        bne @left
@nx:    ldx tj
        inx
        cpx np1
        bcs :+
        jmp @r
:       rts
@step:  lda rrem                   ; + 2D
        clc
        adc rr2
        sta rrem
        lda rq
        adc rq2                    ; (C clear: rem < 4a < 256)
        sta rq
        lda rrem
        cmp ra2
        bcc :+
        sbc ra2
        sta rrem
        inc rq
:       rts

; ---------------------------------------------------------------- columns
cols:   lda xl
        sta x4
        lda #0
        sta ri
@col:   lda x4
        clc
        adc #4
        sta x4p4
        lda x4
        asl a                      ; 8 * column (C: the right half)
        sta coff
        lda #0
        rol a
        sta half
        clc
        adc scrb
        sta scrh
        lda half
        asl a
        adc stb0
        sta stbh
        ; each pixel's top, the highest and lowest
        ldy x4
        lda (topa),y
        sta ys
        sta mn
        sta mx
        ldx #1
:       iny
        lda (topa),y
        sta ys,x
        cmp mn
        bcs :+
        sta mn
:       cmp mx
        bcc :+
        sta mx
:       inx
        cpx #4
        bne :---
        ; the floor
        ldy x4
        lda (bota),y
        iny
        cmp (bota),y
        bcs :+
        lda (bota),y
:       iny
        cmp (bota),y
        bcs :+
        lda (bota),y
:       iny
        cmp (bota),y
        bcs :+
        lda (bota),y
:       sta flr
        clc
        adc #1
        sta flr1
        ; the rungs: past those wholly left
        ldx ri
        lda x4
:       cmp HI,x
        bcc :+
        inx
        bne :-
:       stx ri
        lda LO,x
        cmp x4p4
        bcc @split
        ; one box: ri - 1
        lda CE-1,x
        sta ve
        lda CO-1,x
        sta vo
        jsr zone1
        ldx mx
        cpx flr1
        bcs @next
        ldy flr1
        jsr run
@next:  lda x4
        clc
        adc #4
        sta x4
        cmp xr
        beq :+
        jmp @col
:       rts
@split: lda LO+1,x
        cmp x4p4
        bcs :++
        lda LO+2,x
        cmp x4p4
        bcs :+
        jsr slow                   ; (three: never seen)
        jmp @next
:       jsr split2
        jmp @next
:       jsr split
        jmp @next

; The top zone of a one-box column: lines mn .. min(mx, flr1)-1, each the
; pixels at or below their top.
zone1:  ldx mn
@l:     cpx mx
        bcs @d
        cpx flr1
        bcs @d
        jsr pmask
        txa
        lsr a
        lda ve
        bcc :+
        lda vo
:       jsr zline
        inx
        bne @l
@d:     rts

; msk: line X's pixels at or below their top.
pmask:  lda #0
        cpx ys+3
        rol a
        cpx ys+2
        rol a
        cpx ys+1
        rol a
        cpx ys
        rol a
        tay
        lda MASKB,y
        sta msk
        rts
MASKB:  .byte $00, $88, $44, $CC, $22, $AA, $66, $EE
        .byte $11, $99, $55, $DD, $33, $BB, $77, $FF

; Line X of the column: A in msk's pixels (read-modify-write).  X kept.
zline:  sta zv
        lda LAH,x
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda (zp_),y
        eor zv
        and msk
        eor (zp_),y
        sta (zp_),y
        rts

; A column a rung splits: L = box ri-1, R = box ri.
split:  ldx ri
        lda CE,x
        sta re
        eor CE-1,x
        sta xe
        lda CO,x
        sta ro
        eor CO-1,x
        sta xo
        lda #0
        jsr mktr
        sta bpos
        ; the zone
        lda #0
        sta kk
        ldx mn
@z:     cpx mx
        bcs @zd
        cpx flr1
        bcs @zd
        jsr catchup
        jsr pmask
        jsr bytes
        txa
        lsr a
        lda ve
        bcc :+
        lda vo
:       jsr zline
        inx
        bne @z
@zd:    ldx mx                     ; the runs, from mx
        cpx flr1
        bcs @rd
@rl:    stx yy
        ldy kk
        lda TRL,y
        cmp flr1
        bcc :+
        lda flr1
:       cmp yy
        beq @tr                    ; (transition at or above: bpos only)
        bcc @tr
        pha
        jsr bytes
        pla
        tay
        ldx yy
        sty yy
        jsr run
        ldx yy
        cpx flr1
        bcs @rd
@tr:    ldy kk
        lda TRB,y
        sta bpos
        inc kk
        ldx yy
        jmp @rl
@rd:    rts

; Rung X's transitions in the column into TRL, TRB from A, ended by $FF; A:
; its position in the column at the top (p0).
mktr:   sta tj
        lda RTPL,x
        sta rtp
        lda RTPH,x
        sta rtp+1
        lda BX,x
        jsr clamp4
        sta p1
        lda TX,x
        jsr clamp4
        sta p0
        ldx tj
        cmp p1
        beq @end
        bcs @lt
@rt:    sta tmp                    ; leaning right: pixels p0 .. p1-1, p+1 after
        clc
        adc x4
        tay
        lda (rtp),y
        sta TRL,x
        ldy tmp
        iny
        sty TRB,x
        inx
        tya
        cmp p1
        bne @rt
        beq @end
@lt:    sec                        ; leaning left: pixels p0-1 .. p1, p after
        sbc #1
        sta TRB,x
        clc
        adc x4
        tay
        lda (rtp),y
        sta TRL,x
        inx
        lda TRB-1,x
        cmp p1
        bne @lt
@end:   lda #$FF
        sta TRL,x
        lda p0
        rts

; A column two rungs split (ri, ri+1): boxes L, M, R = ri-1, ri, ri+1, the
; boundaries at bpos and bpos2, each moving at its transitions.
split2: ldx ri
        lda CE-1,x
        sta le
        lda CO-1,x
        sta lo2
        lda CE,x
        sta me
        lda CO,x
        sta mo
        lda CE+1,x
        sta re
        lda CO+1,x
        sta ro
        lda #0
        jsr mktr
        sta bpos
        ldx ri
        inx
        lda #6
        jsr mktr
        sta bpos2
        lda #0
        sta kk
        lda #6
        sta kb
        ldx mn                     ; the zone
@z:     cpx mx
        bcs @zd
        cpx flr1
        bcs @zd
        jsr catch2
        jsr pmask
        jsr bytes2
        txa
        lsr a
        lda ve
        bcc :+
        lda vo
:       jsr zline
        inx
        bne @z
@zd:    ldx mx                     ; the runs, from mx
        cpx flr1
        bcs @rd
@rl:    stx yy
        ldy kk                     ; the next transition, or the floor
        lda TRL,y
        ldy kb
        cmp TRL,y
        bcc :+
        lda TRL,y
:       cmp flr1
        bcc :+
        lda flr1
:       cmp yy
        beq @tr
        bcc @tr
        pha
        jsr bytes2
        pla
        tay
        ldx yy
        sty yy
        jsr run
        ldx yy
        cpx flr1
        bcs @rd
@tr:    ldx yy
        jsr catch2
        jmp @rl
@rd:    rts

; bpos, bpos2 by their transitions at or above line X.
catch2: ldy kk
:       txa
        cmp TRL,y
        bcc :+
        lda TRB,y
        sta bpos
        iny
        bne :-
:       sty kk
        ldy kb
:       txa
        cmp TRL,y
        bcc :+
        lda TRB,y
        sta bpos2
        iny
        bne :-
:       sty kb
        rts

; ve, vo: split2's bytes (X kept).
bytes2: ldy bpos2
        lda me
        eor re
        and LM,y
        eor re
        sta ve
        lda mo
        eor ro
        and LM,y
        eor ro
        sta vo
        ldy bpos
        lda le
        eor ve
        and LM,y
        eor ve
        sta ve
        lda lo2
        eor vo
        and LM,y
        eor vo
        sta vo
        rts

; bpos by the transitions at or above line X.
catchup:
        ldy kk
        txa
:       cmp TRL,y
        bcc :+
        lda TRB,y
        sta bpos
        iny
        txa
        bne :-
:       sty kk
        rts

; ve, vo: the split column's bytes at bpos (X, Y kept).
bytes:  sty tmp
        ldy bpos
        lda xe
        and LM,y
        eor re
        sta ve
        lda xo
        and LM,y
        eor ro
        sta vo
        ldy tmp
        rts
LM:     .byte $00, $88, $CC, $EE, $FF

; A - x4, clamped to 0..4.
clamp4: sec
        sbc x4
        bcs :+
        lda #0
        rts
:       cmp #4
        bcc :+
        lda #4
:       rts

; Lines X .. Y-1 (X < Y) of the column: ve on even lines, vo odd, through STAB.
run:    lda ve
        eor vo
        sta tgl
        lda ENTL,y
        sta rp
        lda ENTH,y
        ora stbh
        sta rp+1
        ldy #0
        lda #OP_RTS
        sta (rp),y
        lda ENTL,x
        sta @j+1
        lda ENTH,x
        ora stbh
        sta @j+2
        txa
        lsr a
        lda ve
        bcc :+
        lda vo
:       ldy coff
@j:     jsr $FFFF
        ldy #0
        lda #OP_STAY
        sta (rp),y
        rts

; ---------------------------------------------------------------- the slow way
; A column two rungs (or more) split: each pixel's box at the top (ri - 1, and
; each rung reaching the column with xt <= x) and transitions (each rung
; crossing it: +1 leaning left, -1 right), then a line at a time.
slow:   ldx #0
@p:     stx tj                     ; pixel p
        txa
        clc
        adc x4
        sta tx1                    ; its x
        ldy ri
        dey
        tya
        sta SPB,x
        txa
        asl a
        asl a
        tay                        ; 4p: its transitions
        lda #$FF
        sta STL,y
        sta STL+1,y
        sta STL+2,y
        sta STL+3,y
        ldx ri
@r:     lda LO,x
        cmp x4p4
        bcs @pd                    ; (the right margin stops it)
        lda tx1
        cmp TX,x
        bcc :+
        stx tmp                    ; left of x at the top
        ldx tj
        inc SPB,x
        ldx tmp
:       lda tx1                    ; crossing x
        cmp LO,x
        bcc @rn
        cmp HI,x
        bcs @rn
        lda RTPL,x
        sta rtp
        lda RTPH,x
        sta rtp+1
        sty tmp
        ldy tx1
        lda (rtp),y
        ldy tmp
        sta STL,y
        lda BX,x
        cmp TX,x
        lda #1
        bcc :+
        lda #$FF
:       sta STD,y
        iny
@rn:    inx
        bne @r
@pd:    ldx tj
        inx
        cpx #4
        bne @p
        ldx mn                     ; a line at a time
@l:     stx yy
        txa
        lsr a
        lda #<CE
        bcc :+
        lda #<CO
:       sta @cl+1
        lda #0
        sta msk
        sta zv
        ldy #3
@lp:    lda yy
        cmp ys,y
        bcc @skip                  ; above its top
        lda PIXM,y
        ora msk
        sta msk
        sty tj
        lda SPB,y
        sta tmp
        tya
        asl a
        asl a
        tax
@s:     lda STL,x
        cmp #$FF
        beq @sd
        lda yy
        cmp STL,x
        bcc @sn
        lda tmp
        clc
        adc STD,x
        sta tmp
@sn:    inx
        bne @s
@sd:    ldx tmp
@cl:    lda CE,x                   ; (CE or CO)
        ldy tj
        and PIXM,y
        ora zv
        sta zv
@skip:  dey
        bpl @lp
        ldx yy
        lda zv
        jsr zline
        inx
        cpx flr1
        bcc @l
        rts
PIXM:   .byte $88, $44, $22, $11

; ---------------------------------------------------------------- readout
; At each flip: the vertical syncs since the last (dvs, the last 8); the
; readout: 400 / their sum, frames a second, to a tenth (FPSL, FPSH: 4000 /
; sum), at the top left.
glyphs: ldx #0                     ; each character's 8 lines, as MODE 1
@c:     stx tcol                   ; bytes in colour 3: left 4 pixels, right 4
        lda gchars,x
        sta oswblk
        lda #10
        ldx #<oswblk
        ldy #>oswblk
        jsr OSWORD
        lda tcol
        asl a
        asl a
        asl a
        asl a
        tax
        ldy #0
@l:     lda oswblk+1,y
        and #$F0
        sta tmp
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp
        sta GLY,x
        lda oswblk+1,y
        and #$0F
        sta tmp
        asl a
        asl a
        asl a
        asl a
        ora tmp
        sta GLY+8,x
        inx
        iny
        cpy #8
        bne @l
        ldx tcol
        inx
        cpx #gchars_end-gchars
        bne @c
        rts
gchars: .byte "0123456789. FPS"
gchars_end:
G_DOT   = 10
G_SP    = 11
G_F     = 12
oswblk: .res 9

readout:
        ldx #7                     ; the sum
        lda #0
        clc
:       adc dvs,x
        bcc :+
        lda #$FF
        bne :++
:       dex
        bpl :--
:       tax
        lda FPSL,x
        sta fps10
        lda FPSH,x
        sta fps10+1
        lda #0
        sta tcol
        ldy #0                     ; hundreds (tens of frames)
:       lda fps10
        sec
        sbc #100
        tax
        lda fps10+1
        sbc #0
        bcc :+
        sta fps10+1
        stx fps10
        iny
        bne :-
:       tya
        bne :+
        lda #G_SP
:       jsr putg
        ldy #0                     ; tens
:       lda fps10
        sec
        sbc #10
        bcc :+
        sta fps10
        iny
        bne :-
:       tya
        jsr putg
        lda #G_DOT
        jsr putg
        lda fps10
        jsr putg
        lda #G_SP
        jsr putg
        lda #G_F
        jsr putg
        lda #G_F+1
        jsr putg
        lda #G_F+2
        ; fall into putg
; Character A at column tcol of the top character row of the screen drawn.
putg:   asl a
        asl a
        asl a
        asl a
        tax
        lda tcol
        asl a
        asl a
        asl a
        asl a
        sta ptr
        lda scrb
        sta ptr+1
        ldy #0
:       lda GLY,x
        sta (ptr),y
        inx
        iny
        cpy #16
        bne :-
        inc tcol
        rts

        .assert * <= $3000, error, "code over the screen"
