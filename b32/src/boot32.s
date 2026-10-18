; ============================================================================
; boot32.s -- the 32K build's loader (.included by land.s into segment BOOT:
; the end of the one file, LANDER, which holds the program's stored parts --
; MAP32 and the code -- then this; b32.cfg loads it at $2000, the loader above
; the program's place, inside the land buffers: clr clears it).  *RUN LANDER
; from any mode.
;
; start, with the MOS still there: any EXEC or SPOOL file closed (the filing
; system is then idle: its workspace is the program's).  Then the MOS is done with:
; interrupts off, the stack reset, every VIA interrupt disabled, IRQ1V ours
; (irq: the MOS ROM's entry still saves A in $FC and jumps through it), the
; program copied down, the holes b32.cfg packs the variables into zeroed, an
; RTI at $0D00 for a stray NMI.  The tables (init), the free block, land
; buffer 0 and the rest below the loader cleared, the CRTC set to a one-frame MODE 1
; with the sync at row 28 (irq takes it from there), the palette, the
; interrupts on: the sync (CA1) and the user VIA's timer 1; then go.
; ============================================================================

IRQ1V   = $0204

        .segment "BOOT"
start:  lda #119                   ; any EXEC or SPOOL file closed: no filing
        jsr OSBYTE                 ; system call follows
        sei                        ; the MOS's interrupts off for good, its
        ldx #$FF                   ; stack ours
        txs
        jsr takeover
        lda #0                     ; screen 0 the one drawn; the game started
        sta back
        jsr setback
        jsr ginit
        ldx #clre-clr-1            ; clr to $1400 (the gap before TOP), then to
@cs:    lda clr,x                  ; it: it clears the loader's pages and
        sta __IMG_START__,x        ; enters the main loop
        dex
        bpl @cs
        lda #$82                   ; the sync (CA1) and timer 1 on
        sta SVIA_IER
        lda #$C0
        sta UVIA_IER
        cli
        jmp __IMG_START__
; clr: run from $1400 (relative branches only): the loader's pages to
; $7FFF black (takeover cleared the rest of the land buffers), then loop.
clr:    lda #0
        sta ptr
        tay
        ldx #>start
@p:     stx ptr+1
@b:     sta (ptr),y
        iny
        bne @b
        inx
        bpl @p                     ; (to $7FFF)
        jmp loop
clre:
        .assert >start >= >__IMG_LAST__+2 && __IMG_START__+clre-clr <= TOP, error, "clr: in the gap before TOP; the loader above the program, a page clear between"

; takeover: the machine taken from the MOS (interrupts off, the stack at $01FF):
; the picture black (the palette, MODE 1's ULA); the VIAs, IRQ1V; the program
; copied to its place from the file (b32.cfg: the code, then CODE2, each
; ascending); every hole
; the uninitialised data lives in zeroed (zero page below $FC, page 1 below the
; stack, page 2 past IRQ1V, $0300-$13FF), the NMI's RTI; the tables the file
; leaves out made (gfill, gpanel) and init's; the memory from the
; program's end through land buffer 0 to the loader cleared; the CRTC (one MODE
; 1 frame) and the palette.  (The tests call it in place of the loader, with
; the file at its load address.)  Clobbers A, X, Y.
takeover:
.ifdef MODE2
        lda #$40                   ; the VideoNULA, if any: register 4, reset (palette
        sta $FE22                  ; mode 0: the ULA's palette, its 4 bits (bit 3:
.ifdef NULA                        ; colours 8-15) the NULA colour, as irq's palettes
        ldx #0                     ; write it); its 16 colours (NULAPAL: (colour <<
:       lda nulapal,x              ; 4 | red), (green << 4 | blue)).  On a plain
        sta $FE23                  ; Model B these write the ULA's mirrors ($FE22,
        inx                        ; $FE23): undone by the control and palette
        cpx #32                    ; writes that follow
        bne :-
