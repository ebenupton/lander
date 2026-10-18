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
        asl a                      ; corner row), mod 256 (the same byte); the
        asl a                      ; fourth ASL's C: ZB's bit 4, set for ZB =
        asl a                      ; 16 or 17 (as hgnd)
        asl a
        sbc #<DI0                  ; (C set: subtracts DI0)
        .assert ZFCLIP = 16, error, "DCUR: ZB (ZFCLIP or ZFCLIP+1) has bit 4 set"
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
        jsr lrng
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
        jsr lrng
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
        lda HT+11,x                ; corners 1..NX-2's range (hrng's)
        sta HLO
        lda HT+12,x
        sta HHI
@r:     lda R7L,y                  ; r
        sta rl
        lda R7H,y
        sta rh
        lda CAME                   ; EYV: 0, or eyrow's with the camera raised
        bne @ey
        sta EYV                    ; (A = 0)
        beq :+                     ; (always)
@ey:    jsr eyrow
:       lda cxs                    ; the ends' heights, by fx
        sta LQ
        lda WH
        ldy WH+1
        jsr lerp4
        sta WH                     ; HLO, HHI widened to the ends (lerp4 keeps
        cmp HLO                    ; WH, HLO, HHI: it clobbers only A, Y, MT0,
        bcs :+                     ; MT1, MQB)
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
:
        jsr ytab                   ; YT
        lda RK                     ; the y's: YT by height, into PY + 16 k
        sta @py+1                  ; (PY page-aligned: the store's low byte)
        ldy #NX-1
:       ldx WH,y
        lda YT,x
@py:    sta PY,y                   ; (operand low byte: RK)
        dey
        bpl :-
        ldx RK
        jsr xrow                   ; the x's into PX + 16 k
        lda RK                     ; the next row, or done
        cmp RN16
        beq @fin
        adc #16                    ; (C clear: cmp RN16 found RK < RN16, both
        sta RK                     ; 16 k, so RK + 16 <= $F0 can't carry; then
        tax                        ; sbc #15 with C clear takes 16)
        lda DCUR
        sbc #15
        sta DCUR
        jmp @nf                    ; (X = RK, not 0: @row's STX and row-0 test
                                   ; skipped)
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
        .segment "SG1"
YT:     .res 16                    ; ytab's: line by height
        .code

; lrng: HLO, HHI = the range of corners 1..NX-2 over HT rows Y/16 and Y/16 + 1
; (hrng's, in each row's columns 11, 12): a lerp between them stays within it.
; X kept.
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
; hrng: HT row X/16's corners 1..NX-2: their least into HT+11,x, greatest
; into HT+12,x (the row's spare columns), for prow32's ranges.  Whenever HT
; changes: project's reload (every row), hsh (the new row; the others move
; with their heights).  X kept; clobbers A, Y, MT0, MT1.
hrng:   txa
        ora #NX-2                  ; Y: corner NX-2 down to 2
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

; lrow: WH = a clip row's heights, HT + Y + i lerped towards HT + Y + 16 + i
; by 16 - czs sixteenths (land.lerp(a, b, 256 - fz)), i = 0..NX-1.
; In: X = RK (both callers); out: X = RK again.  Clobbers A, Y, MT0, MT1, LQ.
lrow:   lda #16
        sec
        sbc czs
        sta LQ
        ldx #0                     ; X: i; Y: the row's offset + i (lerp4e
:       lda HT,y                   ; keeps X and Y)
        sta MT0                    ; a
        lda HT+16,y
        jsr lerp4e                 ; lerp4 past its sta MT0, tya (A = b)
        sta WH,x
        iny
        inx
        cpx #NX
        bne :-
        ldx RK                     ; X back (X = RK at both jsr lrow)
        rts

; lerp4: A = land.lerp(a, b, 16 q) = a + (((b - a) q + 8) >> 4), floor, for
; heights a (A) and b (Y) of 0..15 and q (LQ) 0..15.  X kept; clobbers A, Y,
; MT0 (a), MT1, MQB.
lerp4:  sta MT0

        tya
