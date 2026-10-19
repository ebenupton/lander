; prow7.s: the rows' points, bank 7 of the sideways RAM build, by tables of
; the depth index (gen32.py's bank 7: tools/landgen.py's build7).  Its zero
; page is ramswr.s's overlay names (CX2 .. HOFF) and syp, lp.

.macro PYSE i                       ; (bank 7) corner i's y: SYT7 (syp) by the
        ldy PY+i,x                  ; height in PY + EYV, the camera raised
        lda (syp),y                 ; (C clear on entry; the sum stays within a
        adc EYV                     ; byte, or satrow is used instead)
        sta PY+i,x
.endmacro
.macro PYH i                        ; (bank 7) corner i's y: SYT7 by HT's height
        ldy HT+i,x
        lda (syp),y
        sta PY+i,x
.endmacro
.macro PYHE i                       ; (bank 7) PYH + EYV (C clear on entry)
        ldy HT+i,x
        lda (syp),y
        adc EYV
        sta PY+i,x
.endmacro
; (bank 7) The ends' heights, not y's: between corners 0 and 1, and NX-2 and
; NX-1, of row S by fx (LQP: LERPQ7's row q = cxs), into PY,x and PY+NX-1,x for
; PYSE.  (b | 16) - a - 1 with C clear = b - a + LQOFF, the row's index; the
; table holds lerp - 1 and C is set after, so the ADC gives a + lerp.
.macro EDGESP S
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
; (bank 7) The ends' y's: their heights from row S as EDGESP's, then SYT7
; (syp), into PY,x and PY+NX-1,x.  L0, L1: labels for LERPQ7,y loads whose
; operands prow7 patches to the row; blank: (LQP),y.  NC non-blank: C is known
; clear and the first CLC is left out.
.macro EDGEY S, L0, L1, NC
        lda S+1,x
        ora #16
.ifblank NC
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
; (bank 7) A clip plane's row, corner CI: its height between rows SA and SB by
; 1 - fz ((lp): LERPQ7's row q = 16 - czs, the EDGESP trick), indexed by X if
; IX.  Corners 0 and NX-1: the height to E0, E3 only; 1 and NX-2: to E1, E2
; and, like the rest, through SYT7 (syp) into PY.
.macro LERPY SA, SB, CI, IX
.if IX
        lda SB+CI,x
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
.macro R7BP NOL                     ; (bank 7) the row's r: rl, rh = R7L, R7H[Y]
.ifblank NOL                        ; (Y = di); NOL non-blank: rh alone
        lda R7L,y
        sta rl
.endif
        lda R7H,y
        sta rh
.endmacro

; ---------------------------------------------------------------- bank 7
        .segment "B7CODE"
        .assert LQOFF = 15, error, "LERPQ7 is indexed by (b | 16) - a - 1: LQOFF 15"
; prow7 (bank 7, B7CODE; bank 7 paged in): the rows' screen points,
; land.project.  For rows j = 0..RN (nr of them) corner i's x and y go to PX,
; PY + 16 j + i from the raw heights HT + 16 j + i.  A row's depth index is di
; = 16 ZB - czs - DI0 - 16 j (DCUR, 16 less each row); the clip rows have fixed
; ones: row 0 on the far clip plane (ZFCLIP*16 - DI0, when FACT, or when ZB =
; ZFCLIP and czs = 0 puts a corner row on it) and row RN, the near clip plane's
; (ZCLIP*16 - DI0).  A y is SYT7's for the row (syp = SYT7 + 32 di, HOFF ORed
; into the low byte) indexed by the raw height: its entry is for h - hg + HMAX.
; The edges (corners 0 and NX-1, the x clip planes) have their heights lerped
; by fx between corners 0 and 1, NX-2 and NX-1 (LERPQ7's row cxs: @lq2, @lq3's
; operands, or LQP); the near clip row's heights, and the far's when FACT,
; are lerped by 1 - fz between the corner rows either side (LERPQ7's row 16 -
; czs at lp; LERPY) with the edges' at E0..E3 for @ape.  The x's: corner 1's
; from B1T (bp = B1T + 32 di; entry 2 cxs + 1), each further corner the last
; plus rh and a bit of B1T's carry mask (entry 2 cxs: rl), the edges' PINL7,
; PINR7 by di; a clip row's come straight from PXF7 or PXN7 + 11 cxs (CX11).
; With the camera raised (CAME not 0) each row's y's are EYV more (eyrow;
; PYSE, PYHE, or satrow when EYV >= EYS could carry a y past 254; cliprow7 for
; a lerped row), held at 254.  Last (@fin) the near row's y's are made at
; least the row before's + 1 and row 0's, when FACT, at most row 1's - 1.
; MODE: bit 0 the row's heights lerped (LERPY), bit 6 a clip row (x's from
; PXF7/PXN7), bit 7 the camera raised (CAMF: $80 or 0).  In: HT (and SHF: hsh
; first), cxs, czs, ZB, RN, FACT, CAME.  Out: PX, PY rows 0..RN; np = NX;
; HGV, HOFF (hgnd); EYV (the last row's).  Clobbers A, X, Y, rl, rh, syp, lp,
; tmp, MT0, MT1, zero page CX2..HOFF, and its own operands @lq2, @lq3, @nj.
; Caller: project (pg7 before, pg4 after).
prow7:  lda SHF                    ; (zsh4 stepped the map: shift HT first)
        beq :+
        jsr hsh
:       ldy cxs                    ; LERPQ7's row for fx (the edges): @lq2,
                                   ; @lq3's operands and LQP
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
        sta CX2                    ; 2 cxs
        asl a
        asl a
        adc CX2                    ; (C clear: 8 cxs + 2 cxs, no carry)
        adc cxs
        sta CX11                   ; 11 cxs
        jsr hgnd                   ; HGV, HOFF
        lda #0                     ; CAMF, and @nj's target: @r7 when the camera
        ldy #<@r7                  ; is at CAMH (every row after row 0 then has
        ldx CAME                   ; MODE 0: no test), @rm otherwise
        beq :+
        lda #$80
        ldy #<@rm
