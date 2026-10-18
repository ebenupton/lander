; ============================================================================
; mapgen.s -- the 64-tile map made on the fly (.included by land.s): a 16 x 16
; window of it kept in MC, one page used as a ring, the generator making the
; column or row the camera brings into it (proto/mapgen.py's map, exactly).
;
; The ring: corner (x, z) of the window (x WX0 .. WX0+15, z WZ0 .. WZ0+15, map
; coordinates mod 64) is at slot MWO + 16 (z - WZ0) + (x - WX0), mod 256: a map
; row's 16 corners are 16 consecutive slots (mod 256) and the corner a row on is
; 16 slots on.  MC + 256 .. MC + 272 mirror slots 0..16, so any 17 consecutive
; slots read straight through from MC + the first.  A slot holds the corner's
; height (bits 0-3) and its tile's colour index (bits 4-7; tile (x, z) between
; corners x, x+1 and z, z+1: kept for x < WX0+15, z < WZ0+15).  The window
; follows the camera: WX0 = cxt - 5, WZ0 = czt + 5 (project's columns cxt-4 ..
; cxt+6 and map rows czt+7 .. czt+18 inside it), so a reader's slot for map row
; czt + 5 + r, column cxt - 4 is MWO + 16 r + 1.
; ============================================================================

MGPH    = $8E                      ; mcl's phases (6): p x + q z mod 64 a term
MGA     = $94                      ; the sum + 2560, low and high
MGB     = $95
MGX     = $96                      ; the line's map x, z (mod 64)
MGZ     = $97
MGS     = $98                      ; its slot
MGN     = $99                      ; corners or tiles left
MGD     = $9A                      ; the slot's step: 1 (x on) or 16 (z on)
MGT     = $9B                      ; scratch
MGU     = $9C
MGW     = $9D
MGR     = $9E                      ; mtl's random byte

; mwin: the window to the camera (cxt, czt): stepped a column or row at a time
; while within 8, else made anew (and the first time: MOK 0).  Clobbers A, X,
; Y, $8E-$9E.  Caller: project.
mwin:   lda MOK
        beq @full
@xs:    lda cxt                    ; x: cxt - 5 - WX0
        sec
        sbc #5
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
@zs:    lda czt                    ; z: czt + 5 - WZ0
        clc
        adc #5
        sec
        sbc MWZ
        and #63
        beq @x
        cmp #9
        bcc @zp
        cmp #64-8
        bcc @full
        jsr mzm
        jmp @zs
@zp:    jsr mzp
        jmp @zs
@x:     rts
@full:  lda cxt                    ; anew: every row's corners, then tiles
        sec
        sbc #5
        and #63
        sta MWX
        lda czt
        clc
        adc #5
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
        cmp #16
        bne @fc
        lda #0
        sta MWK
@ft:    lda #0                     ; rows 0..14's tiles
        ldy MWK
        jsr mset
        jsr mxl
        dec MGN
        jsr mtl
        inc MWK
        lda MWK
        cmp #15
        bne @ft
        lda #1
        sta MOK
        rts

; mxp, mxm, mzp, mzm: the window a column right, left, a row on, back: the new
; line's corners, then the tiles they complete.
mxp:    inc MWX
        inc MWO
        lda #15
        jsr mzc
        lda #14
        bne mzt                    ; (always)
mxm:    dec MWX
        dec MWO
        lda #0
        jsr mzc
        lda #0
        beq mzt                    ; (always)
mzp:    inc MWZ
        lda MWO
        clc
        adc #16
        sta MWO
        ldy #15
        jsr mxc
        ldy #14
        bne mxt                    ; (always)
mzm:    dec MWZ
        lda MWO
        sec
        sbc #16
        sta MWO
        ldy #0
        jsr mxc
        ldy #0
        beq mxt                    ; (always)
; mzc, mzt: column A's corners, tiles (z on); mxc, mxt: row Y's (x on)
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
mxl:    lda #1                     ; x on, 16
        ldx #<MGP
        bne :+                     ; (always)
mzl:    lda #16                    ; z on, 16
        ldx #<MGQ
