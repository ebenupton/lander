; ============================================================================
; proj32.s -- the 32K build's projection (.included by land.s): land.project's
; rows of points computed a row at a time, where LAND's bank 7 looked them up
; (SYT7, B1T, PINL7/PINR7, PXF7/PXN7, LERPQ7).  Only r, the row's pixels a
; tile by depth index (R7L, R7H: b32tab.inc), is still a table.
;
; A row (depth index di, r = recip(d), d its depth in 8.8 tiles):
;   - y: corner height h's line is HORIZON + ((CAMH + hg - h) r + 2048) >> 12,
;     plus ey (the camera raised: eyrow), held at 254: ytab makes the 16 of
;     them (YT) by stepping (CAMH + hg) r + 2048 down by r.
;   - x: with M = (1152 + fx) r (fx = 16 cxs; 1152 = XCLIP, corner 0's
;     distance from the line of sight less fx), corner 1's 8.8 x is B1 = 32768
;     + floor((32768 - M) / 256) + r (mod 65536) and each next corner's r more
;     (no carry out for corners 1..NX-2: landgen asserts it); the ends, on the
;     clip planes, are 128 -+ ((1152 r + 32767 or 32768) >> 16) (xrow).
;   - heights: the row's corners' (HT), or for the clip planes' rows lerped
;     between the corner rows either side by 1 - fz; the ends' between
;     corners 0 and 1, NX-2 and NX-1 by fx (lerp4: land.lerp exactly).
; ============================================================================

WH      = $8E                      ; the row's heights, corners 0..NX-1 (11)
Y0      = $99                      ; ytab's 24-bit sum; xrow's M
Q0      = $9C                      ; xrow's 1152 r, 24-bit
LQ      = $9F                      ; lerp4's q (sixteenths)
        .assert NX = 11 && WH + NX <= Y0, error, "WH: NX heights"

; prow32: the rows' screen points (land.project) for rows k = 0..RN: corner
; i's x and y into PX, PY + 16 k + i.  Row 0 is the far clip plane's when FACT
; (heights lerped from rows 0 and 1 by 16 - czs sixteenths), else a corner
; row; row RN is the near clip plane's (heights lerped from rows RN-1 and RN
; when czs is not 0); the rest are corner rows, di = 16 (ZB - k) - czs - DI0.
; Last, the near row's y's are made at least the row before's + 1 and, when
; FACT, row 0's at most row 1's - 1 (row 1's y 0 left alone).
; In: HT (and SHF: hsh first), cxs, czs, ZB, RN, FACT, CAME.  Out: PX, PY rows
; 0..RN; np = NX; HGV; EYV.  Clobbers A, X, Y, rl, rh, tmp, lp, MT0, MT1,
; $8E-$9F, YT.  Caller: project.
prow32: lda SHF                    ; (zsh4 stepped the map: shift HT first)
        beq :+
        jsr hsh
:       jsr hgnd                   ; HGV
        lda #NX
        sta np
        lda RN                     ; 16 RN: the last row's
        asl a
        asl a
        asl a
        asl a
        sta RN16
        lda ZB                     ; DCUR = 16 ZB - DI0 - czs (row 0's as a
        sec                        ; corner row), computed so that nothing
        sbc #9                     ; passes a byte (16 ZB can)
        asl a
        asl a
        asl a
        asl a
        sbc #DI0-9*16-1            ; (C clear: subtracts DI0 - 144)
        .assert DI0 > 9*16 && ZFCLIP >= 9 && ZBACK-ZSKIP >= 9, error, "DCUR: 16 (ZB - 9), DI0 - 144 must be bytes"
        sec
        sbc czs
        sta DCUR
        ldx #0
@row:   stx RK                     ; X = 16 k
        txa
        bne @nf
        lda FACT                   ; row 0: the far clip plane's when FACT
        beq @cor
        ldy #0                     ; heights lerped from rows 0 and 1
        jsr lrow
        ldy #ZFCLIP*16-DI0
        bne @r                     ; (always)
@nf:    cpx RN16
        bne @cor
        ldy #ZCLIP*16-DI0          ; row RN: the near clip plane's
        lda czs
        beq @own                   ; (czs 0: corner row RN is on the plane)
        txa                        ; heights lerped from rows RN-1 and RN
        sec
        sbc #16
        tay
        jsr lrow
        ldy #ZCLIP*16-DI0
        bne @r                     ; (always)
@cor:   ldy DCUR
@own:   lda HT,x                   ; the row's own heights
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
@r:     lda R7L,y                  ; r
        sta rl
        lda R7H,y
        sta rh
        lda #0                     ; EYV: 0, or eyrow's with the camera raised
        sta EYV
        lda CAME
        beq :+
        jsr eyrow
:       lda cxs                    ; the ends' heights, by fx
        sta LQ
        lda WH
        ldy WH+1
        jsr lerp4
        pha
        lda WH+NX-2
        ldy WH+NX-1
        jsr lerp4
        sta WH+NX-1
        pla
        sta WH
        lda WH                     ; HLO, HHI: the row's heights' range
        sta HLO
        sta HHI
        ldy #NX-1
@hr:    lda WH,y
        cmp HLO
        bcs :+
        sta HLO
:       cmp HHI
        bcc :+
        sta HHI
:       dey
        bne @hr
        jsr ytab                   ; YT
        lda RK                     ; the y's: YT by height, into PY + 16 k
        sta tmp                    ; (PY page-aligned)
        lda #>PY
        sta tmp+1
        ldy #NX-1
:       ldx WH,y
        lda YT,x
        sta (tmp),y
        dey
        bpl :-
        ldx RK
        jsr xrow                   ; the x's into PX + 16 k
        ldx RK                     ; the next row, or done
        cpx RN16
        beq @fin
        txa
        clc
        adc #16
        tax
        lda DCUR
        sec
        sbc #16
        sta DCUR
        jmp @row
@fin:   ldx RN16                   ; the near row's y's at least the row
        ldy #NX                    ; before's + 1 (254 at most before: + 1
:       lda PY-16,x                ; stays in a byte)
        cmp PY,x
        bcc :+
        adc #0                     ; (C set: + 1)
        sta PY,x