:       sta CAMF
        sty @nj+1
        lda RN                     ; RN16 = 16 RN
        asl a
        asl a
        asl a
        asl a
        sta RN16
        lda czs                    ; lp = LERPQ7's row 16 - czs (1 - fz: the
        beq :+                     ; clip rows' heights; unused at czs 0, when
                                   ; no row is lerped)
        lda #16
        sec
        sbc czs
        tay
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
:       lda #NX                    ; (np: NX, game.s's; the strips use NX)
        sta np
        lda #0                     ; row 0: tmp = 16 j = 0
        sta tmp
        lda ZB                     ; DCUR = 16 ZB - DI0 - czs, computed as 16
        sec                        ; (ZB - 9) - (DI0 - 144) - czs so that
                                   ; nothing passes a byte (16 ZB can)
        sbc #9
        asl a
        asl a
        asl a
        asl a
        sbc #DI0-9*16-1            ; (C clear: subtracts DI0 - 144)
        .assert DI0 > 9*16 && ZFCLIP >= 9 && ZBACK-ZSKIP >= 9, error, "DCUR: 16 (ZB - 9), DI0 - 144 must be bytes"
        sec
        sbc czs
        sta DCUR
        tay
        lda FACT                   ; MODE for row 0: bit 0 = FACT (its heights
        beq :+                     ; lerped; its di the far plane's), bit 6 if
                                   ; its di is the far plane's either way
        ldy #ZFCLIP*16-DI0
:       cpy #ZFCLIP*16-DI0
        bne :+
        ora #$40
:       ora CAMF
        sta MODE
        eor #$40                   ; MODE $40 or $41 (a clip row, the camera at
        cmp #2                     ; CAMH) is handled here; every other kind
                                   ; goes through @row (C set there)
        bcs @row
        lsr a                      ; (C = FACT)
        lda #<(SYT7+32*(ZFCLIP*16-DI0))
        ora HOFF                   ; syp = the far plane's SYT7 row + HOFF
        sta syp
        lda #>(SYT7+32*(ZFCLIP*16-DI0))
        sta syp+1
        ldx #0
        bcs :+
        jmp @hp0                   ; (a corner row on the plane: HT's heights)
:       jmp @apf                   ; (lerped to row 1's)
@altj:  jmp @cam                   ; (MODE not 0 here has bit 7 set: the camera
                                   ; raised)
; A row: Y = its di, X = tmp = 16 j, MODE; C set on entry.
@row:   lda SYL7,y                 ; syp = SYT7 + 32 di | HOFF (32 di's low 5
        sta bp                     ; bits are 0, HOFF <= HMAX); bp = B1T + 32 di
                                   ; (the low bytes alike)
        ora HOFF
        sta syp
        lda SYH7,y
        sta syp+1
        adc #>B1T - >SYT7 - 1      ; (C set: + the pages between; C clear after)
        sta bp+1
        ldx tmp
@rm:    lda MODE                   ; (MODE 0: a plain row, the camera at CAMH)
        bne @altj
@r7:    R7BP 1                     ; rh = r's high byte (rl is not needed: B1T
                                   ; holds the carries)
        .assert >@rm = >@r7, error, "@nj's operand is patched by its low byte: @rm, @r7 must share a page"
        EDGEY HT, @lq2, @lq3, 1    ; the edges' y's (heights lerped by fx), then
                                   ; corners 1..NX-2's
        .repeat NX-2, i
        PYH i+1
        .endrepeat
@pyd:   ldy CX2                    ; the x's: rl = B1T's carry mask for cxs,
        lda (bp),y                 ; corner 1's x from its next byte; corner
        sta rl                     ; k+2's x = corner k+1's + rh + bit k of the
        iny                        ; mask (the carry out of B's low byte); no
        lda (bp),y                 ; carry out of the high byte for corners
                                   ; 1..NX-2 (landgen asserts it): C clear after
        sta PX+1,x
        .repeat NX-3, k
        lsr rl
        adc rh
        sta PX+2+k,x
        .endrepeat
        ldy DCUR                   ; the edges' x's: the clip planes' at this di
        lda PINL7,y
        sta PX,x
        lda PINR7,y
        sta PX+NX-1,x              ; (within XL..XR: CLP7 is 0 from di NCLP, and
                                   ; these rows' di >= 16)
        .assert (ZCLIP+1)*16 - DI0 - 15 >= NCLP, error, "a corner row could overhang XL, XR"
@nx:    txa                        ; the next row: X = tmp + 16 (C clear from
        adc #16                    ; the x's); the near clip row (16 RN) is the
                                   ; last and is not a corner row
        cmp RN16
        beq @lst
        tax
        lda DCUR                   ; (C clear: tmp + 16 < RN16) di - 16
        sbc #15
        sta DCUR
        tay
        lda syp+1                  ; (C set) SYT7's and B1T's rows 512 bytes
                                   ; back: the pages
        sbc #2                     ; alone change
        sta syp+1
        adc #>B1T - >SYT7 - 1      ; (C set)
        sta bp+1
@nj:    jmp @rm                    ; (operand patched: @r7 when CAMF is 0)
@nxf:   txa                        ; row 1 after the far clip row (X = 0, C set
        adc #15                    ; from @pxc's CPX): tmp = 16; DCUR, Y = row
                                   ; 1's di; syp, bp from @row's tables
        sta tmp
        lda DCUR
        sbc #15                    ; (C clear: - 16)
        sta DCUR
        tay
        jmp @row
@lst:   sta tmp                    ; the near clip row: tmp = 16 RN
        bit CAMF
        bmi @lsc
        tax                        ; (camera at CAMH) X = 16 RN; syp = the near
        lda #<(SYT7+32*(ZCLIP*16-DI0)) ; plane's SYT7 row + HOFF
        ora HOFF
        sta syp
        lda #>(SYT7+32*(ZCLIP*16-DI0))
        sta syp+1
        lda czs
        bne :+
        jmp @hp0                   ; (czs 0: corner row RN is on the plane;
                                   ; heights from HT)
:       jmp @apz                   ; (lerped from row RN-1's)
@lsc:   ldy #ZCLIP*16-DI0          ; (the camera raised) MODE $C0, or $C1 when
        lda czs                    ; lerped; @row, then @alt's @cam
        beq :+
        lda #1
:       ora #$40
        ora CAMF
        sta MODE
        jmp @row
@fin:   ldx RN16                   ; the near clip row's y's at least the row
        .repeat NX, i              ; before's + 1 (y's are 254 at most, so + 1
                                   ; stays in a byte)
        lda PY-16+i,x
        cmp PY+i,x
        bcc :+
        adc #0                     ; (C set: + 1)
        sta PY+i,x
:
        .endrepeat
        lda FACT                   ; the far clip row's y's, when lerped, at
                                   ; most row 1's - 1
        bne :+
        rts
:
        .repeat NX, i              ; (row 1's y 0 left alone: 0 - 1 would wrap)
        lda PY+i
        cmp PY+16+i
        bcc :+
        ldx PY+16+i
        beq :+
        dex
        stx PY+i
:
        .endrepeat
        rts
@hp0:                              ; a clip row's y's from HT (the camera at
                                   ; CAMH): X = 0 or 16 RN, syp set
        EDGEY HT
        .repeat NX-2, i
        PYH i+1
        .endrepeat
        jmp @pxc
@ap:    txa                        ; a lerped clip row with the camera raised
                                   ; (EYV set): row 0 or RN
        beq @apf
        jmp @apz
; The far clip row (row 0; syp its SYT7 row): heights lerped from row 0's (HT)
; towards row 1's (HT+16) by 1 - fz (lp: LERPQ7's row 16 - czs; czs not 0),
; corners 1..NX-2 straight to y's in PY, the edges' heights to E0..E3.
@apf:   .repeat NX, i
        LERPY HT, HT+16, i, 0
        .endrepeat
        jmp @ape
; The near clip row (X = 16 RN; syp its SYT7 row): heights lerped from row
; RN-1's (HT-16,x) towards row RN's (HT,x) by 1 - fz, likewise.
@apz:   .repeat NX, i
        LERPY HT-16, HT, i, 1
        .endrepeat
@ape:   lda E1                     ; the edges: heights by fx (LQP), then y's
        ora #16                    ; (LERPQ7 at (b | 16) - a - 1, + a, C set)
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
        bit MODE                   ; (the camera raised: EYV added, held at 254)
        bmi :+
        jmp @pxc
:       jsr cliprow7
        jmp @pxc
@cam:   R7BP                       ; the camera raised: rl, rh = r, then EYV
        jsr eyrow                  ; (X kept)
        lda MODE
        lsr a
        bcc :+
        jmp @ap                    ; (bit 0: a lerped clip row)
:
        EDGESP HT                  ; the edges' heights by fx into PY, x; then
        lda EYV                    ; the y's, EYV more: satrow when a sum could
                                   ; pass 254, else PYSE (edges) and PYHE
        cmp #EYS
        bcc :+
        jsr satrow
        jmp @cx
:       clc                        ; (C clear for the ADC EYVs: EDGESP sets it)
        .repeat NX, i
        .if i = 0 || i = NX-1
        PYSE i
        .else
        PYHE i
        .endif
        .endrepeat
@cx:    bit MODE                   ; bit 6: a clip row, x's PXF7/PXN7; else B1T
        bvs @pxc
        jmp @pyd
; The clip rows' x's, by cxs alone: PXF7 + 11 cxs for row 0 (on the far plane,
; di ZFCLIP*16 - DI0), PXN7 + 11 cxs for row RN (the near plane's, di ZCLIP*16
; - DI0); both within XL..XR (landgen asserts it).  MODE back to CAMF.
        .assert NX = 11, error, "PXF7, PXN7 are 11 x's a cxs"
@pxc:   lda CAMF
        sta MODE
        ldy CX11
        cpx #0
        bne @pxn
        .repeat NX, i
        lda PXF7+i,y
        sta PX+i
        .endrepeat
        jmp @nxf
@pxn:   .repeat NX, i              ; (the near clip row: the last)
        lda PXN7+i,y
        sta PX+i,x
        .endrepeat
        jmp @fin


; eyrow (bank 7): EYV = (CAME (r >> 5) + 64) >> 7, land.project's ey: how much
; lower the row's y's are with the camera CAME above CAMH.  In: rl, rh = r (the
; row's pixels a tile, 8.8; under 8192, so r >> 5 is a byte), CAME.  Out: EYV,
; X kept; C clear (the trailing CLC: nothing relies on it, @cam's LSR follows).
; Clobbers A, Y, MT0, MT1.  Caller: prow7 (@cam).
eyrow:  lda rh
        sta MT1
        lda rl
        .repeat 5
        lsr MT1
        ror a
        .endrepeat
        sta MT0                    ; r >> 5
        lda CAME
        sta MT1
        lda #0
        ldy #8
        lsr MT1                    ; CAME * MT0, 8 by 8: the multiplier's bits
@m:     bcc :+                     ; out of MT1's bottom, the product shifted in
                                   ; at the top
        clc
        adc MT0
:       ror a
        ror MT1
        dey
        bne @m
        tay                        ; (A high, MT1 low) + 64, >> 7
        lda MT1
        clc
        adc #64
        sta MT1
        tya
        adc #0
        asl MT1
        rol a
        sta EYV
        rts

; hsh (bank 7): the heights HT shifted a row after zsh4's map step.  SHF 1:
; row j becomes row j-1's (rows 7 down to 1), row 0 takes HTN; SHF $FF: row j
; becomes row j+1's (0 up to 6), row 7 takes HTN.  Out: SHF = 0.  Clobbers A,
; X.  Caller: prow7.
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

; hgnd (bank 7): the ground under the ship, land.ground: ZSHIP tiles ahead of
; the camera at its x, i.e. x = cx + 128 in 8.8 tiles, between the four map
; corners surrounding it, across then down (each by LERPQ7: land.lerp).  The
; ship's row is row ZB - ZSHIP (its map row czt + ZSHIP); its column is corner
; 4 (map x cxt) or, at cxs >= 8, corner 5; across by q = (cxs + 8) & 15
; sixteenths on that row and the row before (16 bytes back in HT: one map row
; farther), then down by q = czs.  In: ZB, cxs, czs, HT, LQLO/LQHI.  Out: HGV
; = hg (the game reads it), HOFF = HMAX - hg (the offset into a SYT7 row for a
; raw height: prow7 ORs it into syp).  Clobbers A, X, Y, lp, tmp.  Caller:
; prow7.
hgnd:   lda ZB                     ; X = 16 (ZB - ZSHIP) + 4 + (cxs >= 8)
        sec
        sbc #ZSHIP
        asl a
        asl a
        asl a
        asl a
        adc #4                     ; (C clear: ZB - ZSHIP < 16)
        ldy cxs
        cpy #8
        adc #0
        tax
        lda cxs                    ; across: LERPQ7's row q = (cxs + 8) & 15
        eor #8
        tay
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
        lda HT+1,x                 ; the ship's row: (b | 16) - a - 1 = b - a +
        ora #16                    ; LQOFF, the table's index; its entry is
        clc                        ; lerp(0, b - a) - 1, added to a with C set
        sbc HT,x
        tay
        lda (lp),y
        adc HT,x
        sta tmp+1                  ; hx0
        lda HT-15,x                ; the row before (one map row farther)
        ora #16
        clc
        sbc HT-16,x
        tay
        lda (lp),y
        adc HT-16,x                ; hx1
        ora #16
        clc
        sbc tmp+1                  ; hx1 - hx0 + LQOFF
        sta tmp
        ldy czs                    ; down: q = czs
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
        ldy tmp
        lda (lp),y
        adc tmp+1                  ; hg = lerp(hx0, hx1, czs/16)
        sta HGV
        eor #$FF                   ; HOFF = HMAX - hg
        sec
        adc #HMAX
        sta HOFF
        rts
; satrow (bank 7, CLP7's spare): prow7's row X (16 j) with the camera so far
; raised (EYV >= EYS) that a y plus EYV could pass 254: each corner's y from
; SYT7 (syp) plus EYV, held at 254 (land.project's min(254, sy)).  The edges'
; heights are read from PY (EDGESP's), corners 1..NX-2's from HT.  In: X, syp,
; EYV.  Out: PY + X.., X kept.  Clobbers A, Y, MT0, MT1.  Caller: prow7 (@cam).
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
sat1:   lda (syp),y                ; PY,x = min(254, SYT7[Y] + EYV)
sat2:   clc                        ; PY,x = min(254, A + EYV)
        adc EYV
        bcs :+
        cmp #255
        bcc :++
:       lda #254
:       sta PY,x
        rts
; cliprow7 (bank 7): a clip row's y's (PY + X.., X = 16 j), computed without
; EYV, each EYV more and held at 254.  Out: X = tmp (the row's 16 j).  Clobbers
; A, MT0.  Caller: prow7 (@ape, the camera raised).
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
