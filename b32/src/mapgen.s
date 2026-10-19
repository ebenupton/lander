; mapgen.s: the 64 x 64 map, generated as the camera moves (proto/mapgen.py's,
; exactly).  The window the land reads, 11 columns by 8 corner rows (x WX0 ..
; WX0+10, z WZ0 .. WZ0+7, WX0 = cxt - 4, WZ0 = czt + ZB - 7), is a ring of
; MRING = 88 slots in MC, column-major from slot MWO: corner (x, z) is at MWO +
; 8 (x - WX0) + (z - WZ0), mod 88, and MCB,i is column i's first slot.  The
; slots past the ring's end mirror its first MMIR, so a column or a tile's
; corners read straight on without wrapping.
;
; A slot holds its corner's height (bits 0-3) and, but for the arc build, the
; colour index of the tile whose top left it is (bits 4-7).  The arc build
; keeps the height's terrain kind there instead (the sum's bits 2-3 << 4), with
; bit 6 set for the pad's tiles: crow works the tile out from its corners.
;
; A corner's height counts the thresholds HTL/HTH its terrain sum reaches; the
; sum is six sine terms of p x + q z (mod 64), the first four doubled.  Moving
; the window a column or row makes only the new line's corners and tiles.

MRING   = 88                       ; the ring's slots: 11 columns of 8
.ifdef ARC
MMIR    = 15                       ; the mirror: a tile's corner a column on
.else
MMIR    = 9                        ; the mirror: a tile's corners
.endif

; mwin: the window to the camera: stepped while within 7 columns or rows, else
; made anew (and the first time: MOK 0).  Clobbers A, X, Y, the overlay.
mwin:   lda cxt                    ; the targets WX0, WZ0
        sec
        sbc #4
        and #63
        sta MWT
        lda czt
        clc
        adc ZB
        sec
        sbc #7
        and #63
        sta MWT+1
        lda MOK
        beq @full
        ldy #0                     ; each axis (Y 0: x, 1: z)
@ax:    lda MWT,y
        sec
        sbc MWX,y
        and #63
        beq @nx
        cmp #8
        bcc :+                     ; (C clear: on)
        cmp #64-7
        bcc @full                  ; (C set: back)
:       tya                        ; X = 2 Y + C: mstep's step
        rol a
        tax
        tya
        pha
        jsr mstep
        pla
        tay
        bpl @ax                    ; (always)
@nx:    iny
        cpy #2
        bne @ax
        rts
@full:  lda MWT                    ; anew: every row's corners, then tiles
        sta MWX
        lda MWT+1
        sta MWZ
        lda #0
        sta MWO
        sta MWK
@fc:    lda #0
        ldy MWK
        jsr mset
        jsr mxl
        jsr mcl
        inc MWK
        lda MWK
        cmp #8
        bne @fc
.ifndef ARC
        lda #0
        sta MWK
@ft:    lda #0
        ldy MWK
        jsr mset
        jsr mxl
        dec MGN
        jsr mtl
        inc MWK
        lda MWK
        cmp #7
        bne @ft
.endif
        lda #1
        sta MOK
; mcolb: MCB,i = column i's first slot.  Clobbers A, X.
mcolb:  lda MWO
        ldx #0
:       sta MCB,x
        clc
        adc #8
        cmp #MRING
        bcc :+
        sbc #MRING
:       inx
        cpx #11
        bne :--
        rts
        .assert MWZ = MWX+1, error, "mwin: MWZ after MWX"

; mstep: the window a step, X: 0 a column right, 1 left, 2 a row on, 3 back:
; WX0 or WZ0 and MWO moved, then the new line's corners and the tiles they
; complete.
mstep:  stx MWK
        txa
        lsr a
        tay
        lda MWX,y
        clc
        adc SDL,x
        and #63
        sta MWX,y
        lda MWO
        clc
        adc SWO,x
        cmp #MRING
        bcc :+
        sbc #MRING
:       sta MWO
        lda SCA,x
        ldy SCY,x
        jsr mset
        jsr mdir
        jsr mcl
.ifndef ARC
        ldx MWK
        lda STX0,x
        ldy STY0,x
        jsr mset
        jsr mdir
        dec MGN
        jsr mtl
.endif
        jmp mcolb
