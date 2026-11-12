; tabgen.s: boot.s's table makers, for both builds: mcopy, gfill (traceb's
; fills), grung (the rungs' tables), gqr (div8's table) and init (the
; generated store code, the line tables, the renderer's start).  Included by
; boot.s, in segment BOOT: run once, then cleared (clr).

; mcopy: tmp bytes from (ptr) to (g0), ascending.  Clobbers A, X, Y, and the
; pointers' high bytes.
mcopy:  ldy #0
        ldx tmp+1
        beq @pt
@pg:    lda (ptr),y
        sta (g0),y
        iny
        bne @pg
        inc ptr+1
        inc g0+1
        dex
        bne @pg
@pt:    ldx tmp
        beq @x
@b:     lda (ptr),y
        sta (g0),y
        iny
        dex
        bne @b
@x:     rts

; gfill: the fills, TBLK4 and TBLK5 (STA ROWx-TNB+i,X for i = 0 .. TNB-1, then
; JMP t_back), and their entries for n stores, TBLKx + 3 (TNB - n): TENL + n
; the low byte (the fills share theirs), TEN4H, TEN5H + n the pages.
; Clobbers A, X, Y, ptr, tmp.
        .assert <TBLK5 = <TBLK4 && TBLK5 >= TBLK4+3*TNB+3 && ROWB = ROWA+$100 && <ROWA = 0 && TNB <= 256, error, "gfill"
gfill:  lda #>TBLK4
        ldx #>ROWA-1
        jsr @blk
        lda #>TBLK5
        ldx #>ROWB-1
        jsr @blk
        ldx #0                     ; the entries
        lda #<(TBLK4+3*TNB)
        sta tmp
        lda #>(TBLK4+3*TNB)
        sta tmp+1
@e:     lda tmp
        sta TENL,x
        lda tmp+1
        sta TEN4H,x
        clc
        adc #>(TBLK5-TBLK4)
        sta TEN5H,x
        lda tmp
        sec
        sbc #3
        sta tmp
        bcs @n
        dec tmp+1
@n:     inx
        cpx #TNB+1
        bne @e
        rts
@blk:   sta ptr+1                  ; a fill at page A, its stores' page X + 1
        stx tmp+1
        lda #<TBLK4
        sta ptr
        ldy #0
        ldx #<-TNB
@s:     lda #$9D                   ; STA abs,X
        jsr @put
        txa
        jsr @put
        lda tmp+1
        jsr @put
        inx
        bne @s
        lda #$4C                   ; JMP t_back
        jsr @put
        lda #<t_back
        jsr @put
        lda #>t_back
@put:   sta (ptr),y
        inc ptr
        bne :+
        inc ptr+1
:       rts

; grung: the rungs' tables for a 2..9, D 0..31, at (a & 7) << 5 | D: RQF (D div
; a) << 4 | t(1), RPT the pattern b(j) = t(j+1) - t(j) - q2, j 1..a-1, from
; bit 7 down.  t(j) = ceil(D (2j - 1) / 2a) is stepped as gq, with gr = 2a t -
; D (2j - 1) brought back to 0 or more.  Clobbers A, X, Y.
grung:  lda #2
        sta ga
@a:     asl a
        sta ga2
        lda #0
        sta gd
@d:     lda gd                     ; q2 = D div a
        ldx #0
@q:     cmp ga
        bcc @qd
        sbc ga
        inx
        bne @q                     ; (always)
@qd:    stx gq2
        lda #0                     ; t(1)
        sta gq
        sec
        sbc gd
        jsr @up
        lda gq
        sta gtp
        lda ga
        asl a
        asl a
        asl a
        asl a
        asl a
        ora gd
        tax
        lda gq2
        asl a
        asl a
        asl a
        asl a
        ora gq
        sta RQF,x
        lda #0
        sta gpat
        lda gd
        asl a
        sta gd2
        ldy ga
        dey
@j:     lda gr                     ; each next t, its step's bit
        sec
        sbc gd2
        jsr @up
        lda gq
        sec
        sbc gtp
        sec
        sbc gq2
        lsr a
        rol gpat
        lda gq
        sta gtp
        dey
        bne @j
        lda #9                     ; the pattern's first bit to bit 7
        sec
        sbc ga
        tay
        beq @s0
@sh:    asl gpat
        dey
        bne @sh
@s0:    lda gpat
        sta RPT,x
        inc gd
        lda gd
        cmp #32
        beq :+
        jmp @d
