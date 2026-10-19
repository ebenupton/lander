; project.s: the projection.  The camera sits CAMH height units above the
; ground under the ship (HGV), plus CAME when the game raises it, at tile
; (cxt, czt) plus sixteenths (cxs, czs).  The block drawn is NX = 11 corners
; across (map x cxt-4 .. cxt+6) by nr = 7 or 8 rows, far to near:
;
;   row 0       the far clip plane (ZFCLIP): a corner row when czs is 0, else
;               lerped between the corner rows either side by 1 - fz
;   rows 1..    the corner rows
;   row RN      the near clip plane (ZCLIP), lerped likewise
;
; Each row's ends are pinned to the clip planes at x = +-XCLIP.  For a row at
; depth index di, r = R7L/R7H,di is its pixels a tile; a corner of height h is
; at line HORIZON + ((CAMH + hg - h) r + 2048) >> 12, plus EYV for CAME, and
; corner i at 8.8 x B1 + (i - 1) r, B1 = 32768 + (32768 - (1152 + 16 cxs) r)
; / 256 + r.  Row 0's r is exactly 4096 and the near row's a constant, so both
; have fast paths (@f0, @fn).
;
; The raw heights HT (16 a row) are refetched only when the camera's columns
; or rows change; a step of one row fetches just the new row (zsh4) and shifts
; the rest (hsh).  The strips' box colours are kept in a window of rows (CLE,
; CLO: pcol5), made as rows come into view.

; project: the frame's rows of points, PX and PY + 16 k + i (k the row, i the
; corner), and their boxes' colours.  In: cxt, cxs, czt, czs, CAME.  Out: ZB,
; RN, FACT, nr, np, HT, PX, PY, HGV, CLE, CLO.  Clobbers A, X, Y, tmp, rl, rh,
; MT0, MT1, the overlay.
project:
        lda czs                    ; FACT: the far row lerped (czs != 0); ZB
        cmp #1                     ; its map row offset, ZFCLIP + FACT
        lda #0
        rol a
        tax
        stx FACT
        adc #ZFCLIP
        sta ZB
        sbc #ZCLIP-1               ; (C clear) RN = ZB - ZCLIP, the near row
        sta RN
        tay
        iny
        sty nr
        jsr mwin                   ; the map window to the camera
        lda cxt                    ; the heights still good?
        cmp pkx
        bne @cx
        lda czt
        clc
        adc ZB
        cmp pkz
        beq @j5
@zs:    jsr zsh4                   ; a step of one row: the new row only
        bcc @hl
@j5:    jmp @p5
@cx:    sta pkx
        .assert ZBACK-ZSKIP-ZCLIP+1 = 8 && ZFCLIP-ZCLIP+1 = 7, error, "nr 7 or 8"
        .assert XSKIP = 1, error, "project: the columns cxt-4 .. cxt+6"
@hl:    lda czt                    ; every row: HT + 16 j + i = map row czt +
        clc                        ; ZB - j, column cxt - 4 + i
        adc ZB
        sta pkz
        ldx #NX-1
@hc:    ldy MCB,x
        .repeat 8, r
        lda MC+r,y
        and #15
        sta HT+16*(7-r),x
        .endrepeat
        dex
        bpl @hc
        ldx #$70                   ; each row's range of heights
:       jsr hrng
        txa
        sec
        sbc #16
        tax
        bcs :-
@p5:    jsr pcol5
        jmp prow32

; zsh4: the heights' map rows moved by A - pkz (A = czt + ZB).  For one row on
; (SHF 1) or back (SHF $FF) the new row's heights go to HTN for hsh, C set;
; otherwise C clear.  pkz = A.  Clobbers A, X, Y.
zsh4:   tay
        sec
        sbc pkz
        sty pkz
        cmp #1
        beq @ld
        cmp #$FF
        bne @no
        tya                        ; one back: the new row is row 7
        sbc #7
        tay
        lda #$FF
@ld:    sta SHF
        tya                        ; its slot in the window
        sec
        sbc MWZ
        and #63
        ora #<MC
        sta @zr+1
        ldx #NX-1
