; ============================================================================
; ship.s -- SHIP: Lander's ship, drawn from tools/shipgen.py's tables (every
; orientation pre-rotated and pre-projected) by a triangle rasteriser, on
; LAND's narrow double-buffered MODE 1 screen.  A demo: the ship spins; the
; up and down arrows tilt it.  `shipdraw` and `tri` are the parts LAND will
; take (test/shiptest.py checks them against tools/shipgen.py, pixel for pixel).
;
; shipdraw: direction shk (0..SHIP_NDIR-1), pitch shp (0..SHIP_NPITCH-1),
; centre (shx, shy) on the screen whose high byte is scrb ($30 or $58).  The
; ship must lie wholly on the screen (|dx| <= 17, |dy| <= 18 of its centre).
; Its entry e = shp * SHIP_ND2 + KMAP[shk], drawn mirrored (x negated, the
; normals' x signs inverted) if KMIR[shk]; its vertices to VX, VY; then each
; face that shows, in order (the exhaust, 8, with 7), by `tri` in its dither
; (SHD by pitch, face and the normal's x sign; SDE, SDO its bytes).
;
; tri: the triangle (ax, ay), (bx, by), (cx, cy) in ve (even lines) and vo
; (odd), as shipgen.tri: sorted by y; lines ay .. cy-1; on each the long edge
; (a to c) and the short (a to b, then b to c) by Bresenham (x += q, e += r, a
; carry when e reaches dy: x0 + floor(dx * t / dy)); pixels xl <= x < xr.
; ============================================================================
        .setcpu "6502"
        .include "tables.inc"      ; (LAND's: DQT, DRT in bank 4)

OSWRCH  = $FFEE
OSBYTE  = $FFF4
OSCLI   = $FFF7
CRTC_IDX = $FE00
CRTC_DAT = $FE01

        .zeropage
shk:    .res 1                     ; direction, pitch, centre, screen
shp:    .res 1
shx:    .res 1
shy:    .res 1
scrb:   .res 1
mir:    .res 1                     ; mirrored ($FF) or not
vis:    .res 1
neg:    .res 1
shd0:   .res 1                     ; shp * 18: the pitch's SHD
ff:     .res 1                     ; the face
VX:     .res 9
VY:     .res 9
ve:     .res 1                     ; the dither, even and odd lines
vo:     .res 1
ax:     .res 1                     ; the triangle
ay:     .res 1
bx:     .res 1
by:     .res 1
cx:     .res 1
cy:     .res 1
lx:     .res 1                     ; the long edge: x, error, q, r, dy
le:     .res 1
lq:     .res 1
lr:     .res 1
ldy_:   .res 1
sx:     .res 1                     ; the short edge
se:     .res 1
sq:     .res 1
sr:     .res 1
sdy:    .res 1
yy:     .res 1                     ; the line
nn:     .res 1                     ; lines left in this part
xr:     .res 1                     ; the span's end (exclusive)
msk0:   .res 1
lbl:    .res 1                     ; the line's address, less the column's
lbh:    .res 1
colx:   .res 1                     ; ve ^ vo
dq:     .res 2                     ; DQT, DRT's row for the divisor
dr:     .res 2
col:    .res 1
msk:    .res 1
ptr:    .res 2
dvd:    .res 1
dv:     .res 1
tmp:    .res 1
back:   .res 1                     ; (the demo's)
frame:  .res 1
bx0:    .res 2                     ; the box last drawn, by screen: first byte
byt:    .res 2                     ;   column, top line

        .code
        .assert * = $1900, error, "*RUN enters at $1900"
start:  ldx #<cmd_load              ; LAND's TABLES to bank 4 (by $3000)
        ldy #>cmd_load
        jsr OSCLI
        sei
        lda #4
        sta $F4
        sta $FE30
        cli
        lda #$30
        sta ptr+1
        lda #$80
        sta dq+1
        ldy #0
        sty ptr
        sty dq
        ldx #$40
:       lda (ptr),y
        sta (dq),y
        iny
        bne :-
        inc ptr+1
        inc dq+1
        dex
        bne :-
        ldx #0                     ; the palette (!BOOT has set MODE 1)
:       lda vdu_init,x
        jsr OSWRCH
        inx
        cpx #vdu_end-vdu_init
        bne :-
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
        lda #0
        sta shk
        lda #3
        sta shp
        lda #128
        sta shx
        lda #80
        sta shy
loop:   lda #19                    ; the vertical sync, then show the screen drawn
        jsr OSBYTE
        lda #12
        sta CRTC_IDX
        lda back
        eor #1
        sta back
        beq :+
        lda #>($5800/8) - >($3000/8)
:       clc
        adc #>($3000/8)
        sta CRTC_DAT
        lda back                   ; draw the other
        eor #1
        tax
        lda scrs,x
        sta scrb
        jsr unbox                  ; its last ship gone
        inc frame                  ; spin; the arrows tilt
        lda frame
        and #3
        bne :+
        lda shk
        clc
        adc #1
        and #SHIP_NDIR-1
        sta shk
:       lda frame
        and #7
        bne @nk
        ldx #<-58                  ; up: more pitch
        jsr key
        bne :+
        lda shp
        cmp #SHIP_NPITCH-1
        beq :+
        inc shp
:       ldx #<-42                  ; down: less
        jsr key
        bne @nk
        lda shp
        beq @nk
        dec shp
@nk:    jsr shipdraw
        jmp loop

key:    lda #129                   ; Z clear if the key (INKEY X) is down
        ldy #$FF
        jsr OSBYTE
        cpx #$FF
        rts

scrs:   .byte $30, $58
cmd_load: .byte "LOAD TABLES 3000", 13

; The box round the ship on screen scrb black: 12 bytes by 40 lines from its
; centre less 22 pixels, 20 lines; noted for next time.
unbox:  lda back
        eor #1
        tax
        lda byt,x
        sta yy
        lda bx0,x
        sta tmp
        lda #40
        sta nn
@l:     lda yy
        and #7
        ldx tmp
        ora XC8L,x
        sta ptr
        lda yy
        lsr a
        lsr a
        and #$FE
        clc
        adc scrb
        adc XC8H,x
        sta ptr+1
        lda #0
        ldy #0
:       sta (ptr),y
        tya
        clc
        adc #8
        tay
        lda #0
        cpy #12*8
        bne :-
        inc yy
        dec nn
        bne @l
        lda back                   ; this time's
        eor #1
        tax
        lda shx
        sec
        sbc #22
        and #$FC
        sta bx0,x
        lda shy
        sec
        sbc #20
        sta byt,x
        rts

vdu_init:
        .byte 19, 1, 6, 0, 0, 0
        .byte 19, 2, 5, 0, 0, 0
        .byte 19, 3, 3, 0, 0, 0
vdu_end:
crtc_regs:
        .byte 1, 64, 2, 90, 6, 20, 7, 28
        .byte 12, >($3000/8), 13, <($3000/8), 10, $20
crtc_end:

; Both screens black; the boxes somewhere harmless.
init:   lda #0
        tay
        sta ptr
        ldx #$30
        stx ptr+1
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        bpl :-
        lda #0
        sta back
        sta frame
        sta bx0
        sta bx0+1
        sta byt
        sta byt+1
        rts

; ---------------------------------------------------------------- shipdraw
shipdraw:
        ldy shk
        lda shp
        asl a
        asl a
        asl a
        asl a
        adc shp                    ; (C clear: shp < 16)
        .assert SHIP_ND2 = 17, error, "shp * 17"
        adc KMAP,y
        tax                        ; the entry
        lda KMIR,y
        sta mir
        bne @mir
        .repeat 9, i
        lda shx
        clc
        adc .ident(.sprintf("SVX%d", i)),x
        sta VX+i
        .endrepeat
        jmp @y
@mir:   .repeat 9, i
        lda shx
        sec
        sbc .ident(.sprintf("SVX%d", i)),x
        sta VX+i
        .endrepeat
@y:     .repeat 9, i
        lda shy
        clc
        adc .ident(.sprintf("SVY%d", i)),x
        sta VY+i
        .endrepeat
        lda SVIS,x
        sta vis
        lda SNEG,x
        eor mir
        sta neg
        lda shp                    ; shd0 = shp * 18
        asl a
        asl a
        asl a
        adc shp
        asl a
        sta shd0
        ldx #0
@f:     lda vis
        and FBIT,x
        beq @n
        stx ff
        lda neg
        and FBIT,x
        cmp #1                     ; (C: the normal's x < 0)
        txa
        rol a
        adc shd0                   ; (C clear)
        tay
        lda SHD,y
        tay
        lda SDE,y
        sta ve
        lda SDO,y
        sta vo
        eor ve
        sta colx
        ldy FVA,x
        lda VX,y
        sta ax
        lda VY,y
        sta ay
        ldy FVB,x
        lda VX,y
        sta bx
        lda VY,y
        sta by
        ldy FVC,x
        lda VX,y
        sta cx
        lda VY,y
        sta cy
        jsr tri
        ldx ff
@n:     inx
        cpx #9
        bne @f
        rts

FBIT:   .byte $01, $02, $04, $08, $10, $20, $40, $80, $80

; ---------------------------------------------------------------- tri
.macro SWAP p, q
        lda p
        ldx q
        stx p
        sta q
.endmacro

tri:    lda by                     ; sort by y: a top, c bottom
        cmp ay
        bcs :+
        SWAP ax, bx
        SWAP ay, by
:       lda cy
        cmp by
        bcs :+
        SWAP bx, cx
        SWAP by, cy
        lda by
        cmp ay
        bcs :+
        SWAP ax, bx
        SWAP ay, by
:       lda cy
        sec
        sbc ay
        bne :+
        rts                        ; (no lines)
:       sta ldy_                   ; the long edge, a to c
        tay
        lda cx
        sec
        sbc ax
        jsr slope
        sta lq
        stx lr
        lda ax
        sta lx
        lda #0
        sta le
        lda ay                     ; the first line: its address (less the
        and #7                     ; column's), its dither
        sta lbl
        lda ay
        lsr a
        lsr a
        and #$FE
        clc
        adc scrb
        sta lbh
        lda ay
        lsr a
        lda ve
        bcc :+
        lda vo
:       sta col
        lda by                     ; the top part: a to b
        sec
        sbc ay
        beq @p2
        sta nn
        sta sdy
        tay
        lda bx
        sec
        sbc ax
        jsr slope
        sta sq
        stx sr
        lda ax
        sta sx
        lda #0
        sta se
        jsr lines
@p2:    lda cy                     ; the bottom part: b to c
        sec
        sbc by
        beq @d
        sta nn
        sta sdy
        tay
        lda cx
        sec
        sbc bx
        jsr slope
        sta sq
        stx sr
        lda bx
        sta sx
        lda #0
        sta se
        jsr lines
@d:     rts

; A (signed) div Y (1..), floored: A the quotient, X the remainder (0..Y-1).
; By DQT, DRT (Y < 32, |A| < 64), else divs.
slope:  sty dv
        cpy #32
        bcs divs
        sta dvd
        lda DVL,y
        sta dq
        sta dr
        lda DVH,y
        sta dq+1
        lda DVR,y
        sta dr+1
        lda dvd
        bmi @n
        cmp #64
        bcs @s
        tay
        lda (dr),y
        tax
        lda (dq),y
        rts
@n:     eor #$FF                   ; |A|
        adc #1                     ; (C clear)
        cmp #64
        bcs @s
        tay
        lda (dr),y
        beq @x                     ; exact: -q, 0
        eor #$FF                   ; Y - r
        sec
        adc dv
        tax
        lda (dq),y                 ; -q - 1
        eor #$FF
        rts
@x:     tax
        lda (dq),y
        eor #$FF
        adc #1                     ; (C clear)
        rts
@s:     lda dvd
        ldy dv

; A (signed) div Y (1..127), floored, by subtracting: A the quotient, X the
; remainder.
divs:   sty dv
        cmp #$80
        bcs @neg
        jmp divu
@neg:   eor #$FF                   ; -A
        adc #0                     ; (C set: +1)
        jsr divu
        cpx #0
        beq @x                     ; exact: -q, 0
        eor #$FF                   ; -q - 1
        sta tmp
        txa                        ; dv - r
        eor #$FF
        sec
        adc dv
        tax
        lda tmp
        rts
@x:     eor #$FF
        clc
        adc #1
        rts

; A (0..127) div dv: A the quotient, X the remainder.
divu:   sta dvd
        lda #0
        ldx #8
@l:     asl dvd
        rol a
        cmp dv
        bcc :+
        sbc dv
        inc dvd
:       dex
        bne @l
        tax
        lda dvd
        rts

; nn lines from the one at lbl, lbh: the span between the edges, then both
; edges a line on.
lines:
@l:     lda lx                     ; X: xl, Y: xr (lx and sx in order)
        cmp sx
        bne :+
        jmp @st                    ; (empty)
:       bcc :+
        ldx sx
        tay
        bcs @sp
:       tax
        ldy sx
@sp:    lda lbl                    ; the first byte
        ora XC8L,x
        sta ptr
        lda lbh
        clc
        adc XC8H,x
        sta ptr+1
        lda XEL,y                  ; the last's offset
        sec
        sbc XC8L,x
        bne @w
        lda LMT,x                  ; one byte
        and RMX,y
        sta msk
        ldy #0
        lda (ptr),y
        eor col
        and msk
        eor (ptr),y
        sta (ptr),y
        jmp @st
@w:     sty xr
        tay
        lda LMT,x
        sta msk0
        lda (ptr),y                ; the last
        eor col
        ldx xr
        and RMX,x
        eor (ptr),y
        sta (ptr),y
        ldx col                    ; the middle, from the end down
        sec
@m:     tya
        sbc #8                     ; (C stays set)
        tay
        beq @f
        txa
        sta (ptr),y
        bcs @m
@f:     lda (ptr),y                ; the first (Y = 0)
        eor col
        and msk0
        eor (ptr),y
        sta (ptr),y
@st:    lda col                    ; the next line: its dither, address
        eor colx
        sta col
        inc lbl
        lda lbl
        cmp #8
        bne :+
        lda #0
        sta lbl
        lda lbh
        adc #1                     ; (C set: +2)
        sta lbh
:       lda le                     ; the long edge on
        clc
        adc lr
        cmp ldy_
        bcc :+
        sbc ldy_
:       sta le
        lda lx
        adc lq
        sta lx
        lda se                     ; the short
        clc
        adc sr
        cmp sdy
        bcc :+
        sbc sdy
:       sta se
        lda sx
        adc sq
        sta sx
        dec nn
        beq :+
        jmp @l
:       rts

; ---------------------------------------------------------------- tables
        .align 256
XC8L:                              ; x's byte column * 8, low and high
        .repeat 256, v
        .byte <((v >> 2) * 8)
        .endrepeat
XC8H:
        .repeat 256, v
        .byte >((v >> 2) * 8)
        .endrepeat
LMT:                               ; pixels x & 3 .. 3 of x's byte
        .repeat 256, v
        .byte (($F0 >> (v & 3)) & $F0) | ($0F >> (v & 3))
        .endrepeat
XEL:                               ; XC8L of x - 1 (x a span's end)
        .repeat 256, v
        .byte .lobyte((((v - 1) & 255) >> 2) * 8)
        .endrepeat
RMX:                               ; pixels 0 .. (x - 1) & 3
        .repeat 256, v
        .byte (($F0 << (3 - ((v - 1) & 3))) & $F0) | ((($F0 << (3 - ((v - 1) & 3))) & $F0) >> 4)
        .endrepeat

        .include "ship.inc"
