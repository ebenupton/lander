; boot.s: the loader.  LANDER loads at $2000 and is *RUN at start, from any
; mode, with the MOS still in charge.  The file holds the stored parts (the
; tables, the code, the code in the parity tables' tails) and then this
; segment, which runs where it is loaded, in the land buffers.  It takes the
; machine (the MOS's interrupts off for good: IRQ1V is ours, the NMI an RTI),
; zeroes the data, copies the stored parts to their places, makes the tables
; and the generated code, sets the CRTC and palette, and enters the main loop
; through a last stub that clears the loader's own pages.

        .segment "BOOT"
start:  lda #119                   ; any EXEC or SPOOL file closed
        jsr OSBYTE
        sei
        ldx #$FF
        txs
        jsr takeover
        lda #0                     ; screen 0 drawn first
        sta back
        jsr setback
        jsr ginit
        ldx #clre-clr-1            ; clr into the free block, and on to it
@cs:    lda clr,x
        sta __DATA_LAST__,x
        dex
        bpl @cs
        lda #$82                   ; the sync and timer 1's interrupts on
        sta SVIA_IER
        lda #$C0
        sta UVIA_IER
        cli
        jmp __DATA_LAST__
; clr: the loader's pages to $7FFF black, then the main loop.  (Relocatable.)
clr:    lda #0
        sta ptr
        tay
        ldx #>__BOOT_LOAD__
@p:     stx ptr+1
@b:     sta (ptr),y
        iny
        bne @b
        inx
        bpl @p
        jmp loop
clre:
        .assert __DATA_LAST__ + clre - clr <= __PROG_START__, error, "clr: room in the free block"
        .assert __BOOT_LOAD__ >= $5000, error, "the loader above the top frame"

; takeover: everything but the interrupts' start.  (The tests call it with the
; file at $2000.)  Clobbers A, X, Y.
takeover:
.ifdef MODE2
        lda #$40                   ; a VideoNULA reset (on a plain ULA, a
        sta $FE22                  ; mirror of its registers)
.ifdef NULA
        ldx #0                     ; and its palette
:       lda nulapal,x
        sta $FE23
        inx
        cpx #32
        bne :-
.endif
.endif
        ldx #15                    ; every colour black, MODE 1
@pk:    txa
        asl a
        asl a
        asl a
        asl a
        ora #7
        sta $FE21
        dex
        bpl @pk
        lda #$D8
        sta ULA_CTL
        lda #$7F                   ; the VIAs' interrupts off
        sta SVIA_IER
        sta UVIA_IER
        lda #<irq
        sta IRQ1V
        lda #>irq
        sta IRQ1V+1
        lda #0                     ; timer 2 counts the clock
        sta UVIA_ACR
        sta UVIA_T2L
        ldx #$FC                   ; the data zeroed: zero page to $FB, page
@z0:    dex                        ; 1 below the stack, page 2 past the
        sta $00,x                  ; vectors, and $0300 to the data's end
        bne @z0
        ldx #<STACK
@z1:    dex
        sta $0100,x
        bne @z1
        ldx #$FA
@z2:    dex
        sta $0206,x
        bne @z2
        tay
        ldx #>$0300
        stx ptr+1
        sta ptr
@z3:    sta (ptr),y
        iny
        bne @z3
        inc ptr+1
        ldx ptr+1
        cpx #>(__DATA_LAST__+255)
        bne @z3
        .assert __DATA_LAST__ + 255 < $2000, error, "takeover: the zeroing stops below the file"
        lda #$40                   ; RTI: the NMI's
        sta NMI
        ldx #0                     ; the stored parts to their places
@cl:    lda copies,x
        sta ptr
        lda copies+1,x
        sta ptr+1
        lda copies+2,x
        sta g0
        lda copies+3,x
        sta g0+1
        lda copies+4,x
        sta tmp
        lda copies+5,x
        sta tmp+1
        txa
        pha
        jsr mcopy
        pla
        clc
        adc #6
        tax
        cpx #copye-copies
        bne @cl
        jsr gfill
        jsr gqr
        jsr grung
        jsr gpanel
        jsr init
        lda #0                     ; the land buffers black below the loader
        tay
        sta ptr
        ldx #>LAND0