@zn:    ldy MCB,x
@zr:    lda MC,y                   ; (operand: the row's slot)
        and #15
        sta HTN,x
        dex
        bpl @zn
        sec
        rts
@no:    clc
        rts

; prow32: the rows' points.  Corner rows take di = 16 (ZB - k) - czs - DI0; the
; clip rows lerp their heights.  Last, the near row is kept below the row
; before it and, when lerped, row 0 above row 1.  In: HT, SHF, cxs, czs, ZB,
; RN, FACT, CAME.  Out: PX, PY, np, HGV, EYV.
prow32: lda CAME                   ; EHIT: the rows' EYVs kept from last frame
        cmp ECAME                  ; (CAME and czs unchanged)
        bne :+
        lda czs
        cmp ECZS
        bne :+
        lda #$80
        bne :++                    ; (always)
:       lda CAME
        sta ECAME
        lda czs
        sta ECZS
        lda #0
:       sta EHIT
        lda SHF
        beq :+
        jsr hsh
:       jsr hgnd
        lda #NX
        sta np
        lda RN
        asl a
        asl a
        asl a
        asl a
        sta RN16
        lda ZB                     ; DCUR: row 0's di as a corner row; the
        asl a                      ; last ASL's carry is ZB's bit 4, set
        asl a
        asl a
        asl a
        sbc #<DI0
        .assert ZFCLIP = 16, error, "DCUR: ZB has bit 4 set"
        sec
        sbc czs
        sta DCUR
        ldx #0
@row:   stx RK                     ; X = RK = 16 k
        txa
        bne @nf
        lda FACT                   ; row 0: the far plane's, lerped
        beq @cor
        ldy #0
        jsr lrng
        jsr lrow
        ldy #ZFCLIP*16-DI0
        bne @r                     ; (always)
@nf:    cpx RN16
        bne @cor
        ldy #ZCLIP*16-DI0          ; row RN: the near plane's
        lda czs
        beq @own
        txa
        sec
        sbc #16
        tay
        jsr lrng
        jsr lrow
        ldy #ZCLIP*16-DI0
        bne @r                     ; (always)
@cor:   ldy DCUR                   ; a corner row: its own heights
@own:   lda HT,x
        sta WH
        lda HT+1,x
        sta WH+1
        lda HT+2,x
        sta WH+2
        lda HT+3,x
        sta WH+3
        lda HT+4,x
        sta WH+4
        lda HT+5,x
        sta WH+5
        lda HT+6,x
        sta WH+6
        lda HT+7,x
        sta WH+7
        lda HT+8,x
        sta WH+8
        lda HT+9,x
        sta WH+9
        lda HT+10,x
        sta WH+10
        lda HT+11,x
        sta HLO
        lda HT+12,x
        sta HHI
@r:     sty RD                     ; the ends' heights, lerped by cxs, and the
        lda cxs                    ; range widened to them
        sta LQ
        lda WH
        ldy WH+1
        jsr lerp4
        sta WH
        cmp HLO
        bcs :+
        sta HLO
:       cmp HHI
        bcc :+
        sta HHI
:       lda WH+NX-2
        ldy WH+NX-1
        jsr lerp4
        sta WH+NX-1
        cmp HLO
        bcs :+
        sta HLO
:       cmp HHI
        bcc :+
        sta HHI
:       ldy RD
        ldx RK
        bne :+
        jmp @f0
:       cpx RN16
        bne :+
        jmp @fn
:       lda R7L,y                  ; r
        sta rl
        lda R7H,y
        sta rh
        lda CAME                   ; EYV: 0, kept (HT+13,x), or eyrow's
        bne @ey
        sta EYV
        beq @ye                    ; (always)
@ey:    bit EHIT
        bpl @ec
        lda HT+13,x
        sta EYV
        jmp @ye
@ec:    jsr eyrow
        lda EYV
        sta HT+13,x
@ye:    jsr ytab                   ; the y's by height
        lda RK
        sta @py+1
        ldy #NX-1
:       ldx WH,y
        lda YT,x
@py:    sta PY,y                   ; (operand: PY + RK)
        dey
        bpl :-
        ldx RK
        jsr xrow
@nx:    lda RK                     ; the next row
        cmp RN16
        beq @fin
        adc #16                    ; (C clear)
        sta RK
        tax
        lda DCUR
        sbc #15                    ; (C clear: - 16)
        sta DCUR
        jmp @nf
@fin:   ldx RN16                   ; the near row below the one before
        ldy #NX
:       lda PY-16,x
        cmp PY,x
        bcc :+
        adc #0                     ; (C set: + 1)
        sta PY,x
:       inx
        dey
        bne :--
        lda FACT                   ; a lerped row 0 above row 1
        beq @x
        ldx #NX-1
:       lda PY,x
        cmp PY+16,x
        bcc :+
        ldy PY+16,x
        beq :+
        dey
        tya
        sta PY,x
:       dex
        bpl :--
@x:     rts

; row 0 on the far plane, r = 4096: y = HORIZON + CAMH + hg + CAME - h, never
; held; x: the ends 128 -+ 72, corner i 72 - cxs + 16 (i - 1).
@f0:    lda HGV
        clc
        adc #HORIZON+CAMH
        adc CAME
        sta RD
        ldx #NX-1
:       lda RD
        sec
        sbc WH,x
        sta PY,x
        dex
        bpl :-
        lda #56
        sta PX
        lda #200
        sta PX+NX-1
        lda #72                    ; (C set)
        sbc cxs
        ldx #0
:       sta PX+1,x
        clc
        adc #16
        inx
        cpx #NX-2
        bne :-
        jmp @nx

; row RN on the near plane, r constant (NRL, NRH): y = TN + 15 + h - hg + EYV,
; held at 254, EYV kept while CAME stands; x: the ends NXL, NXR, corner 1 from
; B1N by cxs, each next r on.
@fn:    lda CAME
        cmp ncame
        beq @fe
        sta ncame
        lda #NRL
        sta rl
        lda #NRH
        sta rh
        jsr eyrow
        lda EYV
        sta neyv
@fe:    lda neyv
        sta EYV
        lda RK
        sta @pn+1
        lda #15
        sec
        sbc HGV
        sta RD
        ldy #NX-1
@nl:    lda WH,y
        clc
        adc RD
        tax
        lda TN,x
        clc
        adc EYV
        bcs @nh
        cmp #255
        bcc @pn
@nh:    lda #254
@pn:    sta PY,y                   ; (operand: PY + RK)
        dey
        bpl @nl
        ldx RK
        lda #NXL
        sta PX,x
        lda #NXR
        sta PX+NX-1,x
        lda cxs
        asl a
        tay
        lda B1N,y
        sta Y0+1
        lda B1N+1,y
        tay
        sta PX+1,x
        .repeat NX-3, I
        lda Y0+1
        clc
        adc #NRL
        .if I < NX-4
        sta Y0+1
        .endif
        tya
        adc #NRH
        .if I < NX-4
        tay
        .endif
        sta PX+2+I,x
        .endrepeat
        jmp @nx
        .assert ZCLIP*16-DI0 = NDIN, error, "prow32: the near row's di"
        .assert ZFCLIP*16-DI0 = 111 && HORIZON+CAMH+15+EMAX <= 254, error, "prow32: row 0's di 111, y never held"

; ytab: YT,h = the row's line for height h, HLO..HHI: HORIZON + ((CAMH + hg -
; h) r + 2048) >> 12, plus EYV, held at 254.  The sum is kept times 16 as 24
; bits at Y0, so the line is its top byte, stepping by 16 r (Q0) a height.  In:
; rl, rh, HGV, EYV, HLO, HHI.  Clobbers A, X, Y.
ytab:   lda #0                     ; Q0 = 16 r
        sta Q0+2
        lda rh
        sta Q0+1
        lda rl
        .repeat 4
        asl a
        rol Q0+1
        rol Q0+2
        .endrepeat
        sta Q0
        lda rl                     ; Y0 = (6 r << 8) + 32768: the sum at h = hg
        asl a
        sta Y0+1
        lda rh
        rol a
        sta Y0+2
        lda Y0+1
        asl a
        tax
        lda Y0+2
        rol a
        tay
        txa
        adc Y0+1
        sta Y0+1
        tya
        adc Y0+2
        sta Y0+2
        lda Y0+1
        eor #$80
        sta Y0+1
        bmi :+
        inc Y0+2
