; prow7.s: the rows' points, bank 7 of the sideways RAM build (B7CODE; project
; pages bank 7 in): prow7 and its eyrow, hsh, hgnd, satrow and cliprow7, by
; the bank's tables of the depth index (tools/landgen.py's build7).  Its zero
; page is syp, lp and ram.s's overlay names (CX2 .. HOFF).
;
; A y is SYT7's entry for the row and the height: syp = SYT7 + 32 di + HOFF,
; indexed by the raw height h (the entry is for h - hg + HMAX).  A lerp of
; heights a towards b is LERPQ7's: its row for q (LQLO, LQHI) at (b | 16) - a
; - 1, which with C clear is b - a + LQOFF.  The entry is lerp(0, b - a) - 1
; and the SBC leaves C set, so ADC a gives the height.

.macro PYSE i                      ; corner i's y: SYT7 (syp) by the
        ldy PY+i,x                 ; height in PY, plus EYV (C clear on entry;
        lda (syp),y                ; the sum stays in a byte, or satrow is
        adc EYV                    ; used instead)
        sta PY+i,x
.endmacro
.macro PYH i                       ; corner i's y: SYT7 by HT's height
        ldy HT+i,x
        lda (syp),y
        sta PY+i,x
.endmacro
.macro PYHE i                      ; PYH plus EYV (C clear on entry)
        ldy HT+i,x
        lda (syp),y
        adc EYV
        sta PY+i,x
