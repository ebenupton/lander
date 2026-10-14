; ============================================================================
; shiprast.s -- the ship's drawing (included by ship.s, the demo, and shipb.s,
; LAND's bank 6): `shipdraw`, `tri`, their tables, and tools/shipgen.py's
; ship.inc.  The includer declares the variables (the hot ones in zero page)
; and DVH, DVR, DVL, DQT, DRT (D div a, D mod a: tools/landgen.py's layout).
;
; shipdraw: direction shk (0..SHIP_NDIR-1), pitch shp (0..SHIP_NPITCH-1),
; centre (shx, shy) on the screen whose high byte is scrb ($30 or $58).  The
; ship must lie wholly on the screen (|dx| <= 17, |dy| <= 18 of its centre).
; Its entry e = shp * SHIP_ND2 + KMAP[shk], drawn mirrored (each span's pixels
; mirrored about shx, the normals' x signs inverted) if KMIR[shk]; its
; vertices to VX, VY; then each
; face that shows, in order (the exhaust, 8, with 7), by `tri` in its dither
; (SHD by pitch, face and the normal's x sign; SDE, SDO its bytes).
;
; tri: the triangle (ax, ay), (bx, by), (cx, cy) in ve (even lines) and vo
; (odd), as shipgen.tri: sorted by y; lines ay .. cy-1; on each the long edge
; (a to c) and the short (a to b, then b to c) by Bresenham (x += q, e += r, a
; carry when e reaches dy: x0 + floor(dx * t / dy)); pixels xl <= x < xr.
; ============================================================================

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
        lda shx                    ; (2 shx + 1: a mirrored span's)
        sec
        rol a
        sta s2
        .repeat 9, i
        lda shx
        clc
        adc .ident(.sprintf("SVX%d", i)),x
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
@sp:    bit mir                    ; mirrored: pixels xl..xr-1 to
        bpl @sp2                   ; 2 shx - xr + 1 .. 2 shx - xl
        stx tmp
        sty xr
        lda s2
        sec
        sbc xr
        tax
        lda s2
        sec
        sbc tmp
        tay
@sp2:   lda lbl                    ; the first byte
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