lerp4e: sec                        ; (lrow's entry: A = b, MT0 = a)
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
        .repeat 4, k
        .if k = 0
        lsr a                      ; bit 0 from A; MQB = q >> 1 (as before)
        sta MQB
        lda #0                     ; (C kept)
        bcc :+
        lda MT1                    ; 0 + MT1
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
        rts                        ; C clear: the last bcc's, or its adc's
                                   ; (the sum at most 225)
        .segment "SG1"
        .code

; ytab: YT + h = corner height h's line in the row: HORIZON + ((CAMH + hg - h)
; r + 2048) >> 12, plus EYV, held at 254 (land.project's sy), for h = HLO..HHI
; (the row's least and greatest).  The sum is kept 16 times over, Z = 16 ((CAMH
; + hg - h) r) + 32768, 24-bit at Y0 (under 2^24: r < 9440), so the line less
; HORIZON is its top byte; it is stepped down by 16 r (Q0) a height.
; In: rl, rh = r; HGV; EYV; HLO, HHI.  Clobbers A, X, Y, Y0..Y0+2,
; Q0..Q0+2.
ytab:   lda rh                     ; Q = 4 r, the multiplicand (r < 8192:
        sta Q0+1                   ; eyrow's assert, so 4 r < 32768)
        lda rl
        asl a
        rol Q0+1
        asl a
        rol Q0+1
        sta Q0
        lda HGV                    ; m = CAMH + hg - HLO
        clc
        adc #CAMH
        sec
        sbc HLO
        lsr a                      ; 4 m r + 8192, 8 x 16 from m's bottom bit:
        sta Y0                     ; the sum's top bytes in A and Y0+1, started
        lda #0                     ; at 8192 (A = 32), shifted down into Y0 as
        sta Y0+1                   ; m's bits leave it
        ldx #8
        lda #32
@m:     bcc :+
        tay
        lda Y0+1
        clc
        adc Q0
        sta Y0+1
        tya
        adc Q0+1
:       ror a
        ror Y0+1
        ror Y0
        dex
        bne @m
:       asl Y0                     ; 4 times: 16 m r + 32768 (4 m r + 8192 <
        rol Y0+1                   ; 2^22: no bit lost)
        rol a
        asl Y0
        rol Y0+1
        rol a
        sta Y0+2
:       lda #0                     ; Q = 16 r: 4 r shifted twice more
        asl Q0
        rol Q0+1
        rol a
:       asl Q0
        rol Q0+1
        rol a
        sta Q0+2
        ldy HLO
@h:     lda Y0+2                   ; the line less HORIZON, + EYV + HORIZON
        clc                        ; (-16), held at 254
        adc EYV
        bcs @c
        sbc #-HORIZON-1            ; (C clear: - 16; the line is at least 16:
                                   ; no borrow)
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
@c:     cmp #15                    ; 256 + A - 16 > 254?
        bcc @in
        lda #254                   ; held at 254
        bne @st                    ; (always)
@in:    adc #256+HORIZON           ; (C clear: + 240)
        bcc @st                    ; (always)
        .assert HORIZON = -16, error, "ytab: HORIZON -16"
        .segment "SG1"
        .code