:       inx
        dey
        bne :--
        lda FACT                   ; the far row's, when lerped, at most row
        beq @x                     ; 1's - 1 (row 1's y 0 left alone)
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
        .assert <PY = 0, error, "PY page-aligned"
        .segment "HIB"
RK:     .res 1                     ; prow32's: the row's 16 k
RN16:   .res 1                     ; 16 RN
DCUR:   .res 1                     ; the row's di as a corner row
YT:     .res 16                    ; ytab's: line by height
        .code

; lrow: WH = a clip row's heights, HT + Y + i lerped towards HT + Y + 16 + i
; by 16 - czs sixteenths (land.lerp(a, b, 256 - fz)), i = 0..NX-1.
; Clobbers A, Y, MT0, MT1, LQ, lp.
lrow:   lda #16
        sec
        sbc czs
        sta LQ
        sty lp
        lda #0
        sta lp+1                   ; (lp: the row's offset; lp+1: i)
:       ldy lp
        lda HT+16,y
        pha
        lda HT,y
        tay
        pla
        sta MT1
        tya
        ldy MT1
        jsr lerp4
        ldy lp+1
        sta WH,y
        inc lp
        inc lp+1
        lda lp+1
        cmp #NX
        bne :-
        rts

; lerp4: A = land.lerp(a, b, 16 q) = a + (((b - a) q + 8) >> 4), floor, for
; heights a (A) and b (Y) of 0..15 and q (LQ) 0..15.  X kept; clobbers A, Y,
; MT0 (a), MT1, MQB.
lerp4:  sta MT0
        sty MT1
        tya
        sec
        sbc MT0                    ; d = b - a (C set: d >= 0)
        beq @z
        bcc @n
        jsr mul4                   ; d q (C clear after)
        adc #8                     ; + 8, >> 4, + a
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc MT0
        rts
@n:     eor #$FF                   ; |d| (C clear: + 1)
        adc #1
        jsr mul4                   ; m = |d| q: a - ((m + 7) >> 4)
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
; mul4: A = A (0..15) times LQ (0..15), at most 225; C clear after.  X, Y
; kept; clobbers MT1, MQB.
mul4:   sta MT1
        lda LQ
        sta MQB
        lda #0
        .repeat 4, k
        lsr MQB
        bcc :+
        clc
        adc MT1
:
        .if k < 3
        asl MT1
        .endif
        .endrepeat
        clc
        rts
        .segment "HIB"
MQB:    .res 1                     ; mul4's multiplier
        .code

; ytab: YT + h = corner height h's line in the row: HORIZON + ((CAMH + hg - h)
; r + 2048) >> 12, plus EYV, held at 254 (land.project's sy), for h = HLO..HHI
; (the row's least and greatest).  The sum is kept 16 times over, Z = 16 ((CAMH
; + hg - h) r) + 32768, 24-bit at Y0 (under 2^24: r < 9440), so the line less
; HORIZON is its top byte; it is stepped down by 16 r (Q0) a height.
; In: rl, rh = r; HGV; EYV; HLO, HHI.  X kept; clobbers A, Y, Y0..Y0+2,
; Q0..Q0+2, MT1.
ytab:   lda HGV                    ; (CAMH + hg - HLO) r, 8 x 16: the
        clc                        ; multiplier's bits from the top, the sum
        adc #CAMH                  ; shifted up
        sec
        sbc HLO
        sta MT1
        lda #0
        sta Y0
        sta Y0+1
        sta Y0+2
        ldy #8