@z4p:   stx ptr+1
@z4:    sta (ptr),y
        iny
        bne @z4
        inx
        cpx #>__BOOT_LOAD__
        bne @z4p
        ldx #0                     ; the CRTC
@cr:    lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne @cr
        jsr chst
.ifdef MODE2
        jmp pal5
.else
        ldx #15                    ; MODE 1's palette
@pl:    lda palv,x
        sta $FE21
        dex
        bpl @pl
        rts
.endif

; mcopy: tmp bytes from (ptr) to (g0), ascending.  Clobbers A, X, Y.
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

; copies: source, destination, length; in the file's order, each destination
; below every later source.
copies: .word __TABLES_LOAD__, __TABLES_RUN__, __TABLES_SIZE__
        .word __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
        .word __T0_LOAD__, __T0_RUN__, __T0_SIZE__
        .word __T1_LOAD__, __T1_RUN__, __T1_SIZE__
        .word __T2_LOAD__, __T2_RUN__, __T2_SIZE__
        .word __T3_LOAD__, __T3_RUN__, __T3_SIZE__
        .word __T4_LOAD__, __T4_RUN__, __T4_SIZE__
        .word MGQ_S, MGQ, 31
        .word HTL_S, HTL, 30
        .word LUT_S, LUT, 32
        .word TN_S, TN, 31
        .word B1N_S, B1N, 32
copye:
        .assert __TABLES_RUN__ + __TABLES_SIZE__ <= __TABLES_LOAD__, error, "copies: TABLES"
        .assert __CODE_RUN__ <= __CODE_LOAD__ && $4900 <= __T0_LOAD__, error, "copies: CODE"
        .assert __T0_RUN__ <= __T0_LOAD__ && __T1_RUN__ <= __T1_LOAD__ && __T2_RUN__ <= __T2_LOAD__ && __T3_RUN__ <= __T3_LOAD__ && __T4_RUN__ <= __T4_LOAD__, error, "copies: the tails"
        .assert MGP = MGQ+7 && YQT = MGP+6 && LQT = YQT+7 && SEAI = LQT+7 && HTH = HTL+15, error, "copies: the tables in order"
        .assert MGP_S = MGQ_S+7 && YQT_S = MGP_S+6 && LQT_S = YQT_S+7 && SEAI_S = LQT_S+7 && HTH_S = HTL_S+15, error, "copies: their sources in order"

; gfill: the fills, TBLK4 and TBLK5 (STA ROWx-TNB+i,X for i = 0 .. TNB-1, then
; JMP t_back), and their entries TENxL, TENxH + n: TBLKx + 3 (TNB - n).
; Clobbers A, X, Y, ptr, tmp.
        .assert TBLK5 = TBLK4+3*TNB+3 && ROWB = ROWA+$100 && <ROWA = 0 && TNB <= 256, error, "gfill"
gfill:  lda #<TBLK4
        sta ptr
        lda #>TBLK4
        sta ptr+1
        ldy #0
        lda #>ROWA-1
        sta tmp+1
@t:     ldx #<-TNB
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
        jsr @put
        inc tmp+1
        lda tmp+1
        cmp #>ROWB
        bne @t
        ldx #0                     ; the entries
        lda #<(TBLK4+3*TNB)
        sta tmp
        lda #>(TBLK4+3*TNB)
        sta tmp+1
@e:     lda tmp
        sta TEN4L,x
        clc
        adc #<(3*TNB+3)
        sta TEN5L,x
        lda tmp+1
        sta TEN4H,x
        adc #>(3*TNB+3)
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
@put:   sta (ptr),y
        inc ptr
        bne :+
        inc ptr+1
:       rts

