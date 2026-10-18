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
        ldx #3                     ; FUEL's letters as the full build's glyphs5
@g:     stx gpx                    ; makes them: OSWORD 10's definition, each
        lda flab,x                 ; line two MODE 1 bytes (its left and right
        sta oswb                   ; 4 pixels, colour 3), 16 a letter into glb
        lda #10
        ldx #<oswb
        ldy #>oswb
        jsr OSWORD
        lda gpx
        asl a
        asl a
        asl a
        asl a
        tax
        ldy #0
@l:     lda oswb+1,y
        and #$F0
        sta gpc
        lsr a
        lsr a
        lsr a
        lsr a
        ora gpc
        sta glb,x
        lda oswb+1,y
        and #$0F
        sta gpc
        asl a
        asl a
        asl a
        asl a
        ora gpc
        sta glb+8,x
        inx
        iny
        cpy #8
        bne @l
        ldx gpx
        dex
        bpl @g
        sei                        ; the MOS's interrupts off for good, its
        ldx #$FF                   ; stack ours
        txs
        jsr takeover
        lda #0                     ; screen 0 the one drawn; the game started
        sta back
        jsr setback
        jsr ginit
        ldx #clre-clr-1            ; clr to the free block, then to it: it
@cs:    lda clr,x                  ; clears the loader's pages and enters the
        sta __IMG_LAST__+1,x       ; main loop
        dex
        bpl @cs
        lda #$82                   ; the sync (CA1) and timer 1 on
        sta SVIA_IER
        lda #$C0
        sta UVIA_IER
        cli
        jmp __IMG_LAST__+1
; clr: run from the free block (relative branches only): the loader's pages to
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
        .assert >start >= >__IMG_LAST__+2 && __IMG_LAST__+1+clre-clr <= start && __IMG_LAST__+1+clre-clr <= __TOP_START__, error, "clr: in the free block below the loader, a page clear between"

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
        ldx #15                    ; the palette (MODE 1: logical colour c's
@pl:    lda palv,x                 ; four entries; black, cyan, magenta,
        sta $FE21                  ; yellow)
        dex
        bpl @pl
        rts
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
; gpanel: the top frame as the full build's screen top: row 0's columns 0..47
; (TOP) FUEL at columns 0..7 (glb: start's, from the MOS's font), the rest
; black; the map (MAP, as gamegen's MAPI: 64 lines of 64 pixels, line y, pixel
; px the tile x = px - MAPX, z = MAPZ - y, mod 64): the pad PADG's grey (by
; the pixel's parity), the sea (its four corners 0) colour 1, land colour 3.
; The corners are mapgen.s's (mcl), a map row at a time into MC: row z at slot
; 64 (y & 1), row z + 1 the line before's (MOK stays 0: the first frame makes
; the window).  Clobbers A, X, Y, ptr, $8E-$9E.
gpanel: ldx #0
@c:     lda #0
        sta MAP,x
        sta MAP+$100,x
        sta MAP+$200,x
        sta MAP+$300,x
        cpx #48*8-$100
        bcs :+
        sta TOP+$100,x
:       cpx #64
        bcc :+
        sta TOP,x
        bcs :++
:       lda glb,x                  ; FUEL
        sta TOP,x
:       inx
        bne @c
        .assert 48*8 > $100 && 48*8 <= $200, error, "gpanel: TOP 1..2 pages"
        lda #(MAPZ+1) & 63         ; row MAPZ + 1, line -1's, at slot 64
        ldx #64
        jsr @row
        lda #0
        sta gpy
@y:     lda gpy                    ; row z = MAPZ - y at slot 64 (y & 1)
        and #1
        lsr a
        ror a
        lsr a
        sta gpb
        lda #MAPZ
        sec
        sbc gpy
        and #63
        sta gpz
        ldx gpb
        jsr @row
        lda gpy                    ; MAP + 128 (y >> 3) + (y & 7)
        and #8
        asl a
        asl a
        asl a
        asl a
        sta ptr
        lda gpy
        and #7
        ora ptr
        sta ptr
        lda gpy
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #>MAP
        sta ptr+1
        ldx #63                    ; px