@m:     asl Y0
        rol Y0+1
        rol Y0+2
        asl MT1
        bcc :+
        lda Y0
        clc
        adc rl
        sta Y0
        lda Y0+1
        adc rh
        sta Y0+1
        bcc :+
        inc Y0+2
:       dey
        bne @m
        ldy #4                     ; 16 times
:       asl Y0
        rol Y0+1
        rol Y0+2
        dey
        bne :-
        lda Y0+1                   ; + 32768
        eor #$80
        sta Y0+1
        bmi :+
        inc Y0+2
:       lda rl                     ; Q = 16 r
        sta Q0
        lda rh
        sta Q0+1
        lda #0
        ldy #4
:       asl Q0
        rol Q0+1
        rol a
        dey
        bne :-
        sta Q0+2
        ldy HLO
@h:     lda Y0+2                   ; the line less HORIZON, + EYV + HORIZON
        clc                        ; (-16), held at 254
        adc EYV
        bcs @c
        sbc #-HORIZON-1            ; (C clear: - 16; the line is at least 16:
        jmp @st                    ; no borrow)
@c:     cmp #15                    ; 256 + A - 16 > 254?
        bcs @sat
        adc #256+HORIZON           ; (C clear: + 240)
        bcc @st                    ; (always)
@sat:   lda #254
@st:    sta YT,y
        cpy HHI
        beq @x
        lda Y0                     ; the next height: 16 r less
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
        .assert HORIZON = -16, error, "ytab: HORIZON -16"
        .segment "HIB"
HLO:    .res 1                     ; the row's least and greatest heights
HHI:    .res 1
        .code