; grung: the rungs' tables for a 2..9, D 0..31, at (a & 7) << 5 | D: RQF (D div
; a) << 4 | t(1), RPT the pattern b(j) = t(j+1) - t(j) - q2 from bit 7.
; t(j) = ceil(D (2j - 1) / 2a) is stepped as gq, with gr = 2a t - D (2j - 1)
; brought back to 0 or more.  Clobbers A, X, Y.
grung:  lda #2
        sta ga
@a:     asl a
        sta ga2
        lda #0
        sta gd
@d:     lda gd                     ; q2
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
        lda #9                     ; from bit 7
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
@up:    bpl @ux
@u:     inc gq
        clc
        adc ga2
        bmi @u
@ux:    sta gr
        rts
ga:     .byte 0
ga2:    .byte 0
gd:     .byte 0
gd2:    .byte 0
gr:     .byte 0
gq:     .byte 0
gtp:    .byte 0
gq2:    .byte 0
gpat:   .byte 0

; gqr: div8's table: QRA rows d 2..8, each D d..31: (D div d) << 4 | D mod d;
; QOA,d-2 the row's offset less d.  Clobbers A, X, Y, ptr, gt0..gt2.
gqr:    ldx #2
@d:     cpx #2
        bne @o
        lda #<QRA
        ldy #>QRA
@p:     sta ptr
        sty ptr+1
        lda #0
        sta gt0
@o:     stx gt1
        lda gt0
        sec
        sbc gt1
        sta QOA-2,x
        lda #32
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
        sbc gt1                  ; (C set) r back to 0, q + 1
        adc #$0F
@k:     dec gt2
        bne @D
        inx
        cpx #9
        bne @d
        rts
        .assert QRAN = 189, error, "gqr: the table's size"

; gpanel: the top frame: FUEL, the rest black, and the map (64 lines of 32
; pixels, a pixel two tiles: x = 2t - MAPX, z = MAPZ - y): the pad black, the
; sea colour 1, land 3.  The corners are mcl's, two map columns at a time in
; MC (all 128 slots).  Clobbers A, X, Y, ptr, the overlay.
        .assert TOP+24*8 = MAP && <MAP = 0, error, "gpanel: TOP then MAP, page-aligned"
gpanel: ldx #0
@c:     lda #0
        sta MAP,x
        sta MAP+$100,x
        cpx #24*8
        bcs :+
        cpx #32
        bcs @z
        lda FUELG,x
@z:     sta TOP,x
:       inx
        bne @c
        lda #128                   ; mcl's ring: 128 slots meanwhile
        sta mnm1+1
        sta mnm2+1
        lda #0
        sta gpt
@t:     lda gpt                    ; pixel t: map columns 2t - MAPX and on,
        asl a                      ; all 64 rows, at slots 0 and 64
        sec
        sbc #MAPX
        and #63
        sta gpx
        ldx #0
        jsr @col
        lda gpx
        clc
        adc #1
        and #63
        ldx #64
        jsr @col
        lda gpt
        and #3
        tay
.ifdef MODE2
        lda PIX5,y
.else
        lda PIXM,y
.endif
        sta gpm
        lda gpt
        and #$1C
        asl a
        sta gpo
        ldx #63                    ; X = k: line 63 - k, z = z0 + k
@k:     lda gpx                    ; the pad: black
        cmp #PADN
        bcs @np
        txa
        clc
        adc #(MAPZ-63) & 63
        and #63
        cmp #PADN
        bcc @nx
.ifdef ARC
@np:    lda MC,x                   ; land if a corner is above the sea
        ora MC+64,x
        and #15
.else
@np:    lda MC,x
        ora MC+64,x
        sta gpc
        txa
        clc
        adc #1
        and #63
        tay
        lda MC,y
        ora MC+64,y
        ora gpc
.endif
        beq :+
        lda #$FF
        bne @cl                    ; (always)