.endmacro
; EDGESP S: the ends' heights (not y's), lerped by fx (LQP: LERPQ7's row cxs)
; between corners 0 and 1, and NX-2 and NX-1, of row S, into PY,x and
; PY+NX-1,x for PYSE.  C set after.
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
; EDGEY S, L0, L1, NC: the ends' y's: their heights as EDGESP's, then SYT7
; (syp), into PY,x and PY+NX-1,x.  L0, L1: labels for LERPQ7,y loads whose
; operands prow7 patches to the row; blank: (LQP),y.  NC non-blank: C is clear
; on entry and the first CLC is left out.
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
; LERPY SA, SB, CI, IX: a clip row's corner CI: its height lerped from row SA
; towards row SB by 1 - fz ((lp): LERPQ7's row 16 - czs), the rows indexed by X
; if IX.  Corners 0 and NX-1: the height to E0, E3 only; 1 and NX-2: to E1, E2
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
.macro R7BP NOL                    ; rl, rh = R7L, R7H,y (Y = di): the row's r;
.ifblank NOL                       ; NOL non-blank: rh alone
        lda R7L,y
        sta rl
.endif
        lda R7H,y
        sta rh
.endmacro

        .segment "B7CODE"
        .assert LQOFF = 15, error, "LERPQ7 is indexed by (b | 16) - a - 1: LQOFF 15"
; prow7: the rows' screen points, as proto/land.py's project.  For rows j =
; 0..RN, corner i's x and y go to PX, PY + 16 j + i from the raw heights HT +
; 16 j + i.  Row j's depth index is di = 16 ZB - czs - DI0 - 16 j (DCUR), but
; the clip rows' are fixed: row 0 is on the far clip plane (ZFCLIP*16 - DI0)
; and row RN on the near (ZCLIP*16 - DI0).
;
; y: SYT7's (syp).  The ends (corners 0 and NX-1, on the x clip planes) take
; heights lerped by fx between corners 0 and 1, NX-2 and NX-1 (EDGEY, EDGESP).
; A clip row's heights are lerped by 1 - fz between the corner rows either
; side (LERPY; the ends' from E0..E3 at @ape), unless czs is 0, when a corner
; row is on the plane.  With the camera raised (CAME not 0) each y is EYV more
; (eyrow's, or the row's EYV kept in HT+13), held at 254: PYSE and PYHE, satrow
; when EYV >= EYS (a sum could pass 254), cliprow7 for a lerped row.
;
; x: corner 1's from B1T (bp = B1T + 32 di; entry 2 cxs + 1), each further
; corner the last plus rh and a bit of B1T's carry mask (entry 2 cxs), the
; ends PINL7, PINR7 by di.  A clip row's come whole from PXF7 or PXN7 + 11
; cxs.
;
; Last (@fin) the near row's y's are made at least the row before's + 1 and
; row 0's, when lerped, at most row 1's - 1.
;
; MODE: bit 0 the row's heights lerped, bit 6 a clip row, bit 7 the camera
; raised (CAMF).  In: HT, SHF (hsh first if not 0), cxs, czs, ZB, RN, FACT,
; CAME.  Out: PX, PY rows 0..RN; np = NX; HGV, HOFF; EYV (the last row's).
; Clobbers A, X, Y, rl, rh, syp, lp, tmp, MT0, MT1, the overlay's CX2..HOFF;
; patches its own operands @lq2, @lq3, @nj.
prow7:  lda CAME                   ; EHIT: the rows' EYVs (HT+13) stand, CAME
        cmp ECAME                  ; and czs being the last frame's
        bne @en
        lda czs
        cmp ECZS
        bne @en
        lda #$80
        bne @es                    ; (always)
@en:    lda CAME
        sta ECAME
        lda czs
        sta ECZS
        lda #0
@es:    sta EHIT
        lda SHF                    ; (zsh4 stepped a row: HT shifted first)
        beq :+
        jsr hsh
:       ldy cxs                    ; LERPQ7's row for fx (the ends): @lq2,
        lda LQHI,y                 ; @lq3's operands, and LQP
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
        adc CX2                    ; (C clear: 8 cxs + 2 cxs)
        adc cxs
        sta CX11                   ; 11 cxs
        jsr hgnd                   ; HGV, HOFF
        lda #0                     ; CAMF; @nj's target: @r7 with the camera
        ldy #<@r7                  ; at CAMH (every row after row 0 is plain:
        ldx CAME                   ; no test of MODE), else @rm
        beq :+
        lda #$80
        ldy #<@rm
:       sta CAMF
        sty @nj+1
        lda RN                     ; RN16
        asl a
        asl a
        asl a
        asl a
        sta RN16
        lda czs                    ; lp: LERPQ7's row 16 - czs (1 - fz, for
        beq :+                     ; the clip rows; at czs 0 none is lerped)
        lda #16
        sec
        sbc czs
        tay
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
:       lda #NX                    ; np = NX (the game reads it)
        sta np
        lda #0                     ; row 0: tmp = 16 j = 0
        sta tmp
        lda ZB                     ; DCUR = 16 ZB - DI0 - czs, as 16 (ZB - 9)
        sec                        ; - (DI0 - 144) - czs, to stay in a byte
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
        lda FACT                   ; row 0's MODE: bit 0 = FACT (lerped, on the
        beq :+                     ; far plane); bit 6 its di the far plane's
        ldy #ZFCLIP*16-DI0
:       cpy #ZFCLIP*16-DI0
        bne :+
        ora #$40
:       ora CAMF
        sta MODE
        eor #$40                   ; MODE $40 or $41 (a clip row, the camera
        cmp #2                     ; at CAMH) goes on here; any other through
        bcs @row                   ; @row (C set there)
        lsr a                      ; (C = FACT)
        lda #<(SYT7+32*(ZFCLIP*16-DI0))
        ora HOFF                   ; syp = the far plane's SYT7 row + HOFF
        sta syp
        lda #>(SYT7+32*(ZFCLIP*16-DI0))
        sta syp+1
        ldx #0
        bcs :+
        jmp @hp0                   ; (a corner row on the plane: HT's heights)
:       jmp @apf                   ; (lerped towards row 1's)
@altj:  jmp @cam                   ; (MODE not 0 at @rm: the camera raised)
; A row: Y = its di, tmp = 16 j, MODE set; C set.
@row:   lda SYL7,y                 ; syp = SYT7 + 32 di | HOFF (32 di's low 5
        sta bp                     ; bits are 0, HOFF <= HMAX); bp = B1T + 32
        ora HOFF                   ; di (the low bytes alike)
        sta syp
        lda SYH7,y
        sta syp+1
        adc #>B1T - >SYT7 - 1      ; (C set: + the pages between; C clear after)
        sta bp+1
        ldx tmp
@rm:    lda MODE                   ; (MODE 0: a plain row)
        bne @altj
@r7:    R7BP 1                     ; rh (rl is not needed: B1T has the carries)
        .assert >@rm = >@r7, error, "@nj's operand is patched by its low byte: @rm, @r7 must share a page"
        EDGEY HT, @lq2, @lq3, 1    ; the ends' y's, then corners 1..NX-2's
        .repeat NX-2, i
        PYH i+1
        .endrepeat
@pyd:   ldy CX2                    ; the x's: rl = B1T's carry mask for cxs,
        lda (bp),y                 ; corner 1's x its next byte; corner k+2's
        sta rl                     ; = corner k+1's + rh + the mask's bit k
        iny                        ; (the carry out of the low byte).  No
        lda (bp),y                 ; carry out of the high byte (landgen
        sta PX+1,x                 ; asserts it): C clear after
        .repeat NX-3, k
        lsr rl
        adc rh
        sta PX+2+k,x
        .endrepeat
        ldy DCUR                   ; the ends' x's: the clip planes' at this di
        lda PINL7,y
        sta PX,x
        lda PINR7,y
        sta PX+NX-1,x              ; (within XL..XR: these rows' di >= NCLP)
        .assert (ZCLIP+1)*16 - DI0 - 15 >= NCLP, error, "a corner row could overhang XL, XR"
@nx:    txa                        ; the next row: X + 16 (C clear from the
        adc #16                    ; x's); the near clip row (16 RN) is last
        cmp RN16
        beq @lst
        tax
        lda DCUR                   ; (C clear: X + 16 < RN16) di - 16
        sbc #15
        sta DCUR
        tay
        lda syp+1                  ; (C set) SYT7's and B1T's rows 512 bytes
        sbc #2                     ; back: the pages alone change
        sta syp+1
        adc #>B1T - >SYT7 - 1      ; (C set)
        sta bp+1
@nj:    jmp @rm                    ; (operand patched: @r7 when CAMF is 0)
@nxf:   txa                        ; row 1 after the far clip row (X = 0, C set
        adc #15                    ; from @pxc's CPX): tmp = 16; DCUR, Y = row
        sta tmp                    ; 1's di
        lda DCUR
        sbc #15                    ; (C clear: - 16)
        sta DCUR
        tay
        jmp @row
@lst:   sta tmp                    ; the near clip row: tmp = 16 RN
        bit CAMF
        bmi @lsc
        tax                        ; (the camera at CAMH) syp = the near
        lda #<(SYT7+32*(ZCLIP*16-DI0)) ; plane's SYT7 row + HOFF
        ora HOFF
        sta syp
        lda #>(SYT7+32*(ZCLIP*16-DI0))
        sta syp+1
        lda czs
        bne :+
        jmp @hp0                   ; (czs 0: corner row RN is on the plane)
:       jmp @apz                   ; (lerped from row RN-1's)
@lsc:   ldy #ZCLIP*16-DI0          ; (the camera raised) MODE $C0, or $C1 when
        lda czs                    ; lerped; @row, then @cam
        beq :+
        lda #1
:       ora #$40
        ora CAMF
        sta MODE
        jmp @row
@fin:   ldx RN16                   ; the near row's y's at least the row
        .repeat NX, i              ; before's + 1 (a y is 254 at most)
        lda PY-16+i,x
        cmp PY+i,x
        bcc :+
        adc #0                     ; (C set: + 1)
        sta PY+i,x
:
        .endrepeat
        lda FACT                   ; a lerped row 0's y's at most row 1's - 1
        bne :+
        rts
:
        .repeat NX, i              ; (a row 1 y of 0 is left alone)
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
        EDGEY HT                   ; CAMH): X = 0 or 16 RN, syp set
        .repeat NX-2, i
        PYH i+1
        .endrepeat
        jmp @pxc
@ap:    txa                        ; a lerped clip row, the camera raised:
        beq @apf                   ; row 0
        jmp @apz                   ; or row RN
; The far clip row (X = 0; syp its SYT7 row; czs not 0): heights lerped from
; row 0's (HT) towards row 1's (HT+16) by 1 - fz, corners 1..NX-2 straight to
; y's in PY, the ends' to E0..E3.
@apf:   .repeat NX, i
        LERPY HT, HT+16, i, 0
        .endrepeat
        jmp @ape
; The near clip row (X = 16 RN; syp its SYT7 row): heights lerped from row
; RN-1's (HT-16,x) towards row RN's (HT,x) by 1 - fz, likewise.
@apz:   .repeat NX, i
        LERPY HT-16, HT, i, 1
        .endrepeat
@ape:   lda E1                     ; the ends: heights by fx (LQP), then y's
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
        bit MODE                   ; (the camera raised: EYV more, held at 254)
        bmi :+
        jmp @pxc
:       jsr cliprow7
        jmp @pxc
@cam:   R7BP                       ; the camera raised: rl, rh = r; EYV kept
        bit EHIT                   ; (HT+13,x) or eyrow's (X kept)
        bpl @ec
        lda HT+13,x
        sta EYV
        jmp @ek
@ec:    jsr eyrow
        lda EYV
        sta HT+13,x
@ek:    lda MODE
        lsr a
        bcc :+
        jmp @ap                    ; (bit 0: a lerped clip row)
:
        EDGESP HT                  ; the ends' heights into PY; then the y's,
        lda EYV                    ; EYV more: satrow when a sum could pass
        cmp #EYS                   ; 254, else PYSE (the ends) and PYHE
        bcc :+
        jsr satrow
        jmp @cx
:       clc                        ; (EDGESP leaves C set)
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
; The clip rows' x's, by cxs alone: PXF7 + 11 cxs for row 0, PXN7 + 11 cxs for
; row RN; both within XL..XR (landgen asserts it).  MODE back to CAMF.
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

; eyrow: EYV = (CAME (r >> 5) + 64) >> 7, the lines the row drops with the
; camera raised by CAME.  In: rl, rh = r (under 8192, so r >> 5 is a byte),
; CAME.  X kept; clobbers A, Y, MT0, MT1.
        .assert DI0 > 128, error, "eyrow: r < 8192"
eyrow:  lda rl                     ; r >> 5: (rl & $E0 | rh) rotated left 3
        and #$E0
        ora rh
        .repeat 3
        asl a
        adc #0
        .endrepeat
        sta MT0
        lda CAME                   ; CAME times it: the multiplier's bits out
        lsr a                      ; of MT1's bottom, the product shifted in at
        sta MT1                    ; the top
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
ECAME:  .byte $FF                  ; the CAME and czs the rows' EYVs are for
ECZS:   .byte 0
EHIT:   .byte 0                    ; $80: kept

; hsh: the heights HT shifted a row after zsh4's step.  SHF 1: rows 0..6 move
; to 1..7 and row 0 takes HTN; SHF $FF: rows 1..7 move to 0..6 and row 7 takes
; HTN.  SHF = 0 after.  Clobbers A, X.
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

; hgnd: the ground under the ship (proto/land.py's ground): ZSHIP tiles ahead
; of the camera, between the four corners round it.  The ship's row is row ZB
; - ZSHIP; its column corner 4, or 5 at cxs >= 8.  The heights are lerped
; across by q = (cxs + 8) & 15 on that row and the row before (one map row
; farther), then between the two by q = czs.  Out: HGV = hg; HOFF = HMAX - hg
; (prow7 ORs it into syp).  Clobbers A, X, Y, lp, tmp.
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
        lda HT+1,x                 ; the ship's row: hx0
        ora #16
        clc
        sbc HT,x
        tay
        lda (lp),y
        adc HT,x
        sta tmp+1
        lda HT-15,x                ; the row before (a map row farther): hx1
        ora #16
        clc
        sbc HT-16,x
        tay
        lda (lp),y
        adc HT-16,x
        ora #16
        clc
        sbc tmp+1                  ; hx1 - hx0 + LQOFF
        sta tmp
        ldy czs                    ; between them: q = czs
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
        ldy tmp
        lda (lp),y
        adc tmp+1                  ; hg
        sta HGV
        eor #$FF                   ; HOFF = HMAX - hg
        sec
        adc #HMAX
        sta HOFF
        rts

; satrow: prow7's row X (16 j) with the camera raised so far (EYV >= EYS)
; that a y plus EYV could pass 254: each corner's y is SYT7's (syp) plus EYV,
; held at 254.  The ends' heights are read from PY (EDGESP's), corners
; 1..NX-2's from HT.  X kept; clobbers A, Y, MT0, MT1.
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

; cliprow7: a clip row's y's (PY + X .. X + NX-1), made without EYV, each EYV
; more and held at 254.  Out: X = tmp (the row's 16 j).  Clobbers A, MT0.
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