:       inc ga
        lda ga
        cmp #10
        beq :+
        jmp @a
:       rts
@up:    bpl @ux                    ; gr = A brought to 0 or more by 2a's, gq
@u:     inc gq                     ; one more for each
        clc
        adc ga2
        bmi @u
@ux:    sta gr
        rts
ga:     .byte 0                    ; a
ga2:    .byte 0                    ; 2a
gd:     .byte 0                    ; D
gd2:    .byte 0                    ; 2D
gr:     .byte 0                    ; 2a t - D (2j - 1)
gq:     .byte 0                    ; t(j)
gtp:    .byte 0                    ; t(j-1)
gq2:    .byte 0                    ; q2
gpat:   .byte 0                    ; the pattern

; gqr: div8's table: QRA's rows d 2..8, each D d..31: (D div d) << 4 | D mod
; d; QOA,d-2 the row's offset in QRA less d.  Clobbers A, X, Y, ptr, gt0..gt2.
gqr:    ldx #2
@d:     cpx #2
        bne @o
        lda #<QRA
        ldy #>QRA
@p:     sta ptr
        sty ptr+1
        lda #0
        sta gt0
@o:     stx gt1                    ; gt1 = d; gt0 the next entry's offset
        lda gt0
        sec
        sbc gt1
        sta QOA-2,x
        lda #32                    ; gt2: the row's entries, 32 - d
        sec
        sbc gt1
        sta gt2
        lda #$10                   ; D = d: q 1, r 0
@D:     ldy gt0
        sta (ptr),y
        inc gt0
        clc
        adc #1
        tay
        and #$0F
        cmp gt1
        tya
        bcc @k
        sbc gt1                    ; (C set) r back to 0, q + 1
        adc #$0F
@k:     dec gt2
        bne @D
        inx
        cpx #9
        bne @d
        rts
        .assert QRAN = 189, error, "gqr: the table's size"

; init: the renderer's start.  Both builds: c_v1, LAH, the column records
; empty (TOPS $FF, BOTS 0), the camera at tile (40, 30), the strips'
; constants; the arc version: the colour window's last entries black.  32K:
; shtab (the ship's tables), R7L, R7H (r by depth index: (2^21 + k) div 2k, k
; = DI0 + di), the four parity tables, OL, and the first RTS planted.  SWR:
; run's eight store pages, EINL, and runk's first RTS.  Clobbers A, X, Y, ptr,
; tmp.
rk:     .res 2                     ; init's division (32K): k = DI0 + di
rd:     .res 2                     ; 2k
rn:     .res 3                     ; 2^21 + k, then the quotient r
rr:     .res 2                     ; the remainder
init:
.ifdef ARC
        ldx #9                     ; arc: the colour window's entry NX-1 in
:       txa                        ; each row: class 6*9, black (CTE, CTO)
        asl a
        asl a
        asl a
        asl a
        tay
        lda #6*9
        sta CLE+10,y
        dex
        bpl :-
.endif
        lda #$40                   ; c_v1: BIT c_v1 sets V
        sta c_v1
.ifndef SWR
        jsr shtab
        lda #<DI0                  ; R7L, R7H
        sta rk
        lda #>DI0
        sta rk+1
        ldx #0
@r7:    lda rk                     ; the divisor 2k
        asl a
        sta rd
        lda rk+1
        rol a
        sta rd+1
        lda rk                     ; the dividend 2^21 + k
        sta rn
        lda rk+1
        sta rn+1
        lda #$20
        sta rn+2
        lda #0
        sta rr
        sta rr+1
        ldy #24
@rd:    asl rn
        rol rn+1
        rol rn+2
        rol rr
        rol rr+1
        lda rr
        sec
        sbc rd
        pha
        lda rr+1
        sbc rd+1
        bcc :+
        sta rr+1
        pla
        sta rr
        inc rn
        bne :++                    ; (always)
:       pla
:       dey
        bne @rd
        lda rn
        sta R7L,x
        lda rn+1
        sta R7H,x
        inc rk
        bne :+
        inc rk+1
:       inx
        cpx #NDI
        bne @r7
.endif
.ifdef SWR
        lda #0                     ; run's store pages: page q at >RUNT + q,
        sta tmp                    ; q = 4 screen + 2 half + (odd lines):
