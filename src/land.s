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
; sideways RAM bank 4, paged in throughout, TABLES2 into bank 5 (project's
; colours, a moment) and SHIPB (shipb.s: the keys and the ship) into bank 6
; (call6, between the frame's parts); then it closes !BOOT and takes the
; filing system's workspace:
;   $0400, $0500  ROWA, ROWB: a row's line by pixel (a strip's top and bottom)
;   $0600         RTBUF: the rungs' transition lines
;   $0700         the frame's rows' points; $0900 its strips' boxes and
;                 columns, $0A40 the strip's, $0B00 the
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
BANK3   = 6                        ; and the ship's (shipb.s: the keys too)
B6_KEYS = $8000
B6_SHIP = $8003
G_INIT  = $A100                    ; bank 5: the game (game.s)
G_STEP  = $A103
G_POST  = $A106
BANK7   = 7                        ; and the projection (project's)
BANK2   = 5                        ; and the tiles' colours (project's, a moment)

                                   ; (YSKY, YGND: proto/frame.py's, tables.inc)
MARGIN  = 0                        ; (to the byte boundary: the land extents clear the rest)

ROWA    = $0400
ROWB    = $0500
RTBUF   = $0600
PX      = $0700                    ; the rows', far to near: 16 a row (NZ)
PY      = $0800
CLE     = $0900                    ; the land strips' box bytes: 16 a strip (NZ - 1)
CLO     = $09A0
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
ENTL    = $0D00-YSKY               ; each line's entry in STAB (low, high: lines
ENTH    = $0D61-YSKY               ; YSKY..YGND+1, 97 each)
TOPS    = $0C00                    ; by screen, column: the land's highest line last time
BOTS    = $0C80                    ; and lowest
CURT    = $0B60                    ; this frame's
CURB    = $0BA0
STAB    = $0E00
LAH     = $16C2-YSKY               ; each line's 2 * (y >> 3) (lines YSKY..YGND+1)
LAH0    = $1600-YSKY               ; and its address's high byte, screen 0 (left half)
LAH1    = $1661-YSKY               ; screen 1
        .assert YGND+2-YSKY <= 97, error, "LAH, ENTL: 97 lines each"