@t:     txa                        ; x = px - MAPX
        sec
        sbc #MAPX
        and #63
        sta gpx
        cmp #PADN                  ; the pad: PADG's grey
        bcs @nb
        lda gpz
        cmp #PADN
        bcs @nb
        lda gpy
        and #1
        asl a
        sta gpc
        txa
        and #1
        ora gpc
        tay
        lda PADG,y
        jmp @k
@nb:    lda gpx                    ; the four corners: row z at gpb, z + 1 at
        ora gpb                    ; gpb ^ 64
        tay
        lda MC,y
        sta gpc
        tya
        eor #64
        tay
        lda MC,y
        ora gpc
        sta gpc
        lda gpx
        clc
        adc #1
        and #63
        ora gpb
        tay
        lda MC,y
        ora gpc
        sta gpc
        tya
        eor #64
        tay
        lda MC,y
        ora gpc                    ; (heights only: mcl's colour nibbles 0)
        beq :+
        lda #3                     ; land
        bne @k
:       lda #1                     ; the sea
@k:     sta gpc                    ; colour c into pixel px & 3: c's high bit at
        txa                        ; bit 7 - p, low at 3 - p
        and #3
        tay
        lda gpc
        lsr a                      ; (C: low bit)
        lda #0
        bcc :+
        lda PIXM,y
        and #$0F
:       sta gpb+1                  ; (scratch: gpx is free now)
        lda gpc
        and #2
        beq :+
        lda PIXM,y
        and #$F0
:       ora gpb+1
        sta gpc
        txa                        ; byte 8 (px >> 2)
        and #$3C
        asl a
        tay
        lda (ptr),y
        ora gpc
        sta (ptr),y
        dex
        bmi :+
        jmp @t
:       inc gpy
        lda gpy
        cmp #64
        beq :+
        jmp @y
:       rts
@row:   sta MGZ                    ; map row A's 64 corners at slot X
        stx MGS
        lda #0
        sta MGX
        lda #1
        sta MGD
        lda #64
        sta MGN
        jmp mcl
flab:   .byte "FUEL"
oswb:   .res 9                     ; (start's: OSWORD 10's block)
glb:    .res 64                    ; FUEL's letters (start's; zero in the tests,
                                   ; which skip start)
gpy:    .byte 0                    ; (gpanel's: y, z, row z's slot, a byte, x)
gpz:    .byte 0
gpb:    .byte 0, 0
gpc:    .byte 0
gpx:    .byte 0

mtc:    .word MGP_S, MGP
        .byte 32
        .word HTL_S, HTL
        .byte 30
        .word LUT_S, LUT
        .byte 32
        .word TN_S, TN
        .byte 31
        .word B1N_S, B1N
        .byte 32
mtce:
        .assert YQT = MGP+6 && MGQ = YQT+9 && LQT = MGQ+6 && SEAI = LQT+7 && HTH = HTL+15, error, "mtc: the holes' tables in order"
        .assert YQT_S = MGP_S+6 && MGQ_S = YQT_S+9 && LQT_S = MGQ_S+6 && SEAI_S = LQT_S+7 && HTH_S = HTL_S+15, error, "mtc: the sources in order"

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
palv:   .repeat 16, e
        .byte e << 4 | ((($3560 >> (4 * (((e >> 3) & 1) * 2 + ((e >> 1) & 1)))) & 7) ^ 7)
        .endrepeat
        .import __P1H_START__, __P1H_SIZE__
        .import __IMG_START__, __IMG_LAST__
        .import __MAPD_LOAD__, __MAPD_RUN__, __CODE_LOAD__, __CODE_RUN__, __SHIP_RUN__, __SHIP_SIZE__, __CODE2_RUN__, __CODE2_SIZE__, __CODE2_LOAD__, __SHIP_LOAD__, __TOP_START__, __TOP_SIZE__