:       lda #0
        sta Y0
        ldy HGV                    ; then stepped to h = HLO
        cpy HLO
        beq @go
        bcc @up
@dn:    lda Y0
        clc
        adc Q0
        sta Y0
        lda Y0+1
        adc Q0+1
        sta Y0+1
        lda Y0+2
        adc Q0+2
        sta Y0+2
        dey
        cpy HLO
        bne @dn
        beq @go                    ; (always)
@up:    lda Y0
        sec
        sbc Q0
        sta Y0
        lda Y0+1
        sbc Q0+1
        sta Y0+1
        lda Y0+2
        sbc Q0+2
        sta Y0+2
        iny
        cpy HLO
        bne @up
@go:    ldy HLO
@h:     lda Y0+2                   ; the line, held at 254
        clc
        adc EYV
        bcs @c
        sbc #-HORIZON-1            ; (C clear: + HORIZON)
@st:    sta YT,y
        cpy HHI
        beq @x
        lda Y0
        sec
        sbc Q0
        sta Y0
        lda Y0+1
        sbc Q0+1
        sta Y0+1
        lda Y0+2
        sbc Q0+2
        sta Y0+2
        iny
        bne @h                     ; (always)
@x:     rts
@c:     cmp #15
        bcc @in
        lda #254
        bne @st                    ; (always)