:       sta MGD
        stx mcp+1                  ; (mcl's phase steps: p or q)
        lda #16
        sta MGN
        rts
        .assert >MGP = >MGQ, error, "mxl, mzl: MGP, MGQ in one page"

; mset: MGX, MGZ, MGS for the window's corner A across, Y down (each 0..15):
; x = WX0 + A, z = WZ0 + Y (mod 64), slot MWO + 16 Y + A.  Clobbers A.
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
        tya
        asl a
        asl a
        asl a
        asl a
        clc
        adc MGT
        clc
        adc MWO
        sta MGS
        rts

; mcl: MGN corners from (MGX, MGZ) at slot MGS, each next MGD slots on and x or
; z one on (mcp's operand: MGP or MGQ, the phases' steps): each height into its
; slot (colour 0), and the mirror.  The height: PADH on the pad (x, z <= PADN),
; else the count of HTL/HTH's thresholds the sum + 2560 reaches, the sum the
; six terms' SIN16 + 256 (madd's), the four k = 2 terms' doubled.  Clobbers A,
; X, Y.
mcl:    ldx #5                     ; the phases: p x + q z (mod 64)
@ph:    lda MGP,x
        ldy MGX
        jsr mul64
        sta MGW
        lda MGQ,x
        ldy MGZ
        jsr mul64
        clc
        adc MGW
        and #63
        sta MGPH,x
        dex
        bpl @ph
mcl_c:  lda MGX                    ; the pad?
        cmp #PADN+1
        bcs :+
        lda MGZ
        cmp #PADN+1
        lda #PADH
        bcc mcl_s
:       lda #0                     ; the sum: terms 3..0 (k = 2) doubled, then
        sta MGB                    ; terms 4, 5 (A its low byte, MGB its high)
        ldx #3
:       jsr madd
        dex
        bpl :-
        asl a
        rol MGB
        ldx #4
        jsr madd
        inx
        jsr madd
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
        cpy #17
        bcs :+
        sta MC+256,y
:       jsr mnext
        beq mcl_x
        ldx #5                     ; the phases on
:       lda MGPH,x
        clc
mcp:    adc MGP,x                  ; (operand's low byte: MGP or MGQ, mxl's)
        and #63
        sta MGPH,x
        dex
        bpl :-
        jmp mcl_c
mcl_x:  rts
; madd: A (and MGB) + term X's SIN16 + 256: SL's byte, 256 more for i <= 32.
; Clobbers Y.
madd:   ldy MGPH,x
        cpy #33
        bcs :+
        inc MGB
:       clc
        adc SL,y
        bcc :+
        inc MGB
:       rts
; mnext: a line's next: MGN - 1 (Z set: done), else the slot MGD on and x (MGD
; 1) or z one on (Z clear after).  Clobbers A, X.
mnext:  dec MGN
        beq @x
        lda MGS
        clc
        adc MGD
        sta MGS
        ldx #0                     ; (MGZ = MGX + 1)
        lda MGD
        lsr a                      ; (C: MGD 1)
        bcs :+
        inx
:       lda MGX,x
        clc
        adc #1
        and #63
        sta MGX,x
        lda #1                     ; (Z clear)
@x:     rts
        .assert MGZ = MGX + 1, error, "mnext: MGZ after MGX"

; mul64: A = A Y mod 64 (A 0..63).  Clobbers Y, MGU, MGT.
mul64:  sta MGU
        sty MGT
        lda #0
        ldy #6
@l:     lsr MGU
        bcc :+
        clc
        adc MGT
:       asl MGT
        dey
        bne @l
        and #63
        rts

; mtl: MGN tiles from (MGX, MGZ) at slot MGS on (as mcl): each one's colour
; index into its slot's high nibble (and the mirror's), from its corners (the
; slot, + 1, + 16, + 17) and r = RA[(x + RA[z]) & 63] (R1, R2 its nibbles): the
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
        lda MC,y                   ; the left corners' sum (MGW), the right's
        and #15                    ; (MGT)
        sta MGT
        lda MC+16,y
        and #15
        clc
        adc MGT
        sta MGW
        lda MC+1,y
        and #15
        sta MGT
        lda MC+17,y
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
        cpy #17
        bcs :+
        sta MC+256,y
:       jsr mnext
        beq :+
        jmp mtl
:       rts

MWX:    .byte 0                    ; the window: WX0, WZ0, MWO (its slot), MOK
MWZ:    .byte 0                    ; (0: none made yet), MWK (mwin's row)
MWO:    .byte 0
MOK:    .byte 0
MWK:    .byte 0
        .include "mapgen.inc"      ; SL, RA, PADI; the rest's sources (_S, BOOT)
; the tables the loader copies into holes (takeover's mtc): the phases' steps,
; the quantiles, the sea's colours; the height thresholds; the colour table.
        .segment "P2T"
MGP:    .res 6
MGQ:    .res 6
YQT:    .res 7
LQT:    .res 7
SEAI:   .res 4
        .segment "ST2"
HTL:    .res 15
HTH:    .res 15
        .segment "ST0"
LUT:    .res 32
        .code