@tab:   lda tmp                    ; STA line,Y for each of its lines from
        clc                        ; R2OFF, an RTS at $FF
        adc #>RUNT
        sta ptr+1
        lda #R2OFF
        sta ptr
        lda tmp
        and #1
        ora #YSKY
        tax                        ; (X: the page's first line)
        ldy #0
@line:  lda #OP_STAY
        sta (ptr),y
        iny
        txa                        ; the line's address: y & 7, and 2 (y >>
        and #7                     ; 3) + the half + the screen's page
        sta (ptr),y
        iny
        txa
        lsr a
        lsr a
        and #$FE
        sta tmp+1
        lda tmp
        lsr a
        and #1
        ora tmp+1
        sta tmp+1
        lda tmp
        and #4
        beq :+
        lda #SCR1-SCR0
:       clc
        adc #SCR0
        adc tmp+1
        sta (ptr),y
        iny
        inx
        inx
        cpx #YGND+1
        bcc @line
        lda #OP_RTS
        ldy #$FF-R2OFF
        sta (ptr),y
        inc tmp
        lda tmp
        cmp #8
        bne @tab
        .assert R2OFF + 3 * R2N = 255, error, "the store pages: the slots end at $FF"
        ldx #YSKY-1                ; EINL,y: R2OFF + 3 ceil((y - YSKY) / 2),
@el:    txa                        ; $FF at most (YGND+2's: the end slot)
        sec
        sbc #YSKY-1
        lsr a
        sta tmp+1
        asl a
        adc tmp+1
        adc #R2OFF
        bcc :+
        lda #$FF
:       sta EINL,x
        inx
        cpx #YGND+3
        bne @el
.else
        lda #0                     ; the parity tables: table t = 2 screen +
        sta tmp                    ; half at >STAB + t: STA line,Y for each
@tab:   lda tmp                    ; even line, YSKY .. YGND+1
        clc
        adc #>STAB
        sta ptr+1
        lda #0
        sta ptr
        ldx #YSKY
        ldy #0
@line:  lda #OP_STAY
        sta (ptr),y
        iny
        txa                        ; the line's address: y & 7, and 2 (y >>
        and #7                     ; 3) + the half + the screen's page
        sta (ptr),y
        iny
        txa
        lsr a
        lsr a
        and #$FE
        sta tmp+1
        lda tmp
        and #1
        ora tmp+1
        sta tmp+1
        lda tmp
        and #2
        beq :+
        lda #SCR1-SCR0
:       clc
        adc #SCR0
        adc tmp+1
        sta (ptr),y
        iny
        inx
        inx
        cpx #YGND+3
        bcc @line
        inc tmp
        lda tmp
        cmp #4
        bne @tab
        ldx #YSKY                  ; OL,y: line y's entry, 3 ((y - YSKY) >> 1)
@ol:    txa
        sec
        sbc #YSKY
        lsr a
        sta tmp
        asl a
        adc tmp
        sta OL,x
        inx
        cpx #YGND+3
        bne @ol
.endif
        ldx #0                     ; LAH,y = 2 (y >> 3), y YSKY .. YGND+1
@ent:   cpx #YSKY
        bcc :+
        cpx #YGND+2
        bcs :+
        txa
        lsr a
        lsr a
        and #$FE
        sta LAH,x
:       inx
        beq :+
        jmp @ent
:       ldx #127                   ; nothing drawn on either screen
:       lda #$FF
        sta TOPS,x
        lda #0
        sta BOTS,x
        dex
        bpl :-
.ifdef SWR
        lda #<(BLKT+3*(YGND+1-YSKY)) ; kpp: table 0's end slot, an RTS as stored
        sta kpp
        lda #>(BLKT+3*(YGND+1-YSKY))
        sta kpp+1
.endif
.ifndef SWR
        lda #<(STAB+PTEND)         ; the first RTS, at table 0's end slot
        sta pp
        lda #>(STAB+PTEND)
        sta pp+1
        lda #OP_RTS
        sta STAB+PTEND
.endif
        lda #40                    ; the camera's tile
        sta cxt
        lda #30
        sta czt
        lda #0
        sta cxs
        sta czs
        sta topa                   ; the rows' pages' low bytes
        sta bota
        sta CE                     ; the margins' boxes black
        sta CO
        sta CE+NX
        sta CO+NX
        lda #$FF                   ; the sentinel before the first rung's
        sta RTBUF+4
        lda #>RTBUF                ; alloc, rtp: RTBUF's page
        sta alloc+1
        sta rtp+1
        rts