@in:    adc #256+HORIZON           ; (C clear)
        bcc @st                    ; (always)
        .assert HORIZON = -16, error, "ytab: HORIZON -16"

; lrng: HLO, HHI = the range of corners 1..NX-2 over HT rows Y/16 and Y/16+1,
; which any lerp between them stays within.  X kept.
lrng:   lda HT+11,y
        cmp HT+16+11,y
        bcc :+
        lda HT+16+11,y
:       sta HLO
        lda HT+12,y
        cmp HT+16+12,y
        bcs :+
        lda HT+16+12,y
:       sta HHI
        rts

; hrng: HT row X/16's corners 1..NX-2: their least into HT+11,x and greatest
; into HT+12,x (the row's spare columns).  X kept; clobbers A, Y, MT0, MT1.
hrng:   txa
        ora #NX-2
        tay
        lda HT+1,x
        sta MT0
        sta MT1
@l:     lda HT,y
        cmp MT0
        bcs :+
        sta MT0
:       cmp MT1
        bcc :+
        sta MT1
:       dey
        tya
        and #15
        cmp #1
        bne @l
        lda MT0
        sta HT+11,x
        lda MT1
        sta HT+12,x
        rts
        .assert NX-2 = 9, error, "hrng: corners 1..9, columns 11, 12 spare"

        .include "neartab.inc"
        .code

; lrow: WH = HT row Y/16 lerped towards the next by 16 - czs sixteenths.
; X = RK in and out; clobbers A, Y, MT0, MT1, LQ.
lrow:   lda #16
        sec
        sbc czs
        sta LQ
        ldx #0
:       lda HT,y
        sta MT0
        lda HT+16,y
        jsr lerp4e
        sta WH,x
        iny
        inx
        cpx #NX
        bne :-
        ldx RK
        rts

; lerp4: A = a + (((b - a) q + 8) >> 4) for heights a = A, b = Y (0..15) and
; q = LQ (0..15), rounding as land.lerp.  X kept; clobbers Y, MT0, MT1, MQB.
lerp4:  sta MT0
        tya
lerp4e: sec                        ; (lrow's entry: A = b, MT0 = a)
        sbc MT0
        beq @z
        bcc @n
        jsr mul4
        adc #8
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc MT0
        rts
@n:     eor #$FF                   ; b < a: a - ((|d| q + 7) >> 4)
        adc #1
        jsr mul4
        adc #7
        lsr a
        lsr a
        lsr a
        lsr a
        eor #$FF
        sec
        adc MT0
        rts
@z:     lda MT0
        rts

; mul4: A = A times LQ, both 0..15; C clear after.  X, Y kept; clobbers MT1,
; MQB.
mul4:   sta MT1
        lda LQ
        .repeat 4, k
        .if k = 0
        lsr a
        sta MQB
        lda #0
        bcc :+
        lda MT1
        .else
        lsr MQB
        bcc :+
        clc
        adc MT1
        .endif
:
        .if k < 3
        asl MT1
        .endif
        .endrepeat
        rts

; xrow: PX + X + i, the row's x's.  The ends from Q = 1152 r: 128 + ((Q +
; 32768) >> 16) and 128 - ((Q + 32767) >> 16); corners 1..NX-2 from B1, r
; apart.  In: X = RK, rl, rh, cxs.  Clobbers A, X, Y, Y0, Q0.
xrow:   lda rh                     ; Q = r << 7 + r << 10
        sta Y0+2
        lsr a
        sta Q0+2
        lda rl
        ror a
        sta Q0+1
        lda #0
        ror a
        sta Q0
        lda rl
        asl a
        rol Y0+2
        asl a
        rol Y0+2
        .assert DI0 > 128, error, "xrow: r < 8192"
        adc Q0+1
        sta Q0+1
        tay
        lda Q0+2
        adc Y0+2
        sta Q0+2
        cpy #$80                   ; the right end
        adc #128
        sta PX+NX-1,x
        lda #0                     ; the left end: the borrow is ([Q1 Q0] >
        cmp Q0                     ; $8000)
        lda #$80
        sbc Q0+1
        lda #128
        sbc Q0+2
        sta PX,x
        lda cxs                    ; M = Q + 16 cxs r: the product by shifts,
        sta Y0                     ; cxs's bits from the bottom of Y0
        lda #0
        sta Y0+1
        lsr Y0
        bcc :+
        lda rl
        sta Y0+1
        lda rh
:       lsr a
        ror Y0+1
        ror Y0
        bcc @b2
        tay
        clc
        lda Y0+1
        adc rl
        sta Y0+1
        tya
        adc rh
@b2:    ror a
        ror Y0+1
        ror Y0
        bcc :+
        tay
        clc
        lda Y0+1
        adc rl
        sta Y0+1
        tya
        adc rh
:       ror a
        ror Y0+1
        ror Y0
        bcc @b4
        tay
        clc
        lda Y0+1
        adc rl
        sta Y0+1
        tya
        adc rh
@b4:    ror a
        ror Y0+1
        ror Y0
        tay
        lda Y0
        clc
        adc Q0
        sta Y0
        lda Y0+1
        adc Q0+1
        sta Y0+1
        tya
        adc Q0+2
        eor #$7F                   ; B1 = (32768 - M) >> 8 + 32768 + r
        tay
        lda #0
        sec
        sbc Y0
        lda #$80
        sbc Y0+1
        sta Y0+1
        tya
        adc #0
        tay
        .repeat NX-2, I            ; corners 1..NX-2, r apart
        lda Y0+1
        clc
        adc rl
        .if I < NX-3
        sta Y0+1
        .endif
        tya
        adc rh
        .if I < NX-3
        tay
        .endif
        sta PX+1+I,x
        .endrepeat
        rts

; hgnd: HGV, the ground under the ship (ZSHIP tiles ahead of the camera): the
; four corners round it lerped across by (cxs + 8) & 15, then down by czs.
; Clobbers A, X, Y, MT0, MT1, MQB, LQ, tmp.
hgnd:   lda ZB                     ; X = 16 (ZB - ZSHIP) + 4 + (cxs >= 8)
        asl a
        asl a
        asl a
        asl a
        adc #<(3-16*ZSHIP)
        .assert ZFCLIP = 16, error, "hgnd: ZB has bit 4 set"
        ldy cxs
        cpy #8
        adc #0
        tax
        tya
        eor #8
        sta LQ
        lda HT,x
        ldy HT+1,x
        jsr lerp4
        sta tmp
        lda HT-16,x
        ldy HT-15,x
        jsr lerp4
        tay
        lda czs
        sta LQ
        lda tmp
        jsr lerp4
        sta HGV
        rts

; eyrow: EYV = (CAME (r >> 5) + 64) >> 7, the lines the row drops when the
; camera is raised.  In: rl, rh, CAME.  X kept; clobbers A, Y, MT0, MT1.
        .assert DI0 > 128, error, "eyrow: r < 8192"
eyrow:  lda rl                     ; r >> 5: (rl & $E0 | rh) rotated left 3
        and #$E0
        ora rh
        .repeat 3
        asl a
        adc #0
        .endrepeat
        sta MT0
        lda CAME                   ; CAME times it
        lsr a
        sta MT1
        lda #0
        ldy #8
@m:     bcc :+
        clc
        adc MT0
:       ror a
        ror MT1
        dey
        bne @m
        asl MT1                    ; + 64, >> 7
        rol a
        asl MT1
        adc #0
        sta EYV
        rts

; hsh: HT shifted a row for zsh4's step: SHF 1 moves rows down (row 0 takes
; HTN), SHF $FF up (row 7 takes HTN); then the new row's range.  SHF = 0 after.
; Clobbers A, X, Y.
hsh:    ldx #NX+1                  ; (the range columns move with their rows)
@c:     lda SHF
        bmi @b
        txa
        ora #$60
        tay
        sec
