; rungs.s: the rungs of a strip.  Rung i joins point i of the top row (xt, yt)
; to point i of the bottom (xb, yb), D = yb - yt, a = |xb - xt|.  It crosses
; pixels LO .. HI-1, and its j'th pixel from xt changes box at line yt +
; ceil(D (2j - 1) / 2a): Bresenham, stepping in y.  The lines go to RTPL's page
; of RTBUF, a + 1 bytes a rung from alloc, pixel x's at RTPL + x + 1, then an
; $FF that ends a walk along the pixels (leaning right) or, as the byte before
; the next rung's, one back along them (leaning left; RTBUF+4 for the first).
; The margins (rungs 0 and NX+1) are upright with no bytes.
;
; The lines step by q2 = D div a or q2 + 1 after the first, the longer when
; the error E += r2 carries (r2 = 2 (D mod a), E = 255 - e).  A rung with a <=
; 9 and D < 32 takes its steps from tables instead (RPT, RQF: grung's).

; rungs: LO, HI, RTPL and the transitions for rungs 0 .. NX+1.  In: TX, TY,
; BX, BY, xl, xr.  Clobbers A, X, Y, tj, the division's zero page.
rg_up:  sta LO,x                   ; upright: no pixels
        sta HI,x
        eor #$FF                   ; RTPL = alloc - LO - 1
        clc
        adc alloc
        sta RTPL,x
        ldy #0
        sty dva
        jmp rg_nr
rg_lft: sta LO,x                   ; leaning left: pixels xb .. xt-1
        eor #$FF
        adc alloc                  ; (C clear)
        sta RTPL,x
        sec
        lda TX,x
        sta HI,x
        sbc BX,x                   ; a
        sta dva
.ifdef SWR
        tay                        ; (bank 4: by its tables when a <= RFA and
        jmp rfastl                 ; D < 16, else back to rg_rdl)
rg_rdl: asl a
.else
        asl a                      ; 2a
.endif
        sta ra2
        sta dvx
        lda BY,x                   ; D
        sec
        sbc TY,x
        sta dvd
        cmp #32
        bcs :+
        ldy dva
        cpy #10
        bcs :+
        jmp rg_lf
:       jmp rg_lsl
rungs:  lda xl                     ; the margins
        sta LO
        sta HI
        ldx #NX+1
        lda xr
        sta LO,x
        sta HI,x
        lda #<(RTBUF+5)
        sta alloc
        ldx #1
rg_r:   stx tj                     ; rung X
        lda BX,x
        cmp TX,x
        beq rg_up
        bcc rg_lft
        sta HI,x                   ; leaning right: pixels xt .. xb-1
        sbc TX,x                   ; a
        sta dva
.ifdef SWR
        tay
        lda TX,x
        sta LO,x
        eor #$FF                   ; RTPL = alloc - LO - 1
        clc
        adc alloc
        sta RTPL,x
        jmp rfastr                 ; (bank 4, as rfastl; else back to rg_rdr)
rg_rdr: tya
        asl a
        sta ra2
        sta dvx
.else
        asl a                      ; 2a
        sta ra2
        sta dvx
        lda TX,x
        sta LO,x
        eor #$FF                   ; RTPL = alloc - LO - 1 (C clear)
        adc alloc
        sta RTPL,x
.endif
        lda BY,x                   ; D
        sec
        sbc TY,x
        sta dvd
        cmp #32
        bcs rg_rsl
        ldy dva
        cpy #10
        bcs rg_rsl
        jmp rg_rf
rg_rsl: jsr divs                   ; E = rem - 2a - 1, or 255 for rem 0
        lda rrem
        beq rg_rz
        clc
        sbc ra2
        sec                        ; (C: rem > 0)
rg_rst: sta rrem
        lda ra2                    ; dvd = 255 - 2a, a carry's correction
        eor #$FF
        sta dvd
        lda TY,x                   ; the first line: yt + q + (rem > 0)
        adc rq
        ldy rq2                    ; rq = q2 + 1
        iny
        sty rq
        ldy #0
        sta (alloc),y
        iny
        cpy dva
        beq rg_nr
rg_rs:  tax                        ; each next line q2 or q2 + 1 on
        lda rrem
        adc rr2
        bcs :+
        sta rrem
        txa
        adc rq2
        sta (alloc),y
        iny
        cpy dva
        bne rg_rs
        beq rg_nr                  ; (always)
:       adc dvd
        sta rrem
        txa
        adc rq
        sta (alloc),y
        iny
        cpy dva
        bne rg_rs
rg_ld:  ldy dva
rg_nr:  lda #$FF                   ; the sentinel; alloc past it
        sta (alloc),y
        tya
        sec
        adc alloc
        sta alloc
        ldx tj
        inx
        cpx #NX+1
        bcs :+
        jmp rg_r
:       rts
rg_rz:  eor #$FF
        bcc rg_rst                 ; (always)
rg_lz:  lda #$FF
        bne :+                     ; (always)
rg_lsl: jsr divs                   ; leaning left, by division: as rg_rsl, the
        lda ra2                    ; lines from the far end down
        eor #$FF
        sta dvd
        lda rrem
        beq rg_lz
        clc
        adc dvd
        sec
:       sta rrem
        lda TY,x
        adc rq
        ldy rq2
        iny
        sty rq
        ldy dva
        dey
        sta (alloc),y
        beq rg_ld
rg_lw:  tax                        ; (C cleared each line: D may have wrapped)
        clc
        lda rrem
        adc rr2
        bcs :+
        sta rrem
        txa
        adc rq2
        dey
        sta (alloc),y
        bne rg_lw
        beq rg_ld                  ; (always)
:       adc dvd
        sta rrem
        txa
        adc rq
        dey
        sta (alloc),y
        bne rg_lw
        beq rg_ld                  ; (always)

; rg_rf, rg_lf: a rung with a 1..9, D < 32, from the tables: t(j+1) = t(j) +
; q2 + b(j), the pattern b in RPT and q2 << 4 | t(1) in RQF, both at (a & 7)
; << 5 | D.  The unrolled bodies are entered at step 10 - a; both end at rg_ld.
rg_rf:  lda dva
        cmp #1
        beq @a1
        jsr rg_tb
        ldy dva
        lda rg_rbe-1,y
        sta @j+1
        tya
        clc
        adc alloc
        tay                        ; Y = alloc + a
        lda rq
        adc TY,x
@j:     jmp rg_rb                  ; (operand: the entry)
@a1:    lda dvd                    ; a = 1: yt + ceil(D / 2)
        lsr a
        adc TY,x
        ldy alloc
        iny
        jmp rg_rb9
rg_lf:  lda dva
        cmp #1
        beq @a1
        jsr rg_tb
        ldy dva
        lda rg_lbe-1,y
        sta @j+1
        ldy alloc
        lda rq
        clc
        adc TY,x
@j:     jmp rg_lb                  ; (operand: the entry)
@a1:    lda dvd
        lsr a
        adc TY,x
        ldy alloc
        jmp rg_lb9

; rg_tb: rq = t(1), rq2 = q2, rrem = the pattern; X = tj after.
rg_tb:  lda dva
        asl a
        asl a
        asl a
        asl a
        asl a
        ora dvd
        tax
        lda RPT,x
        sta rrem
        lda RQF,x
        tay
        and #$0F
        sta rq
        tya
        lsr a
        lsr a
        lsr a
        lsr a
        sta rq2
        ldx tj
        rts

.macro RB k
        sta RTBUF-10+k,y
        asl rrem
        adc rq2
.endmacro
.macro LB k
        sta RTBUF+9-k,y
        asl rrem
        adc rq2
.endmacro
rg_rb:  RB 1
        RB 2
        RB 3
        RB 4
        RB 5
        RB 6
        RB 7
        RB 8
rg_rb9: sta RTBUF-1,y
        jmp rg_ld
rg_lb:  LB 1
        LB 2
        LB 3
        LB 4
        LB 5
        LB 6
        LB 7
        LB 8
rg_lb9: sta RTBUF,y
        jmp rg_ld
        .pushseg
        .segment "TABLES"
rg_rbe: .repeat 9, i
        .byte <(rg_rb + (8 - i) * 7)
        .endrepeat
rg_lbe: .repeat 9, i
        .byte <(rg_lb + (8 - i) * 7)
        .endrepeat
        .popseg
        .assert >rg_rb = >rg_rb9 && >rg_lb = >rg_lb9, error, "rg_rf, rg_lf: each body in one page"
        .assert rg_lb - rg_rb = 8*7 + 6, error, "rg_rb: 7-byte steps"

.ifdef SWR
; rfastr, rfastl (bank 4): rung X leaning right or left by RFA's tables when a
; <= RFA and D < 16 (a wrapped D, yb < yt, is 16 or more): TRk, TLk (gen32.py)
; hold pixel k's line less yt at 16 (RFA - a) + D, k counted from LO.  The
; unrolled bodies store pixels RFA-1 .. 0, entered at pixel a-1; then the
; sentinel, alloc on, and the next rung.  Otherwise back to rg_rdr, rg_rdl.
; In: X the rung, Y = dva = a, alloc, tj.  Clobbers A, X, Y, rrem.
        .pushseg
        .segment "B4CODE"
rfastr: cpy #RFA+1                 ; a > RFA: the other ways
        bcs @sl
        lda TY,x
        sta rrem                   ; yt
        eor #$FF                   ; D = yb - yt (yb + ~yt + 1)
        sec
        adc BY,x
        cmp #16
        bcs @sl                    ; (C clear after: the bodies' ADCs rely on it)
        ora B16-1,y                ; X = 16 (RFA - a) + D
        tax
        lda DUFR-1,y               ; the entry for a
        sta @j+1
        ldy alloc
@j:     jmp FR0                    ; (operand's low byte patched)
@sl:    jmp rg_rdr
rfastl: cpy #RFA+1
        bcs @sl
        lda TY,x
        sta rrem
        eor #$FF
        sec
        adc BY,x
        cmp #16
        bcs @sl
        ora B16-1,y
        tax
        lda DUFL-1,y
        sta @j+1
        ldy alloc
@j:     jmp FL0
@sl:    tya
        jmp rg_rdl
B16:    .repeat RFA, i             ; B16[a-1] = 16 (RFA - a)
        .byte 16 * (RFA - 1 - i)
        .endrepeat
DUFR:   .repeat RFA, i             ; the bodies' entries for a (8 bytes a pixel)
        .byte <(FR0 + 8 * (RFA - 1 - i))
        .endrepeat
DUFL:   .repeat RFA, i
        .byte <(FL0 + 8 * (RFA - 1 - i))
        .endrepeat
.macro RFBODY T                    ; pixels RFA-1 .. 0: yt + T<k>[X] to RTBUF +
        .repeat RFA, i             ; alloc + k
        lda .ident(.sprintf("%s%d", T, RFA - 1 - i)),x
        adc rrem                   ; (C stays clear: yt + offset <= yb < 256)
        sta RTBUF + RFA - 1 - i,y
        .endrepeat
        tya                        ; alloc += a + 1; the sentinel at the old
        sec                        ; alloc + a
        adc dva
        sta alloc
        tay
        lda #$FF
        sta RTBUF-1,y
        ldx tj                     ; the next rung, or done
        inx
        cpx #NX+1
        bcs :+
        jmp rg_r
:       rts
.endmacro
        .segment "B4BODY"
FR0:    RFBODY "TR"
FL0:    RFBODY "TL"
        .assert >FR0 = >(FR0 + 8 * RFA - 1) && >FL0 = >(FL0 + 8 * RFA - 1), error, "rfast: each body's entries in one page"
        .popseg
.endif
