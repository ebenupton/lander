; ============================================================================
; ship.s -- SHIP: Lander's ship, drawn from tools/shipgen.py's tables (every
; orientation pre-rotated and pre-projected) by a triangle rasteriser, on
; LAND's narrow double-buffered MODE 1 screen.  A demo: the ship spins; the
; up and down arrows tilt it.  `shipdraw` and `tri` (shiprast.s) are shared with
; LAND (shipb.s); test/shiptest.py checks them against tools/shipgen.py.
;
; (The drawing itself: shiprast.s.)
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

        .include "shiprast.s"