:       lda HT,y
        sta HT+16,y
        tya
        sbc #16
        tay
        bcs :-
        lda HTN,x
        sta HT,x
        bcc @n                     ; (always)
@b:     txa
        ora #$90
        tay
        clc
:       lda HT+16-$90,y
        sta HT-$90,y
        tya
        adc #16
        tay
        bcc :-
        lda HTN,x
        sta HT+$70,x
@n:     dex
        bpl @c
        ldx #0
        lda SHF
        bpl :+
        ldx #$70
:       jsr hrng
        lda #0
        sta SHF
        rts

; pcol5: the strips' box colours.  Window row m (CLE, CLO + 16 m, m 0..9) holds
; map row WK - m's tiles for the columns at cxt = WX.  The strips need rows o ..
; o+6, o = WK - czt - ZB + 1; with o in 0..3 the missing rows are made (VLO ..
; VHI grows), otherwise the window is remade.  Out: setup's operands for
; window row o.  Clobbers A, X, Y.
pcol5:  lda cxt
        cmp WX
        bne @fx
        lda WK                     ; o
        clc
        sbc czt
        sec
        sbc ZB
        clc
        adc #2
        cmp #4
        bcs @f
@o:     sta WO
        tax                        ; rows o .. VLO-1
:       cpx VLO
        bcs :+
        jsr crow
        inx
        bne :-