; xrow: PX + X + i, the row's x's (land.project's sx): the ends on the clip
; planes from Q = 1152 r, corners 1..NX-2 from B1 and r (the module's header).
; In: X = 16 k, rl, rh = r, cxs.  Clobbers A, X, Y, Y0..Y0+2 (M), Q0..Q0+2.
xrow:   lda rh                     ; Q = r << 7 ... (rh also seeds Y0+2,
        sta Y0+2                   ; r << 2's high byte, below)
        lsr a
        sta Q0+2
        lda rl
        ror a
        sta Q0+1
        lda #0
        ror a
        sta Q0
        lda rl                     ; ... + r << 10 (low byte 0): r << 2,
        asl a                      ; its high byte shifted in Y0+2, its low
        rol Y0+2                   ; byte in A
        asl a
        rol Y0+2                   ; (C clear after: rh < 32, bit 6 clear)
        .assert DI0 > 128, error, "xrow: r < 8192 (rh < 32): no carry out of r << 2"
        adc Q0+1
        sta Q0+1
        tay                        ; (Q0+1 kept for the right end's carry)
        lda Q0+2
        adc Y0+2
        sta Q0+2
        cpy #$80                   ; the right end: 128 + ((Q + 32768) >> 16)
        adc #128                   ; (C: the carry from Q + 32768)
        sta PX+NX-1,x
        lda #0                     ; the left: 128 - ((Q + 32767) >> 16) = 128
        cmp Q0                     ; - Q2 - ([Q1 Q0] >= $8001): C here is
        lda #$80                   ; $8000 >= [Q1 Q0], the inverse, so the
        sbc Q0+1                   ; SBC's borrow subtracts that carry
        lda #128
        sbc Q0+2
        sta PX,x
        lda cxs                    ; M = Q + 16 cxs r: 16 cxs r first, cxs's
        sta Y0                     ; bits (0..15) from the bottom of Y0 itself,
        lda #0                     ; each ror Y0 shifting the next into C as
        sta Y0+1                   ; the sum (A its top byte) shifts down into
                                   ; it (exact: its low 4 bits end 0, cxs's
                                   ; gone after 5 shifts; under 2^24, r < 9440)
        lsr Y0                     ; bit 0 (the sum 0 before it)
        bcc :+
        lda rl
        sta Y0+1
        lda rh
:       lsr a
        ror Y0+1
        ror Y0                     ; C: bit 1
        bcc @b2
        tay
        clc
        lda Y0+1
        adc rl
        sta Y0+1
        tya
        adc rh
@b2:    ror a                      ; (the add's carry in)
        ror Y0+1
        ror Y0                     ; C: bit 2
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
        ror Y0                     ; C: bit 3
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
        tay                        ; (Y: M's top byte)
        lda Y0                     ; + Q
        clc
        adc Q0
        sta Y0
        lda Y0+1
        adc Q0+1
        sta Y0+1
        tya
        adc Q0+2                   ; M's top byte M2, not stored: B's high
        eor #$7F                   ; byte is (0 - M2 - borrow) ^ $80 =
        tay                        ; (M2 ^ $7F) + C, its C added below
        lda #0                     ; 32768 - M, its top two bytes (floor /
        sec                        ; 256), + 32768 (bit 15 flipped), + r: B1
        sbc Y0
        lda #$80
        sbc Y0+1
        sta Y0+1                   ; (B's low byte)
        tya
        adc #0
        tay                        ; (B's high byte, kept in Y)
        .repeat NX-2, I            ; corners 1..NX-2: r more each, unrolled
        lda Y0+1
        clc
        adc rl
        .if I < NX-3
        sta Y0+1                   ; (the last corner's sum is not kept)
        .endif
        tya
        adc rh
        .if I < NX-3
        tay
        .endif
        sta PX+1+I,x
        .endrepeat
:       rts                        ; (the : keeps the anonymous labels' count)

; hgnd: the ground under the ship (land.ground): ZSHIP tiles ahead of the
; camera at its x, x = cx + 128 in 8.8 tiles, between the four map corners
; round it, across then down.  The ship's row is row ZB - ZSHIP (map row czt
; + ZSHIP); its column corner 4 (map x cxt) or, at cxs >= 8, corner 5; across
; by q = (cxs + 8) & 15 on that row and the row before (16 bytes back in HT:
; one map row farther), then down by czs.  In: ZB, cxs, czs, HT.  Out: HGV.
; Clobbers A, X, Y, MT0, MT1, MQB, LQ, tmp.
hgnd:   lda ZB                     ; X = 16 (ZB - ZSHIP) + 4 + (cxs >= 8): 16 ZB
        asl a                      ; (mod 256) + 1 (the fourth ASL's C: ZB's
        asl a                      ; bit 4, set for ZB = 16 or 17) + 3 - 16 ZSHIP
        asl a
        asl a
        adc #<(3-16*ZSHIP)
        .assert ZFCLIP = 16, error, "hgnd: ZB (ZFCLIP or ZFCLIP+1) has bit 4 set"
        ldy cxs
        cpy #8
        adc #0
        tax
        tya                        ; across: q = (cxs + 8) & 15 (Y = cxs)
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
        .assert DI0 > 128, error, "eyrow: r < 8192 (rh < 32)"
eyrow:  lda rl                     ; r >> 5 = (rl & $E0 | rh) rotated left 3
        and #$E0                   ; (rh < 32: bits 0-4)
        ora rh
        .repeat 3
        asl a                      ; 8-bit rotate: bit 7 into bit 0 (C clear after)
        adc #0
        .endrepeat
        sta MT0                    ; r >> 5
        lda CAME
        lsr a                      ; CAME * MT0, 8 by 8: the multiplier's bits
        sta MT1                    ; (C kept through the STA, LDA, LDY)
        lda #0
        ldy #8
@m:     bcc :+                     ; out of MT1's bottom, the product shifted in
        clc                        ; at the top
        adc MT0
:       ror a
        ror MT1
        dey
        bne @m
        asl MT1                    ; (A high, MT1 low) + 64, >> 7 = 2 A + lo bit 7
        rol a                      ; + lo bit 6
        asl MT1
        adc #0
        sta EYV
        rts

; hsh: the heights HT shifted a row after zsh4's map step.  SHF 1: row j
; becomes row j-1's (rows 7 down to 1), row 0 takes HTN; SHF $FF: row j
; becomes row j+1's (0 up to 6), row 7 takes HTN.  Out: SHF = 0.  Clobbers A,
; X, Y.
hsh:    ldx #NX+1                  ; (columns NX, NX+1: hrng's range moves with
                                   ; the row; the new row's made after)
@c:     lda SHF
        bmi @b
        txa                        ; (X: the column, < 16; Y: 16 j + the column,
        ora #$60                   ; j 6 down to 0: the borrow past row 0 ends it)
        tay
        sec
:       lda HT,y                   ; rows 7 .. 1 from the row before
        sta HT+16,y
        tya
        sbc #16
        tay
        bcs :-
        lda HTN,x
        sta HT,x
        bcc @n                     ; (always: the loop's borrow)
@b:     txa                        ; Y = 16 j + the column + $90, j 0 up to 6:
        ora #$90                   ; the carry out past row 6 ends it
        tay
        clc
:       lda HT+16-$90,y            ; rows 0 .. 6 from the row after
        sta HT-$90,y
        tya
        adc #16
        tay
        bcc :-
        lda HTN,x
        sta HT+$70,x
@n:     dex
        bpl @c
        ldx #0                     ; the new row's range: row 0 (SHF 1) or 7
        lda SHF
        bpl :+
        ldx #$70
:       jsr hrng
        lda #0
        sta SHF
        rts
