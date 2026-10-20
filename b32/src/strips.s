; strips.s: the land, a strip at a time, top to bottom.  Strip ns lies between
; rows ns-1 and ns: strip 0 has only its bottom row (row 0), strips 1 .. nr-1
; are the land's, and the last of them, the near strip, also blacks the ground
; below.  A strip's points are the rows' corners plus its margins (points 0
; and NX+1, at byte boundaries outside the bottom row's ends, level with them).
;
; Each row is traced into a page of lines by pixel x (ROWA, ROWB: the last
; strip's bottom row is this one's top).  Then the rungs, the segments joining
; the rows' corresponding points, are found (rungs.s) and the strip drawn a byte
; column at a time (columns.s).
;
; The screen is never cleared.  Each column's highest and lowest land line is
; kept in three sets of 64: one for each screen, as last drawn there, and one
; this frame's.  Drawing blacks what the land covered last time and no longer
; does; the sets then rotate.

; strips: the frame's strips.  In: back, nr, PX, PY, CLE, CLO, vcount, vflip.
; Out: the screen drawn and the column sets rotated.  Clobbers A, X, Y and
; the renderer's zero page.
strips: ldx back                   ; the screen's set: gone's pointers, and the
        ldy sidx,x                 ; sites that read it
        lda setTl,y
        sta tsp
        sta pT5+1
        sta pT5c+1
        sta pT6+1
        lda setTh,y
        sta tsp+1
        sta pT5+2
        sta pT5c+2
        sta pT6+2
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
        ldy cidx                   ; this frame's set: the sites that write it
        lda setTl,y
        sta pT3+1
        sta pT3c+1
        sta pT4+1
        lda setTh,y
        sta pT3+2
        sta pT3c+2
        sta pT4+2
        lda setBl,y
        sta pB4+1
        sta pB7+1
        lda setBh,y
        sta pB4+2
        sta pB7+2
        lda #>ROWA                 ; the rows' lines (low bytes 0 for good)
        sta topa+1
        lda #>ROWB
        sta bota+1
        lda #0
        sta ns
@strip: jsr setup                  ; the points and the bottom row's line,
        lda BCL                    ; held on the screen unless all or none of
        beq @nbc                   ; its points are below it
        cmp #NX
        beq @nbc
        jsr bclip
@nbc:   lda ns
        beq @swap                  ; (strip 0: traced only)
        jsr rungs
        lda ns                     ; before the first store: wait until the
        cmp #1                     ; screen is no longer shown
        bne @draw
@wait:  lda vcount
        cmp vflip
        bne @draw
        lda UVIA_T2H
        cmp #T2DEND
        bcs @wait
@draw:  jsr cols
@swap:  lda topa+1                 ; the bottom row is the next top
        sta bota+1
        eor #>ROWA ^ >ROWB
        sta topa+1
        lda xl
        sta xlp
        lda xr
        sta xrp
        inc ns
        bit last
        bpl @strip
        jsr gone                   ; the columns the land has left
        ldx back                   ; rotate: this frame's set is the screen's
        ldy cidx
        lda sidx,x
        sta cidx
        tya
        sta sidx,x
        rts
        .pushseg
        .segment "TABLES"
sidx:   .byte 0, 1                 ; each screen's set
cidx:   .byte 2                    ; this frame's
setTl:  .byte <TOPS, <(TOPS+64), <CURT
setTh:  .byte >TOPS, >(TOPS+64), >CURT
setBl:  .byte <BOTS, <(BOTS+64), <CURB
setBh:  .byte >BOTS, >(BOTS+64), >CURB
        .popseg

; setup: the strip's points and boxes, then its bottom row traced.  Points 1 ..
; NX from rows ns-1 (TX, TY) and ns (BX, BY), boxes 1 .. NX-1 from the colour
; window (CE, CO); strip 0 takes row 0 as its bottom row only.  BCL counts the
; bottom points below YGND, last is $FF for the near strip, xl and xr are the
; margins.  Falls into traceb.
setup:
.ifdef ARC
        lda ns                     ; the strip's brightness less 4, 7 - nr +
        clc                        ; ns, into the colour tables' operands
        adc #<CTE+7
        sec
        sbc nr
.ifdef SWR
        sta cte                    ; (SWR: their pointers)
        adc #CTO-CTE-1
        sta cto
        lda #>CTE
        sta cte+1
        sta cto+1
.else
        sta su_te+1
        adc #CTO-CTE-1             ; (C set)
        sta su_to+1
.endif
        .assert CTO = CTE+61 && <CTE+13 <= 255 && <CTO+13 <= 255, error, "su_te, su_to: in their pages"
.endif
        ldx #0
        stx BCL
        ldy ns
        iny
        cpy nr
        bne :+
        dex
:       stx last
        lda ns
        beq su_r
.ifdef SWR
        asl a                      ; Y = 16 (ns - 1): bank 4's su_l4
        asl a
        asl a
        asl a
        adc #$F0
        tay
        jmp su_l4
.else
        asl a                      ; Y = 16 (ns - 1) + NX-1: point NX of row
        asl a                      ; ns-1, walked down
        asl a
        asl a
        adc #$F0+NX-2
        tay
        iny
        ldx #NX-1
su_l:   lda PX,y
        sta TX+1,x
        lda PY,y
        sta TY+1,x
        lda PX+16,y
        sta BX+1,x
.ifdef ARC
su_ce:  lda CLE,y                  ; (operand: CLE + 16 o) the box's class;
        sty su_ry+1                ; its bytes by the strip's brightness
        tay
su_te:  lda CTE,y
        sta CE+1,x
su_to:  lda CTO,y
        sta CO+1,x
su_ry:  ldy #0                     ; (operand: Y)
.else
su_ce:  lda CLE,y                  ; (operands: CLE, CLO + 16 o)
        sta CE+1,x
su_co:  lda CLO,y
        sta CO+1,x
.endif
        lda PY+16,y
        sta BY+1,x
        cmp #YGND+1
        bcc :+
        inc BCL
:       dey
        dex
        bpl su_l
        jmp su_m
.endif
su_qc:  inc BCL
        bcs su_qb                  ; (always)
su_r:   ldx #NX-1                  ; strip 0: row 0 as the bottom row
su_q:   lda PX,x
        sta BX+1,x
        lda PY,x
        sta BY+1,x
        cmp #YGND+1
        bcs su_qc
su_qb:  dex
        bpl su_q
su_m:   lda BX+1                   ; the margins: the byte boundaries outside
        and #$FC                   ; the row's ends
        sta xl
        sta TX
        sta BX
        lda BX+NX
        clc
        adc #3
        and #$FC
        sta xr
        sta TX+NX+1
        sta BX+NX+1
        lda TY+NX
        sta TY+NX+1
        lda BY+NX
        sta BY+NX+1
        lda TY+1
        sta TY
        lda BY+1
        sta BY

; traceb: the bottom row into (bota), a line a pixel, as points.py's
; bresenham_ys, widened to the next strip's margins (this row is its top).  A
; level run of pixels is pending from tcnt at line tyv until something ends
; it; the fills (TBLK4, TBLK5: STA ROWx-k,X for k = TNB .. 1, then JMP t_back)
; store it in one go, entered n stores from their end (TENxL, TENxH + n).  A
; shallow segment is drawn as its runs: q2 or q2 + 1 long after the first (q2,
; r2 = dx div |dy|, 2 (dx mod |dy|)), the longer when E += r2 carries.  Wide
; or steep segments go a pixel at a time (t_old, t_steep).  In: BX, BY, ns,
; PX, bota, xl.  Clobbers A, X, Y, the trace's zero page; returns to strips.
traceb: lda bota+1                 ; the row's page: the fills' entry tables
        sta jvb+2                  ; into the sites that read them
        and #1
        tay
        lda tenl,y
        sta tv_l+1
        sta tx_l+1
        lda tenl+2,y
        sta tv_l+2
        sta tx_l+2
        lda tenl+4,y
        sta tf_l+1
        lda tenl+6,y
        sta tf_l+2
        lda tenh,y                 ; (TEN4H, TEN5H share a page)
        sta tv_h0+1
        sta tx_h+1
        lda tenh+2,y
        sta tf_h+1
        ldy BX+NX+1                ; the end: xr + 1, or the next strip's
        iny
        sty t_end+1
        lda BX                     ; the start: xl, or the next strip's
        sta tcnt
        bit last
        bmi @t0
        lda ns
        asl a
        asl a
        asl a
        asl a
        tay
        lda PX+16,y
        and #$FC
        cmp tcnt
        bcs :+
        sta tcnt
:       clc
        lda PX+16+NX-1,y
        adc #3
        and #$FC
        cmp t_end+1
        bcc @t0
        adc #0                     ; (C set: + 1)
        sta t_end+1
@t0:    lda BCL                    ; all below YGND: one run at YGND+1
        cmp #NX
        beq t_all
        lda BY
        sta tyv
        ldx #0
        beq t_seg                  ; (always)
t_all:  lda #YGND+1
        sta tyv
t_end:  ldx #0                     ; (operand: the end) the last run, then
        jmp t_fl                   ; t_fr's RTS returns to strips
t_stj:  jmp t_steep
t_o:    jsr t_fl0
        jmp t_old
t_dx0:  lda BX,x                   ; no width: the run ends; a new one at y1
        tax
        jsr t_fl
        ldx tj
        lda BX,x
        sta tcnt
        lda BY+1,x
        sta tyv
t_next: lda tyv
        ldx tj
t_nx:   inx
        cpx #NX+1
        bcs t_end
t_seg:  cmp BY+1,x                 ; segment X: A = tyv = its y0
        beq t_nx                   ; (level: the run goes on)
        stx tj
        lda BX+1,x
        sec
        sbc BX,x
        beq t_dx0
        sta terr                   ; dx
        lda BY+1,x
        sbc tyv                    ; dy
        ldy #$E6                   ; the step, t_inc's opcode: INC zp falling,
        bcs :+                     ; DEC zp rising
        eor #$FF
        adc #1
        ldy #$C6
:       cmp terr
        bcs t_stj                  ; |dy| >= dx: steep
        sty t_inc
        sta dva
        tay
        cmp #1
        beq t_one
        asl a
        bcs t_o
        sta ra2                    ; 2|dy|
.ifdef SWR
        ora terr                   ; q2, r2 by DQT, DRT (row |dy|, + dx) when
        cmp #64                    ; |dy| < 32 and dx < 64, else div8
        bcs t_dv
        lda DVH,y
        sta t_dq+2
        adc #>(DRT-DQT)
        sta t_dr+2
        lda DVL,y
        ora terr
        tay
t_dq:   lda DQT,y                  ; (operands' pages: the row's)
        sta dvd
t_dr:   lda DRT,y
        sta t_rr+1
        ldy dvd
t_dj:
.else
        sty dvx                    ; q2, r2
        lda terr
        sta dvd
        jsr div8
        asl a
        sta t_rr+1
        ldy dvd
.endif
        cpy #TNB+1
        bcs t_o
        sty rq2                    ; the first step at x0 + q + (rem > 0),
        lsr dvd                    ; q, rem = dx div, mod 2|dy|; E = rem -
        bcc :+                     ; 2|dy| - 1, or $FF for rem 0
        adc ra2
:       lsr a
        beq :+
        sec
        sbc ra2
:       sbc #0
        sta rrem
        lda dvd
        adc #0
        adc BX,x
        tax
        ldy rq2                    ; jv0: the fill of q2 stores
tv_l:   lda TEN4L,y
        sta jv0+1
tv_h0:  lda TEN4H,y                ; (operand: the row's table)
        sta jv0+2
        txa                        ; the pending run to the first step
        sbc tcnt
        tay
        cpy #TNB
        bcs t_fl1
tf_l:   lda TEN4L+1,y
        sta tf_j+1
tf_h:   lda TEN4H+1,y              ; (operand: the row's table)
        sta tf_j+2
        ldy dva
        lda tyv
tf_j:   jmp t_back                 ; (operand: the fill)
t_one:  lda terr                   ; |dy| 1: the step at x0 + ceil(dx / 2)
        lsr a
        adc BX,x
        tax
        sbc tcnt
        tay
        cpy #TNB
        bcc tf_l
t_fl1:  ldy dva                    ; a first run longer than TNB
        jmp t_flo
.ifdef SWR
t_dv:   sty dvx                    ; (beyond DQT, DRT) q2, r2 by div8
        lda terr
        sta dvd
        jsr div8
        asl a
        sta t_rr+1
        ldy dvd
        jmp t_dj
        .assert DRT - DQT = $800 && <DQT = 0, error, "t_dq, t_dr: DRT's rows 8 pages on"
.endif
t_fr:   lda #<(t_last-t_bq-2)      ; t_fl's end: t_bq back, and t_fl returns
        sta t_bq+1
        rts
t_last: stx tcnt                   ; the last step: the run from X pending
        jmp t_next
t_fl0:  lda tyv                    ; the pending run to x0, then pixel x0
        pha
        ldx tj
        lda BX,x
        tax
        jsr t_fl
        pla
        sta tyv
        ldx tj
        lda BX+1,x
        sta tx1
        lda terr
        asl a
        sta tdx2
        ldy BX,x
        lda tyv
        sta (bota),y
        rts
t_fl:   lda #<(t_fr-t_bq-2)        ; the pending run to X as a subroutine:
        sta t_bq+1                 ; t_back's last step ends at t_fr
        txa
        sec
        sbc tcnt
        tay
        cpy #TNB+1
        bcs t_flf
tx_l:   lda TEN4L,y
        sta tx_j+1
tx_h:   lda TEN4H,y                ; (operand: the row's table)
        sta tx_j+2
        ldy #1
        lda tyv
tx_j:   jmp t_back                 ; (operand: the fill)
t_flf:  ldy #1
        jmp t_flo
t_back:                            ; the fills' end: X the run's end, Y the
t_inc:  inc tyv                    ; steps left; y steps (INC or DEC)
        dey
t_bq:   beq t_last                 ; (or t_fr: t_fl's)
        lda rrem                   ; the next run: q2, or q2 + 1 if E carries
t_rr:   adc #0                     ; (operand: r2)
        bcs :+
        sta rrem
t_q2:   txa
        adc rq2
        tax
        lda tyv
jv0:    jmp t_back                 ; (operand: the fill of q2)
:       sbc ra2
        sta rrem
        lda tyv
jvb:    sta ROWB,x                 ; (operand: the row's page) its first pixel
        sec
        bcs t_q2                   ; (always)
        .assert t_last-t_bq-2 >= -128 && t_fr-t_bq-2 >= -128 && t_last-t_bq-2 < 128 && t_fr-t_bq-2 < 128, error, "t_bq: its targets in reach"

; t_old: a shallow segment with dx >= 64 or |dy| >= 32, a pixel at a time, the
; error biased so that a carry is a step.
t_old:  lda t_inc
        sta tr_inc
        lda dva
        asl a
        sta tdy2
        lda tdx2
        eor #$FF
        sta tr_k+1
        clc
        adc terr
        adc #1
        tay
        lda BX,x
        tax
        clc
        jsr tr_l
t_ox:   ldx tj                     ; the pending run from x1 at y1
        lda BY+1,x
        sta tyv
        lda tx1
        sta tcnt
        jmp t_next

; t_steep: |dy| >= dx > 0 (rare), as bresenham_ys is written.
t_steep: sty tg_op
        asl a
        sta tdy2
        jsr t_fl0
        sta tyy
        tya
        tax
t_gl:   inx
        lda terr
        clc
        adc tdy2
:       cmp tdx2
        bcc :+
        sbc tdx2
tg_op:  inc tyy                    ; (INC or DEC)
        jmp :-
:       sta terr
        txa
        tay
        lda tyy
        sta (bota),y
        cpx tx1
        bne t_gl
        beq t_ox                   ; (always)

; t_flo: a run longer than TNB, by the row's fill chained to itself until
; less than TNB is left, then entered for the rest.  V is kept.
t_flo:  php
        sty tdx2
        stx tfe
        lda bota+1
        and #1
        tay
        lda tfbl,y
        sta tfb+1
        lda tfbh,y
        sta tfb+2
        lda #<t_fch
        sta TBLK4+3*TNB+1
        sta TBLK5+3*TNB+1
        lda #>t_fch
        sta TBLK4+3*TNB+2
        sta TBLK5+3*TNB+2
        ldx tcnt
t_fch:  txa
        clc
        adc #TNB
        bcs t_fcl
        cmp tfe
        bcs t_fcl
        tax
        lda tyv
tfb:    jmp $FFFF                  ; (operand: the row's fill)
t_fcl:  lda #<t_back
        sta TBLK4+3*TNB+1
        sta TBLK5+3*TNB+1
        lda #>t_back
        sta TBLK4+3*TNB+2
        sta TBLK5+3*TNB+2
        txa                        ; the entry for n = tfe - X: TNB - n stores
        eor #$FF                   ; in
        sec
        adc tfe
        eor #$FF
        clc
        adc #TNB+1
        sta tfn
        asl a
        adc tfn
        adc tfb+1
        sta tfj+1
        lda tfb+2
        adc #0
        sta tfj+2
        ldx tfe
        ldy tdx2
        plp
        clc
        lda tyv
tfj:    jmp $FFFF                  ; (operand: the entry)
        .pushseg
        .segment "TABLES"
tfbl:   .byte <TBLK4, <TBLK5
tfbh:   .byte >TBLK4, >TBLK5
        .popseg

; divs: rq, rrem = D div 2a, D mod 2a, and rq2, rr2 = D div a, 2 (D mod a).
; In: dva = a, ra2 = dvx = 2a, dvd = D.  Clobbers A, Y, dvx, dvd.
divs:
.ifdef SWR
        lda dva                    ; a < 32 and D < 64: DQT, DRT's row a, + D
        cmp #32
        bcs @dv
        lda dvd
        cmp #64
        bcs @dv
        ldy dva
        lda DVH,y
        sta @q+2
        adc #>(DRT-DQT)            ; (C clear)
        sta @r+2
        lda DVL,y
        ora dvd
        tay
@r:     lda DRT,y                  ; rr2 = 2 (D mod a); D mod 2a = D mod a, + a
        sta rr2                    ; if D div a is odd
        lsr a
        sta rrem
@q:     lda DQT,y                  ; rq2 = D div a, rq = D div 2a
        sta rq2
        lsr a
        sta rq
        bcc :+
        lda rrem
        adc dva                    ; (C set: + a + 1, less the 1)
        sbc #0
        sta rrem
:       rts
@dv:
.endif
        jsr div8
        sta rrem
        cmp dva
        bcc :+
        sbc dva
:       tay
        lda dvd
        sta rq
        rol a
        sta rq2
        tya
        asl a
        sta rr2
        rts


        TAIL "T5"
; div8: dvd = dvd div dvx, A = dvd mod dvx (A = dvd in).  Small cases at once
; or from QRA ((q << 4) | r, row dvx at QOA,dvx-2); the rest by shift and
; subtract.  X kept; clobbers Y.
div8:   cmp dvx
        bcc @lt
        cmp #32
        bcs @sl
        ldy dvx
        cpy #16
        bcs @one
        cpy #9
        bcs @sl
        adc QOA-2,y                ; (C clear)
        tay
        lda QRA,y
        tay
        lsr a
        lsr a
        lsr a
        lsr a
        sta dvd
        tya
        and #$0F
        rts
@one:   sbc dvx                    ; dvx 16..31: q 1
        ldy #1
        sty dvd
        rts
@lt:    ldy #0                     ; dvd < dvx: q 0
        sty dvd
        rts
@sl:    lda #0
        ldy #8
@l:     asl dvd
        rol a
        bcs @s
        cmp dvx
        bcc :+
@s:     sbc dvx
        inc dvd
:       dey
        bne @l
        rts

        ENDTAIL

        TAIL "T4"
; tr_l: t_old's pixels X+1 .. tx1; Y is the error, a carry out of Y + 2|dy|
; a step (tr_k, tr_inc patched).  In: C clear.  Clobbers A, X, Y, tyy.
tr_l:   inx
        tya
        adc tdy2
        tay
        bcs tr_s
tr_y:   sty tyy
        txa
        tay
        lda tyv
        sta (bota),y
        ldy tyy
        cpx tx1
        bne tr_l
        rts
tr_s:   tya
tr_k:   adc #0                     ; (operand: 255 - 2dx)
        tay
tr_inc: inc tyv                    ; (INC or DEC)
        jmp tr_y

        ENDTAIL

        TAIL "T6"
; bclip: the bottom row's lines held at YGND+1, between the point before the
; first past YGND and the point after the last (beyond, every line is on the
; screen already); a segment with both points past is past throughout.
; In: BX, BY, bota.  Clobbers A, X, Y.
bclip:  ldx #NX+1                  ; the last point past
:       dex
        lda BY,x
        cmp #YGND+1
        bcc :-
        stx bcl+1
        ldx #0                     ; the first
:       inx
        lda BY,x
        cmp #YGND+1
        bcc :-
        dex
        ldy #0
        txa
        beq bc_s
bc_n:   ldy BX,x                   ; segment X-1 .. X, Y its first pixel
bc_s:   inx
        lda #0
        cpx #NX+1
        bcs :+
        lda BX,x
:       sta bc_e+1
        sta bc_f+1
        cpy bc_e+1
        beq bc_nx
        lda BY-1,x
        cmp #YGND+1
        bcc bc_c
        lda BY,x
        cmp #YGND+1
        bcc bc_c
        lda #YGND+1                ; both past: all of it
:       sta (bota),y
        iny
bc_f:   cpy #0                     ; (operand: the end)
        bne :-
        beq bc_nx                  ; (always)
bc_c:   lda #YGND+1                ; else each line at most YGND+1
:       cmp (bota),y
        bcs :+
        sta (bota),y
:       iny
bc_e:   cpy #0                     ; (operand: the end)
        bne :--
bc_nx:  dex
bcl:    cpx #0                     ; (operand: the last past)
        inx
        bcc bc_n
        rts

        ENDTAIL

; The fills: generated code (gfill), in the code region.
.ifndef SWR                        ; (SWR: in bank 4, swrtab.inc's)
        .segment "FILLS"
TBLK4:  .res 3*TNB+3
TBLK5:  .res 3*TNB+3
        .code
.endif
        .pushseg
        .segment "TABLES"
tenl:   .byte <TEN4L, <TEN5L, >TEN4L, >TEN5L, <(TEN4L+1), <(TEN5L+1), >(TEN4L+1), >(TEN5L+1)
tenh:   .byte <TEN4H, <TEN5H, <(TEN4H+1), <(TEN5H+1)
        .popseg
        .assert >TEN4H = >TEN5H && >(TEN4H+1) = >(TEN5H+1), error, "traceb: TEN4H, TEN5H share a page"

.ifdef SWR
; su_l4 (bank 4): setup's strip unrolled.  Corner i of rows ns-1 and ns (PX, PY
; + Y + i, + 16) into points i+1 (TX, TY; BX, BY), BCL counting the bottom ones
; past YGND; then window entry i of row o + ns - 1 (CLE, CLO + ldCLE + Y + i)
; into box i+1 (CE, CO; the arc build's by the strip's brightness, cte and
; cto).  In: Y = 16 (ns-1).  On to su_m.  Clobbers A, X, Y.
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
.ifdef ARC
        ldy CLE+i,x
        lda (cte),y
        sta CE+1+i
        lda (cto),y
        sta CO+1+i
.else
        lda CLE+i,x
        sta CE+1+i
        lda CLO+i,x
        sta CO+1+i
.endif
.endmacro
        .pushseg
        .segment "B4CODE"
su_l4:  .repeat NX, i
        SUPX i
        .endrepeat
        tya
        clc
        adc ldCLE
        tax
        .repeat NX, i
        SUCL i
        .endrepeat
        jmp su_m
        .assert <CLO + 160 <= 256 && <CLE + 160 <= 256, error, "su_l4: the window's rows in their pages"
        .popseg
.endif