; xrow: PX + X + i, the row's x's (land.project's sx): the ends on the clip
; planes from Q = 1152 r, corners 1..NX-2 from B1 and r (the module's header).
; In: X = 16 k, rl, rh = r, cxs.  Clobbers A, X, Y, Y0..Y0+2 (M), Q0..Q0+2.
xrow:   lda rh                     ; Q = r << 7 ...
        lsr a
        sta Q0+2
        lda rl
        ror a
        sta Q0+1
        lda #0
        ror a
        sta Q0
        lda rl                     ; ... + r << 10 (low byte 0)
        asl a
        sta Y0+1
        lda rh
        rol a
        sta Y0+2
        asl Y0+1
        rol Y0+2
        lda Q0+1
        clc
        adc Y0+1
        sta Q0+1
        lda Q0+2
        adc Y0+2
        sta Q0+2
        lda Q0+1                   ; the right end: 128 + ((Q + 32768) >> 16)
        cmp #$80                   ; (C: the carry from Q + 32768)
        lda Q0+2
        adc #128
        sta PX+NX-1,x
        lda Q0                     ; the left: 128 - ((Q + 32767) >> 16), the
        cmp #1                     ; carry from Q + 32767 being [Q1 Q0] >=
        lda Q0+1                   ; $8001
        sbc #$80
        lda Q0+2
        adc #0
        eor #$FF
        sec
        adc #128
        sta PX,x
        lda #0                     ; M = Q + 16 cxs r: cxs r, the multiplier's
        sta Y0                     ; bits from the top (4), the sum shifted up
        sta Y0+1
        sta Y0+2
        lda cxs
        asl a
        asl a
        asl a
        asl a
        sta MT1
        ldy #4
@m:     asl Y0
        rol Y0+1
        rol Y0+2
        asl MT1
        bcc :+
        lda Y0
        clc
        adc rl
        sta Y0
        lda Y0+1
        adc rh
        sta Y0+1
        bcc :+
        inc Y0+2
:       dey
        bne @m
        ldy #4                     ; 16 cxs r
:       asl Y0
        rol Y0+1
        rol Y0+2
        dey
        bne :-
        lda Y0                     ; + Q
        clc
        adc Q0
        sta Y0
        lda Y0+1
        adc Q0+1
        sta Y0+1
        lda Y0+2
        adc Q0+2
        sta Y0+2
        lda #0                     ; 32768 - M, its top two bytes (floor /
        sec                        ; 256), + 32768 (bit 15 flipped), + r: B1
        sbc Y0
        lda #$80
        sbc Y0+1
        sta Y0+1                   ; (B's low byte)
        lda #0
        sbc Y0+2
        eor #$80
        sta Y0+2                   ; (B's high byte)
        lda Y0+1
        clc
        adc rl
        sta Y0+1
        lda Y0+2
        adc rh
        sta Y0+2
        sta PX+1,x                 ; corner 1
        ldy #NX-3                  ; corners 2..NX-2: r more each
:       lda Y0+1
        clc
        adc rl
        sta Y0+1
        lda Y0+2
        adc rh
        sta Y0+2
        sta PX+2,x
        inx
        dey
        bne :-
        rts

; hgnd: the ground under the ship (land.ground): ZSHIP tiles ahead of the
; camera at its x, x = cx + 128 in 8.8 tiles, between the four map corners
; round it, across then down.  The ship's row is row ZB - ZSHIP (map row czt
; + ZSHIP); its column corner 4 (map x cxt) or, at cxs >= 8, corner 5; across
; by q = (cxs + 8) & 15 on that row and the row before (16 bytes back in HT:
; one map row farther), then down by czs.  In: ZB, cxs, czs, HT.  Out: HGV.
; Clobbers A, X, Y, MT0, MT1, MQB, LQ, tmp.
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
        lda cxs                    ; across: q = (cxs + 8) & 15
        eor #8
        sta LQ
        lda HT,x                   ; hx0, the ship's row
        ldy HT+1,x
        jsr lerp4
        sta tmp
        lda HT-16,x                ; hx1, the row before
        ldy HT-15,x
        jsr lerp4
        tay
        lda czs                    ; down: q = czs
        sta LQ
        lda tmp
        jsr lerp4
        sta HGV
        rts

; eyrow: EYV = (CAME (r >> 5) + 64) >> 7, land.project's ey: how much lower
; the row's y's are with the camera CAME above CAMH.  In: rl, rh = r (under
; 8192, so r >> 5 is a byte), CAME.  Out: EYV; X kept.  Clobbers A, Y, MT0, MT1.
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
        clc                        ; at the top
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

; hsh: the heights HT shifted a row after zsh4's map step.  SHF 1: row j
; becomes row j-1's (rows 7 down to 1), row 0 takes HTN; SHF $FF: row j
; becomes row j+1's (0 up to 6), row 7 takes HTN.  Out: SHF = 0.  Clobbers A,
; X, Y.
hsh:    ldx #NX-1
@c:     lda SHF
        bmi @b
        txa                        ; (X: the column; Y: 16 j + the column)
        clc
        adc #$70
        tay
:       lda HT-16,y                ; rows 7 .. 1 from the row before
        sta HT,y
        tya
        sec
        sbc #16
        tay
        cmp #16
        bcs :-
        lda HTN,x
        sta HT,x
        jmp @n
@b:     txa
        tay
:       lda HT+16,y                ; rows 0 .. 6 from the row after
        sta HT,y
        tya
        clc
        adc #16
        tay
        cmp #$70
        bcc :-
        lda HTN,x
        sta HT+$70,x
@n:     dex
        bpl @c
        lda #0
        sta SHF
        rts