.endif
.endif
        ldx #15                    ; every colour black, MODE 1's ULA (the
@pk:    txa                        ; screen's leftovers unseen)
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
        lda #$7F
        sta SVIA_IER
        sta UVIA_IER
        lda #<irq
        sta IRQ1V
        lda #>irq
        sta IRQ1V+1
        lda #0                     ; the user VIA's timers: 1 one-shot, 2
        sta UVIA_ACR               ; counting the clock from $FF00
        sta UVIA_T2L
        lda #<__CODE_LOAD__        ; the code: whole pages from its start (what
        ldx #>__CODE_LOAD__        ; follows its end is cleared below)
        sta ptr
        stx ptr+1
        lda #<__CODE_RUN__
        ldx #>__CODE_RUN__
        ldy #>(__SHIP_RUN__+__SHIP_SIZE__-__CODE_RUN__+255)
        jsr @copy
        lda #<__CODE2_LOAD__       ; CODE2 after RUNGT's gap (its source is
        ldx #>__CODE2_LOAD__       ; past what the copy above wrote: the run
        sta ptr                    ; addresses are below the load addresses)
        stx ptr+1
        lda #<__CODE2_RUN__
        ldx #>__CODE2_RUN__
        ldy #>(__CODE2_SIZE__+255)
        jsr @copy
        .assert __CODE2_RUN__ < __CODE2_LOAD__ && __SHIP_LOAD__+__SHIP_SIZE__ >= ((__SHIP_RUN__+__SHIP_SIZE__+255) & $FF00), error, "takeover: the copies overlap"
        lda #0                     ; zeroed: zero page, page 1 below the stack,
        ldx #$FC                   ; page 2 past IRQ1V, $0300-$13FF (the MOS's
@z0:    dex                        ; leftovers otherwise; init makes the tables
        sta $00,x                  ; over it)
        bne @z0
        ldx #$ED                   ; (to the stack)
@z1:    dex
        sta $0100,x
        bne @z1
        ldx #$FA
@z2:    dex
        sta $0206,x
        bne @z2
        .assert __P1H_START__ + __P1H_SIZE__ + 19 = $0200, error, "takeover: the stack's 19 bytes"
        tay
        ldx #>$0300
        stx ptr+1
        sta ptr
@z3:    sta (ptr),y
        iny
        bne @z3
        inc ptr+1
        ldx ptr+1
        cpx #>__IMG_START__
        bne @z3
        lda #$40                   ; RTI: a stray NMI
        sta $0D00
        ldx #mtce-mtc-5            ; the tables kept in holes (mtc: source,
@tc:    lda mtc,x                  ; destination, length)
        sta ptr
        lda mtc+1,x
        sta ptr+1
        lda mtc+2,x
        sta z:g0
        lda mtc+3,x
        sta z:g0+1
        ldy mtc+4,x
@tb:    dey
        lda (ptr),y
        sta (g0),y
        tya
        bne @tb
        txa
        sec
        sbc #5
        tax
        bcs @tc
        jsr gfill
        jsr gqr
        jsr grung
        jsr gpanel
        jsr init
        lda #0                     ; the pages after the program's to TOP, and
        tay                        ; from the land buffers to the loader, black
        ldx #>__IMG_LAST__+1       ; (the free block, land buffer 0; clr clears
        sta ptr                    ; the rest)
@z4p:   cpx #>__TOP_START__
        bne :+
        ldx #>$5000
:       cpx #>start
        beq @z4d
        stx ptr+1
@z4:    sta (ptr),y
        iny
        bne @z4
        inx
        bne @z4p                   ; (always)
@z4d:
        .assert __TOP_START__ + __TOP_SIZE__ = $5000 && <__TOP_START__ = 0 && >__IMG_LAST__+1 <= >__TOP_START__ && >start > $50, error, "takeover: TOP below the land buffers"
        ldx #0                     ; the CRTC: one MODE 1 frame, 64 wide, 20