CX      = $0B30                    ; project's: the columns' map x
PXX     = $0B40                    ; and a clipped row's x's high bytes
ZCF     = $07D0                    ; the far clip on (1: always, init's)
BCL     = $07D5                    ; bclip: this strip's bottom row held at YGND+1
ZB      = $07D1                    ; project's: ZBACK less the first row's j, the
RN      = $07D2                    ; near clip's row (j ZBACK - ZCLIP, less it), the
DIB     = $07D3                    ; first row's di (less 16 j, czs), and the far
FACT    = $07D4                    ; clip's row (1: row 0, from the rows either side)
CAME    = $07D6                    ; the camera above CAMH (0..EMAX: the game's), and
HGV     = $07D7                    ; the ground under the ship (hgnd's, for the game)
EYV     = $07D8                    ; prow7's: a row's y's for CAME, and its multiply's
MT0     = $07D9
MT1     = $07DA

SWT     = $9400                    ; init's line tables, in bank 4's free space: two a
                                   ; page, by line (YSKY..YGND+1, 97 lines): one at
                                   ; its page's start (its base before the page: a
                                   ; read crosses it, a cycle more), one 97 on (none)
EXLB    = SWT+97-YSKY              ; run's entries (low), and high by STAB
LAHSB0  = SWT+$100+97-YSKY         ; each line's address, high byte: by screen and half
LAHSB1  = SWT+$200+97-YSKY
LAHSB2  = SWT+$300+97-YSKY
LAHSB3  = SWT+$400+97-YSKY
EXHB0   = SWT+$400-YSKY
EXHB1   = SWT+$500-YSKY
EXHB2   = SWT+$500+97-YSKY
EXHB3   = SWT+$600+97-YSKY
ENTB0   = SWT-YSKY                 ; each STAB's ENTH
ENTB1   = SWT+$100-YSKY
ENTB2   = SWT+$200-YSKY
ENTB3   = SWT+$300-YSKY
        .assert YGND+2-YSKY <= 97 && 97+YGND+1-YSKY < $100, error, "SWT: a line table crosses its page"
OP_STAY = $99
OP_LDAZ = $A5
OP_TXA  = $8A
OP_RTS  = $60
OP_JMP  = $4C
OP_INY  = $C8
OP_DEY  = $88
OP_INX  = $E8
OP_DEX  = $CA

        .zeropage
cxt:    .res 1                     ; the camera: tile and step (0-15), x and z
cxs:    .res 1
czt:    .res 1
czs:    .res 1
back:   .res 1                     ; the screen being drawn: 0 ($3000), 1 ($5800)
scrb:   .res 1                     ; its high byte
stb0:   .res 1                     ; its STAB's (left half)
np:     .res 1                     ; points a row (8 or 9)
nr:     .res 1                     ; rows (4 to 6)
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
tyv:    .res 1                     ; (traceb: the run's y)
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
lastri: .res 1                     ; fsplit: the rung BE, BO, rbl, rbh are for
BE      = $8E                      ; fsplit's rung's bytes by bpos (the ship's
HPZ     = $8E                      ; project's map row pointers (8: the ship's scratch)
BO      = BE+5                     ; zero page: strips' scratch, $8E-$97)
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
bpos:   .res 1
p0:     .res 1
p1:     .res 1
yy:     .res 1
kk:     .res 1
fwe     = kk                       ; (fsplit's: kk is split2's): the walk's end, in the row
rsm     = yy                       ; fsplit: the walker's row's first line - 1
fwu     = tj                       ; fsplit: a transition beyond the row
FSRJ    = 8                        ; fsplit: t walked to if within 8 + FSRJ of the row
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
; (LANDS, at $7000, has loaded the banks and set the screen up: it ends here.)
        .assert * = $1900, error, "go must be first"
go:     jsr init
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

        lda #<G_INIT               ; (bank 5: the game's screen top, the ship)
        jsr call5
loop:   lda #<G_STEP               ; the game: keys, flight, the camera
        jsr call5
        lda #<B6_KEYS              ; (bank 6: the ship's attitude and place)
        jsr call6
        jsr project
        jsr strips                 ; (waiting for the flip before drawing)
        lda GSHV                   ; the ship (not while crashed)
        beq :+
        lda #<B6_SHIP
        jsr call6
:       lda #<G_POST               ; the dots, the map, the status
        jsr call5
        jsr readout
        jsr flip
        jmp loop

vsync:  php
        inc vcount
        plp
        rts

; Bank 6's routine at $8000 + A (B6_KEYS or B6_SHIP), bank 4 paged back after.
call6:  sta @j+1
        lda #BANK3
        sta ROMCOPY
        sta ROMSEL
@j:     jsr $8000
        lda #BANK
        sta ROMCOPY
        sta ROMSEL
        rts

; Bank 5's routine at $A100 + A (G_INIT, G_STEP, G_POST: game.s), bank 4 after.
call5:  sta @j+1
        lda #BANK2
        sta ROMCOPY
        sta ROMSEL
@j:     jsr G_INIT
        lda #BANK
        sta ROMCOPY
        sta ROMSEL
        rts

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
init:   lda #1                     ; (the far clip on: always)
        sta ZCF
        lda #0
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
        lda #<t_back               ; traceb's fills' way back
        sta TBLK4+3*TNB+1
        sta TBLK5+3*TNB+1
        lda #>t_back
        sta TBLK4+3*TNB+2
        sta TBLK5+3*TNB+2
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

; ---------------------------------------------------------------- project
; Lander's block of NX x NZ corners (proto/land.py: project): the columns' map x
; (CX: cxt - 5 + i, i from XSKIP: NX, tables.inc's, the corners drawn), each drawn row's map row (czt + ZBACK - j, far to near, j
; from ZSKIP: the far ZSKIP rows not drawn); with
; bank 4 paged, every corner's height (into PY); bank 5, each land strip's boxes'
; bytes (CLE, CLO: the tile at its left column and near row); bank 7, by the
; row's depth index (di = 16 (ZBACK - j) - czs - DI0), its y's (SYT7, from the
; heights) and x's (B0 + i r, its x * 256 for corner i: B0L/H/X, R7L/H), the
; rows overhanging the screen (CLP) clipped (land.clip).
        .assert <PY = 0, error, "PY page-aligned"
cd      = zq                       ; (cyc's)
cn      = ha
cdy     = hb
cpl     = lqx
cph     = lqx+1
.macro PH i                         ; (bank 4) corner i's height: PY
        ldy CX+i
        lda (hp0),y
        and #15
        sta PY+i,x
.endmacro
.macro CBOX i                       ; (bank 5) box i's colour: CMAPE, CMAPO
        ldy CX+i
        lda (hp0),y
        sta CLE-16+i,x
        lda (hp1),y
        sta CLO-16+i,x
.endmacro
.macro PYS i                        ; (bank 7) corner i's y: SYT7 by its height
        ldy PY+i,x
        lda (syp),y
        sta PY+i,x
.endmacro
.macro PYSE i                       ; (bank 7) the same, the camera CAME higher
        ldy PY+i,x
        lda (syp),y
        adc EYV                     ; (C clear: y's within a byte)
        sta PY+i,x
.endmacro
.macro PXS i                        ; (bank 7) corner i's x (B's high byte, in A),
        sta PX+i,x                  ; then B += r (16 bits: the edges' beyond them
        tay                         ; replaced after)
        lda vx
        clc
        adc rl
        sta vx
        tya
        adc rh
.endmacro

project:
        lda #NX                    ; (always: the strips' np)
        sta np
        lda #ZBACK-ZSKIP           ; the first row (ZB: ZBACK less its j): ZSKIP's,
        ldx #0                     ; or the far clip's: on its plane (fz 0), or
        ldy ZCF                    ; from the rows either side (FACT)
        beq :+
        lda #ZFCLIP
        ldy czs
        beq :+
        lda #ZFCLIP+1
        inx
:       sta ZB
        stx FACT
        sec                        ; the near clip's row: ZB - ZCLIP (the last)
        sbc #ZCLIP
        sta RN
        tay
        iny
        sty nr
        lda ZB                     ; the first row's di: 16 ZB - DI0
        sec
        sbc #9
        asl a
        asl a
        asl a
        asl a
        sbc #DI0-9*16-1            ; (C clear: - (DI0 - 144))
        sta DIB
        .assert DI0 > 9*16 && ZFCLIP >= 9 && ZBACK-ZSKIP >= 9, error, "DIB's arithmetic"
        lda cxt                    ; the drawn columns' map x
        sec
        sbc #5-XSKIP
        ldx #0
:       and #63
        sta CX,x
        clc
        adc #1
        inx
        cpx #NX
        bne :-
        lda #$9D                   ; (bank 4) each row's heights: row j's map
        ldy nr                     ; row's pointer at HPZ + 2 j (the ship's zero
        cpy #8                     ; page: scratch), then by column, all 8 rows
        beq :+                     ; (row 7 not stored if nr = 7: LDA, not STA)
        lda #$BD
:       sta @h7
        .assert ZBACK-ZSKIP-ZCLIP+1 = 8 && ZFCLIP-ZCLIP+1 = 7, error, "nr 7 or 8"
        lda czt                    ; (row 7's map row first: czt + ZB - 7)
        clc
        adc ZB
        sbc #6
        ldx #14
@hp:    and #63
        tay
        lda MRL,y
        sta HPZ,x
        lda MRH,y
        sta HPZ+1,x
        iny
        tya
        dex
        dex
        bpl @hp
        ldx #NX-1
@hc:    ldy CX,x
        lda (HPZ+14),y
        and #15
@h7:    sta PY+$70,x
        .repeat 7, i
        lda (HPZ+12-2*i),y
        and #15
        sta PY+$60-16*i,x
        .endrepeat
        dex
        bpl @hc
        lda #BANK7                 ; (bank 7) each row's y's and x's (prow7)
        sta ROMCOPY
        sta ROMSEL
        jsr prow7
        lda #BANK2                 ; (bank 5) each land strip's boxes (pcol5)
        sta ROMCOPY
        sta ROMSEL
        jsr pcol5
        lda #BANK
        sta ROMCOPY
        sta ROMSEL
        rts

; ---------------------------------------------------------------- strips
; The sky (ns = 0), the land's (ns = 1 .. nr-1: rows ns-1 and ns), the ground
; (ns = nr).  A strip's points: 0 its left margin, 1..np the rows', np+1 its
; right margin.
strips: ldx back                   ; this screen's TOPS, BOTS (a set of three)
        ldy sidx,x
        lda setTl,y
        sta tsp
        sta pT5+1
        sta pT6+1
        sta pT6b+1
        lda setTh,y
        sta tsp+1
        sta pT5+2
        sta pT6+2
        sta pT6b+2
        lda setBl,y
        sta bsp
        sta pB5+1
        sta pB6+1
        sta pB8+1
        lda setBh,y
        sta bsp+1
        sta pB5+2
        sta pB6+2
        sta pB8+2
        ldy cidx                   ; and this frame's: CURT, CURB's operands
        lda setTl,y                ; (each column's set by the strip it is first
        sta pT3+1                  ; in, CURB by the near strip; the rest by gone:
        sta pT4+1                  ; each strip's columns are within the next's)
        sta pT4b+1
        lda setTh,y
        sta pT3+2
        sta pT4+2
        sta pT4b+2
        lda setBl,y
        sta pB4+1
        sta pB7+1
        sta pB7b+1
        lda setBh,y
        sta pB4+2
        sta pB7+2
        sta pB7b+2
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
        jsr bclip                  ; (the bottom row past the screen's bottom)
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
        ldx back                   ; this frame's set the screen's next, its
        ldy cidx                   ; last the next frame's
        lda sidx,x
        sta cidx
        tya
        sta sidx,x
        rts
sidx:   .byte 0, 1                 ; each screen's set (TOPS, BOTS: init's)
cidx:   .byte 2                    ; this frame's
setTl:  .byte <TOPS, <(TOPS+64), <CURT
setTh:  .byte >TOPS, >(TOPS+64), >CURT
setBl:  .byte <BOTS, <(BOTS+64), <CURB
setBh:  .byte >BOTS, >(BOTS+64), >CURB

; The bottom row clipped at the screen's bottom: if a point of it is past
; YGND, its line (bota) held at YGND+1 (so every column's floor, top and line
; stay on the screen: flr1 at most YGND+1, cols' c_lv's flrc), BCL set.
bclip:  lda #0
        sta BCL
        ldx np1
:       lda BY,x
        cmp #YGND+1
        bcs :+
        dex
        bpl :-
        rts
:       inc BCL
        ldy #0
        lda #YGND+1
:       cmp (bota),y
        bcs :+
        sta (bota),y
:       iny
        bne :--
        rts
; (c_lv's, for a strip whose bottom row bclip held: the floor's line after, at
; most YGND+1.)
flrc:   tax
        inx
        cpx #YGND+2
        bcc :+
        dex
:       stx flr1
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
        adc np                     ; (C clear after: 16 ns + np < 256)
        adc #$EF                   ; 16 (ns - 1) + np - 1: box np, down to 1
        tay
        ldx np
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
        dey
        dex
        bne @p
        beq @m
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
        .if MARGIN
        sec
        sbc #MARGIN
        .endif
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
        sta TX+1,x
        sta BX+1,x
        lda TY,x
        sta TY+1,x
        lda BY,x
        sta BY+1,x
        lda TY+1
        sta TY
        lda BY+1
        sta BY
        ; the boxes: 0 and np black, 1..np-1 the strip's (all black: sky, ground)
        lda #0
        sta CE
        sta CO
        sta CE,x
        sta CO,x
@bot:   lda ns                     ; the bottom row's line
        cmp nr
        beq :+
        jmp traceb
        .res 4                     ; (the layout kept)
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


; The bottom row (BX, BY 0..np+1) into (bota): each segment as points.py's
; bresenham_ys, one y a pixel.  A shallow segment (|dy| < dx): the error kept
; in Y biased by 256 - 2dx, so the carry is the step; y in tyv.
traceb: lda bota+1
        sta tr_st+2
        sta tg_st+2
        sta fl_0+2
        sta fl_1+2
        sta fl_2+2
        sta fl_3+2
        clc                        ; the fills' entries: TENH4 or TENH5
        adc #>TENH4-4
        sta tf_h+2
        sta t1_h+2
        sta tx_h+2
        sta tv_h0+2
        sta tv_h1+2
        ldx np1                    ; the row: xl .. xr, and widened to the next
        ldy BX,x                   ; strip's margins (its top row: the margin
        iny                        ; segments' ys run on to them)
        sty t_end+1
        lda BX
        sta tcnt
        ldy ns
        iny
        cpy nr
        bcs @t0
        tya
        asl a
        asl a
        asl a
        asl a
        tay
        lda PX,y                   ; (setup's xl, xr for row ns + 1)
        and #$FC
        cmp tcnt
        bcs :+
        sta tcnt
:       tya
        clc
        adc np
        tay
        lda PX-1,y
        adc #3
        and #$FC
        cmp t_end+1
        bcc @t0
        adc #0                     ; (C set: + 1)
        sta t_end+1
@t0:    lda BY
        sta tyv
        ldx #0
        beq t_seg
t_end:  ldx #0                     ; the row's end: the run pending, to the end
        jmp t_fl                   ; (back by t_fr's RTS)
t_o:    jsr t_fl0                  ; (in reach) the run pending, to x0
        jmp t_old
t_dx0:  lda BY+1,x                 ; (none: a margin on the row's end) the run
        cmp tyv                    ; pending ends at x0 if the next y differs
        beq t_next
        jsr t_fl0
        ldx tj
        lda BX,x
        sta tcnt
t_next: ldx tj
        inx
        cpx np1
        bcs t_end
t_seg:  stx tj
        lda BX+1,x                 ; (tx1: t_fl0's, for t_old and t_steep)
        sec
        sbc BX,x
        beq t_dx0
        sta terr                   ; dx
        lda BY,x
        sta tyv
        lda BY+1,x
        sec
        sbc tyv
        beq t_next                 ; (level: the run pending goes on)
        ldy #$E6                   ; INC zp
        bcs :+
        eor #$FF                   ; rising: |dy|, DEC
        adc #1
        ldy #$C6
:       cmp terr
        bcc :+
        jmp t_steep                ; (Y: INC or DEC)
:       sty t_inc                  ; ($E6 or $C6: +1 or -1 below)
        sta dva                    ; a run a y: the steps at x0 + ceil(dx (2k-1) / 2|dy|)
        tay                        ; (k = 1 .. |dy|; ragged.transitions' sum)
        asl a
        sta ra2                    ; (t_old: none of ra2)
        ora terr                   ; |dy| < 32 and dx < 64 (|dy| < dx: 2|dy| < 256
        cmp #64                    ; or dx >= 128)
        bcs t_o
        cpy #1
        beq t_one
        lda DVH,y                  ; divt's, inline: q, rem = dx div 2|dy|, mod;
        sta t_dq+2                 ; q2, r2 = 2dx's
        lda DVR,y
        sta t_dr+2
        lda DVL,y
        ora terr
        tay
t_dq:   lda DQT,y                  ; q2 = dx div |dy|: q = q2 / 2
        sta rq2
        lsr a
        sta rq
t_dr:   lda DRT,y                  ; r2 = 2 (dx mod |dy|) (DRT holds 2r)
        sta rr2                    ; rem = r + |dy| (q2 odd)
        bcc :+
        adc ra2                    ; (C set: 2r + 2|dy| + 1)
:       lsr a                      ; (C clear if rem = 0)
        beq :+                     ; e: how far short of the next step (2|dy| - rem,
        eor #$FF                   ; or 0; C: rem > 0)
        sec
        adc ra2
:       sta rrem
        lda rq                     ; the first run: the pending one, to x0 + q +
        adc #0                     ; (rem > 0)
        adc BX,x                   ; (C clear)
        tax
        ldy rq2                    ; the runs between: q2 or q2 + 1 (|dy| >= 2:
                                   ; t_one's 1)
        lda TENL,y
        sta jv0+1
tv_h0:  lda TENH4,y
        sta jv0+2
        lda TENL+1,y
        sta jv1+1
tv_h1:  lda TENH4+1,y
        sta jv1+2
        txa
        sec
        sbc tcnt
        tay
        cpy #TNB+1
        bcs t_fl1
        lda TENL,y
        sta tf_j+1
tf_h:   lda TENH4,y
        sta tf_j+2
        ldy dva                    ; (Y: the runs left after this one)
        lda tyv
tf_j:   jmp t_back
        .res 5
t_one:  lda terr
        lsr a                      ; |dy| 1: the first run to x0 + ceil(dx / 2)
        adc BX,x
        tax
        sec
        sbc tcnt
        tay
        cpy #TNB+1
        bcs t_fl1
        lda TENL,y
        sta tf_j+1
t1_h:   lda TENH4,y
        sta tf_j+2
        ldy #1
        lda tyv
        jmp tf_j
t_fl1:  ldy dva                    ; (longer)
        jmp t_flo
        .res 2                     ; (the layout kept)
t_fl0:  lda tyv                    ; the run pending to x0 (not including), and
        pha                        ; back (tyv kept, X = tj)
        ldx tj
        lda BX,x
        tax
        jsr t_fl
        pla
        sta tyv
        ldx tj
        lda BX+1,x                 ; (x1: t_old's and t_steep's)
        sta tx1
        rts
t_fl:   txa                        ; the run pending to X (not including): back
        sec                        ; by t_fr
        sbc tcnt
        tay
        cpy #TNB+1
        bcs t_flf
        lda TENL,y
        sta tx_j+1
tx_h:   lda TENH4,y
        sta tx_j+2
        ldy #0
        lda tyv
tx_j:   jmp t_back
t_flf:  ldy #0                     ; (longer)
t_flo:  stx fe                     ; (longer: 4 at a time, from tcnt to fe)
        ldx tcnt
t_run:  lda tyv                    ; (bota) from X to (not including) fe (> X):
fl_0:   sta ROWB,x                 ; A, 4 at a time (up to 3 more: the next run's,
fl_1:   sta ROWB+1,x               ; or the next segment's, put right after)
fl_2:   sta ROWB+2,x
fl_3:   sta ROWB+3,x
        inx
        inx
        inx
        inx
        cpx #4                     ; (wrapped: done)
        bcc :+
        cpx fe
        bcc fl_0
:       ldx fe
t_back:                            ; (the fills' way back: X the run's end)
t_inc:  inc tyv                    ; (INC or DEC: as tr_inc, patched)
        dey
        bmi t_fr
        beq t_last
        lda rrem                   ; the next step: + 2dx / 2|dy|, by e
        sec
        sbc rr2
        bcs :+
        adc ra2                    ; (C set after: + 1)
        sta rrem
        txa
        adc rq2
        tax
        lda tyv
jv1:    jmp t_back
:       sta rrem
        txa
        clc
        adc rq2
        tax
        lda tyv
jv0:    jmp t_back
t_fr:   rts
t_last: stx tcnt                   ; the last run: pending (at y1)
        jmp t_next
t_old:  lda t_inc                  ; (dx >= 64 or |dy| >= 32) a pixel at a time
        sta tr_inc
        lda terr
        asl a
        sta tdx2
        ldy BX,x                   ; (x0's)
        lda tyv
        sta (bota),y
        lda dva
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
t_ox:   ldx tj                     ; the run pending: x1 on, at y1
        lda BY+1,x
        sta tyv
        lda tx1
        sta tcnt
        jmp t_next
t_steep: sty tr_inc                 ; (rare) the general loop
        asl a
        sta tdy2
        jsr t_fl0                  ; (the run pending, to x0)
        lda terr
        asl a
        sta tdx2
        ldy BX,x                   ; (x0's)
        lda tyv
        sta (bota),y
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
        pha                        ; (tg_inc's A)
        jsr tg_inc
        pla
        jmp :-
:       sta terr
        lda tyy
tg_st:  sta ROWB,x
        cpx tx1
        bne t_gl
        beq t_ox
tg_inc: lda tr_inc                 ; tyy +- 1, as tr_inc
        cmp #$E6
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
        .res 3                     ; (keeps the layout: DRT's 2r saved 3 bytes)
divt:   ldy dva                    ; (D div a, D mod a: q2, and q, rem, r2 from them)
        lda DVH,y
        sta @q+2
        lda DVR,y
        sta @r+2
        lda DVL,y
        ora dvd
        tay
@q:     lda DQT,y                  ; q2 = D div a: q = q2 / 2
        sta rq2
        lsr a
        sta rq
@r:     lda DRT,y                  ; r2 = 2 (D mod a) (DRT holds 2r)
        sta rr2                    ; rem = r + a (q2 odd)
        bcc :+
        adc ra2                    ; (C set: 2r + 2a + 1)
:       lsr a
        sta rrem
        rts
        .res 3                     ; (keeps the layout)
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
tr_y:   lda tyv
tr_st:  sta ROWB,x
        cpx tx1
        bne tr_l
        rts
tr_s:   tya                        ; a step: unbias, y +- 1
tr_k:   adc #0
        tay
tr_inc: inc tyv
        jmp tr_y

; ---------------------------------------------------------------- rungs
; Each rung's pixels (LO..HI-1) and transitions: rung (xt, yt) - (xb, yb), D =
; yb - yt, a = |xb - xt|: its j'th pixel from xt (xt + j - 1 leaning right, xt
; - j left) changes box at line yt + ceil(D (2j - 1) / 2a) (ragged.transitions).
; Kept at RTBUF on, (RTP),x for pixel x.  The margins: none.  Each rung's a + 1
; bytes from alloc (+ 1 each rung): pixel x at (alloc),x-LO, then $FF (the
; sentinel after it leaning right, and the next's before it leaning left).
; q, rem = D div 2a, mod; q2, r2 = 2D's (divt's, inline: a < 32, D < 64; else
; divs); e: how far short of the next step (2a - rem, or 0); C: rem > 0.
.macro RDIV slow
        lda BY,x                   ; D
        sec
        sbc TY,x
        sta dvd
        ldy dva
        cpy #32
        bcs slow
        cmp #64
        bcs slow
        lda DVH,y
        sta :+ + 2
        lda DVR,y
        sta :++ + 2
        lda DVL,y
        ora dvd
        tay
:       lda DQT,y                  ; q2 = D div a: q = q2 / 2
        sta rq2
        lsr a
        sta rq
:       lda DRT,y                  ; r2 = 2 (D mod a) (DRT holds 2r)
        sta rr2                    ; rem = r + a (q2 odd)
        bcc :+
        adc ra2                    ; (C set: 2r + 2a + 1)
:       lsr a                      ; (C clear if rem = 0)
        beq :+
        eor #$FF
        sec
        adc ra2
:
.endmacro
; Then the steps: E = 255 - e, kept by ADC (C clear: C set after if a step's
; e < 0); 255 - 2a in dvd, q2 + 1 in rq.
.macro RSET
        eor #$FF
        sta rrem
        lda ra2
        eor #$FF
        sta dvd
        lda TY,x                   ; the first pixel's line: yt + q + (rem > 0)
        adc rq
        ldy rq2
        iny
        sty rq
.endmacro
rungs:  lda xl
        sta LO
        sta HI
        ldx np1
        lda xr
        sta LO,x
        sta HI,x
        lda #$FF                   ; (the first's sentinel leaning left)
        sta RTBUF
        lda #<(RTBUF+1)
        sta alloc
        lda #>RTBUF
        sta alloc+1
        ldx #1
rg_r:     stx tj
        lda BX,x
        cmp TX,x
        bne :+
        sta LO,x                   ; upright: none (its sentinel only)
        sta HI,x
        eor #$FF                   ; RTP = alloc - LO
        sec
        adc alloc
        sta RTPL,x
        lda alloc+1
        adc #$FF
        sta RTPH,x
        ldy #0
        sty dva
        jmp rg_nr
rg_rsl:   jsr divs                   ; (a >= 32 or D >= 64)
        lda rrem
        beq rg_rz
        lda ra2
        sec
        sbc rrem
rg_rz:    cmp #1
        jmp rg_rst
:       bcs :+
        jmp rg_lft
:       sta HI,x                   ; leaning right: xt .. xb-1
        sbc TX,x                   ; (C set)
        sta dva                    ; (a)
        lda TX,x
        sta LO,x
        eor #$FF                   ; RTP = alloc - LO
        sec
        adc alloc
        sta RTPL,x
        lda alloc+1
        adc #$FF
        sta RTPH,x
        jmp rfastr                 ; (bank 4: a <= RFA, D < 16; else back,
rg_rdr:   RDIV rg_rsl                  ; ra2 = 2a)
rg_rst:   RSET                       ; (C clear after)
        ldy #0                     ; the pixels, from xt (Y = x - LO) to Y = a
        sta (alloc),y
        iny
        cpy dva
        beq rg_nr
rg_rs:    tax                        ; the next pixel's: + q2 (+ 1: a step)
        lda rrem
        adc rr2
        bcs :+
        sta rrem
        txa
        adc rq2
        sta (alloc),y
        iny
        cpy dva
        bne rg_rs                    ; (C clear: Y < a)
        beq rg_nr
        .res 3                     ; (keeps the layout)
:       adc dvd                    ; (C set: + 2a; C clear after)
        sta rrem
        txa
        adc rq
        sta (alloc),y
        iny
        cpy dva
        bne rg_rs
rg_nr:    lda #$FF                   ; the sentinel (Y = a)
        sta (alloc),y
        tya                        ; alloc += a + 1
        sec
        adc alloc
        sta alloc
        bcc rg_nx
        inc alloc+1
rg_nx:    ldx tj
        inx
        cpx np1
        bcs :+
        jmp rg_r
:       rts
rg_lslj:  jmp rg_lsl                   ; (in reach)
        .res 3                     ; (keeps the layout)
rg_lft:   sta LO,x                   ; leaning left: xb .. xt-1
        eor #$FF                   ; RTP = alloc - LO
        sec
        adc alloc
        sta RTPL,x
        lda alloc+1
        adc #$FF
        sta RTPH,x
        lda TX,x
        sta HI,x
        sec
        sbc BX,x
        sta dva                    ; (a)
        jmp rfastl                 ; (bank 4: a <= RFA, D < 16; else back,
rg_rdl:   RDIV rg_lslj                 ; ra2 = 2a)
rg_lst:   RSET                       ; (C clear after)
        ldy dva                    ; the pixels, from xt-1 (Y = x - LO) to 0
        dey
        sta (alloc),y
        beq rg_ld
rg_ls:    tax
        lda rrem
        adc rr2
        bcs :+
        sta rrem
        txa
        adc rq2
        dey
        sta (alloc),y
        bne rg_ls                    ; (C clear)
        beq rg_ld
:       adc dvd
        sta rrem
        txa
        adc rq
        dey
        sta (alloc),y
        bne rg_ls
rg_ld:    ldy dva
        jmp rg_nr
rg_lsl:   jsr divs                   ; (a >= 32 or D >= 64)
        lda rrem
        beq :+
        lda ra2
        sec
        sbc rrem
:       cmp #1
        RSET
        ldy dva                    ; (as below, but D may be "negative": the
        dey                        ; lines wrap, so C cleared each pixel)
        sta (alloc),y
        beq rg_ld
rg_lw:    tax
        clc
        lda rrem
        adc rr2
        bcs :+
        sta rrem
        txa
        adc rq2
        dey
        sta (alloc),y
        bne rg_lw
        beq rg_ld
:       adc dvd
        sta rrem
        txa
        adc rq
        dey
        sta (alloc),y
        bne rg_lw
        beq rg_ld

; ---------------------------------------------------------------- columns
cols:   lda #$FF                   ; (fsplit: a new strip's boxes and rungs)
        sta lastri
        lda topa+1                 ; this strip's rows' pages
        sta pt0+2
        sta pt1+2
        sta pt2+2
        sta pt3+2
        sta zt1+2
        sta zt2+2
        sta zt3+2
        sta ot0+2
        sta ot3+2
        sta oz1+2
        sta oz2+2
        sta oz3a+2
        sta oz3b+2
        lda bota+1
        sta ob0+2
        sta ob3+2
        sta obz+2
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
        ldx #$AA                   ; TAX / INX / STX flr1: the floor's line after
        ldy #$E8                   ; (JMP c_nd: no nearpost)
        lda #$86
        bit last
        bpl :+
        ldx #$85                   ; (the near strip: STA flr / STA flr1, the floor
        ldy #flr                   ; itself if level; JMP nearpost)
        txa
        bne @lvs
:       lda BCL                    ; (bclip's: JSR flrc / NOP)
        beq @lvn
        ldx #$20
        ldy #<flrc
        lda #$EA
        sta c_lv+3
        sta o_lv+3
        lda #>flrc
        bne @lvp
@lvs:   ldx #$85                   ; (STA flr / STA flr1)
@lvn:   lda #flr1
        sta c_lv+3
        sta o_lv+3
        lda #$86
        cpx #$85
        bne @lvp
        txa
@lvp:   stx c_lv
        sty c_lv+1
        sta c_lv+2
        stx o_lv
        sty o_lv+1
        sta o_lv+2
        lda #<c_nd
        ldy #>c_nd
        bit last
        bpl :+
        lda #<nearpost
        ldy #>nearpost
:       sta c_np+1
        sty c_np+2
        lda xlp                    ; record below xlp or from xrp on (strip 1: all,
        ldx ns                     ; to xr): phase's
        dex
        bne :+
        lda xr
:       sta ph_lo+1
        lda xrp
        sta ph_hi+1
        lda #0
        sta ri
        lda xl
        sta x4
        jsr phase
        asl a                      ; 8 * column (C: the right half)
        sta coff
        lda #0
        rol a
        jsr sethalf
        ldy x4
        jmp c_coly
; (rare: out of cols' way) a column whose top or floor is not level
; The columns from A (x4) to the next of xlp, xrp, xr (c_xe's): recorded or
; not (c_rec, o_rec: JMP record, or on).  A kept.
phase:
ph_lo:  cmp #0
        bcs ph_h
        ldx ph_lo+1                ; (record to xlp)
        bcc ph_rec
ph_h:
ph_hi:  cmp #0
        bcs ph_x
        ldx ph_hi+1                ; (none to xrp)
        cpx xr
        bcc ph_n
        ldx xr
ph_n:   stx c_xe+1
        ldx #<o_nr
        stx o_rec+1
        ldx #>o_nr
        stx o_rec+2
        ldx #<c_srx
        stx c_rec+1
        ldx #>c_srx
        stx c_rec+2
        rts
ph_x:   ldx xr                     ; (record to xr)
ph_rec: cpx xr                     ; (at most xr)
        bcc ph_r
        ldx xr
ph_r:   stx c_xe+1
        ldx #<record
        stx o_rec+1
        stx c_rec+1
        ldx #>record
        stx o_rec+2
        stx c_rec+2
        rts
c_lim:  cmp xr                     ; (the next phase, or the end)
        beq c_end
        jsr phase
        jmp c_xt
c_nh:   lda #0                     ; (a new half)
        rol a
        jsr sethalf
        ldy x4
        jmp c_coly
c_end:  rts
o_zt:   sta ys                     ; (one box, its top not level; C: p0 > p3)
        bcs :+                     ; each pixel's top, the highest and lowest
        sta mn
oz3a:   lda ROWA+3,y
        sta mx
        bcc :++
:       sta mx
oz3b:   lda ROWA+3,y
        sta mn
:       sta ys+3
oz1:    lda ROWA+1,y
        sta ys+1
oz2:    lda ROWA+2,y
        sta ys+2
        bit c_v1                   ; (V: a top not level)
        jmp o_ft
o_zb:   bcs :+                     ; (one box, its floor not level; C: p0 > p3)
obz:    lda ROWB+3,y               ; the lowest
:       sta flr                    ; (as c_zb)
        tax
        inx
        cpx #YGND+2
        bcc :+
        dex
        dec flr
:       stx flr1
        jmp o_rec
c_ri0:  inx                        ; (the next rung)
        cmp HI,x
        bcs c_ri0
        stx ri
        jmp c_rr0

c_nd:                               ; the next column (c_np's, nearpost's)
        lda x4
        clc
        adc #4
        sta x4
c_xe:   cmp #0                     ; (phase: xlp, xrp or xr)
        beq c_lim
c_xt:   tay
        asl a                      ; 8 * column
        sta coff
        beq c_nh
c_coly:                            ; (V clear: the adc #4 above, or sethalf's
        ldx ri                     ; last sbc) the rungs: past those wholly left
        tya
        cmp HI,x
        bcs c_ri0
c_rr0:  ora #3
        cmp LO,x
        bcs c_sp                   ; (LO <= x4 + 3: a rung in the column)
                                   ; one box: no vertex of either row inside it
                                   ; (rungs ri-1 and before: at or left of x4;
                                   ; ri on: right of x4 + 3), so each row
                                   ; monotonic across it: level if its ends are,
                                   ; its highest and lowest at its ends
ot0:    lda ROWA,y                 ; the top (cols: ot0, ot3, oz1-3 this strip's)
ot3:    cmp ROWA+3,y
        bne o_zt
        sta mx                     ; (mn: mx, V clear; record's, c_dbl's)
o_ft:
ob0:    lda ROWB,y                 ; the floor (cols: ob0, ob3, obz)
ob3:    cmp ROWB+3,y
        bne o_zb
o_lv:   tax                        ; (as c_lv, c_ra, c_rb)
        inx
        stx flr1
o_rec:  jmp record                 ; (phase: or o_nr)
c_sp:                              ; a rung in the column: the top level?
pt0:    lda ROWA,y
pt1:    cmp ROWA+1,y
        bne c_zt
pt2:    cmp ROWA+2,y
        bne c_zt
pt3:    cmp ROWA+3,y
        bne c_zt
        sta mx                     ; (mn: mx, V clear)
c_ft:                               ; the floor: level?
pb0:    lda ROWB,y
pb1:    cmp ROWB+1,y
        bne c_zb
pb2:    cmp ROWB+2,y
        bne c_zb
pb3:    cmp ROWB+3,y
        bne c_zb
c_lv:   tax                        ; (level; cols: STA flr / STA flr1 in the near
        inx                        ; strip, its ground's from the floor's line on;
        stx flr1                   ; flr only nearpost's)
c_rec:  jmp record                 ; a column new this frame (strip 1's, or
                                   ; beyond the last strip's): record it (phase:
                                   ; or c_srx)
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
zt3:    lda ROWA+3,y               ; (ZTP 3, to c_ft directly)
        sta ys+3
        cmp mn
        bcs :+
        sta mn
        bcc c_ft
:       cmp mx
        bcc c_ft
        sta mx
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
        cpx #YGND+2                ; (at most YGND+1, and flr then YGND: bclip's;
        bcc :+                     ; nearpost's not level kept)
        dex
        dec flr
:       stx flr1
        jmp c_rec
; A land strip's column: its highest and lowest lines into CURT, CURB (cols'
; inline: on to c_rd, Y = x4).
record: ldx DIV4,y                 ; (always the column's first strip this
                                   ; frame: PINL, PINR widen to the near row)
        lda mx                     ; the column's first strip this frame: its
        bvc :+                     ; (mn: mx if V clear, its top level)
        lda mn
:
pT3:    sta CURT,x                 ; highest line, and black from the land's
pT5:    lda TOPS,x                 ; highest last time down to its top's lowest
                                   ; (the pixels above their top in its top zone
                                   ; kept)
        cmp mx
        bcs c_rd                   ; (Y = x4)
        tax
        inx                        ; one line: here (V kept: c_rr's)
        cpx mx
        bne rc_r
        dex
rc_h:   lda LAHSB0,x               ; (sethalf's, the screen and half's)
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
        ldy x4
        jmp c_rd
rc_r:   dex
        ldy mx
        lda #0
        sta ve
        sta vo
        jsr run
        ldy x4
c_rd:
        ldx ri                     ; the rungs: past those wholly left
        tya
        cmp HI,x
        bcs c_ri
c_rr:   ora #3
        cmp LO,x
        bcs c_split                 ; (LO <= x4 + 3)
o_nr:   ldx ri
c_one:  lda CE-1,x                 ; one box: ri - 1
        sta ve
        lda CO-1,x
        sta vo
        bvs c_z1                   ; (a top not level)
c_r1:    ldx mx
        cpx flr1
        bcs c_next
        ldy flr1
        jsr run2
c_next:
c_np:   jmp nearpost               ; (cols: c_nd but in the near strip; back to c_nd)
c_ri:   inx                        ; (the next rung)
        cmp HI,x
        bcs c_ri
        stx ri
        jmp c_rr
c_v1:   .byte $40                  ; (BIT: V)
c_z1:    jmp zone1                  ; (back to c_r1)
c_srx:  ldx ri                     ; (c_coly's)
        tya
        ora #3
c_split: cmp LO+1,x
        bcs c_dbl
        bvs :+
        jmp fsplit                 ; (back to c_next)
:       jmp split

c_dbl:  lda x4
        ora #3
        cmp LO+2,x
        bcs c_d3
        bvs :+                     ; (two rungs: s2v, its top level; else split2)
        jmp s2v
:       jsr split2
        jmp c_next
c_d3:   bvs :+                     ; (three: never seen; slow reads ys)
        lda mx                     ; (mn: mx, V clear)
        sta mn
        sta ys
        sta ys+1
        sta ys+2
        sta ys+3
:       jsr slow
        jmp c_next

; The near strip's column, drawn (to the line before its floor if its bottom
; row is level there, else to the floor): below the near row black (the line
; at the floor, or the pixels at or below their bottom-row line, read-modify-
; write); then black to the land's lowest line last time (BOTS); CURB.  (cols'
; inline: back to c_nd.)
nearpost:
        lda flr                    ; (its bottom level: flr1 = flr)
        cmp flr1
        bne np_z
        cmp #YGND+1                ; (off the screen: bclip's)
        bcs np_b
        tax
        and #7
        sta zp_
np_h:   lda LAHSB0,x               ; (sethalf's, the screen and half's)
        sta zp_+1
        ldy coff
        lda #0
        sta (zp_),y
np_b:     ldx x4                     ; the land's lowest line now, and last time's
        ldy DIV4,x
        lda flr
        cmp #YGND+1                ; (on the screen: bclip's)
        bcc :+
        lda #YGND
:
pB4:    sta CURB,y
pB5:    cmp BOTS,y
        bcs np_n
        adc #1                     ; (C clear) flr + 1
        tax
pB6:    cmp BOTS,y
        bne np_r
        lda LAH,x                  ; one line (flr + 1 = BOTS): black, here
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
        jmp c_nd
np_r:
pB8:    lda BOTS,y
        tay
        iny
        lda #0
        sta ve
        sta vo
        jsr run
        jmp c_nd                   ; (C clear: run keeps it)
np_n:   lda x4                     ; (C set: c_nd's, inline)
        adc #3
        sta x4
        jmp c_xe                   ; (V clear: the adc above)
np_z:     ldy x4
        lda (bota),y
        sta ys
        iny
        lda (bota),y
        sta ys+1
        iny
        lda (bota),y
        sta ys+2
        iny
        lda (bota),y
        sta ys+3
        cmp ys+2                   ; the highest
        bcc :+
        lda ys+2
:       cmp ys+1
        bcc :+
        lda ys+1
:       cmp ys
        bcc :+
        lda ys
:       tax
np_l:
np_h2:    lda LAHSB0,x             ; (zline, black: the byte AND not pmask's; sethalf's)
        sta zp_+1
        txa
        and #7
        sta zp_
        lda #0
        cpx ys+3
        rol a
        cpx ys+2
        rol a
        cpx ys+1
        rol a
        cpx ys
        rol a
        tay
        lda MASKN,y
        ldy coff
        and (zp_),y
        sta (zp_),y
        inx
        cpx flr1
        bcc np_l
        jmp np_b

; Columns the land has left since last time: black from its highest line to
; its lowest.  Each column outside this frame's land: none this frame (CURT
; $FF, CURB 0).
.macro GONE1 lt, lc, lb
        .local nd
lt      = *
        lda TOPS,x
        cmp #$FF
        beq nd
        jsr gn_d
nd:     lda #$FF
lc      = *
        sta CURT,x
        lda #0
lb      = *
        sta CURB,x
.endmacro
gone:   lda xr                     ; (right to left: the columns are independent)
        lsr a                      ; the columns right of the near strip's (all
        lsr a                      ; the strips' columns: within the near strip's)
        sta tsy
        ldx #63
        cpx tsy
        bcc gn_l
gn_c:   GONE1 pT6, pT4, pB7
        dex
        cpx tsy
        bcs gn_c
gn_l:   lda xl                     ; and left of them
        lsr a
        lsr a
        tax
        dex
        bmi gn_x
gn_c2:  GONE1 pT6b, pT4b, pB7b
        dex
        bpl gn_c2
gn_x:   rts
gn_d:   stx tj
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
        ldy tj                     ; (sethalf leaves Y its STAB's)
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
        lda #OP_STAY               ; run2's RTSes back (its pages change)
        ldx rE+1
sh_1:   sta TPE0*256,x
        ldx rO+1
sh_2:   sta TPO0*256,x
        sty pY+1                   ; (none planted: Y < YSKY)
        lda tpe,y
        sta pr0+2
        sta pp0+2
        sta je+2
        sta sh_1+2
        lda tpo,y
        sta pr1+2
        sta pp1+2
        sta jo+2
        sta sh_2+2
        lda lahsl,y
        sta fs_h+1
        sta fr_h+1
        sta np_h+1
        sta np_h2+1
        sta rc_h+1
        lda lahsh,y
        sta fs_h+2
        sta fr_h+2
        sta np_h+2
        sta np_h2+2
        sta rc_h+2
        rts
tpe:    .byte TPE0, TPE1, TPE2, TPE3 ; (tools/landgen.py's)
tpo:    .byte TPO0, TPO1, TPO2, TPO3
exhl:   .byte <(EXHB0), <(EXHB1), <(EXHB2), <(EXHB3)
exhh:   .byte >(EXHB0), >(EXHB1), >(EXHB2), >(EXHB3)
lahsl:  .byte <(LAHSB0), <(LAHSB1), <(LAHSB2), <(LAHSB3)
lahsh:  .byte >(LAHSB0), >(LAHSB1), >(LAHSB2), >(LAHSB3)
enthl:  .byte <(ENTB0), <(ENTB1), <(ENTB2), <(ENTB3)
enthh:  .byte >(ENTB0), >(ENTB1), >(ENTB2), >(ENTB3)

fs_nt:  jmp fs_new
; A column a rung (X = ri) splits, its top level: from mx down to the floor,
; the boxes split at bpos (the rung's pixels left of it), bpos moving a pixel
; at each of the rung's transitions in the column.  Y = bpos throughout; rtp +
; Y: its transition (pixel x4 + Y changes, bpos + 1 after, leaning right; x4 +
; Y - 1, bpos - 1, leaning left), ended by the rung's sentinel ($FF: rungs) or
; the column's edge (fend); BE, BO + Y: its bytes (the rung's, made at its
; first column, fs_new: lastri).  The walker: X = the line in its character
; row (rsm: the row's first line - 1), each line's byte stored at f_wse or
; f_wso (by its parity; operand: the row, coff), to fwe (the transition in
; the row: crossing into the next at X = 8); a run instead to a transition
; 8 + FSRJ lines or more past the row, or to a floor past it (fe_r); a floor
; in the row walked by its copy (ff_se, ff_so).  (cols' inline: c_split
; jumps here, back to c_next.)
fsplit: cpx lastri
        bne fs_nt
fs_c:   lda #0                     ; (C set) fl_e, fl_o's operands = RTP + x4
rbl     = *-1                      ; (- 1 leaning left) (fs_new's: the rung's
        adc x4                     ; transitions, less 1 (2 leaning left))
        sta fl_e+1
        sta fl_o+1
        lda #0
rbh     = *-1
        adc #0
        sta fl_e+2
        sta fl_o+2                 ; (C clear)
        lda TX,x                   ; bpos: TX - x4, clamped to 0..4
        sbc x4
        tay
        ldx CLMP1,y
fs_w:   lda coff                   ; the walker's stores: (zp_),y, the column's,
        sta zp_                    ; Y's row
        ldy mx
fs_h:   lda LAHSB0,y               ; (sethalf: the screen and half's)
        sta zp_+1
        lda RSMT,y
        sta rsm                    ; (the row's first line - 1)
        tya
        and #7
        tay                        ; Y: the line in its row
        lsr a                      ; (by its parity: fl_e, fl_o)
        bcc fl_e
        bcs fl_o
fw_c:   lda zp_+1                  ; the next row (C set): + 2
        adc #1
        sta zp_+1
        lda rsm                    ; (C clear)
        adc #8
        sta rsm
        ldy #0
        lda fwe
        sbc #7                     ; (C clear) - 8
        sta fwe
        beq fn_e
fw_e:   lda BE,x                   ; an even line
        sta (zp_),y                ; (the row's line Y)
        iny
        cpy fwe
        beq fn_o
fw_o:   lda BO,x                   ; an odd line
        sta (zp_),y
        iny
        cpy #8
        beq fw_c                   ; (the row's end)
        cpy fwe
        bne fw_e
fn_e:                              ; Y even
fst_e:  inx                        ; (or DEX: fs_new)
fen_e:  cpx #4                     ; (or 0)
        beq fe_x
fl_e:   lda $FFFF,x                ; the transition's line, t (operand: fs_c's)
        cmp flr1
        bcs fe_x
        sbc rsm                    ; (C clear) t, in the row (fwe)
        sta fwe
        cpy fwe
        bcs fn_e                   ; (at or above Y: bpos only)
        cmp #8+FSRJ
        bcc fw_e                   ; (walked, crossing a row at most)
        bcs fr
fn_o:                              ; Y odd
fst_o:  inx                        ; (or DEX: fs_new)
fen_o:  cpx #4                     ; (or 0)
        beq fe_x
fl_o:   lda $FFFF,x
        cmp flr1
        bcs fe_x
        sbc rsm
        sta fwe
        cpy fwe
        bcs fn_o
        cmp #8+FSRJ
        bcc fw_o
fr:     stx bpos                   ; (C set) lines Y .. t-1, a run
        adc rsm
        sta fwu                    ; t
        lda BE,x
        sta ve
        lda BO,x
        sta vo
        tya
        sec
        adc rsm                    ; the line
        tax
        ldy fwu
        jsr run2
        ldy fwu
fr_h:   lda LAHSB0,y               ; (sethalf) the walker from t
        sta zp_+1
        lda RSMT,y
        sta rsm
        tya
        and #7
        tay
        ldx bpos
        lsr a
        bcc fn_e
        bcs fn_o
fe_x:   lda flr1                   ; the floor: the rest at bpos
        clc
        sbc rsm
        cmp #8
        bcs fe_r                   ; (beyond the row: a run; Y < 8 here)
        sta fwe                    ; (the floor in the row)
        cpy fwe
        bcs ff_d
        tya                        ; (in it: walked, by the walker's copy)
        lsr a
        bcs ff_o
ff_e:   lda BE,x
        sta (zp_),y
        iny
        cpy fwe
        beq ff_d
ff_o:   lda BO,x
        sta (zp_),y
        iny
        cpy fwe
        bne ff_e
ff_d:   jmp c_next
fe_r:   lda BE,x                   ; the floor's run
        sta ve
        lda BO,x
        sta vo
        tya
        sec
        adc rsm
        tax
        ldy flr1
        jsr run2
        jmp c_next
fs_new: stx lastri                 ; the rung's bytes by bpos: 0 the right box,
        lda CE-1,x                 ; 4 the left (Y: the two EORed)
        sta BE+4
        lda CE,x
        sta BE
        eor BE+4
        tay
        and #$88
        eor BE
        sta BE+1
        tya
        and #$CC
        eor BE
        sta BE+2
        tya
        and #$EE
        eor BE
        sta BE+3
        lda CO-1,x
        sta BO+4
        lda CO,x
        sta BO
        eor BO+4
        tay
        and #$88
        eor BO
        sta BO+1
        tya
        and #$CC
        eor BO
        sta BO+2
        tya
        and #$EE
        eor BO
        sta BO+3
        lda BX,x
        cmp TX,x
        bcs fs_nr
        lda RTPL,x                 ; leaning left: x4 + bpos - 1, bpos - 1 after
        sbc #1                     ; (C clear: - 2)
        sta rbl
        lda RTPH,x
        sbc #0
        sta rbh
        lda #OP_DEX                ; (the last rung's lean, kept)
        cmp fst_e
        beq fs_nj                  ; (C set)
        sta fst_e
        sta fst_o
        lda #0
        sta fen_e+1
        sta fen_o+1
        sec
        bcs fs_nj
fs_nr:  lda RTPL,x                 ; leaning right (or upright): pixel x4 + bpos
        sbc #1                     ; changes, bpos + 1 after (- 1; C set)
        sta rbl
        lda RTPH,x
        sbc #0
        sta rbh
        lda #OP_INX
        cmp fst_e
        beq fs_nj                  ; (C set)
        sta fst_e
        sta fst_o
        lda #4
        sta fen_e+1
        sta fen_o+1
        sec
fs_nj:  jmp fs_c                   ; (split's: sp_r)
        .res 18                    ; (spare: keeps the code after in place)

; The top zone of a one-box column: lines mn .. min(mx, flr1)-1, each the
; pixels at or below their top (pmask, zline inline; cols' inline: back to c_r1).
zone1:  ldx mn
@l:     cpx mx
        bcs @d
        cpx flr1
        bcs @d
        lda #0                     ; (pmask)
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
        lda LAH,x                  ; (zline)
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        lsr a                      ; (C: an odd line)
        ldy coff
        lda (zp_),y
        bcs @o
        eor ve
        and msk
        eor (zp_),y
        sta (zp_),y
        inx
        bne @l
@o:     eor vo
        and msk
        eor (zp_),y
        sta (zp_),y
        inx
        bne @l
@d:     jmp c_r1

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
MASKN:  .byte $FF, $77, $BB, $33, $DD, $55, $99, $11
        .byte $EE, $66, $AA, $22, $CC, $44, $88, $00

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

; A column a rung splits, its top not level: the zone (lines mn .. min(mx,
; flr1)-1, each the pixels at or below their top) at bpos as it is at the
; line, from fsplit's tables (rtp, BE, BO); then fsplit's, from mx.
split:  ldx ri
        cpx lastri
        beq sp_c
        lda #<sp_r                 ; (fs_new: back to sp_r)
        sta fs_nj+1
        lda #>sp_r
        sta fs_nj+2
        jmp fs_new
sp_r:   lda #<fs_c                 ; (C set) fs_new's own again
        sta fs_nj+1
        lda #>fs_c
        sta fs_nj+2
sp_c:   lda rbl                    ; (C set) as fs_c
        adc x4
        sta rtp
        sta fl_e+1
        sta fl_o+1
        lda rbh
        adc #0
        sta rtp+1
        sta fl_e+2
        sta fl_o+2
        lda TX,x
        sbc x4
        tax                        ; (X reloaded below)
        ldy CLMP1,x
        ldx mn
        lda fst_e
        cmp #OP_INX
        bne sp_lz
sp_rz:  cpx mx                     ; leaning right (or upright)
        bcs sp_zd
        cpx flr1
        bcs sp_zd
sp_rc:  cpy #4                     ; bpos: the transitions at or above line X
        beq sp_rb
        txa
        cmp (rtp),y
        bcc sp_rb
        iny
        bne sp_rc
sp_rb:  jsr sp_ln
        inx
        bne sp_rz
sp_lz:  cpx mx                     ; leaning left
        bcs sp_zd
        cpx flr1
        bcs sp_zd
sp_lc:  cpy #0
        beq sp_lb
        txa
        cmp (rtp),y
        bcc sp_lb
        dey
        bpl sp_lc
sp_lb:  jsr sp_ln
        inx
        bne sp_lz
sp_zd:  tya                        ; (fs_w's: X = bpos)
        tax
        jmp fs_w
; Line X of the zone at bpos Y (X, Y kept).
sp_ln:  sty bpos
        jsr pmask
        ldy bpos
        txa
        lsr a
        lda BE,y
        bcc :+
        lda BO,y
:       jsr zline
        ldy bpos
        rts

; Rung X's transitions in the column into TRL, TRB (bpos as its LM mask) from
; A, ended by $FF; A: LM of its position in the column at the top (p0).
mktr:   sta tj
        lda RTPL,x                 ; (rtp: RTP + x4, by position)
        clc
        adc x4
        sta rtp
        lda RTPH,x
        adc #0
        sta rtp+1                  ; (C clear)
        lda BX,x                   ; (A - x4, clamped to 0..4)
        sbc x4
        tay
        lda CLMP1,y
        sta p1
        clc
        lda TX,x
        sbc x4
        tay
        lda CLMP1,y
        sta p0
        ldx tj
        cmp p1
        beq @end
        bcs @lt
        tay
@rt:    lda (rtp),y                ; leaning right: pixels p0 .. p1-1, p+1 after
        sta TRL,x
        lda LM+1,y
        sta TRB,x
        inx
        iny
        cpy p1
        bne @rt
        beq @end
@lt:    tay                        ; leaning left: pixels p0-1 .. p1, p after
:       dey
        lda LM,y
        sta TRB,x
        lda (rtp),y
        sta TRL,x
        inx
        cpy p1
        bne :-
@end:   lda #$FF
        sta TRL,x
        ldy p0
        lda LM,y
        rts

; A column two rungs split (ri, ri+1): boxes L, M, R = ri-1, ri, ri+1, the
; boundaries at bpos and bpos2, each moving at its transitions.
split2: ldx ri
        lda CE-1,x
        sta le
        lda CO-1,x
        sta lo2
        lda CE+1,x
        sta re
        eor CE,x
        sta me                     ; (as me ^ re)
        lda CO+1,x
        sta ro
        eor CO,x
        sta mo                     ; (as mo ^ ro)
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
        stx yy
        ldy kb                     ; the next transition, or the floor
        jmp @rl3
@tr:    ldy kk                     ; (catch2, inline: X = yy)
        txa
        cmp TRL,y
        bcc @k2
:       lda TRB,y
        sta bpos
        iny
        txa
        cmp TRL,y
        bcs :-
        sty kk
@k2:    ldy kb                     ; (A = X)
        cmp TRL,y
        bcc @rl3
:       lda TRB,y
        sta bpos2
        iny
        txa
        cmp TRL,y
        bcs :-
        sty kb
@rl3:   lda TRL,y                  ; (Y = kb)
        ldy kk
        cmp TRL,y
        bcc :+
        lda TRL,y
:       cmp flr1
        bcc :+
        lda flr1
:       cmp yy
        beq @tr
        bcc @tr
        tay
        lda me                     ; (bytes2, inline)
        and bpos2
        eor re
        sta ve
        eor le
        and bpos
        eor ve
        sta ve
        lda mo
        and bpos2
        eor ro
        sta vo
        eor lo2
        and bpos
        eor vo
        sta vo
        ldx yy
        sty yy
        jsr run
        ldx yy
        cpx flr1
        bcc @tr
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

; ve, vo: split2's bytes (X, Y kept; bpos, bpos2 as LM masks).
bytes2: lda me
        and bpos2
        eor re
        sta ve
        lda mo
        and bpos2
        eor ro
        sta vo
        lda le
        eor ve
        and bpos
        eor ve
        sta ve
        lda lo2
        eor vo
        and bpos
        eor vo
        sta vo
        rts

LM:     .byte $00, $88, $CC, $EE, $FF

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

; Lines X .. Y-1 (X < Y), as run, in two passes: the even lines (ve), then the
; odd (vo), each through its table for the screen and half (tools/landgen.py's,
; sethalf's pages: pr0, pp0, je; pr1, pp1, jo), from EIN, OIN + X to an RTS
; planted at EIN, OIN + Y (OIN = EIN - 1; rE, rO; pY: the line they are for,
; kept while the next run2's end is the same; put back by the next run2's that
; ends elsewhere, or sethalf).
run2:   lda EIN,x
        sta je+1
        lda EIN-1,x                ; (OIN)
        sta jo+1
pY:     cpy #$FF                   ; (the RTSes already at Y's)
        beq pY_k
        sty pY+1
        lda #OP_STAY               ; the last back
rE:     ldx #$FF
pr0:    sta $FF00,x
rO:     ldx #$FF
pr1:    sta $FF00,x
        lda #OP_RTS
        ldx EIN,y
        stx rE+1
pp0:    sta $FF00,x
        ldx EIN-1,y
        stx rO+1
pp1:    sta $FF00,x
pY_k:   lda ve
        ldy coff
je:     jsr $FFFF
        lda vo
jo:     jmp $FFFF                  ; (its RTS returns from run2)

; ---------------------------------------------------------------- readout
; At each flip: the vertical syncs since the last (dvs, the last 8); the
; readout: 400 / their sum, frames a second, to a tenth (FPSL, FPSH: 4000 /
; sum), at the top left.
G_DOT   = 10                       ; (the readout's characters, GLY: LANDS's
G_SP    = 11                       ; glyphs makes them)
G_F     = 12

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

fps10:  .res 2                     ; (the readout's)
dvs:    .res 8
dvi:    .res 1
vlast:  .res 1
tcol:   .res 1

        .assert * <= $3000, error, "code over the screen"

; ---------------------------------------------------------------- s2v
; (bank 4, its free space) A column two rungs split (ri, ri+1), its top level:
; fsplit's for ri+1 (boxes M, R), then box L over the pixels left of ri at
; each line (mktr's transitions, from TRL; bpos2 the LM mask; le, lo2 L's
; bytes; c_np's way on kept in me, mo while fsplit's ends at s2ov).
        .segment "B4V1"
s2v:    lda CE-1,x                 ; (X = ri) L's bytes
        sta le
        lda CO-1,x
        sta lo2
        lda #0                     ; ri's transitions
        jsr mktr
        sta bpos2
        lda #0
        sta kb
        lda c_np+1                 ; fsplit's end here
        sta me
        lda c_np+2
        sta mo
        lda #<s2ov
        sta c_np+1
        lda #>s2ov
        sta c_np+2
        ldx ri
        inx
        jmp fsplit
s2ov:   lda me                     ; (c_np's again)
        sta c_np+1
        lda mo
        sta c_np+2
        lda #0
        sta zp_
        ldx mx                     ; from mx
        cpx flr1
        bcs s2_d
        ldy kb
        jmp s2_c
s2_d:   jmp c_np
        .segment "B4V2"
s2_c:   txa                        ; (X: the line) the mask by ri's
        cmp TRL,y                  ; transitions at or above it
        bcc s2_e
:       lda TRB,y
        sta bpos2
        iny
        txa
        cmp TRL,y
        bcs :-
s2_e:   sty kb
        lda TRL,y                  ; the run's end: the next, or the floor
        cmp flr1
        bcc :+
        lda flr1
:       sta tj
        lda bpos2
        beq s2_n                   ; (none left of ri)
        jmp s2_l
s2_n:   ldx tj
        cpx flr1
        bcs s2_x
        ldy kb
        jmp s2_c
s2_x:   jmp c_np
        .segment "B4V3"
s2_l:   lda LAH,x                  ; lines X .. tj-1: L in the mask's pixels
        clc                        ; (read-modify-write)
        adc scrh
        sta zp_+1
        txa
        and #7
        ora coff
        tay
        txa
        lsr a
        bcs s2_o
s2_v:   lda (zp_),y                ; an even line
        eor le
        and bpos2
        eor (zp_),y
        sta (zp_),y
        iny
        inx
        cpx tj
        beq s2_m
s2_o:   lda (zp_),y                ; an odd line
        eor lo2
        and bpos2
        eor (zp_),y
        sta (zp_),y
        iny
        inx
        cpx tj
        beq s2_m
        txa
        and #7
        bne s2_v
        inc zp_+1                  ; the next row
        inc zp_+1
        ldy coff
        jmp s2_v
s2_m:   jmp s2_n

; ---------------------------------------------------------------- LANDS
; LANDS: the start, run once from $7000 (!BOOT: *LOAD LAND, *RUN LANDS): the
; banks loaded (each file *LOADed to $3000, below this, and copied), the
; palette, the readout's characters, the screen narrowed; then LAND's `go`
; (whose init clears the screens, this with them).
        .segment "BOOT"
start:  ldx #<cmd_load7             ; TABLES7 to bank 7, SHIPB to bank 6,
        ldy #>cmd_load7            ; TABLES2 to bank 5, TABLES to bank 4
        lda #BANK7
        jsr ldbank
        ldx #<cmd_load3
        ldy #>cmd_load3            ; (each by $3000)
        lda #BANK3
        jsr ldbank
        ldx #<cmd_load2
        ldy #>cmd_load2
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
        lda #BANK2                 ; the game's letters, in bank 5
        sta ROMCOPY
        sta ROMSEL
        jsr glyphs5
        lda #BANK
        sta ROMCOPY
        sta ROMSEL
        ldx #0                     ; narrow the screen: 64 bytes by 20 rows
:       lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne :-
        jmp go

cmd_load: .byte "LOAD TABLES 3000", 13
cmd_load3: .byte "LOAD SHIPB 3000", 13
cmd_load7: .byte "LOAD TABLES7 3000", 13
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
glyphs5:                           ; (as glyphs: the game's letters to GLY5)
        ldx #0
@c:     stx tcol
        lda lchars,x
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
        sta GLY5,x
        lda oswblk+1,y
        and #$0F
        sta tmp
        asl a
        asl a
        asl a
        asl a
        ora tmp
        sta GLY5+8,x
        inx
        iny
        cpy #8
        bne @l
        ldx tcol
        inx
        cpx #lchars_end-lchars
        bne @c
        rts
lchars: .byte "FUELANDCRSH"
lchars_end:
oswblk: .res 9

; ---------------------------------------------------------------- rungs' fast way
; (bank 4, its free space) A rung with a <= RFA and 0 <= D < 16: each pixel's
; transition from tools/landgen.py's tables, TRk (leaning right) or TLk (left)
; by X = 16 (RFA - a) + D: the k'th pixel's offset from yt (the pixel at
; (alloc),k), k < a; the code entered at the a-1'th pixel (DUFR, DUFL by a).
; Else back to the division (ra2 = 2a).  (rungs': X the rung, dva = a.)
        .segment "B4C"
rfastr: ldy dva
        cpy #RFA+1
        bcs @sl
        lda TY,x
        sta rrem                   ; (yt)
        lda BY,x
        sec
        sbc rrem
        cmp #16
        bcs @sl                    ; (C clear after: kept below)
        ora B16-1,y
        tax
        lda DUFR-1,y
        sta @j+1
@j:     jmp FR0
@sl:    lda dva
        asl a
        sta ra2
        jmp rg_rdr
rfastl: ldy dva
        cpy #RFA+1
        bcs @sl
        lda TY,x
        sta rrem
        lda BY,x
        sec
        sbc rrem
        cmp #16
        bcs @sl
        ora B16-1,y
        tax
        lda DUFL-1,y
        sta @j+1
@j:     jmp FL0
@sl:    lda dva
        asl a
        sta ra2
        jmp rg_rdl
B16:    .repeat RFA, i
        .byte 16 * (RFA - 1 - i)
        .endrepeat
DUFR:   .repeat RFA, i
        .byte <(FR0 + 9 * (RFA - 1 - i))
        .endrepeat
DUFL:   .repeat RFA, i
        .byte <(FL0 + 9 * (RFA - 1 - i))
        .endrepeat
.macro RFBODY T
        .repeat RFA, i
        lda .ident(.sprintf("%s%d", T, RFA - 1 - i)),x
        adc rrem                   ; (C clear: no carry)
        ldy #RFA - 1 - i
        sta (alloc),y
        .endrepeat
        lda #$FF                   ; the sentinel (Y = a), alloc += a + 1
        ldy dva
        sta (alloc),y
        tya
        sec
        adc alloc
        sta alloc
        bcc :+
        inc alloc+1
:       ldx tj                     ; the next rung (rungs' @nx)
        inx
        cpx np1
        bcs :+
        jmp rg_r
:       rts
.endmacro
        .segment "B4R"
FR0:    RFBODY "TR"
        .segment "B4L"
FL0:    RFBODY "TL"

; ---------------------------------------------------------------- bank 7
        .segment "B7CODE"
; (bank 7) Each row's y's (SYT7) and x's (fast, or clipr), the near clip's row
; (RN) the last, on its plane, and the far clip's (row 0 with FACT) on its.
HOFF    = $9E                      ; (bank 7: hgnd's HMAX - hg; project's scratch)
prow7:  lda cxs                    ; LERPQ7's row for fx: + 32 cxs
        lsr a
        lsr a
        lsr a
        clc
        adc #>LERPQ7
        sta @lq0+2
        sta @lq1+2
        lda cxs
        asl a
        asl a
        asl a
        asl a
        asl a
        sta @lq0+1
        sta @lq1+1
        jsr hgnd                   ; the heights less the ground's under the ship
        lda RN                     ; the near clip: its row's heights (all still
        asl a                      ; raw), and the far clip's
        asl a
        asl a
        asl a
        sta tmp
        jsr zlerp
        lda FACT
        beq :+
        jsr flerp
:       lda #0
        sta pr
@r:     lda pr                     ; di = 16 (ZBACK - j) - czs - DI0 (j = pr + ZSKIP)
        asl a
        asl a
        asl a
        asl a
        sta tmp                    ; (16 j: the row's place in PX, PY)
        lda DIB
        sec
        sbc tmp
        sec
        sbc czs
        tay
        lda pr                     ; the clips' rows: on their planes (their
        cmp RN                     ; heights: zlerp's, flerp's)
        bne :+
        ldy #ZCLIP*16-DI0
:       lda FACT
        beq :+
        lda pr
        bne :+
        ldy #ZFCLIP*16-DI0
:       sty xt1                    ; (di)
        lda R7L,y
        sta rl
        lda R7H,y
        sta rh
        tya                        ; di * 32: the row's SYT7
        lsr a
        lsr a
        lsr a
        clc
        adc #>SYT7
        sta syp+1
        tya
        asl a
        asl a
        asl a
        asl a
        asl a
        ora HOFF                   ; (+ HMAX - hg: 0..15, di*32's low 5 bits 0)
        sta syp
        tya                        ; di * 16: its B0's for cxs
        lsr a
        lsr a
        lsr a
        lsr a
        sta tmp+1
        tya
        asl a
        asl a
        asl a
        asl a
        sta lp
        sta hp0
        sta hp1
        ldx tmp                    ; the edges' heights: corners 1 to 2, and 10
        lda PY+1,x                 ; to 11, by fx (LERPQ7: land.lerp)
        sec
        sbc PY,x
        clc
        adc #LQOFF
        tay
@lq0:   lda LERPQ7,y
        clc
        adc PY,x
        sta PY,x
        lda PY+NX-1,x
        sec
        sbc PY+NX-2,x
        clc
        adc #LQOFF
        tay
@lq1:   lda LERPQ7,y
        clc
        adc PY+NX-2,x
        sta PY+NX-1,x
        lda CAME                   ; (the camera higher: eyrow's)
        beq :+
        jsr eyrow
        jmp @pyd
:       .repeat NX, i
        PYS i
        .endrepeat
@pyd:   lda tmp+1
        clc
        adc #>B0L
        sta hp0+1
        lda tmp+1
        clc
        adc #>B0H
        sta hp1+1
        ldy cxs
        lda (hp0),y
        sta vx
        lda (hp1),y
        .repeat NX, i
        PXS i
        .endrepeat
        ldy xt1                    ; the edges' x: -XCLIP, +XCLIP
        lda PINL7,y
        sta PX,x
        lda PINR7,y
        sta PX+NX-1,x
        lda CLP7,y                 ; past the screen's edges: clipr
        beq @nx
        jsr clipr
@nx:    lda pr                     ; the near clip's row: a line or more below
        cmp RN                     ; the row before (then the last)
        bne @fc
        ldx tmp
        ldy #NX
:       lda PY-16,x
        cmp PY,x
        bcc :+
        adc #0                     ; (C set: + 1)
        sta PY,x
:       inx
        dey
        bne :--
        rts
@fc:    cmp #1                     ; the far clip's row: a line or more above
        bne @nr                    ; this (row 1)
        lda FACT
        beq @nr
        ldx #0
        ldy #NX
:       lda PY+16,x
        sec
        sbc #1
        cmp PY,x
        bcs :+
        sta PY,x
:       inx
        dey
        bne :--
@nr:    inc pr
        jmp @r


; The row's y's (SYT7 by height, X: 16 j) with the camera CAME higher: each
; (CAME (r >> 5) + 64) >> 7 more (land.project's ey, EYV; r < 8192).
eyrow:  lda rh
        sta MT1
        lda rl
        .repeat 5
        lsr MT1
        ror a
        .endrepeat
        sta MT0                    ; (r >> 5)
        lda CAME
        sta MT1
        lda #0
        ldy #8
        lsr MT1
@m:     bcc :+
        clc
        adc MT0
:       ror a
        ror MT1
        dey
        bne @m
        tay                        ; (A, MT1: the product) + 64, >> 7
        lda MT1
        clc
        adc #64
        sta MT1
        tya
        adc #0
        asl MT1
        rol a
        sta EYV
        clc
        .repeat NX, i
        PYSE i
        .endrepeat
        rts

; The ground under the ship (land.ground: ZSHIP ahead at the camera's x, corner
; rows j ZBACK - ZSHIP and the next farther, columns CX 4 + (cxs >= 8) and the
; next, across by (cxs + 8) & 15 sixteenths, then down by czs: LERPQ7), and
; every raw height (rows 0..nr-1) less it, + HMAX (SYT7's index).
hgnd:   lda #ZBACK-ZSHIP           ; its row: ZBACK - ZSHIP less the first's j
        sec                        ; (ZBACK - ZB)
        sbc #ZBACK
        clc
        adc ZB
        asl a
        asl a
        asl a
        asl a
        sta tmp                    ; (16 r)
        lda cxs                    ; its column: 4, or 5 at cxs >= 8
        cmp #8
        lda #4
        adc #0
        clc
        adc tmp
        tax                        ; X: 16 r + its column
        lda cxs                    ; across: q = (cxs + 8) & 15
        clc
        adc #8
        and #15
        jsr lqrow
        lda PY+1,x                 ; the near corners
        sec
        sbc PY,x
        clc
        adc #LQOFF
        tay
        lda (lp),y
        clc
        adc PY,x
        sta tmp+1                  ; (hx0)
        lda PY-15,x                ; the far corners (the row before: 16 back)
        sec
        sbc PY-16,x
        clc
        adc #LQOFF
        tay
        lda (lp),y
        clc
        adc PY-16,x                ; (hx1)
        sec
        sbc tmp+1
        clc
        adc #LQOFF
        pha
        lda czs                    ; down: q = czs
        jsr lqrow
        pla
        tay
        lda (lp),y
        clc
        adc tmp+1                  ; hg
        sta HGV
        eor #$FF                   ; HMAX - hg: prow7's SYT7 offset (the
        sec                        ; heights stay raw)
        adc #HMAX
        sta HOFF
        rts
lqrow:  pha                        ; lp: LERPQ7's row q (A)
        lsr a
        lsr a
        lsr a
        clc
        adc #>LERPQ7
        sta lp+1
        pla
        asl a
        asl a
        asl a
        asl a
        asl a
        sta lp
        rts

; The near clip's row's heights (X: 16 j, raw): from the row before's by 1 -
; fz (land.lerp, LERPQ7: q = 16 - czs; none at fz 0: the row itself).
zlerp:  lda czs
        beq @d
        lda #16
        sec
        sbc czs
        pha
        lsr a
        lsr a
        lsr a
        clc
        adc #>LERPQ7
        sta @zq+2
        pla
        asl a
        asl a
        asl a
        asl a
        asl a
        sta @zq+1
        ldx tmp
        ldy #NX
        sty tmp+1
:       lda PY,x                   ; b - a + 12
        sec
        sbc PY-16,x
        clc
        adc #LQOFF
        tay
@zq:    lda LERPQ7,y
        clc
        adc PY-16,x
        sta PY,x
        inx
        dec tmp+1
        bne :-
@d:     rts

; The far clip's row's heights (row 0, raw): to row 1's by 1 - fz (land.lerp,
; LERPQ7: q = 16 - czs; fz not 0).
flerp:  lda #16
        sec
        sbc czs
        pha
        lsr a
        lsr a
        lsr a
        clc
        adc #>LERPQ7
        sta @fq+2
        pla
        asl a
        asl a
        asl a
        asl a
        asl a
        sta @fq+1
        ldx #NX-1
:       lda PY+16,x                ; b - a + 12
        sec
        sbc PY,x
        clc
        adc #LQOFF
        tay
@fq:    lda LERPQ7,y
        clc
        adc PY,x
        sta PY,x
        dex
        bpl :-
        rts

; A row the screen's edges clip (X: 16 j): its corners left of XL onto XL, those
; right of XR onto XR, at the row's y where it crosses (land.clip: y0 +
; floor(((y1 - y0) n 2 + d) / 2d), n the distance to the edge, d the segment's
; width).
clipr:  ldy #NX-1                   ; (all on: 8 bits)
        lda #0
:       sta PXX,y
        dey
        bpl :-
        ldx tmp
        ldy #0                     ; the left edge: the first corner on (x >= XL)
@lf:    lda PXX,y
        bne @ln                    ; (x < 0)
        tya
        clc
        adc tmp
        tax
        lda PX,x
        cmp #XL
        bcs :+
@ln:    iny
        bne @lf
:       tya
        beq @rt
        sta tj                     ; k
        clc
        adc tmp
        tax                        ; X: 16 j + k
        lda PX,x                   ; d = x1 - x0 (x0 < 0)
        sec
        sbc PX-1,x
        sta cd
        lda #XL                    ; n = XL - x0
        sec
        sbc PX-1,x
        sta cn
        lda PY,x                   ; dy = y1 - y0
        sec
        sbc PY-1,x
        jsr cyc
        sta cdy
        lda tj
        clc
        adc tmp
        tax
        lda cdy
        clc
        adc PY-1,x                 ; yc
        ldy tj                     ; corners 0..k-1 onto (XL, yc)
        ldx tmp
:       sta PY,x
        lda #XL
        sta PX,x
        lda PY,x
        inx
        dey
        bne :-
@rt:    ldy #NX-1                  ; the right edge: the last corner on (x <= XR)
:       lda PXX,y
        bne :+
        tya
        clc
        adc tmp
        tax
        lda PX,x
        cmp #XR+1
        bcc :++
:       dey
        bpl :--
:       cpy #NX-1
        beq @d
        sty tj                     ; k
        tya
        clc
        adc tmp
        tax                        ; X: 16 j + k
        lda PX+1,x                 ; d = x1 - x0 (x1 > XR: 9 bits)
        sec
        sbc PX,x
        sta cd
        lda #XR                    ; n = XR - x0
        sec
        sbc PX,x
        sta cn
        lda PY+1,x
        sec
        sbc PY,x
        jsr cyc
        sta cdy
        lda tj
        clc
        adc tmp
        tax
        lda cdy
        clc
        adc PY,x                   ; yc
        ldy tj                     ; corners k+1..NX-1 onto (XR, yc)
:       iny
        cpy #NX
        beq @d
        inx
        sta PY,x
        pha
        lda #XR
        sta PX,x
        pla
        bne :-                     ; (yc > 0)
@d:     rts

; floor((A n 2 + d) / 2d), A signed (dy), n = cn, d = cd (1..127): A.  The
; product by adding, the quotient by subtracting (both small).
cyc:    sta cdy
        lda #0
        sta cpl
        sta cph
        ldy cn
        beq @m
@a:     lda cdy                    ; + dy, n times (16 bits, signed)
        bpl :+
        dec cph
:       clc
        adc cpl
        sta cpl
        bcc :+
        inc cph
:       dey
        bne @a
@m:     asl cpl                    ; * 2, + d
        rol cph
        lda cpl
        clc
        adc cd
        sta cpl
        bcc :+
        inc cph
:       lda cd                     ; 2d
        asl a
        sta cd
        ldy #0                     ; floor(N / 2d): N >= 0 by subtracting; N < 0
        lda cph                    ; by adding (q from 0 down)
        bmi @n
@p:     lda cpl
        sec
        sbc cd
        tax
        lda cph
        sbc #0
        bcc @pq
        sta cph
        stx cpl
        iny
        bne @p
@pq:    tya
        rts
@n:     dey                        ; N + 2d (q - 1) until N >= 0
        lda cpl
        clc
        adc cd
        sta cpl
        lda cph
        adc #0
        sta cph
        bmi @n
        tya
        rts


; ---------------------------------------------------------------- the slow way
; (bank 4, its free space, in two: never seen)
        .segment "B4S"
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
        jmp slow2
        .segment "B4S2"
slow2:  ldx mn                     ; a line at a time
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

; ---------------------------------------------------------------- bank 5
        .segment "B5CODE"
; (bank 5) Each land strip's boxes' bytes (CLE, CLO): box i the tile at its left
; column and the near row's.
pcol5:  lda #1
        sta pr
@cs:    lda czt
        clc
        adc ZB
        sec
        sbc pr
        and #63
        tax
        lsr a
        lsr a
        ora #>CMAPE                ; (CMAPE: $8000, 64 a row)
        sta hp0+1
        ora #>CMAPO
        sta hp1+1
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        asl a
        sta hp0
        sta hp1
        lda pr                     ; the strip's stores: 16 (strip - 1) on
        asl a
        asl a
        asl a
        asl a
        sec
        sbc #16
        sta tmp
        clc
        adc #<CLE
        sta @se+1
        lda #>CLE
        adc #0
        sta @se+2
        lda tmp
        clc
        adc #<CLO
        sta @so+1
        lda #>CLO
        adc #0
        sta @so+2
        ldx #NX-2
@b:     ldy CX,x
        lda (hp0),y
@se:    sta CLE,x
        lda (hp1),y
@so:    sta CLO,x
        dex
        bpl @b
        inc pr
        lda pr
        cmp nr
        beq :+
        jmp @cs
:       rts

        .include "game.s"
