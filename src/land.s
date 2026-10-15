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
;   $0700         the frame's rows' points ($07E0 HTN: zsh4's new row of
;                 heights; $0880 HT: the rows' raw heights, project's, kept
;                 while the map rows and columns are); $0900 its strips' boxes and
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
FMIN    = 4                        ; vertical syncs a frame, at least (flip's)
BANK3   = 6                        ; and the ship's (shipb.s: the keys too)
B6_KEYS = $8000
B6_SHIP = $8003
G_INIT  = $A100                    ; bank 5: the game (game.s)
G_STEP  = $A103
G_POST  = $A106
G_PRE   = $A109
BANK7   = 7                        ; and the projection (project's)
BANK2   = 5                        ; and the tiles' colours (project's, a moment)
; (banks 4..7 are logical: each is the socket BANKMAP holds, LANDS's find_ram's)
MOS_ROMTAB = $02A1                 ; the MOS's ROM table: each socket's ROM type
ROMHDR_TYPE = $8006                ; a ROM's type byte, its copyright offset
ROMHDR_COPY = $8007
UVIA_DDRB = $FE62                  ; the user VIA's port B direction (Solidisk)
WRSEL_WATFORD = $FF30              ; a Watford board's write bank: a store to here +
WRSEL_SOLIDISK = $FE60             ; the socket; a Solidisk's: the user VIA's port B
BOARD_STD = 0                      ; (find_ram's: writes through ROMSEL, or as above)
BOARD_WATFORD = 1
BOARD_SOLIDISK = 2

; PAGE n: sideways bank n (4..7) paged for reads and writes (pgN: on a
; write-select board LANDS patches its BIT to the board's store).  A = the
; socket, Z, N as it.
.macro PAGE n
        jsr .ident(.sprintf("pg%d", n))
.endmacro

                                   ; (YSKY, YGND: proto/frame.py's, tables.inc)
MARGIN  = 0                        ; (to the byte boundary: the land extents clear the rest)

ROWA    = $0400
ROWB    = $0500
RTBUF   = $0600
PX      = $0700                    ; the rows', far to near: 16 a row (NZ)
PY      = $0800
HTN     = $07E0                    ; zsh4's: the new row's heights (for hsh)
HT      = $0880                    ; project's: the rows' raw heights (by cxt, czt + ZB)
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
EINL    = $1701                    ; run2's EIN (tables.inc's), here: no page crossed
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
        .assert <EINL + YGND+2 < $100 && LAH + YGND+2 < EINL + YSKY-1, error, "EINL: in its page, past LAH"
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
        lda #<G_PRE                ; the dots beyond the ship (in z)
        jsr call5
        lda GSHV                   ; the ship (not while crashed)
        beq :+
        lda #<B6_SHIP
        jsr call6
:       lda #<G_POST               ; the other dots, the map, the status
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
        PAGE 6
@j:     jsr $8000
        PAGE 4
        rts

; Bank 5's routine at $A100 + A (G_INIT, G_STEP, G_POST: game.s), bank 4 after.
call5:  sta @j+1
        PAGE 5
@j:     jsr G_INIT
        PAGE 4
        rts

; Show the screen just drawn (from the next frame), and draw the other.
flip:   lda vcount                 ; (12.5 frames a second at most: four
        sec                        ; vertical syncs since the last flip, the
        sbc vlast                  ; game's step a frame)
        cmp #FMIN
        bcc flip
        lda #12
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
        sta sh_b+1                 ; (sethalf's: 2 * back)
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
        ldx #YSKY-1                ; run2's EINL: EIN's, by line YSKY-1..YGND+2
        lda #R2OFF                 ; (tools/landgen.py's: lines 2k-1, 2k alike)
        clc
:       sta EINL,x
        sta EINL+1,x
        adc #3                     ; (C clear: < 256)
        inx
        inx
        cpx #YGND+3
        bcc :-
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
; heights) and x's (B1 + (i-1) r, its x * 256 for corner i: B1T, R7L/H), the
; rows overhanging the screen (CLP) clipped (land.clip).  The heights (HT) and
; boxes (CLE, CLO: pcol5's window of rows) are kept while the map's columns
; (cxt) and rows (czt + ZB) are: anew when they change, or (rows a step on or
; back) shifted (zsh4, hsh) and only the new row's made.
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
        adc EYV                     ; (C clear: y's within a byte, or satrow's)
        sta PY+i,x
.endmacro
.macro PYH i                        ; (bank 7) PYS, the height from HT
        ldy HT+i,x
        lda (syp),y
        sta PY+i,x
.endmacro
.macro PYHE i                       ; (bank 7) PYSE, the height from HT
        ldy HT+i,x
        lda (syp),y
        adc EYV
        sta PY+i,x
.endmacro
.macro EDGESP S                     ; (bank 7) EDGES, LERPQ7's row at LQP
        lda S+1,x
        ora #16
        clc
        sbc S,x
        tay
        lda (LQP),y
        adc S,x
        sta PY,x
        lda S+NX-1,x
        ora #16
        clc
        sbc S+NX-2,x
        tay
        lda (LQP),y
        adc S+NX-2,x
        sta PY+NX-1,x
.endmacro
; (bank 7) the edges' y's: their heights from S (LERPQ7 at L0, L1, or LQP's
; row when blank) by SYT7 straight into PY
.macro EDGEY S, L0, L1, NC
        lda S+1,x
        ora #16
.ifblank NC                         ; (NC: C known clear)
        clc
.endif
        sbc S,x
        tay
.ifblank L0
        lda (LQP),y
.else
L0:     lda LERPQ7,y
.endif
        adc S,x
        tay
        lda (syp),y
        sta PY,x
        lda S+NX-1,x
        ora #16
        clc
        sbc S+NX-2,x
        tay
.ifblank L1
        lda (LQP),y
.else
L1:     lda LERPQ7,y
.endif
        adc S+NX-2,x
        tay
        lda (syp),y
        sta PY+NX-1,x
.endmacro
.macro R7BP NOL                     ; (bank 7) the row's r (Y: di) and B1T's page
.ifblank NOL                        ; (NOL: rh alone, the row's x's need no rl)
        lda R7L,y
        sta rl
.endif
        lda R7H,y
        sta rh
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
        lda cxt                    ; the map's heights and boxes as last frame's
        cmp pkx                    ; (the same columns, cxt, and map rows, czt +
        bne @cx                    ; ZB): only prow7
        lda czt
        clc
        adc ZB
        cmp pkz
        bne @zs
        jmp @p7
@zs:    jsr zsh4                   ; (bank 4: a step of one map row, the heights
        bcc @hl                    ; shifted (prow7's hsh) and the new row's
        jmp @p5                    ; loaded: zsh4)
@cx:    sta pkx                    ; the drawn columns' map x
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
        .assert ZBACK-ZSKIP-ZCLIP+1 = 8 && ZFCLIP-ZCLIP+1 = 7, error, "nr 7 or 8"
@hl:    lda czt                    ; (bank 4) each row's heights (HT, all 8 rows):
        clc                        ; row j's map row's pointer at HPZ + 2 j (the
        adc ZB                     ; ship's zero page: scratch), then by column
        sta pkz                    ; (row 7's map row first: czt + ZB - 7)
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
        sta HT+$70,x
        .repeat 7, i
        lda (HPZ+12-2*i),y
        and #15
        sta HT+$60-16*i,x
        .endrepeat
        dex
        bpl @hc
@p5:    PAGE 5                     ; (bank 5) each land strip's boxes (pcol5)
        jsr pcol5
@p7:    PAGE 7                     ; (bank 7) each row's y's and x's (prow7)
        jsr prow7
        PAGE 4
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
        sta pT5c+1
        sta pT6+1
        sta pT6b+1
        lda setTh,y
        sta tsp+1
        sta pT5+2
        sta pT5c+2
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
        sta pT3c+1
        sta pT4+1                  ; each strip's columns are within the next's)
        sta pT4b+1
        lda setTh,y
        sta pT3+2
        sta pT3c+2
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
bclip:  lda BCL                    ; (setup's: a point past YGND seen)
        bne :+
        rts
:       ldy #0
        lda #YGND+1
:       cmp (bota),y
        bcs :+
        sta (bota),y
:       iny
        bne :--
        rts
c_rix:
        ldx ri
        tya
:       inx                        ; (the next rung)
        cmp HI,x
        bcs :-
        stx ri
        lda CE-1,x                 ; (c_one's run2 bytes: box ri - 1's)
        sta RVE
        lda CO-1,x
        sta RVO
        lda HI,x                   ; (rpatch, inline)
        sta c_hi+1
        lda LO,x
        and #$FC
        sta c_lo+1
        jmp c_lo
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
setup:  lda #0                     ; the near strip: the ground below it too
        sta BCL                    ; (bclip's: a bottom row's point past YGND)
        sta rec                    ; (a land strip: record its lines, below)
        tax
        ldy ns
        iny
        cpy nr
        bne :+
        dex
:       stx last
        ; the points and the boxes: a land strip's top row ns-1, bottom row ns,
        ; boxes CLE + 16 * (ns - 1) + box - 1 (CE, CO np: zeroed below)
        lda ns
        beq su_r                     ; (A = 0: row 0)
        cmp nr
        beq su_g
        dec rec                    ; ($FF: a land strip)
        asl a                      ; (C clear: ns < 16)
        asl a
        asl a
        asl a
        adc #$F0                   ; 16 (ns - 1): su_l7's Y
        tay
        PAGE 7                     ; (bank 7: su_l7, unrolled)
        jsr su_l7
        PAGE 4
        jmp su_m
ldCLE:  .byte 0                    ; (pcol5's: 16 o, su_l7's CLE, CLO window)
su_qc:    inc BCL
        bcs su_qb
        ; the sky (row 0 both, the top at YSKY) and the ground (row nr-1
        ; both, the bottom at YGND): boxes black
su_g:     asl a                      ; (C clear: 4 shifts of nr < 16)
        asl a
        asl a
        asl a
        adc #$F0
su_r:     tay
        ldx #1
su_q:     lda PX,y
        sta TX,x
        sta BX,x
        lda PY,y
        sta TY,x
        sta BY,x
        cmp #YGND+1
        bcs su_qc
su_qb:    lda #0
        sta CE,x
        sta CO,x
        iny
        inx
        cpx np1
        bcc su_q
        ldx np
        lda ns
        bne su_gb
        lda #YSKY
:       sta TY,x
        dex
        bne :-
        beq su_m
su_gb:    lda #0                     ; (the ground's bottom: YGND, not past it)
        sta BCL
        lda #YGND
:       sta BY,x
        dex
        bne :-
su_m:
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
su_bot:   lda ns                     ; the bottom row's line
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
        sta jvb+2
        clc                        ; the fills' entries: TENH4 or TENH5
        adc #>TENH4-4
        sta tf_h+2
        sta t1_h+2
        sta tx_h+2
        sta tv_h0+2
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
t_stj:  jmp t_steep                ; (in reach; Y: INC or DEC)
t_o:    jsr t_fl0                  ; (in reach) the run pending, to x0
        jmp t_old
t_dx0:  lda BY+1,x                 ; (none: a margin on the row's end) the run
        cmp tyv                    ; pending ends at x0 if the next y differs
        beq t_nx
        jsr t_fl0
        ldx tj
        lda BX,x
        sta tcnt
        lda BY+1,x                 ; (the next segment's y0)
        sta tyv
t_next: ldx tj
t_nx:   inx                        ; (X = tj already)
        cpx np1
        bcs t_end
t_seg:  stx tj
        lda BX+1,x                 ; (tx1: t_fl0's, for t_old and t_steep)
        sec
        sbc BX,x
        beq t_dx0
        sta terr                   ; dx
        lda BY+1,x                 ; (tyv: BY,x already, every way here)
        sbc BY,x                   ; (C set: dx > 0, the row's x non-decreasing)
        beq t_nx                   ; (level: the run pending goes on)
        ldy #$E6                   ; INC zp
        bcs :+
        eor #$FF                   ; rising: |dy|, DEC
        adc #1
        ldy #$C6
:       cmp terr
        bcs t_stj
        sty t_inc                  ; ($E6 or $C6: +1 or -1 below)
        sta dva                    ; a run a y: the steps at x0 + ceil(dx (2k-1) / 2|dy|)
        tay                        ; (k = 1 .. |dy|; ragged.transitions' sum)
        cmp #1                     ; (|dy| 1: t_one's, any dx)
        beq t_one
        asl a
        sta ra2                    ; (t_old: none of ra2)
        ora terr                   ; |dy| < 32 and dx < 64 (|dy| < dx: 2|dy| < 256
        cmp #64                    ; or dx >= 128)
        bcs t_o
        lda DVH,y                  ; divt's, inline: q, rem = dx div 2|dy|, mod;
        sta t_dq+2                 ; q2, r2 = 2dx's
        adc #>(DRT-DQT)            ; (DVR's: DVH + 8; C clear)
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
        beq :+                     ; rrem: 255 - e, e how far short of the next
        sec                        ; step (2|dy| - rem, or 0): rem - 2|dy| - 1,
        sbc ra2                    ; or $FF (C clear: rem < 2|dy|)
:       sbc #0                     ; (C after: rem > 0)
        sta rrem
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
        txa
        sec
        sbc tcnt
        tay                        ; (TNB = $80: N, Y > TNB, or $80, t_flo's alike)
        bmi t_fl1
        lda TENL,y
        sta tf_j+1
tf_h:   lda TENH4,y
        sta tf_j+2
        clc                        ; (t_inc's)
        ldy dva                    ; (Y: the runs left after this one)
        lda tyv
tf_j:   jmp t_back
t_fl1:  ldy dva                    ; (longer)
        jmp t_flo
t_one:  lda terr
        lsr a                      ; |dy| 1: the first run to x0 + ceil(dx / 2)
        adc BX,x
        tax
        sec
        sbc tcnt
        tay                        ; (TNB = $80: N, Y > TNB, or $80, t_flo's alike)
        bmi t_fl1
        lda TENL,y
        sta t1_j+1
t1_h:   lda TENH4,y
        sta t1_j+2
        ldy #1
        lda tyv
t1_j:   jmp t_back                 ; (its own, as tf_j)
t_fr:   rts                        ; (t_back's: in its page, no page crossed)
t_last: stx tcnt                   ; the last run: pending (at y1)
        jmp t_next
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
        clc                        ; (t_inc's)
t_back:                            ; (the fills' way back: X the run's end)
t_inc:  inc tyv                    ; (INC or DEC: as tr_inc, patched)
        dey
        bmi t_fr
        beq t_last
        lda rrem                   ; the next step: + 2dx / 2|dy|, by e (rrem:
        adc rr2                    ; 255 - e; C clear here, every way in)
        bcs :+
        sta rrem
        txa
        adc rq2                    ; (C clear after: x < 256)
        tax
        lda tyv
jv0:    jmp t_back
        .assert <(jv0+1) <> $FF, error, "jv0's operand across a page"
:       sbc ra2                    ; (C clear after: 2|dy| > r2 > A)
        sta rrem
        lda tyv                    ; q2 + 1: the first here, then jv0's q2
jvb:    sta ROWB,x
        txa
        sec
        adc rq2
        tax
        lda tyv
        jmp (jv0+1)                ; (jv0's target)
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
        adc #>(DRT-DQT)            ; (DVR's: DVH + 8; C clear: D < 64)
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
        lda #$FF                   ; (the first's sentinel leaning left; from
        sta RTBUF+4                ; RTBUF+5, all in RTBUF's page: RTP + x4 + 1,
        lda #<(RTBUF+5)            ; at least alloc - 3 for a rung in the column,
        sta alloc                  ; is too, so fsplit, split, mktr and slow
        lda #>RTBUF                ; need its low byte only)
        sta alloc+1
        sta rtp+1                  ; (split's, mktr's)
        ldx #1
rg_r:     stx tj
        lda BX,x
        cmp TX,x
        bne :+
        sta LO,x                   ; upright: none (its sentinel only)
        sta HI,x
        eor #$FF                   ; RTP = alloc - LO - 1 (its low byte)
        clc
        adc alloc
        sta RTPL,x
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
:       bcc rg_lft
        sta HI,x                   ; leaning right: xt .. xb-1
        sbc TX,x                   ; (C set)
        sta dva                    ; (a)
        tay                        ; (rfastr's)
        lda TX,x
        sta LO,x
        eor #$FF                   ; RTP = alloc - LO - 1
        clc
        adc alloc
        sta RTPL,x
        jmp rfastr                 ; (bank 4: a <= RFA, D < 16; else back,
rg_lft:   sta LO,x                   ; leaning left: xb .. xt-1
        eor #$FF                   ; RTP = alloc - LO - 1 (C clear: bcc)
        adc alloc
        sta RTPL,x
        sec
        lda TX,x
        sta HI,x
        sbc BX,x
        sta dva                    ; (a)
        tay                        ; (rfastl's)
        jmp rfastl                 ; (bank 4: a <= RFA, D < 16; else back,
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
        tya                        ; alloc += a + 1 (in RTBUF's page)
        sec
        adc alloc
        sta alloc
rg_nx:    ldx tj
        inx
        cpx np1
        bcs :+
        jmp rg_r
:       rts
rg_lslj:  jmp rg_lsl                   ; (in reach)
        .res 3                     ; (keeps the layout)
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
        sta oz1b+2
        sta oz2b+2
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
        ldx #0                     ; c_lv, o_lv; c_np (patched only when the
        bit last                   ; kind changes: lvk's): 0 TAX / INX / STX
        bpl :+                     ; flr1, LDA x4 / CLC; 1 bclip's JSR flrc /
        ldx #2                     ; NOP; 2 the near strip's STA flr / STA flr1
        bne @lvk                   ; (the floor itself if level), JMP nearpost
:       lda BCL
        beq @lvk
        inx
@lvk:   cpx #$FF                   ; (the kind patched: $FF none yet)
        beq @lvd
        stx @lvk+1
        lda lvt0,x
        sta c_lv
        sta o_lv
        lda lvt1,x
        sta c_lv+1
        sta o_lv+1
        lda lvt2,x
        sta c_lv+2
        sta o_lv+2
        lda lvt3,x
        sta c_lv+3
        sta o_lv+3
        lda npt0,x
        sta c_np
        lda npt1,x
        sta c_np+1
        lda npt2,x
        sta c_np+2
@lvd:
        lda xlp                    ; record below xlp or from xrp on (strip 1: all,
        ldx ns                     ; to xr): phase's
        dex
        bne :+
        lda xr
:       sta ph_lo+1
        lda xrp
        sta ph_hi+1
        ldx #0
        stx ri
        jsr rpatch                 ; (c_coly's: rung 0's; c_one's RVE, RVO:
                                   ; the first column's c_rix's)
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
        ldx #<o_nr                 ; (o_rec's high byte: record's too)
        stx o_rec+1
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
        ldx #<record               ; (its high byte: o_nr's too)
        stx o_rec+1
        .assert >record = >o_nr, error, "record, o_nr: one page (phase)"
        ldx #<recordc
        stx c_rec+1
        ldx #>recordc
        stx c_rec+2
        rts
c_dbl:  cmp LO+2,x                  ; (A: x4 | 3, c_split's)
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

; A land strip's column: its highest and lowest lines into CURT, CURB (cols'
; inline, Y = x4: o_rec's, one box, on to o_nr, c_coly's tests made, ri and
; Y kept; recordc, c_rec's, likewise; the black above, rare: c_rd's tests).
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
        bcs o_nr                   ; (one box: o_rec's)
        bcc rc_t
c_ri:   inx                        ; (the next rung)
        cmp HI,x
        bcs c_ri
        stx ri
        jsr rpv                    ; (and c_one's RVE, RVO)
        tya
        jmp c_rr
c_v1:   .byte $40                  ; (BIT: V)
c_ld:   lda CE-1,x                 ; (fsplit's, split's: a rung's boxes alike)
        sta RVE
        lda CO-1,x
        sta RVO
        bvc c_r1
c_z1:    jmp zone1                  ; (a top not level; back to c_r1)
c_srx:  ldx ri                     ; (c_coly's)
        tya
        ora #3
c_split: cmp LO+1,x
        bcs c_dbl
        bvs :+
fsplit: cpx lastri                 ; (fsplit's test, inline: back to c_next)
        beq :++
        jmp fs_ns
:       jmp split
:       jmp fs_c

rc_t:   tax
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
o_nr:                              ; one box: ri - 1 (RVE, RVO its already: set
c_one:                             ; whenever ri changes, c_rix, c_ri; fe_r, fr
c_on:   bvs c_z1                   ; only in a column rung ri is in)
c_r1:    ldx mx
c_r1x:  cpx flr1                   ; (zone1's: X = mx)
        bcs c_next
        ldy flr1
run2:
pX:     cpx #$FF                   ; (je, jo already X's)
        beq pY
        stx pX+1
        lda EINL,x
        sta je+1
        lda EINL-1,x                ; (OIN)
        sta jo+1
pY:     cpy #$FF                   ; (the RTSes already at Y's)
        beq pY_k
        sty pY+1
        lda #OP_STAY               ; the last back
pr0:    sta $FFFF                  ; (rE: the low byte EIN's)
pr1:    sta $FFFF                  ; (rO)
        lda #OP_RTS
        ldx EINL,y
        stx pr0+1
pp0:    sta $FF00,x
        ldx EINL-1,y
        stx pr1+1
pp1:    sta $FF00,x
pY_k:   lda #0                     ; (RVE: the even lines' byte, and RVO the
RVE     = pY_k+1                   ; odd's: c_rix, c_ri, c_ld, fe_r, fr)
        ldy coff
je:     jsr $FFFF
rvo:    lda #0
RVO     = rvo+1
jo:     jsr $FFFF                  ; (inline: on to c_next; fe_r's too)
c_next:
c_np:   jmp nearpost               ; (cols: LDA x4 / CLC, the next column's,
                                   ; inline, but in the near strip; back to c_xe)
c_nd1:  adc #4                     ; (c_np's LDA x4 / CLC: the next column)
        sta x4
c_xe:   cmp #0                     ; (phase: xlp, xrp or xr)
        beq c_lim
c_xt:   tay
        asl a                      ; 8 * column
        sta coff
        beq c_nh
c_coly:                            ; (V clear: the adc #4 above, or sethalf's
                                   ; last sbc) the rungs: past those wholly left
c_hi:   cpy #0                     ; (rpatch's: rung ri's HI)
        bcs c_ri0
c_lo:   cpy #0                     ; (rpatch's: its LO & $FC; LO <= x4 + 3,
        bcs c_sp                   ; a rung in the column)
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
c_nd:   lda x4                     ; the next column (nearpost's)
        clc
        jmp c_nd1
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
o_zt:   jmp oz_x                   ; (one box, its top not level: oz_x)
o_zb:   bcs :+                     ; (one box, its floor not level; C: p0 > p3)
obz:    lda ROWB+3,y               ; the lowest
:       sta flr                    ; (as c_zb)
        tax
        inx
        cpx #YGND+2
        bcs ob_cl
ob_st:  stx flr1
        jmp o_rec
ob_cl:  dex                        ; (rare)
        dec flr
        bcs ob_st                  ; (C set)
c_ri0:  jmp c_rix                   ; (in reach)

c_sp:                              ; a rung in the column: the top level?
pt0:    lda ROWA,y
pt1:    cmp ROWA+1,y
        bne c_zt
pt2:    cmp ROWA+2,y
        bne c_zt2
pt3:    cmp ROWA+3,y
        bne c_zt3
        sta mx                     ; (mn: mx, V clear)
c_ft:                               ; the floor: level?
pb0:    lda ROWB,y
pb1:    cmp ROWB+1,y
        bne zb1c                   ; (into c_zb past the compares made: C kept)
pb2:    cmp ROWB+2,y
        bne zb2c
pb3:    cmp ROWB+3,y
        bne zb3c
c_lv:   tax                        ; (level; cols: STA flr / STA flr1 in the near
        inx                        ; strip, its ground's from the floor's line on;
        stx flr1                   ; flr only nearpost's)
c_rec:  jmp recordc                ; a column new this frame (strip 1's, or
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
c_zt2:  sta ys                     ; (the first two level: as c_zt, on at zt2)
        sta ys+1
        sta mn
        sta mx
        bit c_v1
        jmp zt2
c_zt3:  sta ys                     ; (the first three level: on at zt3)
        sta ys+1
        sta ys+2
        sta mn
        sta mx
        bit c_v1
        jmp zt3

c_zb:                               ; (rare) the lowest (A: the first's; cols:
zb1:    cmp ROWB+1,y               ; zb1-3 this strip's)
zb1c:   bcs :+
        lda ROWB+1,y
:
zb2:    cmp ROWB+2,y
zb2c:   bcs :+
        lda ROWB+2,y
:
zb3:    cmp ROWB+3,y
zb3c:   bcs :+
        lda ROWB+3,y
:       sta flr                    ; (not level)
        tax
        inx
        cpx #YGND+2                ; (at most YGND+1, and flr then YGND: bclip's;
        bcs zb_cl                  ; nearpost's not level kept)
zb_st:  stx flr1
        jmp c_rec
zb_cl:  dex                        ; (rare)
        dec flr
        bcs zb_st                  ; (C set)
; The near strip's column, drawn (to the line before its floor if its bottom
; row is level there, else to the floor): below the near row black (the line
; at the floor, or the pixels at or below their bottom-row line, read-modify-
; write); then black to the land's lowest line last time (BOTS); CURB.  (cols'
; inline: back to c_nd.)
np_b:     ldx x4                     ; the land's lowest line now, and last time's
        ldy DIV4,x
        lda flr
        cmp #YGND+1                ; (on the screen: bclip's)
        bcc pB4
        lda #YGND
        bcs pB4
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
        txa                        ; (flr)
        ldx x4                     ; (np_b's: flr on the screen here)
        ldy DIV4,x
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
        jmp c_nd
np_n:   lda x4                     ; (C set: + 4)
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

; c_coly's tests for rung X (ri): its HI, and its LO's byte column (x4 a
; multiple of 4: LO <= x4 + 3 iff LO & $FC <= x4).
rpv:    lda CE-1,x                 ; (c_one's run2 bytes: box ri - 1's)
        sta RVE
        lda CO-1,x
        sta RVO
rpatch: lda HI,x
        sta c_hi+1
        lda LO,x
        and #$FC
        sta c_lo+1
        rts

; The column's half of the screen: A (0 left, 1 right).
sethalf:
sh_b:   ora #0                     ; t: the STAB (its ENTBt, EXHBt, LAHSBt):
        tay                        ; 2 * back + half (setback's)
        lda shs,y
        sta scrh
        clv                        ; (c_coly's)
        lda enthh,y               ; (ENTBt's low bytes all ENTB0's)
        sta r_eh1+2
        lda exhl,y
        sta r_eh2+1
        lda exhh,y
        sta r_eh2+2
        lda #OP_STAY               ; run2's RTSes back (its pages change)
        ldx pr0+1
sh_1:   sta TPE0*256,x
        ldx pr1+1
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
        lda lahsh,y               ; (LAHSBt's low bytes all LAHSB0's)
        sta fs_h+2
        sta z1_h+2
        sta np_h+2
        sta np_h2+2
        sta rc_h+2
        sta sl_h+2
        rts
lvt0:   .byte $AA, $20, $85        ; (cols': c_lv, o_lv by kind)
lvt1:   .byte $E8, <flrc, flr
lvt2:   .byte $86, >flrc, $85
lvt3:   .byte flr1, $EA, flr1
npt0:   .byte $A5, $A5, $4C        ; (c_np's)
npt1:   .byte x4, x4, <nearpost
npt2:   .byte $18, $18, >nearpost
shs:    .byte $30, $31, $58, $59   ; (scrb + half, by t)
sht:    .byte >STAB, (>STAB)+2, (>STAB)+4, (>STAB)+6 ; (stb0 + 2 * half)
tpe:    .byte TPE0, TPE1, TPE2, TPE3 ; (tools/landgen.py's)
tpo:    .byte TPO0, TPO1, TPO2, TPO3
exhl:   .byte <(EXHB0), <(EXHB1), <(EXHB2), <(EXHB3)
exhh:   .byte >(EXHB0), >(EXHB1), >(EXHB2), >(EXHB3)
        .assert <(LAHSB0) = <(LAHSB1) && <(LAHSB0) = <(LAHSB2) && <(LAHSB0) = <(LAHSB3), error, "LAHSB lows"
lahsh:  .byte >(LAHSB0), >(LAHSB1), >(LAHSB2), >(LAHSB3)
        .assert <(ENTB0) = <(ENTB1) && <(ENTB0) = <(ENTB2) && <(ENTB0) = <(ENTB3), error, "ENTB lows"
enthh:  .byte >(ENTB0), >(ENTB1), >(ENTB2), >(ENTB3)

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
fs_c:   lda #0                     ; (C set) fl_e, fl_o's operands = RTP + x4
rbl     = *-1                      ; (- 1 leaning left) (fs_new's: the rung's
        adc x4                     ; transitions, less 1 (2 leaning left); in
        sta fl_e+1                 ; RTBUF's page: rungs')
        sta fl_o+1
        clc
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
fwx_e:  lda BE,x                   ; fwe >= 8: to the row's end, then fw_c
        sta (zp_),y
        iny
fwx_o:  lda BO,x
        sta (zp_),y
        iny
        cpy #8
        bne fwx_e
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
fw_e:   lda BE,x                   ; an even line (fwe < 8: within the row)
        sta (zp_),y                ; (the row's line Y)
        iny
        cpy fwe
        beq fn_o
fw_o:   lda BO,x                   ; an odd line
        sta (zp_),y
        iny
        cpy fwe
        bne fw_e
fn_e:                              ; Y even
fst_e:  inx                        ; (or DEX: fs_new)
fen_e:  cpx #4                     ; (or 0)
        beq fe_x
fl_e:   lda RTBUF,x                ; the transition's line, t (operand: fs_c's)
        cmp flr1
        bcs fe_x
        sbc rsm                    ; (C clear) t, in the row (fwe)
        sta fwe
        cpy fwe
        bcs fn_e                   ; (at or above Y: bpos only)
        cmp #8
        bcc fw_e                   ; (walked, within the row)
        cmp #8+FSRJ
        bcc fwx_e                  ; (walked, crossing a row at most)
        bcs fr
fn_o:                              ; Y odd
fst_o:  inx                        ; (or DEX: fs_new)
fen_o:  cpx #4                     ; (or 0)
        beq fe_x
fl_o:   lda RTBUF,x
        cmp flr1
        bcs fe_x
        sbc rsm
        sta fwe
        cpy fwe
        bcs fn_o
        cmp #8
        bcc fw_o
        cmp #8+FSRJ
        bcc fwx_o
fr:     stx bpos                   ; (C set) lines Y .. t-1, a run
        adc rsm
        sta fwu                    ; t
        lda BE,x
        sta RVE
        lda BO,x
        sta RVO
        tya
        sec
        adc rsm                    ; the line
        tax
        ldy fwu
        lda c_np                   ; (rare: run2 is inline, on to c_np: an
        pha                        ; RTS meanwhile)
        lda #OP_RTS
        sta c_np
        jsr run2
        pla
        sta c_np
        ldy fwu
        lda LAH,y                  ; the walker from t (rare: not sethalf's)
        clc
        adc scrh
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
        cmp #9
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
        beq ff_d
fe_r:   lda BE,x                   ; the floor's run
        sta RVE
        lda BO,x
        sta RVO
        tya
        adc rsm                    ; (C set: fe_x's bcs)
        tax
        ldy flr1
        jmp run2                   ; (on to c_next)
ff_d:   jmp c_np                   ; (c_next; s2v's: s2ov)
fs_ee:  lda BE                     ; (fs_new's: the rung's two boxes' even
        sta BE+1                   ; bytes alike)
        sta BE+2
        sta BE+3
        jmp fs_co
fs_oe:  lda BO                     ; (the odd alike)
        sta BO+1
        sta BO+2
        sta BO+3
        jmp fs_ln
fs_ns:  lda CE-1,x                 ; (fsplit's, a new rung: its boxes the same, the
        cmp CE,x                   ; column one box: c_ld's, V clear)
        bne fs_new
        lda CO-1,x
        cmp CO,x
        bne fs_new
        jmp c_ld
fs_new: stx lastri                 ; the rung's bytes by bpos: 0 the right box,
        lda CE-1,x                 ; 4 the left (Y: the two EORed)
        sta BE+4
        lda CE,x
        sta BE
        eor BE+4
        beq fs_ee                  ; (the two boxes alike: BE+1..3 = BE)
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
fs_co:  lda CO-1,x
        sta BO+4
        lda CO,x
        sta BO
        eor BO+4
        beq fs_oe                  ; (alike: BO+1..3 = BO)
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
fs_ln:  lda BX,x
        cmp TX,x
        bcs fs_nr
        lda RTPL,x                 ; leaning left: x4 + bpos - 1, bpos - 1 after
        sbc #0                     ; (C clear: - 2)
        sta rbl
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
        sta rbl                    ; changes, bpos + 1 after (- 1; C set)
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
        .res 1                     ; (spare: keeps the code after in place)

; The top zone of a one-box column: lines mn .. min(mx, flr1)-1, each the
; pixels at or below their top (pmask, zline inline; cols' inline: back to c_r1).
zone1:  ldx mn                     ; (mn < mx: a top not level; msk: mn's,
        cpx flr1                   ; o_zt's or split's)
        bcs z1_n                   ; (and mx: c_r1's run empty)
z1_h:   lda LAHSB0,x               ; (zline; sethalf's, the screen and half's)
        sta zp_+1
        txa
        and #7
        sta zp_
        lsr a                      ; (C: an odd line)
        ldy coff
        lda (zp_),y
        bcs z1_o
        eor RVE
        and msk
        eor (zp_),y
        sta (zp_),y
        inx
        cpx mx
        bcc z1_m
        jmp c_r1x                  ; (X = mx: c_r1's run)
z1_o:   eor RVO
        and msk
        eor (zp_),y
        sta (zp_),y
        inx
        cpx mx
        bcc z1_m
        jmp c_r1x                  ; (X = mx: c_r1's run)
z1_m:   ldy x4                     ; (rare: lines past mn) each pixel's top
        lda (topa),y
        sta ys
        iny
        lda (topa),y
        sta ys+1
        iny
        lda (topa),y
        sta ys+2
        iny
        lda (topa),y
        sta ys+3
z1_l:   cpx flr1
        bcs z1_n
        jsr pmask
        jmp z1_h
z1_n:   jmp c_np

oz_x:   bcs oz_dn                  ; (o_zt's: one box, its top not level; C: p0 > p3)
        sta mn                     ; the highest and lowest, and msk: zone1's
oz3a:   ldx ROWA+3,y               ; first line's (mn's) pixels, those at mn: the
        stx mx                     ; top monotonic, from p0 (mn p0) or p3 (mn p3)
oz1:    ldx ROWA+1,y
        lda #$88
        cpx mn
        bne oz_m
oz2:    ldx ROWA+2,y
        lda #$CC
        cpx mn
        bne oz_m
        lda #$EE
        bne oz_m
oz_dn:    sta mx
oz3b:   ldx ROWA+3,y
        stx mn
oz2b:   ldx ROWA+2,y
        lda #$11
        cpx mn
        bne oz_m
oz1b:   ldx ROWA+1,y
        lda #$33
        cpx mn
        bne oz_m
        lda #$77
oz_m:     sta msk
        bit c_v1                   ; (V: a top not level)
        jmp o_ft

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
        lda CE-1,x                 ; (its boxes the same: one box, c_ld's, V set:
        cmp CE,x                   ; zone1)
        bne :+
        lda CO-1,x
        cmp CO,x
        bne :+
        ldx mn                     ; (zone1's msk: mn's)
        jsr pmask
        ldx ri
        jmp c_ld
:
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
        sta rtp                    ; (rtp+1: rungs')
        sta fl_e+1
        sta fl_o+1
        clc
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
sl_h:   lda LAHSB0,x               ; (zline; sethalf's, the screen and half's)
        sta zp_+1
        txa
        and #7
        sta zp_
        lsr a
        ldy bpos
        lda BE,y
        bcc :+
        lda BO,y
:       sta zv
        ldy coff
        lda (zp_),y
        eor zv
        and msk
        eor (zp_),y
        sta (zp_),y
        ldy bpos
        rts

; Rung X's transitions in the column into TRL, TRB (bpos as its LM mask) from
; A, ended by $FF; A: LM of its position in the column at the top (p0).
mktr:   sta tj
        lda RTPL,x                 ; (rtp: RTP + x4, by position)
        sec
        adc x4
        sta rtp                    ; (rtp+1: rungs')
        clc
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
        stx yy                     ; (the transitions at mx first: then each
                                   ; next past yy)
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
:       tay                        ; (past yy: kk, kb caught to it, yy < flr1)
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

; Lines X .. Y-1 (X < Y), as run, in two passes: the even lines (ve), then the
; odd (vo), each through its table for the screen and half (tools/landgen.py's,
; sethalf's pages: pr0, pp0, je; pr1, pp1, jo), from EIN, OIN + X to an RTS
; planted at EIN, OIN + Y (OIN = EIN - 1; rE, rO; pY: the line they are for,
; kept while the next run2's end is the same; put back by the next run2's that
; ends elsewhere, or sethalf).

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

; record's, c_rec's (a rung in the column): on to c_srx (c_coly's tests made,
; ri and Y kept), or the black above (rare) as record's.
recordc: ldx DIV4,y
        lda mx
        bvc :+
        lda mn
:
pT3c:   sta CURT,x
pT5c:   lda TOPS,x
        cmp mx
        bcc :+
        jmp c_srx
:       jmp rc_t

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

; ---------------------------------------------------------------- readout
; At each flip: the vertical syncs since the last (dvs, the last 8); the
; readout: 400 / their sum, frames a second, to a tenth (FPSL, FPSH: 4000 /
; sum), at the top left.
G_DOT   = 10                       ; (the readout's characters, GLY: LANDS's
G_SP    = 11                       ; glyphs makes them)
G_F     = 12

readout:
        lda fpson                  ; (off: blanks, game.s's F)
        bne @on
        sta tcol
:       lda #G_SP
        jsr putg
        lda tcol
        cmp #8
        bne :-
        rts
@on:    ldx #7                     ; the sum
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
; Character A at column tcol of character row 2 of the screen drawn.
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
        lda scrb                   ; (character row 2)
        clc
        adc #4
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

pkx:    .byte $FF                  ; project's: cxt, czt + ZB its heights (HT) and
pkz:    .byte $FF                  ; boxes (CLE, CLO) are for
SHF:    .byte 0                    ; (zsh4's: HT a row on (1) or back ($FF), HTN)
fps10:  .res 2                     ; (the readout's)
fpson:  .byte 1                    ; (the readout on: game.s's F toggles it)
BANKMAP: .byte 4, 5, 6, 7          ; the sockets of banks 4..7 (LANDS's find_ram)
wrt:    .byte 0                    ; (PAGE's BIT, on a plain machine)
.repeat 4, k                       ; pg4..pg7: bank 4+k paged, write selected
        .ident(.sprintf("pg%d", k+4)):
        lda BANKMAP+k
        sta ROMCOPY
        sta ROMSEL
        .ident(.sprintf("pw%d", k+4)):
        bit wrt                    ; (LANDS: a board's STA)
        rts
.endrepeat
dvs:    .res 8
dvi:    .res 1
vlast:  .res 1
tcol:   .res 1

        .assert * <= $3000, error, "code over the screen"

; ---------------------------------------------------------------- s2v
; (bank 4, its free space) A column two rungs split (ri, ri+1), its top level:
; fsplit's for ri+1 (boxes M, R), then box L over the pixels left of ri at
; each line (mktr's transitions, from TRL; bpos2 the LM mask; le, lo2 L's
; bytes; fsplit's end, ff_d, at s2ov meanwhile).
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
        lda c_np                   ; fsplit's end here: c_np an RTS meanwhile
        pha                        ; (ff_d's, run2's)
        lda #OP_RTS
        sta c_np
        ldx ri
        inx
        cpx lastri                 ; (fsplit's, but not fs_ns's)
        bne :+
        jsr fs_c
        jmp s2ov
:       jsr fs_new
s2ov:   pla                        ; (c_np's again)
        sta c_np
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
; LANDS: the start, run once from $7000 (!BOOT: MODE 1, the palette black and
; the cursor off, *LOAD LAND, *RUN LANDS): the four sideways banks found
; (find_ram, from beebgame's loader: any sockets, written through ROMSEL or a
; Watford or Solidisk board's write select) and every PAGE's write select
; patched for the board; the banks loaded (each file *LOADed to $3000, below
; this, and copied); the readout's characters; the screen narrowed and
; cleared; the palette; then LAND's `go` (whose init clears the screens, this
; with them).
        .segment "BOOT"
start:  lda ROMCOPY
        sta old_bank
        jsr find_ram               ; the four banks into BANKMAP -- or C = 1, fewer
        bcc :+
        jmp no_ram
:       jsr wpatch                 ; PAGE's write selects, for the board
        ldx #<cmd_load7             ; TABLES7 to bank 7, SHIPB to bank 6,
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
        jsr glyphs
        PAGE 5                     ; the game's letters, in bank 5
        jsr glyphs5
        PAGE 4
        ldx #0                     ; narrow the screen: 64 bytes by 20 rows
:       lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne :-
        lda #$30                   ; the shown screen ($3000..$57FF) cleared, then
        sta ptr+1                  ; the palette (the loads' $3000 unseen)
        ldy #0
        sty ptr
        tya
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        ldx ptr+1
        cpx #$58
        bne :-
        ldx #0
:       lda vdu_init,x
        jsr OSWRCH
        inx
        cpx #vdu_end-vdu_init
        bne :-
        jmp go

cmd_load: .byte "LOAD TABLES 3000", 13
cmd_load3: .byte "LOAD SHIPB 3000", 13
cmd_load7: .byte "LOAD TABLES7 3000", 13
cmd_load2: .byte "LOAD TABLES2 3000", 13

; *LOAD (X, Y: the command) to $3000, then the 16K there to bank A (4..7: its
; socket, which is left paged in and write selected).
ldbank: pha
        jsr OSCLI
        pla
        tax
        lda BANKMAP-4,x
        tax
        sei
        jsr selwr
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
rfastr: cpy #RFA+1                  ; (Y: a, rungs')
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
        ldy alloc                  ; (RFBODY's: alloc in RTBUF's page)
@j:     jmp FR0
@sl:    lda dva
        asl a
        sta ra2
        jmp rg_rdr
rfastl: cpy #RFA+1                  ; (Y: a, rungs')
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
        ldy alloc
@j:     jmp FL0
@sl:    lda dva
        asl a
        sta ra2
        jmp rg_rdl
B16:    .repeat RFA, i
        .byte 16 * (RFA - 1 - i)
        .endrepeat
DUFR:   .repeat RFA, i
        .byte <(FR0 + 8 * (RFA - 1 - i))
        .endrepeat
DUFL:   .repeat RFA, i
        .byte <(FL0 + 8 * (RFA - 1 - i))
        .endrepeat
.macro RFBODY T
        .repeat RFA, i                 ; (Y: alloc, the rung's first byte in RTBUF's page)
        lda .ident(.sprintf("%s%d", T, RFA - 1 - i)),x
        adc rrem                   ; (C clear: no carry)
        sta RTBUF + RFA - 1 - i,y
        .endrepeat
        tya                        ; the sentinel (alloc + a), alloc += a + 1
        sec
        adc dva
        sta alloc
        tay
        lda #$FF
        sta RTBUF-1,y
        ldx tj                     ; the next rung (rungs' @nx)
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
        .assert LQOFF = 15, error, "EDGES, zlerp, flerp: LQOFF 15 (b + 16 - a - 1)"
; (bank 7) Each row's y's (SYT7) and x's (fast, or clipr), the near clip's row
; (RN) the last, on its plane, and the far clip's (row 0 with FACT) on its.
CX2     = $8E                      ; (bank 7, prow7's: 2 cxs, the camera higher
CAMF    = $8F                      ; ($80: MODE's bit 7), 16 RN, a normal row's
RN16    = $90                      ; di, MODE (bit 0: the clip's row's heights
DCUR    = $92                      ; lerped, zlerp's or flerp's; bit 6 a clip's
MODE    = $93                      ; row; bit 7 the camera higher), the edges'
LQP     = $94                      ; LERPQ7 row, B1T's row, 11 cxs)
bp      = $96
CX11    = $98
E0      = $99                      ; (zlerp's, flerp's: the edges' heights)
E1      = $9A
E2      = $9B
E3      = $9C
HOFF    = $9E                      ; (bank 7: hgnd's HMAX - hg; project's scratch)
prow7:  lda SHF                    ; (zsh4's: the heights a row on or back)
        beq :+
        jsr hsh
:       ldy cxs                    ; LERPQ7's row for fx: q = cxs (the edges')
        lda LQHI,y
        sta @lq2+2
        sta @lq3+2
        sta LQP+1
        lda LQLO,y
        sta @lq2+1
        sta @lq3+1
        sta LQP
        tya
        asl a
        sta CX2                    ; (2 cxs: B1T's; 11 cxs: PXF7, PXN7's)
        asl a
        asl a
        adc CX2                    ; (C clear: cxs < 16)
        adc cxs
        sta CX11
        jsr hgnd                   ; the ground under the ship (HOFF)
        lda #0                     ; (MODE's bit 7: the camera higher)
        ldx CAME
        beq :+
        lda #$80
:       sta CAMF
        lda RN                     ; the near clip's row's heights (zlerp's,
        asl a                      ; into PY), and the far clip's (flerp's)
        asl a
        asl a
        asl a
        sta RN16
        lda czs                    ; (zlerp's, flerp's LERPQ7 row: q = 16 - czs)
        beq :+
        lda #16
        sec
        sbc czs
        tay
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
:       lda #NX                    ; (always: the strips' np)
        sta np
        lda #0                     ; row 0: di = 16 ZB - DI0 - czs (the rows
        sta tmp                    ; after: 16 less each), or the far clip's
        lda ZB                     ; plane's
        sec
        sbc #9
        asl a
        asl a
        asl a
        asl a
        sbc #DI0-9*16-1            ; (C clear: - (DI0 - 144))
        .assert DI0 > 9*16 && ZFCLIP >= 9 && ZBACK-ZSKIP >= 9, error, "di's arithmetic"
        sec
        sbc czs
        sta DCUR
        tay
        lda FACT                   ; (MODE's bit 0: the heights in PY, not HT;
        beq :+                     ; bit 6: the far clip's plane, x by cxs)
        ldy #ZFCLIP*16-DI0
:       cpy #ZFCLIP*16-DI0
        bne :+
        ora #$40
:       ora CAMF
        sta MODE
        eor #$40                   ; the far clip's row (MODE $40, $41: not
        cmp #2                     ; the camera higher) straight to its
        bcs @row                   ; heights (C set at @row)
        lsr a                      ; (C: FACT's)
        lda #<(SYT7+32*(ZFCLIP*16-DI0))
        ora HOFF
        sta syp
        lda #>(SYT7+32*(ZFCLIP*16-DI0))
        sta syp+1
        ldx #0
        bcs :+
        jmp @hp0
:       jmp @apf
@altj:  jmp @alt
; A row: Y its di, tmp 16 j (its place in PX, PY), MODE; C set.
@row:   lda SYL7,y                 ; di * 32: the row's SYT7 (+ HMAX - hg: 0..15,
        sta bp                     ; di*32's low 5 bits 0) and B1T
        ora HOFF
        sta syp
        lda SYH7,y
        sta syp+1
        adc #>B1T - >SYT7 - 1      ; (C set: B1T's page; C clear after)
        sta bp+1
        ldx tmp                    ; the edges' heights: corners 1 to 2, and 10
        lda MODE                   ; to 11, by fx (LERPQ7: land.lerp), from HT
        bne @altj                  ; (or PY: a clip's row) into PY
        R7BP 1                     ; (r: the clips' rows' x's not by it)
        EDGEY HT, @lq2, @lq3, 1
        .repeat NX-2, i
        PYH i+1
        .endrepeat
@pyd:   ldy CX2                    ; x: corner 1's (B1T: B's carries, then x),
        lda (bp),y                 ; then + rh and B's carry each (the carries
        sta rl                     ; out of B's low byte, + rl each: bit k
        iny                        ; corner k+2's; no carry out of the high:
        lda (bp),y                 ; corners 1..NX-2 on, 8 bits; rl after: 0)
        sta PX+1,x
        .repeat NX-3, k
        lsr rl
        adc rh
        sta PX+2+k,x
        .endrepeat
        ldy DCUR                   ; the edges' x: -XCLIP, +XCLIP (di: DCUR)
        lda PINL7,y
        sta PX,x
        lda PINR7,y
        sta PX+NX-1,x
        cpy #NCLP                  ; past the screen's edges (CLP7: di < NCLP):
        bcs @nx                    ; clipr
        jsr clipr
        ldx tmp
        sec
@nx:    txa                        ; the next row (X: tmp, C set; the near
        adc #15                    ; clip's the last: its x's @pxn's)
        sta tmp
        cmp RN16
        beq @lst
        lda DCUR
        sbc #15                    ; (C clear: - 16)
        sta DCUR
        tay
        jmp @row
@lst:   bit CAMF                   ; the near clip's: on its plane (not the
        bmi @lsc                   ; camera higher: straight to its heights,
        tax                        ; X: RN16, MODE 0)
        lda #<(SYT7+32*(ZCLIP*16-DI0))
        ora HOFF
        sta syp
        lda #>(SYT7+32*(ZCLIP*16-DI0))
        sta syp+1
        lda czs
        bne :+
        jmp @hp0
:       jmp @apz
@lsc:   ldy #ZCLIP*16-DI0
        lda czs                    ; (zlerp's heights: none at czs 0)
        beq :+
        lda #1
:       ora #$40                   ; (x by cxs)
        ora CAMF
        sta MODE
        jmp @row
@fin:   ldx RN16                   ; the near clip's row: a line or more below
        .repeat NX, i              ; the row before (254 at most: 255 at most)
        lda PY-16+i,x
        cmp PY+i,x
        bcc :+
        adc #0                     ; (C set: + 1)
        sta PY+i,x
:
        .endrepeat
        lda FACT                   ; the far clip's row: a line or more above
        bne :+                     ; row 1
        rts
:
        .repeat NX, i
        ldx PY+16+i
        dex
        cpx PY+i
        bcs :+
        stx PY+i
:
        .endrepeat
        rts
@alt:   bpl :+                     ; the clips' rows (bit 6), or the camera higher
        jmp @cam
:       lsr a                      ; (the clips' rows: heights from HT or PY)
        bcc @hp0
        jmp @ap
@hp0:
        EDGEY HT
        .repeat NX-2, i
        PYH i+1
        .endrepeat
        jmp @pxc
@ap:    txa                        ; their heights by 1 - fz between the rows
        bne :+                     ; either side (zlerp, flerp: corners 1..NX-2
@apf:   jsr flerp                  ; straight to y; the edges' heights at E0..E3)
        jmp :++
:
@apz:   jsr zlerp
:       lda E1                     ; the edges: their heights by fx, their y's
        ora #16
        clc
        sbc E0
        tay
        lda (LQP),y
        adc E0
        tay
        lda (syp),y
        sta PY,x
        lda E3
        ora #16
        clc
        sbc E2
        tay
        lda (LQP),y
        adc E2
        tay
        lda (syp),y
        sta PY+NX-1,x
        bit MODE                   ; (the camera higher: EYV more, eyrow's)
        bmi :+
        jmp @pxc
:       jsr cliprow7               ; (EYV more, each held at 254)
        jmp @pxc
@cam:   R7BP
        jsr eyrow                  ; (X kept)
        lda MODE
        lsr a
        bcc :+
        jmp @ap
:
        EDGESP HT
        lda EYV                    ; (a y could pass 254: satrow's)
        cmp #EYS
        bcc :+
        jsr satrow
        jmp @cx
:       clc                        ; (EDGESP's C: PYSE's)
        .repeat NX, i
        .if i = 0 || i = NX-1
        PYSE i
        .else
        PYHE i
        .endif
        .endrepeat
@cx:    bit MODE
        bvs @pxc
        jmp @pyd
; The clips' rows' x's: on their planes (row 0, di ZFCLIP*16-DI0; row RN, di
; ZCLIP*16-DI0), by cxs alone (PXF7, PXN7 + 11 cxs: PINL7, B1 + (i-1) r, PINR7;
; never clipr's).
        .assert NX = 11, error, "PXF7, PXN7: 11 cxs"
@pxc:   lda CAMF
        sta MODE
        ldy CX11
        cpx #0
        bne @pxn
        .repeat NX, i
        lda PXF7+i,y
        sta PX+i
        .endrepeat
        jmp @nx
@pxn:   .repeat NX, i              ; (the near clip's: the last)
        lda PXN7+i,y
        sta PX+i,x
        .endrepeat
        jmp @fin


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
        rts

; The heights (HT) a row on (SHF 1: row j + 1 row j's, row 0 HTN) or back
; ($FF: row j row j + 1's, row 7 HTN): zsh4's.
hsh:    ldx #NX-1
        lda SHF
        bmi @b
@o:     .repeat 7, k
        lda HT+16*(6-k),x
        sta HT+16*(7-k),x
        .endrepeat
        lda HTN,x
        sta HT,x
        dex
        bpl @o
        bmi @d
@b:     .repeat 7, k
        lda HT+16*(k+1),x
        sta HT+16*k,x
        .endrepeat
        lda HTN,x
        sta HT+$70,x
        dex
        bpl @b
@d:     lda #0
        sta SHF
        rts

; The ground under the ship (land.ground: ZSHIP ahead at the camera's x, corner
; rows j ZBACK - ZSHIP and the next farther, columns CX 4 + (cxs >= 8) and the
; next, across by (cxs + 8) & 15 sixteenths, then down by czs: LERPQ7), and
; every raw height (rows 0..nr-1) less it, + HMAX (SYT7's index).
hgnd:   lda ZB                     ; its row: ZBACK - ZSHIP less the first's j
        sec                        ; (ZBACK - ZB): 16 (ZB - ZSHIP), + its column:
        sbc #ZSHIP                 ; 4, or 5 at cxs >= 8
        asl a
        asl a
        asl a
        asl a
        adc #4                     ; (C clear: ZB - ZSHIP < 16)
        ldy cxs
        cpy #8
        adc #0
        tax                        ; X: 16 r + its column
        lda cxs                    ; across: q = (cxs + 8) & 15
        eor #8
        tay
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
        lda HT+1,x                 ; the near corners ((b + 16) - a - 1: b - a
        ora #16                    ; + LQOFF)
        clc
        sbc HT,x
        tay
        lda (lp),y
        adc HT,x
        sta tmp+1                  ; (hx0)
        lda HT-15,x                ; the far corners (the row before: 16 back)
        ora #16
        clc
        sbc HT-16,x
        tay
        lda (lp),y
        adc HT-16,x                ; (hx1)
        ora #16
        clc
        sbc tmp+1
        sta tmp
        ldy czs                    ; down: q = czs
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
        ldy tmp
        lda (lp),y
        adc tmp+1                  ; hg
        sta HGV
        eor #$FF                   ; HMAX - hg: prow7's SYT7 offset (the
        sec                        ; heights stay raw)
        adc #HMAX
        sta HOFF
        rts

; The near clip's row (X: RN16; its SYT7 row at syp): its heights from the row
; before's by 1 - fz (land.lerp, LERPQ7: q = 16 - czs, lp; czs not 0), corners
; 1..NX-2 by SYT7 into PY, the edges' heights (0, 1, NX-2, NX-1) at E0..E3.
.macro LERPY SA, SB, CI, IX
.if IX
        lda SB+CI,x                  ; (b + 16) - a - 1: b - a + LQOFF
        ora #16
        clc
        sbc SA+CI,x
        tay
        lda (lp),y
        adc SA+CI,x
.else
        lda SB+CI
        ora #16
        clc
        sbc SA+CI
        tay
        lda (lp),y
        adc SA+CI
.endif
.if CI = 0
        sta E0
.elseif CI = NX-1
        sta E3
.else
.if CI = 1
        sta E1
.elseif CI = NX-2
        sta E2
.endif
        tay
        lda (syp),y
.if IX
        sta PY+CI,x
.else
        sta PY+CI
.endif
.endif
.endmacro
zlerp:  .repeat NX, i
        LERPY HT-16, HT, i, 1
        .endrepeat
        rts

; The far clip's row (row 0; its SYT7 row at syp): to row 1's by 1 - fz (land.lerp,
; LERPQ7: q = 16 - czs, lp; fz not 0), as zlerp.
flerp:  .repeat NX, i
        LERPY HT, HT+16, i, 0
        .endrepeat
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


; (bank 7) setup's land strip, unrolled (np = NX): Y = 16 (ns - 1), rows ns-1
; and ns (PX, PY) into TX..BY 1..np (BCL: a bottom point past YGND), then the
; boxes CLE, CLO + 16 (ns - 1) + 16 o (ldCLE) into CE, CO 1..np.  In
; five: B7CODE's end, then R7L, R7H, PINL7, PINR7's spare (di >= NDI = 176).
        .assert NX = 11 && NDI = 176, error, "su_l7: unrolled for NX, NDI"
.macro SUPX i
        lda PX+i,y
        sta TX+1+i
        lda PY+i,y
        sta TY+1+i
        lda PX+16+i,y
        sta BX+1+i
        lda PY+16+i,y
        sta BY+1+i
        cmp #YGND+1
        bcc :+
        inc BCL
:
.endmacro
.macro SUCL i
        lda CLE+i,y
        sta CE+1+i
        lda CLO+i,y
        sta CO+1+i
.endmacro
        .segment "B7CODE"
su_l7:
.repeat 8, i
        SUPX i
.endrep
        jmp su_l7a
        .segment "B7A"
su_l7a: SUPX 8
        SUPX 9
        jmp su_l7b
        .segment "B7B"
su_l7b: SUPX 10
        tya
        clc
        adc ldCLE
        tay
.repeat 3, i
        SUCL i
.endrep
        jmp su_l7c
        .segment "B7C"
su_l7c:
.repeat 6, i
        SUCL i+3
.endrep
        jmp su_l7d
        .segment "B7D"
su_l7d: SUCL 9
        SUCL 10
        rts

; (bank 7, CLP7's spare) The camera raised so far a corner's y could pass 254
; (EYV >= EYS): prow7's row X (16 j) by SYT7 (syp) + EYV, each held at 254
; (land.project's: below the screen, the bottom clip's), the edges' heights
; EDGESP's (PY), the rest's HT.  X kept.
        .segment "B7E"
satrow: stx MT1
        ldy PY,x
        jsr sat1
        lda #NX-2
        sta MT0
:       inx
        ldy HT,x
        jsr sat1
        dec MT0
        bne :-
        inx
        ldy PY,x
        jsr sat1
        ldx MT1
        rts
sat1:   lda (syp),y                ; PY,x: y Y's + EYV, 254 at most
sat2:   clc                        ; (A + EYV)
        adc EYV
        bcs :+
        cmp #255
        bcc :++
:       lda #254
:       sta PY,x
        rts
; The clips' rows' y's (PY, X: 16 j) EYV more, each 254 at most; X back from tmp.
cliprow7:
        lda #NX
        sta MT0
:       lda PY,x
        jsr sat2
        inx
        dec MT0
        bne :-
        ldx tmp
        rts
; ---------------------------------------------------------------- the slow way
; (bank 4, its free space, in two: never seen)
        .segment "B4Z"
; (bank 4, its free space) project's map rows a row on (A: czt + ZB, pkz + 1)
; or back (pkz - 1), its columns as before: the new row's heights (row 0's,
; map row czt + ZB; or row 7's, czt + ZB - 7) into HTN, SHF for prow7's hsh,
; pkz; C set.  Else C clear (all anew).
zsh4:   tay
        sec
        sbc pkz
        sty pkz
        cmp #1
        beq @ld
        cmp #$FF
        bne @no
        tya
        sbc #7                     ; (C set)
        tay
        lda #$FF
@ld:    sta SHF
        tya
        and #63
        tay
        lda MRL,y
        sta HPZ
        lda MRH,y
        sta HPZ+1
        ldx #NX-1
:       ldy CX,x
        lda (HPZ),y
        and #15
        sta HTN,x
        dex
        bpl :-
        sec
        rts
@no:    clc
        rts

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
        lda RTPL,x                 ; (RTP + tx1 + 1: in RTBUF's page)
        sec
        adc tx1
        sty tmp
        tay
        lda RTBUF,y
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
pcol5:  lda cxt                    ; a window of 10 rows (m: map row WK - m, by
        cmp WX                     ; columns CX at WX) at CLE, CLO + 16 m, rows
        beq :+                     ; VLO..VHI made; the strips' land rows 1..7
        jmp @f
:
        lda WK                     ; (row k = m - o: map row czt + ZB - 1 - k)
        clc                        ; at o = WK - (czt + ZB) + 1, 0..3
        sbc czt                    ; (C clear: - 1)
        sec
        sbc ZB
        clc
        adc #2
        cmp #4
        bcc :+                     ; (o out of the window: all anew)
        lda cxt
        jmp @f
:
        sta WO
        tax                        ; the rows o.. before VLO
:       cpx VLO
        bcs :+
        txa
        jsr crow
        inx
        bne :-
:       lda WO                     ; and from VHI + 1 to o + 6
        adc #6                     ; (C set: + 7)
        sta WE
        ldx VHI
:       inx
        cpx WE
        bcs :+
        txa
        jsr crow
        jmp :-
:       lda WO                     ; (the made rows grown to o..o+6 at least)
        cmp VLO
        bcs :+
        sta VLO
:       ldx WE
        dex
        cpx VHI
        bcc @pt
        stx VHI
@pt:    lda WO                     ; the strips' (setup's): CLE, CLO + 16 o
        asl a
        asl a
        asl a
        asl a
        sta ldCLE
        rts
@f:     sta WX                     ; all anew: o 1, WK czt + ZB, rows 1..7
        lda czt
        clc
        adc ZB
        sta WK
        lda #1
        sta WO
        sta VLO
        lda #7
        sta VHI
        ldx #1
:       txa
        jsr crow
        inx
        cpx #8
        bne :-
        jmp @pt
        .assert <CLE = 0 && <CLO + 48 < $100, error, "pcol5: setup's operands"
; Window row m (A): map row WK - m, CMAPE, CMAPO by CX into CLE, CLO + 16 m.
crow:   sta WM
        asl a
        asl a
        asl a
        asl a
        sta @se+1
        clc
        adc #<CLO
        sta @so+1
        lda #>CLO
        adc #0
        sta @so+2
        lda WK
        sec
        sbc WM
        and #63
        tay
        lsr a
        lsr a
        ora #>CMAPE
        sta @le+2
        ora #>$1000
        sta @lo+2
        tya
        lsr a
        ror a
        ror a
        and #$C0
        sta @le+1
        sta @lo+1
        txa
        pha
        ldx #NX-2
@c:     ldy CX,x
@le:    lda CMAPE,y
@se:    sta CLE,x
@lo:    lda CMAPO,y
@so:    sta CLO,x
        dex
        bpl @c
        pla
        tax
        rts
WX:     .byte $FF                  ; the window's columns' cxt (none yet), map row
WK:     .byte 0                    ; at m 0, o, the rows made, o + 7, crow's m
WO:     .byte 0
VLO:    .byte 0
VHI:    .byte 0
WE:     .byte 0
WM:     .byte 0
        .assert * <= $A100, error, "pcol5: bank 5 from $A100 the game's"

        .include "game.s"

; ---------------------------------------------------------------- LANDS's RAM
; (Cribbed from beebgame's loader.s, github.com/ebenupton/beebgame: find_ram,
; selwr, wrx; here a socket holding a ROM the MOS runs is never taken.)
        .segment "BOOT"
NSOCK   = 16
SIG_TAG = $C0                      ; a socket's signature: its number, tagged
CLASS_FREE = 0                     ; RAM with no ROM image
CLASS_IMAGE = 1                    ; RAM with an image the MOS is not running
CLASS_ROM = 2                      ; (RAM with a ROM the MOS runs: never taken)
CLASS_NONE = $FF                   ; not RAM (bit 7 also: an alias, SIG_TAG | n)

; selwr: socket X paged for reads and writes (wrx: the write select alone, on
; the board find_ram found).  A X; Y kept.
selwr:  stx ROMCOPY
        stx ROMSEL
wrx:    lda board
        lsr a                      ; plain: 0, C = 0; Watford: 0, C = 1;
        bcc @sol                   ; Solidisk: 1, C = 0
        sta WRSEL_WATFORD,x        ; (Watford: the address says which)
@sol:   beq @done
        stx WRSEL_SOLIDISK         ; (Solidisk: port B bits 0-3)
@done:  rts

; find_ram: C = 0: BANKMAP the four sockets (the lowest free ones, then the
; lowest holding images), board the write select; C = 1 fewer.  As beebgame's:
; a socket takes a write if bit 0 of its ROM type byte flips (and is put back);
; the board the way that finds the most sockets (plain winning a tie); two
; numbers reaching one RAM told by a tagged signature, the higher dropped.
find_ram:
        sei
        lda #BOARD_STD
        sta board
        sta bestb
        jsr @count
        sta best
        inc board                  ; BOARD_WATFORD
        jsr @count
        cmp best
        bcc @solid
        beq @solid
        sta best
        inc bestb
@solid: lda #$0F                   ; Solidisk: port B bits 0-3 out
        sta UVIA_DDRB
        inc board                  ; BOARD_SOLIDISK
        jsr @count
        cmp best
        beq @nsol
        bcs @class
@nsol:  lda bestb
        sta board
        inx                        ; (X = 0: @count leaves $FF) port B back
        stx UVIA_DDRB
@class: ldx #NSOCK-1
@sock:  lda #CLASS_NONE
        sta SOCKCLASS,x
        jsr @selflip
        bne @snext
        lda MOS_ROMTAB,x           ; a ROM the MOS runs
        beq @image
        lda #CLASS_ROM
        bne @cls
@cstr:  .byte 0, "(C)"             ; (never executed)
@image: stx tmp                    ; an image: 0 "(C)" at the copyright offset
        ldy ROMHDR_COPY
        ldx #<-4
@cchk:  lda $8000,y
        cmp @cstr+4-256,x
        bne @free
        iny
        inx
        bne @cchk
        lda #CLASS_IMAGE
        .byte $2C                  ; (BIT abs: the LDA skipped)
@free:  lda #CLASS_FREE
        ldx tmp
@cls:   sta SOCKCLASS,x
@snext: dex
        bpl @sock
        ldx #NSOCK-1               ; the signatures: each RAM socket's ROMHDR_COPY
@sig:   lda SOCKCLASS,x            ; saved and its number written there, tagged
        bmi @signx
        jsr selwr
        lda ROMHDR_COPY
        sta SAVED,x
        txa
        ora #SIG_TAG
        sta ROMHDR_COPY
@signx: dex
        bpl @sig
        ldx #NSOCK-1
@chk:   lda SOCKCLASS,x
        bmi @chknx
        stx ROMCOPY
        stx ROMSEL
        txa
        ora #SIG_TAG
        cmp ROMHDR_COPY
        beq @chknx
        sta SOCKCLASS,x            ; (an alias of a lower number)
@chknx: dex
        bpl @chk
        inx                        ; restored in reverse: aliases unwind
@res:   ldy SOCKCLASS,x
        iny
        beq @resnx
        jsr selwr
        lda SAVED,x
        sta ROMHDR_COPY
@resnx: inx
        cpx #NSOCK
        bne @res
        lda old_bank
        sta ROMCOPY
        sta ROMSEL
        cli
        ldy #CLASS_FREE            ; the lowest free sockets, then images
        sty want
@cl:    ldx #0
@pick:  lda SOCKCLASS,x
        cmp want
        bne @pnext
        txa
        sta BANKMAP,y
        iny
        cpy #4
        beq @found
@pnext: inx
        cpx #NSOCK
        bne @pick
        inc want
        lda want
        cmp #CLASS_ROM
        bne @cl
        sec                        ; fewer than four
        rts
@count: lda #0                     ; A = the sockets taking a write, the board as
        sta want                   ; set (X = $FF after)
        ldx #NSOCK-1
@cnt:   jsr @selflip
        bne @cntnx
        inc want
@cntnx: dex
        bpl @cnt
        lda want
        rts
@selflip:                          ; Z = 1: socket X takes a write
        jsr selwr
        lda ROMHDR_TYPE
        tay
        eor #1
        sta ROMHDR_TYPE
        cmp ROMHDR_TYPE
        sty ROMHDR_TYPE
@found: clc
        rts

; wpatch: each PAGE's BIT made the board's write select: a Watford's STA
; WRSEL_WATFORD + the bank's socket, a Solidisk's STA WRSEL_SOLIDISK (A is the
; socket there); a plain machine's left.
wpatch: lda board
        beq @r
        ldx #3
@l:     lda wrsl,x
        sta ptr
        lda wrsh,x
        sta ptr+1
        ldy #0
        lda #$8D                   ; STA abs
        sta (ptr),y
        lda board
        cmp #BOARD_SOLIDISK
        beq @s
        lda BANKMAP,x
        ora #<WRSEL_WATFORD
        ldy #1
        sta (ptr),y
        iny
        lda #>WRSEL_WATFORD
        bne @h
@s:     ldy #1
        lda #<WRSEL_SOLIDISK
        sta (ptr),y
        iny
        lda #>WRSEL_SOLIDISK
@h:     sta (ptr),y
        dex
        bpl @l
@r:     rts

; no_ram: fewer than four banks: say so (MODE 1's palette black: back to
; white first), and back to the MOS.
no_ram: ldx #0
:       lda msg_ram,x
        beq :+
        jsr OSWRCH
        inx
        bne :-
:       rts
msg_ram: .byte 20, 23, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0
        .byte "LAND needs 64K of sideways RAM:", 13, 10
        .byte "four 16K banks, any sockets, writable", 13, 10
        .byte "(through &FE30, or a Watford or", 13, 10
        .byte "Solidisk board).", 13, 10, 0

old_bank: .byte 0
board:  .byte 0
want:   .byte 0
best:   .byte 0
bestb:  .byte 0
SOCKCLASS: .res NSOCK
SAVED:  .res NSOCK
; pg4..pg7's BITs
wrsl:   .byte <pw4, <pw5, <pw6, <pw7
wrsh:   .byte >pw4, >pw5, >pw6, >pw7
