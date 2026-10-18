; ============================================================================
; mapgen.s -- the 64-tile map made on the fly (.included by land.s): an 11 x 8
; window of it kept in MC, 88 slots used as a ring, column-major, the generator
; making the column or row the camera brings into it (proto/mapgen.py's map,
; exactly).
;
; The ring: corner (x, z) of the window (x WX0 .. WX0+10, z WZ0 .. WZ0+7, map
; coordinates mod 64) is at slot MWO + 8 (x - WX0) + (z - WZ0), mod MRING (88):
; a map column's 8 corners are 8 consecutive slots (mod 88) and the corner a
; column on is 8 slots on.  Every access is LDA/STA MC,X or MC,Y with the whole
; slot in the index register, each slot brought back under 88 (CMP, SBC).  A
; slot holds the corner's height (bits 0-3) and its tile's colour index (bits
; 4-7; tile (x, z) between corners x, x+1 and z, z+1: kept for x < WX0+10, z <
; WZ0+7).  The window is exactly what the land reads: WX0 = cxt - 4, WZ0 = czt
; + ZB - 7 (project's columns cxt-4 .. cxt+6 and its 8 corner rows, czt + ZB -
; 7 .. czt + ZB, whose 7 rows of tiles are the strips'), so a reader's slot for
; map row WZ0 + r, column cxt - 4 + i is MWO + 8 i + r.
; ============================================================================

MGPH    = $8E                      ; mcl's phases (6): p x + q z mod 64 a term
MGA     = $94                      ; the sum + 2560, low and high
MGB     = $95
MGX     = $96                      ; the line's map x, z (mod 64)
MGZ     = $97
MGS     = $98                      ; its slot
MGN     = $99                      ; corners or tiles left
MGD     = $9A                      ; the slot's step: 8 (x on) or 1 (z on)
MGT     = $9B                      ; scratch
MGU     = $9C
MGW     = $9D
MGR     = $9E                      ; mtl's random byte
MWK     = $9F                      ; mwin's row
MRING   = 88                       ; the ring's slots: 11 columns of 8

; mwin: the window to the camera (cxt, czt + ZB): stepped a column or row at a
; time while within 8 columns or 7 rows, else made anew, a row at a time (and
; the first time: MOK 0).  Clobbers A, X, Y, $8E-$9E.  Caller: project (after ZB).
mwin:   lda MOK
        beq @full
@xs:    lda cxt                    ; x: cxt - 4 - WX0
        sec
        sbc #4
        sec
        sbc MWX
        and #63
        beq @zs
        cmp #9
        bcc @xp
        cmp #64-8
        bcc @full
        jsr mxm
        jmp @xs
@xp:    jsr mxp
        jmp @xs
@zs:    lda czt                    ; z: czt + ZB - 7 - WZ0
        clc
        adc ZB
        sec
        sbc #7
        sec
        sbc MWZ
        and #63
        beq @x
        cmp #8
        bcc @zp
        cmp #64-7
        bcc @full
        jsr mzm
        jmp @zs
@zp:    jsr mzp
        jmp @zs
@x:     rts
@full:  lda cxt                    ; anew: every row's corners, then tiles
        sec
        sbc #4
        and #63
        sta MWX
        lda czt
        clc
        adc ZB
        sec
        sbc #7
        and #63
        sta MWZ
        lda #0
        sta MWO
        sta MWK
@fc:    lda #0                     ; row k's corners
        ldy MWK
        jsr mset
        jsr mxl
        jsr mcl
        inc MWK
        lda MWK
        cmp #8
        bne @fc
        lda #0
        sta MWK
@ft:    lda #0                     ; rows 0..6's tiles (10 each)
        ldy MWK
        jsr mset
        jsr mxl
        dec MGN
        jsr mtl
        inc MWK
        lda MWK
        cmp #7
        bne @ft
        lda #1
        sta MOK
        rts

; mxp, mxm, mzp, mzm: the window a column right, left, a row on, back: the new
; line's corners, then the tiles they complete.
mxp:    inc MWX
        lda #8
        jsr mwo
        lda #10
        jsr mzc
        lda #9
        bne mzt                    ; (always)
mxm:    dec MWX
        lda #MRING-8               ; (- 8)
        jsr mwo
        lda #0
        jsr mzc
        lda #0
        beq mzt                    ; (always)
mzp:    inc MWZ
        lda #1
        jsr mwo
        ldy #7
        jsr mxc
        ldy #6
        bne mxt                    ; (always)
mzm:    dec MWZ
        lda #MRING-1               ; (- 1)
        jsr mwo
        ldy #0
        jsr mxc
        ldy #0
        beq mxt                    ; (always)
; mwo: MWO + A (A < MRING), mod MRING.  Clobbers A.
mwo:    clc
        adc MWO
        cmp #MRING
        bcc :+
        sbc #MRING
:       sta MWO
        rts
; mzc, mzt: column A's corners (8), tiles (7) (z on); mxc, mxt: row Y's (11,
; 10: x on)
mzc:    ldy #0
        jsr mset
        jsr mzl
        jmp mcl
mzt:    ldy #0
        jsr mset
        jsr mzl
        dec MGN
        jmp mtl
mxc:    lda #0
        jsr mset
        jsr mxl
        jmp mcl
mxt:    lda #0
        jsr mset
        jsr mxl
        dec MGN
        jmp mtl
mxl:    lda #8                     ; x on, 11
        ldy #11
        bne :+                     ; (always)
mzl:    lda #1                     ; z on, 8
        ldy #8
:       sta MGD                    ; (also mcl's phase steps' index)
        sty MGN
        rts
        .assert MGP = MGQ+7, error, "mcl: MGP = MGQ - 1 + 8"

; mset: MGX, MGZ, MGS for the window's corner A across (0..10), Y down (0..7):
; x = WX0 + A, z = WZ0 + Y (mod 64), slot MWO + 8 A + Y (mod MRING).  Clobbers
; A.
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
        adc MGT                    ; 8 A + Y < MRING
        clc
        adc MWO
        cmp #MRING
        bcc :+
        sbc #MRING
:       sta MGS
        rts

.macro MADD t                      ; A, X (low, high) + term t's SIN16 + 256
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
; mcl: MGN corners from (MGX, MGZ) at slot MGS, each next MGD slots on and x or
; z one on (MGD 8 or 1: MGP or MGQ the phases' steps): each height into its
; slot (colour 0).  The height: PADH on the pad (x, z <= PADN),
; else the count of HTL/HTH's thresholds the sum + 2560 reaches, the sum the
; six terms' SIN16 + 256 (MADD's), the four k = 2 terms' doubled.  Clobbers A,
; X, Y.
mcl:    lda MGX                    ; the phases, p x + q z (mod 64), by sums of
        asl a                      ; x, z doubled (gen32 asserts the terms):
        sta MGA                    ; MGA, MGB, MGT 2x, 4x, 8x; MGU, MGW, MGR
        asl a                      ; 2z, 4z, 8z (mod 256: only bits 0-5 matter)
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
mcl_c:  lda MGX                    ; the pad?
        cmp #PADN+1
        bcs :+
        lda MGZ
        cmp #PADN+1
        bcs :+
        lda #PADH
        jmp mcl_s
:       ldx #0                     ; the sum: terms 0..3 (k = 2) doubled, then
        txa                        ; terms 4, 5 (A its low byte, X its high):
        MADD 0                     ; each SL's byte, 256 more for i <= 32
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
        ldy #0                     ; Y: the thresholds reached (T k at HTL + k
        cmp HTL+7                  ; - 1, k 1..15; A = MGA)
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
mcl_s:  ldy MGS
        sta MC,y
        jsr mnext
        beq mcl_x
        ldy MGD                    ; the phases on: MGQ - 1 + MGD + t (MGD 8, x
        .repeat 6, t               ; on: MGP, MGQ + 7; 1, z on: MGQ)
        lda MGPH+t
        clc
        adc MGQ-1+t,y
        and #63
        sta MGPH+t
        .endrepeat
        jmp mcl_c