:       lda WO                     ; rows VHI+1 .. o+6
        adc #6                     ; (C set: + 7)
        sta WE
        ldx VHI
:       inx
        cpx WE
        bcs :+
        jsr crow
        jmp :-
:       lda WO
        cmp VLO
        bcs :+
        sta VLO
:       ldx WE
        dex
        cpx VHI
        bcc @pt
        stx VHI
@pt:    lda WO                     ; setup reads CLE, CLO + 16 o
        asl a
        asl a
        asl a
        asl a
        sta su_ce+1
        adc #<CLO
.ifndef ARC
        sta su_co+1
.endif
        rts
@f:     lda cxt
@fx:    sta WX                     ; anew: rows 1..7, o 1
        lda czt
        clc
        adc ZB
        sta WK
        ldx #8
        stx VLO
        dex
        stx VHI
        lda #1
        bne @o                     ; (always)
        .assert (<MC & $7F) = 0, error, "MC 128-aligned"
        .assert <CLE = 0 && <CLO + 48 < $100, error, "crow: CLE page-aligned; CLO + 48 in its page"

; crow: window row X from map row (WK - X) & 63: each tile's colour, from its
; corner's colour index (DCE, DCO), or in the arc build its kind * 9 + slope
; (setup adds the strip's brightness).  X kept; clobbers A, Y.
crow:   stx WM
        txa
        asl a
        asl a
        asl a
        asl a
        sta @se+1
.ifndef ARC
        clc
        adc #<CLO
        sta @so+1
        lda #>CLO
        adc #0
        sta @so+2
.endif
        lda WK                     ; the map row's slot in the window
        sec
        sbc WM
        sec
        sbc MWZ
        and #63
        ora #<MC
        sta @le+1
.ifdef ARC
        clc                        ; (and its corner a column on)
        adc #8
        sta @l2+1
        ldx #NX-2
@c:     ldy MCB,x
@l2:    lda MC,y                   ; the right corner: height, kind, pad
        sta MGT
        and #15
        sta MGU
@le:    lda MC,y                   ; the left corner's height
        and #15
        sta MGW
        ora MGU
        bne @l
        lda #5*9                   ; the sea
        bne @se
@l:     lda MGT
        and #$70
        cmp #$40
        bcc :+
        lda #4*9                   ; the pad
        bne @se
:       lsr a                      ; 9 kind
        sta MGT
        lsr a
        lsr a
        lsr a
        clc
        adc MGT
        sta MGT
        lda MGU                  ; + the slope in thirds, at most 2
        sec
        sbc MGW
        bcc @k
        cmp #3
        bcc @k
        inc MGT
        cmp #6
        bcc @k
        inc MGT
@k:     lda MGT
@se:    sta CLE,x
        dex
        bpl @c
.else
        ldx #NX-2
@c:     ldy MCB,x
@le:    lda MC,y                   ; the colour index: the corner's high nibble
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda DCE,y
@se:    sta CLE,x
        lda DCO,y
@so:    sta CLO,x
        dex
        bpl @c
.endif
        ldx WM
        rts

        .pushseg
        .segment "TABLES"
WX:     .byte $FF                  ; the window's cxt ($FF: none yet)
WK:     .byte 0                    ; its row 0's map row
WO:     .byte 0                    ; o
VLO:    .byte 0                    ; the rows made: VLO .. VHI
VHI:    .byte 0
WE:     .byte 0                    ; o + 7
WM:     .byte 0                    ; crow's row
pkx:    .byte $FF                  ; the cxt and czt + ZB the heights are for
pkz:    .byte $FF
SHF:    .byte 0                    ; hsh's shift: 1, $FF, or 0 for none
        .include "colours.inc"
        .popseg