:       lda #$0F
@cl:    and gpm
        sta gpc
        txa
        eor #63
        tay
        and #$38
        asl a
        asl a
        asl a
        sta ptr
        lda #>MAP
        adc #0
        sta ptr+1
        tya
        and #7
        ora gpo
        tay
        lda (ptr),y
        ora gpc
        sta (ptr),y
@nx:    dex
        bpl @k
        inc gpt
        lda gpt
        cmp #32
        beq :+
        jmp @t
:       lda #MRING                 ; the ring's own again
        sta mnm1+1
        sta mnm2+1
        rts
@col:   sta MGX                    ; map column A, 64 corners from slot X
        stx MGS
        lda #(MAPZ-63) & 63
        sta MGZ
        lda #1
        sta MGD
        lda #64
        sta MGN
        jmp mcl
gpt:    .byte 0
gpm:    .byte 0
gpo:    .byte 0
gpc:    .byte 0
gpx:    .byte 0

crtc_regs:                         ; a MODE 1 frame, 64 wide: irq takes over
        .byte 0, 127
        .byte 1, 64
        .byte 2, 90
        .byte 3, $28
        .byte 4, 38
        .byte 5, 0
        .byte 6, 20
        .byte 7, 28
        .byte 8, 0
        .byte 9, 7
        .byte 10, $20              ; no cursor
        .byte 12, >(LAND0/8)
        .byte 13, <(LAND0/8)
crtc_end:

; chst: timer 1 started a known time after a vertical sync.
chst:   lda #$02
        sta SVIA_IFR
:       bit SVIA_IFR
        beq :-
        lda #$40
        sta UVIA_ACR
        lda #<(TZ-30)
        sta UVIA_T1L
        lda #>(TZ-30)
        sta UVIA_T1H
        lda #<(IZA-2)
        sta UVIA_T1LL
        lda #>(IZA-2)
        sta UVIA_T1LH
        lda #0
        sta evn
        rts

.ifdef MODE2
.ifdef NULA
nulapal: NULAPAL                   ; the VideoNULA's 16 colours
.endif
.else
palv:   .repeat 16, e              ; MODE 1: black, cyan, magenta, yellow
        .byte e << 4 | ((($3560 >> (4 * (((e >> 3) & 1) * 2 + ((e >> 1) & 1)))) & 7) ^ 7)
        .endrepeat
.endif
        .import __DATA_LAST__, __PROG_START__, __BOOT_LOAD__
        .import __TABLES_LOAD__, __TABLES_RUN__, __TABLES_SIZE__, __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
        .import __T0_LOAD__, __T0_RUN__, __T0_SIZE__, __T1_LOAD__, __T1_RUN__, __T1_SIZE__
        .import __T2_LOAD__, __T2_RUN__, __T2_SIZE__, __T3_LOAD__, __T3_RUN__, __T3_SIZE__
        .import __T4_LOAD__, __T4_RUN__, __T4_SIZE__

; init: the renderer's tables: R7L, R7H (r by depth index: (2^21 + k) div 2k,
; k = DI0 + di), the parity tables, OL and LAH, the column records empty, the
; first RTS planted, the camera at tile (40, 30), and the strips' constants.
rk:     .res 2
rd:     .res 2
rn:     .res 3
rr:     .res 2
init:
.ifdef ARC
        ldx #9                     ; the colour window's entry NX-1 in each row:
:       txa                        ; black (CTE, CTO's zeros)
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
        lda #0                     ; the parity tables: table t at >STAB + t,
        sta tmp                    ; STA line,Y for each even line
@tab:   lda tmp
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
        ldx #YSKY                  ; OL: each line's entry, 3 ((y - YSKY) >> 1)
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
        ldx #0                     ; LAH: 2 (y >> 3)
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
        lda #<(STAB+PTEND)         ; the first RTS
        sta pp
        lda #>(STAB+PTEND)
        sta pp+1
        lda #OP_RTS
        sta STAB+PTEND
        lda #40                    ; the camera
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
        lda #>RTBUF
        sta alloc+1
        sta rtp+1
        rts