@cr:    lda crtc_regs,x            ; rows, the sync at row 28, land buffer 0
        sta CRTC_IDX               ; shown
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne @cr
.ifdef MODE2
        ldx #35                    ; PALT: irq's palettes, the top's and the land's
:       lda palt,x                 ; (and PIX5)
        sta PALT,x
        dex
        bpl :-
        ldx #19                    ; pal2, pal5 (land.s) in the ring's free tail
:       lda palr,x
        sta pal2,x
        dex
        bpl :-
        .assert MRING+MMIR+20 <= 128, error, "pal2: in MC's tail"
        jmp pal5                   ; the top's
.else
        ldx #15                    ; the palette (MODE 1: logical colour c's
@pl:    lda palv,x                 ; four entries; black, cyan, magenta,
        sta $FE21                  ; yellow)
        dex
        bpl @pl
        rts
.endif
; (copy: Y pages from (ptr) to X:A, ascending.  Clobbers A, X, Y, ptr, g0.)
@copy:  sta z:g0
        stx z:g0+1
        tya
        tax
        ldy #0
@cp:    lda (ptr),y
        sta (g0),y
        iny
        bne @cp
        inc ptr+1
        inc z:g0+1
        dex
        bne @cp
        rts

; gfill: the fills, TBLK4 and TBLK5 (TNB stores STA ROWA-TNB+i,X, ROWB-TNB+i,X,
; then JMP t_back), and their entry tables TEN4L/H, TEN5L/H + n (n 0..TNB):
; TBLKx + 3 (TNB - n).  Clobbers A, X, Y, ptr, tmp.
        .assert TBLK5 = TBLK4+3*TNB+3 && ROWB = ROWA+$100 && <ROWA = 0 && TNB <= 256, error, "gfill"
gfill:  lda #<TBLK4
        sta ptr
        lda #>TBLK4
        sta ptr+1
        ldy #0
        lda #>ROWA-1               ; the stores' page: ROWA - 1, then ROWB - 1
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
        ldx #0                     ; the entries, n = X: TBLK4's end less 3 n,
        lda #<(TBLK4+3*TNB)        ; TBLK5's 3 TNB + 3 on
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
@put:   sta (ptr),y                ; (A at ptr, ptr on)
        inc ptr
        bne :+
        inc ptr+1
:       rts


; grung: the rungs' tables (land.s's rg_rf, rg_lf), for a 2..9 and D 0..31 at
; (a & 7) << 5 | D: RQF (D div a) << 4 | t(1), RPT the pattern: b(j) = t(j +
; 1) - t(j) - q2 for j 1 .. a-1, from bit 7.  t(j) = ceil(D (2j - 1) / 2a) is
; stepped as gq, gr = t, 2a t - D (2j - 1): gr down by 2D a pixel, then up by
; 2a (gq + 1 each) until it is 0 or more.  Clobbers A, X, Y.
grung:  lda #2
        sta ga
@a:     asl a                      ; (A = a)
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
        lda #0                     ; t(1): gr = -D, gq = 0, then up
        sta gq
        sec
        sbc gd
        jsr @up
        lda gq
        sta gtp
        lda ga                     ; X: the index
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
        sta gd2                    ; 2D
        ldy ga
        dey                        ; a - 1 steps
@j:     lda gr
        sec
        sbc gd2
        jsr @up
        lda gq                     ; b = t - t before - q2: 0 or 1
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
        lda #9                     ; from bit 7: << (9 - a)
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
@up:    bpl @ux                    ; A = gr: while below 0, + 2a, gq + 1
@u:     inc gq
        clc
        adc ga2
        bmi @u
@ux:    sta gr
        rts