mcl_x:  rts
; mnext: a line's next: MGN - 1 (Z set: done), else the slot MGD on (mod
; MRING: mnm1, mnm2's operands, gpanel's 128 while it runs) and x (MGD 8) or z
; (1) one on (Z clear after).  Clobbers A, X.
mnext:  dec MGN
        beq mnext_x
        lda MGS
        clc
        adc MGD
mnm1:   cmp #MRING
        bcc :+
mnm2:   sbc #MRING
:       sta MGS
        ldx #0                     ; (MGZ = MGX + 1)
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

; mtl: MGN tiles from (MGX, MGZ) at slot MGS on (as mcl): each one's colour
; index into its slot's high nibble, from its corners (the
; slot, + 1 (z + 1), + 8 (x + 1), + 9, each mod MRING) and r = RA[(x + RA[z]) & 63] (R1, R2 its nibbles): the
; pad PADI (x, z < PADN); the sea (every corner 0) SEAI[R1 & 3]; land LUT's
; entry for qy, ql, the YQT and LQT quantiles TY = 4 R1 + 60 - the corners' sum
; and TL = 3 R2 + 7 clamp(6 - slope2, 0, 12) reach (slope2: the left corners'
; sum less the right's).  Clobbers A, X, Y.
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
        tya                        ; X = the slot 1 on (z + 1)
        clc
        adc #1
        cmp #MRING
        bcc :+
        sbc #MRING
:       tax
        lda MC,y                   ; the left corners' sum (MGW), the right's
        and #15                    ; (MGT)
        sta MGT
        lda MC,x
        and #15
        clc
        adc MGT
        sta MGW
        lda MGS                    ; Y, X: the slots 8 on (x + 1)
        clc
        adc #8
        cmp #MRING
        bcc :+
        sbc #MRING
:       tay
        clc
        adc #1
        cmp #MRING
        bcc :+
        sbc #MRING
:       tax
        lda MC,y
        and #15
        sta MGT
        lda MC,x
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
@l:     lda MGR                    ; TY = 4 R1 + 60 - the sum (0..120)
        and #15
        asl a
        asl a
        adc #60                    ; (C clear: 4 R1 <= 60)
        sec
        sbc MGW
        sbc MGT                    ; (C stays set: TY >= 0)
        ldx #0                     ; X: qy, the YQT thresholds reached
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
        sta MGU                    ; qy << 2
        lda #6                     ; c = clamp(6 - left + right, 0, 12)
        clc
        adc MGT
        sec
        sbc MGW                    ; (-24 .. 36)
        bpl :+
        lda #0
:       cmp #13
        bcc :+
        lda #12
:       sta MGT                    ; 7 c = 8 c - c
        asl a
        asl a
        asl a
        sec
        sbc MGT
        sta MGT
        lda MGR                    ; TL = 3 R2 + 7 c (0..129)
        lsr a
        lsr a
        lsr a
        lsr a
        sta MGW
        asl a
        adc MGW                    ; (C clear: R2 <= 15)
        adc MGT
        ldx #0                     ; X: ql, the LQT thresholds reached
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
:       txa                        ; LUT + (qy << 2 | ql >> 1): odd ql's in the
        lsr a                      ; high nibble (C: ql odd)
        ora MGU
        tax
        lda LUT,x
        bcc :+
        lsr a
        lsr a
        lsr a
        lsr a
:       and #15
mtl_s:  asl a                      ; A: the colour index, into the high nibble
        asl a
        asl a
        asl a
        sta MGT
        ldy MGS
        lda MC,y
        and #15
        ora MGT
        sta MC,y
        jsr mnext
        beq :+
        jmp mtl
:       rts

MWX:    .byte 0                    ; the window: WX0, WZ0, MWO (its slot), MOK
MWZ:    .byte 0                    ; (0: none made yet)
MWO:    .byte 0
MOK:    .byte 0

        .include "mapgen.inc"      ; SL, RA, PADI; the rest's sources (_S, BOOT)
; the tables the loader copies into holes (takeover's mtc): the phases' steps,
; the quantiles, the sea's colours; the height thresholds; the colour table.
        .segment "P2T"
MGQ:    .res 6
        .res 1
MGP:    .res 6
YQT:    .res 7
LQT:    .res 7
SEAI:   .res 4
        .segment "ST2"
HTL:    .res 15
HTH:    .res 15
        .segment "ST0"
LUT:    .res 32
        .code
