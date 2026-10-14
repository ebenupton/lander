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
; A run is STAB (STA line,Y, then LDA vo after an even line, TXA (X = ve)
; after an odd, for the screen and half being drawn) from its first line's entry to an RTS planted at the line after it.
;
; Memory.  LAND loads at $1900 and loads TABLES (tools/landgen.py) into
; sideways RAM bank 4, paged in throughout; then it closes !BOOT and takes the
; filing system's workspace:
;   $0400, $0500  ROWA, ROWB: a row's line by pixel (a strip's top and bottom)
;   $0600         RTBUF: the rungs' transition lines
;   $0900         the frame's rows and columns, $0A40 the strip's, $0B00 the
;                 slow way's
;   $1700 ENTL, ENTH: each line's entry in STAB (low, high); $0C00 TOPS,
;                 BOTS, $0B60 CURT, CURB: each column's highest and lowest
;                 land line, by screen (the last frame drawn there) and this; $1600
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
BANK    = 4                        ; sideways RAM: the tables
BANK2   = 5                        ; and the tiles' colours (project's, a moment)

YSKY    = 68                       ; proto/frame.py's
YGND    = 143
MARGIN  = 0                        ; (to the byte boundary: the land extents clear the rest)
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
ENTH    = $1700+160-YSKY           ; (lines YSKY..YGND+1 only, after ENTL's)
TOPS    = $0C00                    ; by screen, column: the land's highest line last time
BOTS    = $0C80                    ; and lowest
CURT    = $0B60                    ; this frame's
CURB    = $0BA0
STAB    = $0E00
LAH     = $1600+160-YSKY           ; each line's 2 * (y >> 3) (lines YSKY..YGND+1)
LAH0    = $1600-YSKY               ; and its address's high byte, screen 0 (left half)
LAH1    = $1600+80-YSKY            ; screen 1
ENTL    = $1700
RZT     = $0B30                    ; the rows': tile, sixteenths, depth index
RZQ     = $0B38
RDI     = $0B40
RML     = $0B48                    ; each row's map row address
RMH     = $0B50
PINRX   = $0B58                    ; and its right pinned column's x

SWT     = $9400                    ; init's line tables, in bank 4's free space: two a
                                   ; page, by line (YSKY..YGND+1: no page crossed)
EXLB    = SWT                      ; run's entries (low), and high by STAB
LAHSB0  = SWT+$6C                  ; each line's address, high byte: by screen and half
LAHSB1  = SWT+$100
LAHSB2  = SWT+$16C
LAHSB3  = SWT+$200
EXHB0   = SWT+$26C
EXHB1   = SWT+$300
EXHB2   = SWT+$36C
EXHB3   = SWT+$400
ENTB0   = SWT+$46C                 ; each STAB's ENTH
ENTB1   = SWT+$500
ENTB2   = SWT+$56C
ENTB3   = SWT+$600
        .assert YGND+1+$6C < $100, error, "SWT: a line table crosses a page"
OP_STAY = $99
OP_LDAZ = $A5
OP_TXA  = $8A
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
lqx:    .res 2
xt1:    .res 1
lqz:    .res 2
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
rend:   .res 1
dva:    .res 1
dvd:    .res 1
dvp:    .res 2
dvq:    .res 2
fe:     .res 1
tcnt:   .res 1
tsy:    .res 1
last:   .res 1                     ; the near strip ($80)
sx_:    .res 1
; columns
x4:     .res 1                     ; the column's first pixel
x4p4:   .res 1
coff:   .res 1                     ; 8 * column, mod 256 (STAB's Y)
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
pp:     .res 2                     ; run's planted RTS
tsp:    .res 2                     ; TOPS, BOTS for the screen being drawn
bsp:    .res 2
rec:    .res 1                     ; a land strip: record CURT, CURB
bpos2:  .res 1
le:     .res 1                     ; split2: the boxes' bytes
lo2:    .res 1
me:     .res 1
mo:     .res 1

        .code
; ---------------------------------------------------------------- start
        .assert * = $1900, error, "start must be first: *RUN enters at $1900"
start:  ldx #<cmd_load2             ; TABLES2 to bank 5, TABLES to bank 4 (by
        ldy #>cmd_load2            ; $3000)
        lda #BANK2
        jsr ldbank
        ldx #<cmd_load
        ldy #>cmd_load
        lda #BANK
        jsr ldbank
        lda #119                   ; close !BOOT (an EXEC file): the filing
        jsr OSBYTE                 ; system's workspace is then ours
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
        lda #$7D                   ; the system VIA's interrupts off but vertical
        sta $FE4E                  ; sync's (no OS keyboard scan, clock or sound:
        lda #$7F                   ; the keys are read directly), the user VIA's
        sta $FE6E                  ; all off
        lda #0
        sta back
        jsr setback
        lda vcount
        sta vflip
        sta vlast

loop:   jsr keys
        jsr project
        jsr strips                 ; (waiting for the flip before drawing)
        jsr readout
        jsr flip
        jmp loop

vsync:  php
        inc vcount
        plp
        rts

cmd_load: .byte "LOAD TABLES 3000", 13
cmd_load2: .byte "LOAD TABLES2 3000", 13

; *LOAD (X, Y: the command) to $3000, then the 16K there to bank A (which is
; left paged in).
ldbank: pha
        jsr OSCLI
        pla
        sei
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
        rts

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
@line:  lda ptr                    ; ENTL, ENTH: the line's place in its STAB
        sta ENTL,x
        lda ptr+1
        and #1                     ; (each STAB at an even page)
        sta ENTH,x
        ldy #0
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
        iny
        txa                        ; an even line: LDA vo; odd: TXA
        lsr a
        lda #OP_TXA
        bcs :+
        lda #OP_LDAZ
        sta (ptr),y
        iny
        lda #vo
:       sta (ptr),y
        tya
        sec                        ; (C: 1 past)
        adc ptr
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
        ldx #0                     ; LAH; each STAB's ENTH
@ent:   cpx #YSKY                  ; (in range only: ENTH follows ENTL)
        bcc :+
        cpx #YGND+2
        bcs :+
        txa
        lsr a
        lsr a
        and #$FE
        sta LAH,x
        clc
        adc #$30
        sta LAH0,x
        adc #$28
        sta LAH1,x
        sec                        ; (+ the half: LAHS)
        sbc #$28
        sta LAHSB0,x
        adc #0
        sta LAHSB1,x
        adc #$28
        sta LAHSB3,x
        sec
        sbc #1
        sta LAHSB2,x
        lda ENTH,x
        ora #>STAB                 ; and each STAB's
        sta ENTB0,x
        clc
        adc #2
        sta ENTB1,x
        adc #2
        sta ENTB2,x
        adc #2
        sta ENTB3,x
        txa                        ; run's entries: an odd line's 2 bytes early,
        and #1                     ; at the line before's LDA vo (so A need be
        asl a                      ; the even lines' byte only at an even's)
        sta tmp+1
        lda ENTL,x
        sec
        sbc tmp+1
        sta EXLB,x
        lda ENTH,x
        sbc #0
        ora #>STAB
        sta EXHB0,x
        clc
        adc #2
        sta EXHB1,x
        adc #2
        sta EXHB2,x
        adc #2
        sta EXHB3,x
:       inx
        beq :+
        jmp @ent
:
        ldx #127                   ; nothing drawn yet
:       lda #$FF
        sta TOPS,x
        lda #0
        sta BOTS,x
        dex
        bpl :-
        lda #<dummy                ; no RTS planted
        sta pp
        lda #>dummy
        sta pp+1
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
; Arrows: left and right in x, up and down (away and towards) in z.  Read
; from the keyboard directly (the system VIA, its auto-scan off a moment).
SVIA_ORB = $FE40
SVIA_DDRA = $FE43
SVIA_ORA_NH = $FE4F
.macro KEY code, routine
        .local no
        lda #code
        sta SVIA_ORA_NH
        lda SVIA_ORA_NH            ; (bit 7: pressed)
        bpl no
        jsr routine
no:
.endmacro
keys:   sei
        lda #$7F                   ; bits 0-6 out: the key to test
        sta SVIA_DDRA
        lda #3                     ; keyboard auto-scan off
        sta SVIA_ORB
        KEY $19, left
        KEY $79, right
        KEY $39, away
        KEY $29, towards
        lda #$0B                   ; and on
        sta SVIA_ORB
        cli
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
; project's: inner column i's x (vx's top byte, then vx += r << 8; C clear
; before and after), and its y at an inner row (a whole corner).  X: 16 * row.
.macro PXI i
        lda vx+1
        adc rl
        sta vx+1
        lda vx+2
        sta PX+i,x
        adc rh
        sta vx+2
.endmacro
.macro PXT_ i                       ; (bank 5) inner column i's x, from PXT
        ldy #i
        lda (lp),y
        sta PX+i,x
.endmacro
.macro CBOX i                       ; (bank 5) box i's colour: CMAPE, CMAPO
        ldy CT+i
        lda (hp0),y
        sta CLE-16+i,x
        lda (hp1),y
        sta CLO-16+i,x
.endmacro
.macro PYI i
        ldy CT+i
        lda (hp0),y
        and #15
        tay
        lda (syp),y
        sta PY+i,x
.endmacro

project:
        ldy cxs                    ; the columns (landgen's COLO, COLQ, NPT)
        lda NPT,y
        sta np
        tya
        asl a
        asl a
        asl a
        asl a
        tay
        ldx #0
:       lda COLO,y
        clc
        adc cxt
        and #63
        sta CT,x
        lda COLQ,y
        sta CQ,x
        iny
        inx
        cpx np
        bne :-
        lda CQ                     ; (both pinned columns' sixteenths)
        asl a
        asl a
        asl a
        asl a
        asl a
        sta lqx
        lda #>LERPQ
        adc #0
        sta lqx+1
        ldy czs                    ; the rows, far to near (ROWO, ROWQ, ROWD, NRT)
        lda NRT,y
        sta nr
        tya
        asl a
        asl a
        asl a
        tay
        ldx #0
:       lda ROWO,y
        clc
        adc czt
        and #63
        sta RZT,x
        lda ROWQ,y
        sta RZQ,x
        lda ROWD,y
        sta RDI,x
        iny
        inx
        cpx nr
        bne :-
        lda #0
        sta pr
@row:   ldx pr                     ; a row: its map rows, SYT's, LERPQ's
        ldy RZT,x
        lda MRL,y
        sta hp0
        sta RML,x
        lda MRH,y
        sta hp0+1
        sta RMH,x
        iny
        tya
        and #63
        tay
        lda MRL,y
        sta hp1
        lda MRH,y
        sta hp1+1
        lda RZQ,x
        sta zq
        asl a
        asl a
        asl a
        asl a
        asl a
        sta lqz
        lda #>LERPQ
        adc #0
        sta lqz+1
        ldy RDI,x                  ; di
        lda SYPL,y
        sta syp
        lda SYPH,y
        sta syp+1
        txa
        asl a
        asl a
        asl a
        asl a
        tax                        ; (X: 16 * row, throughout)
        stx tmp
        lda PINL,y                 ; its pinned columns' x (the inner ones' from
        sta PX,x                   ; bank 5, after)
        lda PINR,y
        ldy pr
        sta PINRX,y
        pha
        txa
        clc
        adc np
        tay
        pla
        sta PX-1,y
@py:    ldy #0                     ; its y: the pinned columns' (interpolated)
        jsr pinc
        tay
        lda (syp),y
        sta PY,x
        ldy np
        dey
        sty tj
        jsr pinc
        tay
        lda (syp),y
        pha
        txa
        clc
        adc tj
        tay
        pla
        sta PY,y
        lda zq                     ; then the inner ones: whole corners
        bne @zr
        PYI 1
        PYI 2
        PYI 3
        PYI 4
        PYI 5
        PYI 6
        lda np
        cmp #9
        bne @nx
        PYI 7
@nx:    inc pr
        lda pr
        cmp nr
        beq @col
        jmp @row
@zr:    lda #1                     ; (a pinned row: interpolated down)
        sta tj
:       ldy tj
        lda CT,y
        tay
        lda (hp0),y
        and #15
        sta ha
        lda (hp1),y
        and #15
        jsr lerpz
        tay
        lda (syp),y
        ldy tj
        sta PY+1,x
        inx
        iny
        sty tj
        iny
        cpy np
        bcc :-
        ldx tmp
        jmp @nx
@col:   lda #BANK2                 ; bank 5: each row's inner columns' x (PXT)
        sta ROMCOPY
        sta ROMSEL
        ldx #0
        stx pr
@ix:    ldy RDI,x                  ; PXT + di*128 + cxs*8
        tya
        lsr a
        tay
        lda #0
        ror a                      ; ((di & 1) << 7)
        sta lp
        tya
        clc
        adc #>PXT
        sta lp+1
        lda cxs
        asl a
        asl a
        asl a
        ora lp
        sta lp
        txa
        asl a
        asl a
        asl a
        asl a
        tax
        PXT_ 1
        PXT_ 2
        PXT_ 3
        PXT_ 4
        PXT_ 5
        PXT_ 6
        PXT_ 7                     ; (np 8: overwritten by the pinned one, below)
        ldx pr
        inx
        stx pr
        cpx nr
        bne @ix
        ldx #0                     ; (the right pinned x again, for np 8)
:       txa
        asl a
        asl a
        asl a
        asl a
        clc
        adc np
        tay
        lda PINRX,x
        sta PX-1,y
        inx
        cpx nr
        bne :-
        lda #1                     ; each land strip's boxes: their tiles'
        sta pr                     ; colours (CMAPE, CMAPO), the tile row its
@cs:    ldx pr                     ; bottom row's
        lda RML,x
        sta hp0
        sta hp1
        lda RMH,x
        clc
        adc #>(CMAPE-MAP)
        sta hp0+1
        adc #>(CMAPO-CMAPE)
        sta hp1+1
        lda pr
        asl a
        asl a
        asl a
        asl a
        tax                        ; 16 * strip + 16
        CBOX 0
        CBOX 1
        CBOX 2
        CBOX 3
        CBOX 4
        CBOX 5
        CBOX 6
        lda np
        cmp #9
        bne :+
        CBOX 7
:
        inc pr
        lda pr
        cmp nr
        beq :+
        jmp @cs
:
        lda #BANK
        sta ROMCOPY
        sta ROMSEL
        rts

; ha to A by the column's sixteenths (lerpx) or the row's (lerpz): land.lerp,
; by LERPQ.  X kept.
lerpx:  sec
        sbc ha
        clc
        adc #12
        tay
        lda (lqx),y
        clc
        adc ha
        rts
lerpz:  sec
        sbc ha
        clc
        adc #12
        tay
        lda (lqz),y
        clc
        adc ha
        rts

; Pinned column Y's height at the row (across by its sixteenths, and down by
; the row's if it is pinned too): A.  X kept.
pinc:   lda CT,y
        tay
        lda (hp0),y
        and #15
        sta ha
        iny
        tya
        and #63
        sta xt1
        tay
        lda (hp0),y
        and #15
        jsr lerpx
        ldy zq
        beq @d
        sta hb
        ldy xt1
        dey
        tya
        and #63
        tay
        lda (hp1),y
        and #15
        sta ha
        ldy xt1
        lda (hp1),y
        and #15
        jsr lerpx
        pha
        lda hb
        sta ha
        pla
        jmp lerpz
@d:     rts

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

; ---------------------------------------------------------------- strips
; The sky (ns = 0), the land's (ns = 1 .. nr-1: rows ns-1 and ns), the ground
; (ns = nr).  A strip's points: 0 its left margin, 1..np the rows', np+1 its
; right margin.
strips: lda back                   ; this screen's TOPS, BOTS
        lsr a
        ror a
        lsr a                      ; 64 * back
        sta tsp
        ora #<BOTS
        sta bsp
        lda #>TOPS
        sta tsp+1
        sta bsp+1
        ldx #63
:       lda #$FF
        sta CURT,x
        lda #0
        sta CURB,x
        dex
        bpl :-
        lda #>ROWA
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
        lda ns
        beq @swap                  ; (row 0: its line only)
        jsr rungs
        lda ns                     ; (before the first drawing: the screen to
        cmp #1                     ; draw shown no more)
        bne @draw
@wait:  lda vcount
        cmp vflip
        beq @wait
@draw:  jsr cols
@swap:  lda topa+1                 ; the bottom row the next's top
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
        bcc @strip
        jsr gone
        ldy #63                    ; this frame's for the screen's next
:       lda CURT,y
        sta (tsp),y
        lda CURB,y
        sta (bsp),y
        dey
        bpl :-
        rts

; The strip's points (TX..BY) and boxes (CE, CO), its top row's line (the
; last strip's bottom row's, widened, or the sky's) and its bottom row's.
setup:  ldx #0                     ; the near strip: the ground below it too
        lda ns
        clc
        adc #1
        cmp nr
        bne :+
        dex
:       stx last
        ldx #0                     ; a land strip: record its lines
        lda ns
        beq :+
        cmp nr
        beq :+
        dex
:       stx rec
        ; the points and the boxes: a land strip's top row ns-1, bottom row ns,
        ; boxes CLE + 16 * (ns - 1) + box - 1 (CE, CO np: zeroed below)
        lda ns
        beq @r                     ; (A = 0: row 0)
        cmp nr
        beq @g
        asl a                      ; (C clear: ns < 16)
        asl a
        asl a
        asl a
        adc #$F0
        tay
        ldx #1
@p:     lda PX,y
        sta TX,x
        lda PY,y
        sta TY,x
        lda PX+16,y
        sta BX,x
        lda PY+16,y
        sta BY,x
        lda CLE,y
        sta CE,x
        lda CLO,y
        sta CO,x
        iny
        inx
        cpx np1
        bcc @p
        bcs @m
        ; the sky (row 0 both, the top at YSKY) and the ground (row nr-1
        ; both, the bottom at YGND): boxes black
@g:     asl a                      ; (C clear: 4 shifts of nr < 16)
        asl a
        asl a
        asl a
        adc #$F0
@r:     tay
        ldx #1
@q:     lda PX,y
        sta TX,x
        sta BX,x
        lda PY,y
        sta TY,x
        sta BY,x
        lda #0
        sta CE,x
        sta CO,x
        iny
        inx
        cpx np1
        bcc @q
        ldx np
        lda ns
        bne @gb
        lda #YSKY
:       sta TY,x
        dex
        bne :-
        beq @m
@gb:    lda #YGND
:       sta BY,x
        dex
        bne :-
@m:
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
        ; the top row's line
        lda ns
        bne @widen
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
        beq :+
        jmp traceb
:
        ldy xl                     ; the ground's: to each column's lowest land
:       tya                        ; line last time or this (BOTS, CURB)
        lsr a
        lsr a
        tax
        sty tmp
        tay
        lda (bsp),y
        cmp CURB,x
        bcs :+
        lda CURB,x
:       ldy tmp
        sta (bota),y
        iny
        sta (bota),y
        iny
        sta (bota),y
        iny
        sta (bota),y
        iny
        cpy xr
        bne :--
        rts

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
; bresenham_ys, one y a pixel.  A shallow segment (|dy| < dx): the error kept
; in Y biased by 256 - 2dx, so the carry is the step; y in tr_y's LDA #.
traceb: lda bota+1
        sta tr_st+2
        sta tg_st+2
        sta fl_0+2
        sta fl_1+2
        sta fl_2+2
        sta fl_3+2
        ldx #0
t_seg:   stx tj
        lda BX+1,x
        sta tx1
        sec
        sbc BX,x
        bne :+
        jmp t_next                 ; (a margin on the row's end: none)
:       sta terr                   ; dx
        asl a
        sta tdx2
        lda BY,x
        sta tr_y+1
        ldy BX,x
        sta (bota),y
        lda BY+1,x
        sec
        sbc BY,x
        ldy #$EE                   ; INC abs
        bcs :+
        eor #$FF                   ; rising: |dy|, DEC
        adc #1
        ldy #$CE
:       sty tr_inc
        cmp terr
        bcc :+
        jmp t_steep
:       sty t_inc                  ; ($EE or $CE: +1 or -1 below)
        tay
        bne :+
        lda tx1                    ; level: one fill
        sta fe
        inc fe
        lda BX,x
        tax
        jmp t_run                  ; (Y = 0: the last run)
:       sta dva                    ; a run a y: the steps at x0 + ceil(dx (2k-1) / 2|dy|)
        asl a                      ; (k = 1 .. |dy|; ragged.transitions' sum)
        sta ra2
        cpy #32
        bcs t_old
        lda terr
        cmp #64
        bcs t_old
        sta dvd
        jsr divt
        lda rrem                   ; e: how far short of the next step
        beq :+
        lda ra2
        sec
        sbc rrem
:       sta rrem
        cmp #1
        lda BX,x
        adc rq
        sta fe                     ; the first step
        lda BX,x
        tax
        ldy dva                    ; (Y: the runs left after this one)
t_run:  lda tr_y+1                 ; (bota) from X to (not including) fe: A,
        cpx fe                     ; 4 at a time (up to 3 more: the next run's,
        bcs fl_d                   ; or the next segment's, put right after)
fl_0:   sta ROWB,x
fl_1:   sta ROWB+1,x
fl_2:   sta ROWB+2,x
fl_3:   sta ROWB+3,x
        inx
        inx
        inx
        inx
        cpx fe
        bcc fl_0
fl_d:   ldx fe                     ; (C set)
t_inc:  inc tr_y+1                 ; (INC or DEC: as tr_inc, patched)
        dey
        bmi t_next
        beq t_last
        lda rrem                   ; the next step: + 2dx / 2|dy|, by e
        sbc rr2
        bcs :+
        adc ra2                    ; (C set after: + 1)
        sta rrem
        lda fe
        adc rq2
        sta fe
        jmp t_run
:       sta rrem
        lda fe
        clc
        adc rq2
        sta fe
        jmp t_run
t_last: lda tx1                    ; the last run, to x1
        sta fe
        inc fe
        jmp t_run
t_old:  lda dva                    ; (dx >= 64 or |dy| >= 32) a pixel at a time
        asl a
        sta tdy2
        lda #0                     ; k: 256 - 2dx, less the carry
        sec
        sbc tdx2
        sec
        sbc #1
        sta tr_k+1
        lda terr                   ; err dx, biased
        clc
        adc tr_k+1
        adc #1
        tay
        lda BX,x
        tax
        clc
        jsr tr_l
t_next: ldx tj
        inx
        cpx np1
        bcs :+
        jmp t_seg
:       rts
t_steep: asl a                      ; (rare) the general loop
        sta tdy2
        lda tr_y+1
        sta tyy
        lda BX,x
        tax
t_gl:    inx
        lda terr
        clc
        adc tdy2
:       cmp tdx2
        bcc :+
        sbc tdx2
        jsr tg_inc
        jmp :-
:       sta terr
        lda tyy
tg_st:  sta ROWB,x
        cpx tx1
        bne t_gl
        beq t_next
tg_inc: lda tr_inc                 ; tyy +- 1, as tr_inc
        cmp #$EE
        bne :+
        inc tyy
        rts
:       dec tyy
        rts


; rq, rrem = dvd div 2a, mod (a = dva, ra2 = 2a); rq2, rr2: 2 dvd's.  divt:
; by DQT, DRT (a < 32, dvd < 64); divs: by them if it can, else subtracting.
divs:   lda dva
        cmp #32
        bcs @sub
        lda dvd
        cmp #64
        bcc divt
@sub:   lda dvd
        ldy #0
:       cmp ra2
        bcc :+
        sbc ra2
        iny
        bne :-
:       sty rq
        sta rrem
        jmp dv2
divt:   ldy dva                    ; (D div a, D mod a: q2, and q, rem, r2 from them)
        lda DVH,y
        sta @q+2
        lda DVR,y
        sta @r+2
        lda DVL,y
        ora dvd
        tay
@r:     lda DRT,y                  ; r = D mod a: r2 = 2r
        asl a
        sta rr2
@q:     lda DQT,y                  ; q2 = D div a: q = q2 / 2
        sta rq2
        lsr a
        sta rq
        lda rr2                    ; rem = r + a (q2 odd)
        bcc :+
        adc ra2                    ; (C set: 2r + 2a + 1)
:       lsr a
        sta rrem
        rts
dv2:    asl a                      ; 2D = 2q (2a) + 2 rem
        sta rr2
        lda rq
        asl a
        sta rq2
        lda rrem
        cmp dva
        bcc :+
        inc rq2
        lda rr2
        sbc ra2                    ; (C set)
        sta rr2
:       rts

tr_l:   inx                        ; X: the pixel, Y: the biased error, C clear
        tya
        adc tdy2
        tay
        bcs tr_s
tr_y:   lda #0
tr_st:  sta ROWB,x
        cpx tx1
        bne tr_l
        rts
tr_s:   tya                        ; a step: unbias, y +- 1
tr_k:   adc #0
        tay
tr_inc: inc tr_y+1
        jmp tr_y

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
        sta rend                   ; (the last pixel's end: xb either way)
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
:       lda rq                     ; q, rem = D div 2a, mod; q2, r2 = 2D's
        sta dva
        lda rD
        sta dvd
        jsr divs
        lda rrem                   ; the first pixel's line: yt + q + (rem > 0),
        beq :+                     ; and how far short of the next: e = 2a - rem
        lda ra2                    ; (0 if rem = 0)
        sec
        sbc rrem
:       sta rrem
        cmp #1                     ; (C: rem > 0)
        lda TY,x
        adc rq
        ldy TX,x                   ; the pixels, from xt out
        cpy rend
        bcs @ll
@rl:    sta (rtp),y                ; leaning right: xt .. xb-1
        iny
        cpy rend
        beq @nx
@rs:    tax                        ; the next pixel's: + 2D / 2a, by e
        lda rrem
        sec
        sbc rr2
        bcs :+
        adc ra2                    ; (C set after)
        sta rrem
        txa
        adc rq2
        sta (rtp),y
        iny
        cpy rend
        bne @rs
        beq @nx
:       sta rrem
        txa
        clc
        adc rq2
        sta (rtp),y
        iny
        cpy rend
        bne @rs
        beq @nx
@ll:    dey                        ; leaning left: xt-1 .. xb
        sta (rtp),y
        cpy rend
        beq @nx
@ls:    tax                        ; (C set: Y > rend)
        lda rrem
        sbc rr2
        bcs :+
        adc ra2                    ; (C set after)
        sta rrem
        txa
        adc rq2
        dey
        sta (rtp),y
        cpy rend
        bne @ls
        beq @nx
:       sta rrem
        txa
        clc
        adc rq2
        dey
        sta (rtp),y
        cpy rend
        bne @ls
@nx:    ldx tj
        inx
        cpx np1
        bcs :+
        jmp @r
:       rts

; ---------------------------------------------------------------- columns
cols:   lda topa+1                 ; this strip's rows' pages
        sta pt0+2
        sta pt1+2
        sta pt2+2
        sta pt3+2
        sta zt1+2
        sta zt2+2
        sta zt3+2
        lda bota+1
        sta pb0+2
        sta pb1+2
        sta pb2+2
        sta pb3+2
        sta zb1+2
        sta zb1+7
        sta zb2+2
        sta zb2+7
        sta zb3+2
        sta zb3+7
        ldx #$E8                   ; INX: the floor's line after (BIT: no nearpost)
        ldy #$2C
        bit last
        bpl :+
        ldx #$EA                   ; (the near strip: NOP, the floor itself if level;
        ldy #$4C                   ; JMP nearpost)
:       stx c_inx
        sty c_np
        lda xlp                    ; record below c_ra or from c_rb on (strip 1: all)
        ldx ns
        dex
        bne :+
        lda #$FF
:       sta c_ra+1
        lda xrp
        sta c_rb+1
        lda #0
        sta ri
        lda xl
        sta x4
        asl a                      ; 8 * column (C: the right half)
        sta coff
        lda #0
        rol a
        jsr sethalf
        jmp c_col
; (rare: out of cols' way) a column whose top or floor is not level
c_zt:    sta ys                     ; (rare) each pixel's top (A: the first's), the
        sta mn                     ; highest and lowest (cols: zt1-3 this strip's)
        sta mx
        bit c_v1                   ; (V: a top not level, to c_r1's and
                                   ; c_split's tests; nothing between touches V)
.macro ZTP n
        lda ROWA+n,y
        sta ys+n
        cmp mn
        bcs :+
        sta mn
        bcc :++
:       cmp mx
        bcc :+
        sta mx
:
.endmacro
zt1:    ZTP 1
zt2:    ZTP 2
zt3:    ZTP 3
        jmp c_ft

c_zb:                               ; (rare) the lowest (A: the first's; cols:
zb1:    cmp ROWB+1,y               ; zb1-3 this strip's)
        bcs :+
        lda ROWB+1,y
:
zb2:    cmp ROWB+2,y
        bcs :+
        lda ROWB+2,y
:
zb3:    cmp ROWB+3,y
        bcs :+
        lda ROWB+3,y
:       sta flr                    ; (not level)
        tax
        inx
        stx flr1
        jmp c_rec
c_col:   ldy x4                     ; the top: level across the column? (V clear:
c_coly:                            ; the adc #4 below, or sethalf's last sbc)
pt0:    lda ROWA,y
pt1:    cmp ROWA+1,y
        bne c_zt
pt2:    cmp ROWA+2,y
        bne c_zt
pt3:    cmp ROWA+3,y
        bne c_zt
        sta mn
        sta mx
c_ft:                               ; the floor: level?
pb0:    lda ROWB,y
pb1:    cmp ROWB+1,y
        bne c_zb
pb2:    cmp ROWB+2,y
        bne c_zb
pb3:    cmp ROWB+3,y
        bne c_zb
        sta flr                    ; (level)
        tax
c_inx:  inx                        ; (cols: NOP in the near strip, its ground's
        stx flr1                   ; from the floor's line on)
c_rec:                             ; a column new this frame (strip 1's, or
c_ra:   cpy #0                     ; beyond the last strip's): record it
        bcc record
c_rb:   cpy #0
        bcs record
c_rd:
        ldx ri                     ; the rungs: past those wholly left
        tya
        cmp HI,x
        bcs c_ri
c_rr:   ora #3
        cmp LO,x
        bcs c_split                 ; (LO <= x4 + 3)
        lda CE-1,x                 ; one box: ri - 1
        sta ve
        lda CO-1,x
        sta vo
        bvs c_z1                   ; (a top not level)
c_r1:    ldx mx
        cpx flr1
        bcs c_next
        ldy flr1
        jsr run
c_next:
c_np:   jmp nearpost               ; (cols: BIT but in the near strip; back to c_nd)
c_nd:
        lda x4
        clc
        adc #4
        sta x4
        cmp xr
        beq :++
        tay
        asl a                      ; 8 * column
        sta coff
        beq :+
        jmp c_coly
:       lda #0                     ; (a new half)
        rol a
        jsr sethalf
        jmp c_col
:       rts
c_ri:   inx                        ; (the next rung)
        cmp HI,x
        bcs c_ri
        stx ri
        jmp c_rr
c_v1:   .byte $40                  ; (BIT: V)
c_z1:    jsr zone1
        jmp c_r1
c_split: cmp LO+1,x
        bcs c_dbl
        bvs :+
        jsr fsplit
        jmp c_next
:       jsr split
        jmp c_next
; A land strip's column: its highest and lowest lines into CURT, CURB (cols'
; inline: back to c_rd, Y = x4).
record: tya
        lsr a
        lsr a
        tax
        lda CURT,x
        cmp #$FF
        bne @d
        lda mn                     ; the column's first strip this frame: its
        sta CURT,x                 ; highest line, and black from the land's
        txa                        ; highest last time down to its top's lowest
        tay                        ; (the pixels above their top in its top zone
        lda (tsp),y                ; kept)
        cmp mx
        bcs @d
        tax
        ldy mx
        lda #0
        sta ve
        sta vo
        jsr run
@d:     ldy x4
        jmp c_rd

c_dbl:   bvs :+                     ; (the slow ways read ys)
        lda mn
        sta ys
        sta ys+1
        sta ys+2
        sta ys+3
:       lda x4
        ora #3
        cmp LO+2,x
        bcs :+
        jsr split2
        jmp c_next
:       jsr slow                   ; (three: never seen)
        jmp c_next

; The near strip's column, drawn (to the line before its floor if its bottom
; row is level there, else to the floor): below the near row black (the line
; at the floor, or the pixels at or below their bottom-row line, read-modify-
; write); then black to the land's lowest line last time (BOTS); CURB.  (cols'
; inline: back to c_nd.)
np_h    = nearpost+8               ; (nearpost's LAHS)
nearpost:
        lda flr                    ; (its bottom level: flr1 = flr)
        cmp flr1
        bne @z
        ldx flr
        lda LAHSB0,x               ; (np_h: sethalf's, the screen and half's)
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
        beq @b
@z:     ldy x4
        lda (bota),y
        sta ys
        sta mn
        ldx #1
:       iny
        lda (bota),y
        sta ys,x
        cmp mn
        bcs :+
        sta mn
:       inx
        cpx #4
        bne :--
        ldx mn
@l:     jsr pmask
        lda #0
        jsr zline
        inx
        cpx flr1
        bcc @l
@b:     lda x4                     ; the land's lowest line now, and last time's
        lsr a
        lsr a
        tay
        lda flr
        sta CURB,y
        lda (bsp),y
        cmp flr
        beq @n
        bcc @n
        tay
        iny
        ldx flr
        inx
        lda #0
        sta ve
        sta vo
        jsr run
@n:     jmp c_nd

; Columns the land has left since last time: black from its highest line to
; its lowest.
gone:   ldx #0
@c:     lda CURT,x
        cmp #$FF
        bne @n
        txa
        tay
        lda (tsp),y
        cmp #$FF
        beq @n
        stx tj
        txa
        asl a
        asl a
        asl a
        sta coff
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        jsr sethalf
        lda (bsp),y
        pha
        lda (tsp),y
        tax
        pla
        tay
        iny
        lda #0
        sta ve
        sta vo
        jsr run
        ldx tj
@n:     inx
        cpx #64
        bne @c
        rts

; The column's half of the screen: A (0 left, 1 right).
sethalf:
        pha
        clc
        adc scrb
        sta scrh
        pla
        asl a
        adc stb0
        sta stbh
        sec                        ; t: the STAB (its ENTBt, EXHBt, LAHSBt)
        sbc #>STAB
        lsr a
        tay
        lda enthl,y
        sta r_eh1+1
        lda enthh,y
        sta r_eh1+2
        lda exhl,y
        sta r_eh2+1
        lda exhh,y
        sta r_eh2+2
        lda lahsl,y
        sta ln_h+1
        sta s2_h+1
        sta np_h+1
        lda lahsh,y
        sta ln_h+2
        sta s2_h+2
        sta np_h+2
        rts
exhl:   .byte <(EXHB0), <(EXHB1), <(EXHB2), <(EXHB3)
exhh:   .byte >(EXHB0), >(EXHB1), >(EXHB2), >(EXHB3)
lahsl:  .byte <(LAHSB0), <(LAHSB1), <(LAHSB2), <(LAHSB3)
lahsh:  .byte >(LAHSB0), >(LAHSB1), >(LAHSB2), >(LAHSB3)
enthl:  .byte <(ENTB0), <(ENTB1), <(ENTB2), <(ENTB3)
enthh:  .byte >(ENTB0), >(ENTB1), >(ENTB2), >(ENTB3)

; A column a rung (X = ri) splits, its top level: from mx down to the floor,
; the boxes split at bpos (the rung's pixels left of it), bpos moving a pixel
; at each of the rung's transitions in the column.  Each bpos's bytes first
; (BE, BO); then between transitions a single line inline, more by seg2.
fsplit: lda RTPL,x
        sta rtp
        lda RTPH,x
        sta rtp+1
        lda CE,x
        sta re
        eor CE-1,x
        sta xe
        lda CO,x
        sta ro
        eor CO-1,x
        sta xo
        lda BX,x                   ; p1: the rung's bottom in the column
        sec
        sbc x4
        bcs :+
        lda #0
:       cmp #4
        bcc :+
        lda #4
:       sta p1
        lda TX,x                   ; bpos: its top
        sec
        sbc x4
        bcs :+
        lda #0
:       cmp #4
        bcc :+
        lda #4
:       sta bpos
        lda mx
        sta yy
        ldx bpos
        cpx p1
        bne :+
        jmp fs_e
:       bcc fs_r
        jmp fs_l
fs_r:   txa                        ; leaning right: pixel x4 + bpos changes at
        clc                        ; its line, bpos + 1 after
        adc x4
        tay
        lda (rtp),y
        cmp flr1
        bcs fs_e
        sta tj
        sec
        sbc yy
        beq fs_rn
        bcc fs_rn
        cmp #1
        bne :+
        jsr line1
        jmp fs_rn
:       jsr seg2
fs_rn:  inx
        cpx p1
        bcc fs_r
fs_e:   lda flr1                   ; the rest at bpos
        sta tj
        sec
        sbc yy
        beq :+
        bcc :+
        jmp seg2
:       rts
fs_l:   txa                        ; leaning left: pixel x4 + bpos - 1 changes,
        clc                        ; bpos - 1 after
        adc x4
        tay
        dey
        lda (rtp),y
        cmp flr1
        bcs fs_e
        sta tj
        sec
        sbc yy
        beq fs_ln
        bcc fs_ln
        cmp #1
        bne :+
        jsr line1
        jmp fs_ln
:       jsr seg2
fs_ln:  dex
        cpx p1
        bne fs_l
        beq fs_e

; Line yy at bpos X; yy + 1 after.  X kept.
line1:  ldy yy
ln_h:   lda LAHSB0,y                ; (sethalf: the screen and half's)
        sta zp_+1
        tya
        and #7
        sta zp_
        lsr a
        lda LM,x                   ; (the line's parity's byte at bpos X)
        bcs :+
        and xe
        eor re
        ldy coff
        sta (zp_),y
        inc yy
        rts
:       and xo
        eor ro
        ldy coff
        sta (zp_),y
        inc yy
        rts

; Lines yy .. tj-1 (A of them, 2 or more) at bpos X: a run if 3 or more,
; else a line at a time; yy = tj after.  X kept.
seg2:   stx sx_
        tay
        lda LM,x
        and xe
        eor re
        sta ve
        lda LM,x
        and xo
        eor ro
        sta vo
        tya
        cmp #3
        bcs s2_run
        ldx yy
        ldy coff
s2_l:
s2_h:   lda LAHSB0,x
        sta zp_+1
        txa
        and #7
        sta zp_
        lsr a
        lda ve
        bcc :+
        lda vo
:       sta (zp_),y
        inx
        cpx tj
        bne s2_l
        stx yy
        ldx sx_
        rts
s2_run: ldx yy
        ldy tj
        jsr run
        lda tj
        sta yy
        ldx sx_
        rts

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

; Lines X .. Y-1 (X < Y) of the column: ve on even lines, vo odd, through STAB
; (STA line,Y / LDA vo or TXA), from line X's entry to an RTS planted at line
; Y's (pp: put back by the next run).
run:    lda EXLB,x
        sta r_j+1
r_eh2:  lda EXHB0,x                 ; (sethalf: the STAB's own)
        sta r_j+2
        ldx #0
        lda #OP_STAY               ; the last back
        sta (pp,x)
        lda ENTL,y
        sta pp
r_eh1:  lda ENTB0,y
        sta pp+1
        lda #OP_RTS
        sta (pp,x)
        ldx ve                     ; (X: ve, for the odd lines' TXA)
        txa
        ldy coff
r_j:    jmp $FFFF                  ; (its RTS returns from run)
dummy:  .byte 0

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

BE:     .res 5                     ; fsplit's bytes by bpos
BO:     .res 5
fps10:  .res 2                     ; (the readout's)
dvs:    .res 8
dvi:    .res 1
vlast:  .res 1
tcol:   .res 1

        .assert * <= $3000, error, "code over the screen"