mdir:   ldx MWK                    ; a column (z on) for steps 0, 1, a row (x
        cpx #2                     ; on) for 2, 3
        bcs mxl
        bcc mzl                    ; (always)
        .pushseg
        .segment "TABLES"
SDL:    .byte 1, 63, 1, 63         ; by step: WX0 or WZ0's change
SWO:    .byte 8, MRING-8, 1, MRING-1   ; MWO's
SCA:    .byte 10, 0, 0, 0          ; the new corners' first, across and down
SCY:    .byte 0, 0, 7, 0
.ifndef ARC
STX0:   .byte 9, 0, 0, 0           ; the new tiles' first
STY0:   .byte 0, 0, 6, 0
.endif
MWT:    .byte 0, 0                 ; mwin's targets
        .popseg
mxl:    lda #8                     ; a row: 11, x on
        ldy #11
        bne :+                     ; (always)
mzl:    lda #1                     ; a column: 8, z on
        ldy #8
:       sta MGD
        sty MGN
        rts
        .assert MGP = MGQ+7, error, "mcl: MGP = MGQ - 1 + 8"

; mset: MGX, MGZ, MGS for the window's corner A across (0..10), Y down (0..7).
; Clobbers A.
mset:   sta MGT
        clc
        adc MWX
        and #63
        sta MGX
        tya
        clc
        adc MWZ
        and #63
        sta MGZ
        lda MGT
        asl a
        asl a
        asl a
        sty MGT
        clc
        adc MGT
        clc
        adc MWO
        cmp #MRING
        bcc :+
        sbc #MRING
:       sta MGS
        rts

; MADD t: (X:A) += term t's SIN16 + 256.
.macro MADD t
        ldy MGPH+t
        cpy #33
        bcs :+
        inx
:       clc
        adc SL,y
        bcc :+
        inx
:
.endmacro

; mcl: MGN corners from (MGX, MGZ) at slot MGS, each MGD slots and one x
; (MGD 8) or z (1) on: each one's height into its slot.  Clobbers A, X, Y.
mcl:    lda MGX                    ; the phases p x + q z, from 2x, 4x, 8x
        asl a                      ; (MGA, MGB, MGT) and 2z, 4z, 8z (MGU,
        sta MGA                    ; MGW, MGR)
        asl a
        sta MGB
        asl a
        sta MGT
        lda MGZ
        asl a
        sta MGU
        asl a
        sta MGW
        asl a
        sta MGR
        lda MGX                    ; x - 2z
        sec
        sbc MGU
        and #63
        sta MGPH
        lda MGB                    ; 4x + 3z
        clc
        adc MGU
        clc
        adc MGZ
        and #63
        sta MGPH+1
        lda MGU                    ; -5x + 3z
        clc
        adc MGZ
        sec
        sbc MGB
        sec
        sbc MGX
        and #63
        sta MGPH+2
        lda MGT                    ; 7x + 5z
        sec
        sbc MGX
        clc
        adc MGW
        clc
        adc MGZ
        and #63
        sta MGPH+3
        lda MGB                    ; 5x + 11z
        clc
        adc MGX
        clc
        adc MGR
        clc
        adc MGU
        clc
        adc MGZ
        and #63
        sta MGPH+4
        lda MGT                    ; 10x + 7z
        clc
        adc MGA
        clc
        adc MGR
        sec
        sbc MGZ
        and #63
        sta MGPH+5
mcl_c:
.ifndef ARC
        lda MGX                    ; the pad: PADH
        cmp #PADN+1
        bcs :+
        lda MGZ
        cmp #PADN+1
        bcs :+
        lda #PADH
        jmp mcl_s
:
.endif
        ldx #0                     ; the sum: terms 0..3 doubled, then 4, 5
        txa
        MADD 0
        MADD 1
        MADD 2
        MADD 3
        asl a
        sta MGA
        txa
        rol a
        tax
        lda MGA
        MADD 4
        MADD 5
        stx MGB
        sta MGA
        ldy #0                     ; the thresholds reached, by binary search
        cmp HTL+7
        lda MGB
        sbc HTH+7
        bcc :+
        ldy #8
:       lda MGA
        cmp HTL+3,y
        lda MGB
        sbc HTH+3,y
        bcc :+
        iny
        iny
        iny
        iny
:       lda MGA
        cmp HTL+1,y
        lda MGB
        sbc HTH+1,y
        bcc :+
        iny
        iny
:       lda MGA
        cmp HTL,y
        lda MGB
        sbc HTH,y
        bcc :+
        iny
:       tya
.ifdef ARC
        sta MGT                  ; the corner's byte: height | kind << 4 |
        ldx MGZ                    ; $40 for the pad's tiles (x - 1 and z under
        cpx #PADN+1                ; PADN); the pad's corners at PADH
        bcs @k
        lda MGX
        cmp #PADN+1
        bcs @k
        lda #PADH
        sta MGT
        cpx #PADN
        bcs @k
        lda MGX
        beq @k
        lda #$40
        ora MGT
        sta MGT
@k:     lda MGA                    ; kind: the sum's bits 2, 3
        and #12
        asl a
        asl a
        ora MGT
.endif
mcl_s:  ldy MGS
        sta MC,y
        cpy #MMIR                  ; (and its mirror)
        bcs :+
        sta MC+MRING,y
:       jsr mnext
        beq mcl_x
        ldy MGD                    ; the phases a corner on
        .repeat 6, t
        lda MGPH+t
        clc
        adc MGQ-1+t,y
        and #63
        sta MGPH+t
        .endrepeat
        jmp mcl_c
mcl_x:  rts

; mnext: MGN less one (Z set: done), else the slot MGD on (mod MRING: mnm1,
; mnm2's operands) and x or z one on.  Clobbers A, X.
mnext:  dec MGN
        beq mnext_x
        lda MGS
        clc
        adc MGD
mnm1:   cmp #MRING
        bcc :+
mnm2:   sbc #MRING
:       sta MGS
        ldx #0
        lda MGD
        lsr a                      ; (C: MGD 1, z on)
        bcc :+
        inx
:       lda MGX,x
        clc
        adc #1
        and #63
        sta MGX,x
        lda #1                     ; (Z clear)
mnext_x: rts
        .assert MGZ = MGX + 1, error, "mnext: MGZ after MGX"

.ifndef ARC
; mtl: MGN tiles from (MGX, MGZ) at slot MGS (as mcl): each one's colour index
; into its slot's high nibble.  The pad PADI; the sea (all four corners 0)
; SEAI by R1 & 3; land LUT's entry by the quantiles TY and TL reach, TY = 4 R1
; + 60 - the corners' sum, TL = 3 R2 + 7 clamp(6 - slope, 0, 12), the slope
; the left corners' sum less the right's; R1, R2 the nibbles of r = RA[(x +
; RA[z]) & 63].  Clobbers A, X, Y.
mtl:    ldy MGS
        lda MGX                    ; the pad?
        cmp #PADN
        bcs :+
        lda MGZ
        cmp #PADN
        lda #PADI
        bcs :+
        jmp mtl_s
:       ldx MGZ                    ; r
        lda RA,x
        clc
        adc MGX
        and #63
        tax
        lda RA,x
        sta MGR
        lda MC,y                   ; the left corners' sum (MGW), the right's
        and #15                    ; (MGT)
        sta MGT
        lda MC+1,y
        and #15
        clc
        adc MGT
        sta MGW
        lda MC+8,y
        and #15
        sta MGT
        lda MC+9,y
        and #15
        clc
        adc MGT
        sta MGT
        ora MGW
        bne @l
        lda MGR                    ; the sea
        and #3
        tax
        lda SEAI,x
        jmp mtl_s
@l:     lda MGR                    ; TY
        and #15
        asl a
        asl a
        adc #60
        sec
        sbc MGW
        sbc MGT
        ldx #0                     ; qy
        cmp YQT+3
        bcc :+
        ldx #4
:       cmp YQT+1,x
        bcc :+
        inx
        inx
:       cmp YQT,x
        bcc :+
        inx
:       txa
        asl a
        asl a
        sta MGU
        lda #6                     ; c = clamp(6 - left + right, 0, 12)
        clc
        adc MGT
        sec
        sbc MGW
        bpl :+
        lda #0
:       cmp #13
        bcc :+
        lda #12
:       sta MGT                    ; 7 c
        asl a
        asl a
        asl a
        sec
        sbc MGT
        sta MGT
        lda MGR                    ; TL
        lsr a
        lsr a
        lsr a
        lsr a
        sta MGW
        asl a
        adc MGW
        adc MGT
        ldx #0                     ; ql
        cmp LQT+3
        bcc :+
        ldx #4
:       cmp LQT+1,x
        bcc :+
        inx
        inx
:       cmp LQT,x
        bcc :+
        inx
:       txa                        ; LUT: two entries a byte, odd ql high
        lsr a
        ora MGU
        tax
        lda LUT,x
        bcc :+
        lsr a
        lsr a
        lsr a
        lsr a
:       and #15
mtl_s:  asl a                      ; into the slot's high nibble
        asl a
        asl a
        asl a
        sta MGT
        ldy MGS
        lda MC,y
        and #15
        ora MGT
        sta MC,y
        cpy #MMIR
        bcs :+
        sta MC+MRING,y
:       jsr mnext
        beq :+
        jmp mtl
:       rts
.endif

        .pushseg
        .segment "TABLES"
MWX:    .byte 0                    ; the window: WX0, WZ0, its first slot, and
MWZ:    .byte 0                    ; MOK 0 until it is made
MWO:    .byte 0
MOK:    .byte 0
        .include "mapgen.inc"
        .popseg