ga:     .byte 0                    ; (grung's: a, 2a, D, 2D, gr, gq, t before,
ga2:    .byte 0                    ; q2, the pattern)
gd:     .byte 0
gd2:    .byte 0
gr:     .byte 0
gq:     .byte 0
gtp:    .byte 0
gq2:    .byte 0
gpat:   .byte 0
; gqr: div8's table: QRA rows d 2..8, each D d..31 in turn: (D div d) << 4 |
; D mod d; QOA + d - 2: row d's index less d.  Clobbers A, X, Y, ptr,
; z:gt0..z:gt2.
gqr:    ldx #2                     ; d
@d:     cpx #2
        bne @o
        lda #<QRA                  ; (row 2: QRA from its start)
        ldy #>QRA
@p:     sta ptr
        sty ptr+1
        lda #0
        sta z:gt0                    ; (the index)
@o:     stx z:gt1
        lda z:gt0                  ; the offset: index - d
        sec
        sbc z:gt1
        sta QOA-2,x
        lda #32                    ; the row's entries, 32 - d
        sec
        sbc z:gt1
        sta z:gt2
        lda #$10                   ; D = d: q 1, r 0
@D:     ldy z:gt0
        sta (ptr),y
        inc z:gt0
        clc                        ; D + 1: r + 1, or r 0 and q + 1 at d
        adc #1
        tay
        and #$0F
        cmp z:gt1
        tya
        bcc @k
        sbc z:gt1                    ; (C set) q << 4
        adc #$0F                   ; (C set: + $10)
@k:     dec z:gt2
        bne @D
        inx
        cpx #9
        bne @d
        rts
        .assert QRAN = 189, error, "gqr: the table's size"

; gpanel: the top frame: row 0's columns 0..23 (TOP) FUEL at columns 0..3
; (FUELG: the MODE 2 build's narrow letters, a byte a line), the rest black; the map (MAP, MODE 5: 64
; lines of 32 pixels, 64 bytes a character row; line y, pixel t the tile x = 2t
; - MAPX, z = MAPZ - y, mod 64): the pad black, the sea (its four corners 0)
; colour 1, land colour 3.  The corners are mapgen.s's (mcl), two map columns
; at a time into MC (128 slots meanwhile: MOK stays 0, so the first frame makes
; the window).  Clobbers A, X, Y, ptr, $8E-$9E.
        .assert TOP+24*8 = MAP && <MAP = 0, error, "gpanel: TOP then MAP, page-aligned"
gpanel: ldx #0
@c:     lda #0
        sta MAP,x
        sta MAP+$100,x
        cpx #24*8
        bcs :+
        cpx #32
        bcs @z
        lda FUELG,x                ; FUEL (gen32's: the MODE 2 build's letters)
@z:     sta TOP,x
:       inx
        bne @c
        lda #128                   ; (mcl's ring: 128 slots meanwhile)
        sta mnm1+1
        sta mnm2+1
        lda #0
        sta gpt
@t:     lda gpt                    ; pixel t: map columns x = 2t - MAPX and x + 1,
        asl a                      ; z0 .. z0 + 63 (z0 = MAPZ - 63: all 64, so
        sec                        ; z + 1 wraps with the map), at slots 0, 64
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
        lda gpt                    ; the pixel's bits, its byte's column
        and #3
        tay
