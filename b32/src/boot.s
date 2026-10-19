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
        .include "tabgen.s"