.ifdef MODE2
        lda palt+32,y              ; (PIX5: MODE 5's pixels)
.else
        lda PIXM,y
.endif
        sta gpm
        lda gpt
        and #$1C
        asl a
        sta gpo
        ldx #63                    ; X = k: line y = 63 - k, z = z0 + k
@k:     lda gpx                    ; the pad: black (nothing to store)
        cmp #PADN
        bcs @np
        txa
        clc
        adc #(MAPZ-63) & 63
        and #63
        cmp #PADN
        bcc @nx
.ifdef ARC
@np:    lda MC,x                   ; (arc) the corners x, x + 1 at z: heights
        ora MC+64,x
        and #15
.else
@np:    lda MC,x                   ; the four corners
        ora MC+64,x
        sta gpc
        txa
        clc
        adc #1
        and #63
        tay
        lda MC,y
        ora MC+64,y
        ora gpc                    ; (heights only: mcl's colour nibbles 0)
.endif
        beq :+
        lda #$FF                   ; land
        bne @cl
:       lda #$0F                   ; the sea
@cl:    and gpm
        sta gpc
        txa                        ; line y = 63 - k: MAP + 64 (y >> 3) + 8 (t
        eor #63                    ; >> 2) + (y & 7)
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
:       lda #MRING                 ; (the ring's own modulus back)
        sta mnm1+1
        sta mnm2+1
        rts
@col:   sta MGX                    ; map column A's 64 corners from z0 at slot X
        stx MGS
        lda #(MAPZ-63) & 63
        sta MGZ
        lda #1
        sta MGD
        lda #64
        sta MGN
        jmp mcl
gpt:    .byte 0                    ; (gpanel's: t, the pixel's bits, its column)
gpm:    .byte 0
gpo:    .byte 0
gpy:    .byte 0                    ; (gpanel's: y, z, row z's slot, a byte, x)
gpz:    .byte 0
gpb:    .byte 0, 0
gpc:    .byte 0
gpx:    .byte 0

mtc:    .word MGQ_S, MGQ
        .byte 31
        .word HTL_S, HTL
        .byte 30
        .word LUT_S, LUT
        .byte 32
        .word TN_S, TN
        .byte 31
        .word B1N_S, B1N
        .byte 32
mtce:
        .assert MGP = MGQ+7 && YQT = MGP+6 && LQT = YQT+7 && SEAI = LQT+7 && HTH = HTL+15, error, "mtc: the holes' tables in order"
        .assert MGP_S = MGQ_S+7 && YQT_S = MGP_S+6 && LQT_S = YQT_S+7 && SEAI_S = LQT_S+7 && HTH_S = HTL_S+15, error, "mtc: the sources in order"

crtc_regs:                         ; (register, value) pairs: MODE 1's, but
        .byte 0, 127               ; 64 characters displayed
        .byte 1, 64
        .byte 2, 90                ; the horizontal sync, centring the 64
        .byte 3, $28
        .byte 4, 38
        .byte 5, 0
        .byte 6, 20                ; 20 rows displayed
        .byte 7, 28                ; the vertical sync at row 28
        .byte 8, 0                 ; not interlaced (the rupture wants whole
        .byte 9, 7                 ; frames)
        .byte 10, $20              ; the cursor off
        .byte 12, >(LAND0/8)
        .byte 13, <(LAND0/8)
crtc_end:
; palv: the ULA's palette writes, (entry << 4) | (colour ^ 7), MODE 1's
; logical colour c in the entries with c's high bit at bit 3, its low at 1
.ifdef MODE2
palt:   P5PAL                      ; (the MODE 2 builds': gen32.py's, copied to PALT)
        P2PAL
        .byte $88, $44, $22, $11   ; PIX5: the top's pixels (MODE 5: four a byte)
palr:   .byte $A2, 31, $2C, $A2, 15, $BD, <PALT, >PALT, $8D, $21, $FE   ; pal2, pal5
        .byte $CA, $8A, $29, 15, $C9, 15, $D0, $F2, $60
.ifdef NULA
nulapal: NULAPAL
.endif
.else
palv:   .repeat 16, e
        .byte e << 4 | ((($3560 >> (4 * (((e >> 3) & 1) * 2 + ((e >> 1) & 1)))) & 7) ^ 7)
        .endrepeat
.endif
        .import __P1H_START__, __P1H_SIZE__
        .import __IMG_START__, __IMG_LAST__
        .import __MAPD_LOAD__, __MAPD_RUN__, __CODE_LOAD__, __CODE_RUN__, __SHIP_RUN__, __SHIP_SIZE__, __CODE2_RUN__, __CODE2_SIZE__, __CODE2_LOAD__, __SHIP_LOAD__, __TOP_START__, __TOP_SIZE__
