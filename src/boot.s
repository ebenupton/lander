; boot.s: the program's start (segment BOOT), both builds.  The disc's loader
; (loader.s) loads the file (the 32K build's BASE at $2000; the sideways RAM
; build's MAIN at $3000, its banks filled already) and enters `start` with the
; MOS in charge and the screen in MODE 7.  The file holds the stored parts
; (the tables, the code, the generated pages' code) and then this segment,
; which runs where it is loaded, in screen 0.  It takes the machine (the MOS's
; interrupts off for good: IRQ1V is ours), zeroes the data, copies the stored
; parts to their places, makes the tables and the generated code (tabgen.s),
; sets the CRTC and palette, and enters the main loop through a stub in RTBUF
; that clears this segment's own pages.
;
; The sideways RAM build's start has X, Y the address of the loader's
; parameters: banks 4 .. 7's sockets and the board's write select.

        .segment "BOOT"
.ifdef SWR
BOARD_SOLIDISK = 2                 ; the loader's write selects: 0 ROMSEL
                                   ; alone, 1 a Watford board, 2 a Solidisk
start:  stx ptr
        sty ptr+1
        ldy #4
:       lda (ptr),y
        sta fbank,y
        dey
        bpl :-
        sei
.else
start:  sei
.endif
        ldx #$FF
        txs
        jsr takeover
        ldx #clre-clr-1            ; clr copied to RTBUF, and entered below
@cs:    lda clr,x
        sta RTBUF,x
        dex
        bpl @cs
        lda #$82                   ; the sync's interrupt on
        sta SVIA_IER
.ifndef SWR
        lda #$C0                   ; and timer 1's
        sta UVIA_IER
.endif
        cli
        jmp RTBUF
; clr: this segment's pages, to the end of screen 0, black; then the main
; loop.  Runs in RTBUF (it is position-independent).
clr:    lda #0
        sta ptr
        tay
        ldx #>__BOOT_LOAD__
@p:     stx ptr+1
@b:     sta (ptr),y
        iny
        bne @b
        inx
        cpx #>LAND1
        bne @p
        jmp loop
clre:
        .assert __BOOT_LOAD__ >= LAND0 + PANEL && __BOOT_LOAD__ + __BOOT_SIZE__ <= LAND1, error, "the start-up code in screen 0's land, which the first frame is drawn on"

; takeover: everything but the interrupts' start: the machine taken, the data
; zeroed, the tables and generated code made, the display set.  (The tests
; call it with the file loaded and the banks filled.)  Clobbers A, X, Y.
takeover:
.ifdef MODE2
        lda #$40                   ; a VideoNULA reset (a plain ULA takes it
        sta $FE22                  ; as its control register, set below)
.ifdef NULA
        ldx #0                     ; and its palette
:       lda nulapal,x
        sta $FE23
        inx
        cpx #32
        bne :-
.endif
.endif
        ldx #15                    ; every colour black
@pk:    txa
        asl a
        asl a
        asl a
        asl a
        ora #7
        sta $FE21
        dex
        bpl @pk
        lda #$C4                   ; (1MHz, as the MOS's MODE 7 frame, whose
        sta ULA_CTL                ; lines stay 64us until the frame below)
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
        bne @z0                    ; (the sideways RAM build's but page $0D)
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
@z3p:   stx ptr+1
        sta ptr
@z3:    sta (ptr),y
        iny
        bne @z3
        inx
.ifdef SWR
        cpx #>$0D00
        bne :+
        inx
:
.endif
        cpx #>(__DATA_LAST__+255)
        bne @z3p
        .assert __DATA_LAST__ + 255 < __TABLES_LOAD__, error, "takeover: the zeroing stops below the file"
.ifdef SWR
        ldx #3                     ; the banks' sockets
:       lda fbank,x
        sta BANKMAP,x
        dex
        bpl :-
.else
        lda #$40                   ; RTI: the NMI's
        sta NMI
.endif
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
.ifdef SWR
        jsr wpatch                 ; the banks' write selects, the version's
        jsr patch                  ; patches; bank 4 in
        jsr pg4
.endif
        jsr gfill                  ; the tables and the generated code
        jsr gqr
        jsr grung
.ifndef SWR
        jsr gpanel
.endif
        jsr init
        lda #0                     ; the screens black, but for this segment's
        tay                        ; pages to the end of screen 0 (clr's)
        sta ptr
        ldx #>LAND0
@z4p:   cpx #>__BOOT_LOAD__
        bne :+
        ldx #>LAND1
:       stx ptr+1
@z4:    sta (ptr),y
        iny
        bne @z4
        inx
        bpl @z4p
        lda #ULAL                  ; the land's mode: 2MHz, as the frame
        sta ULA_CTL
        ldx #0                     ; the CRTC
@cr:    lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne @cr
        lda #0                     ; screen 0 drawn first, screen 1 shown
        sta back
        jsr setback
        jsr ginit                  ; the game's start
.ifdef SWR
        ldx #15                    ; the palette
@pl:    lda palv,x
        sta $FE21
        dex
        bpl @pl
        rts
.else
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
.ifdef SWR
        .word __T5_LOAD__, __T5_RUN__, __T5_SIZE__
        .word __T6_LOAD__, __T6_RUN__, __T6_SIZE__
        .word __T7_LOAD__, __T7_RUN__, __T7_SIZE__
.else
        .word MGQ_S, MGQ, 31       ; (32K) MGQ, MGP, YQT, LQT, SEAI
        .word HTL_S, HTL, 30       ; HTL, HTH
        .word LUT_S, LUT, 32
        .word TN_S, TN, 31
        .word B1N_S, B1N, 32
.endif
copye:
        .assert __TABLES_RUN__ + __TABLES_SIZE__ <= __TABLES_LOAD__ && __CODE_RUN__ <= __CODE_LOAD__, error, "copies: below their sources"
        .assert __T0_RUN__ <= __T0_LOAD__ && __T1_RUN__ <= __T1_LOAD__ && __T2_RUN__ <= __T2_LOAD__ && __T3_RUN__ <= __T3_LOAD__ && __T4_RUN__ <= __T4_LOAD__, error, "copies: the generated pages' code"
.ifdef SWR
        .assert __T5_RUN__ <= __T5_LOAD__ && __T6_RUN__ <= __T6_LOAD__ && __T7_RUN__ <= __T7_LOAD__, error, "copies: the generated pages' code"
.else
        .assert MGP = MGQ+7 && YQT = MGP+6 && LQT = YQT+7 && SEAI = LQT+7 && HTH = HTL+15, error, "copies: the tables in order"
        .assert MGP_S = MGQ_S+7 && YQT_S = MGP_S+6 && LQT_S = YQT_S+7 && SEAI_S = LQT_S+7 && HTH_S = HTL_S+15, error, "copies: their sources in order"
.endif

.ifdef SWR
; wpatch (SWR): pg4..pg7's write selects made the board's.  Each pwN is BIT
; wrt (3 bytes); on a Watford board it becomes STA WRSEL_WATFORD + the bank's
; socket, on a Solidisk STA WRSEL_SOLIDISK (pgN has the socket in A by then);
; on a plain machine nothing changes.  In: board, BANKMAP.  Clobbers A, X, Y,
; ptr.
wpatch: lda board
        beq @r
        ldx #3
@l:     lda wrsl,x                 ; ptr = the BIT (wrsl, wrsh)
        sta ptr
        lda wrsh,x
        sta ptr+1
        ldy #0
        lda #$8D                   ; STA abs
        sta (ptr),y
        lda board
        cmp #BOARD_SOLIDISK
        beq @s
        ldy wrsb,x                 ; Watford: $FF30 | the bank's socket (< 16)
        lda BANKMAP,y
        ora #<WRSEL_WATFORD
        ldy #1
        sta (ptr),y
        iny
        lda #>WRSEL_WATFORD
        bne @h
@s:     ldy #1                     ; Solidisk: $FE60
        lda #<WRSEL_SOLIDISK
        sta (ptr),y
        iny
        lda #>WRSEL_SOLIDISK
@h:     sta (ptr),y
        dex
        bpl @l
@r:     rts

; patch (SWR): the version's differences from the disc's shared bank images,
; written into the banks: records of a bank (4 .. 7; 0 ends them), an address,
; a length (1 .. 255) and that many bytes, from `patches`.  Leaves the last
; record's bank paged.  Clobbers A, X, Y, ptr, g0, tmp.
patch:  lda #<patches
        sta ptr
        lda #>patches
        sta ptr+1
@r:     ldy #0
        lda (ptr),y
        beq @x
        tax
        lda pgl-4,x
        sta @j+1
        lda pgh-4,x
        sta @j+2
@j:     jsr pg4                    ; (operand: the record's bank)
        ldy #1
        lda (ptr),y
        sta g0
        iny
        lda (ptr),y
        sta g0+1
        iny
        lda (ptr),y
        sta tmp
        lda ptr
        clc
        adc #4
        sta ptr
        bcc :+
        inc ptr+1
:       ldy #0
@c:     lda (ptr),y
        sta (g0),y
        iny
        cpy tmp
        bne @c
        tya
        clc
        adc ptr
        sta ptr
        bcc @r
        inc ptr+1
        bne @r                     ; (always)
@x:     rts

fbank:  .byte 4, 5, 6, 7           ; the loader's parameters: banks 4 .. 7's
board:  .byte 0                    ; sockets, and the write select
wrsl:   .byte <pw4, <pw5, <pw6, <pw7 ; wpatch: each pgN's BIT wrt,
wrsh:   .byte >pw4, >pw5, >pw6, >pw7 ; low and high bytes,
wrsb:   .byte 0, 1, 2, 3           ; and its bank less 4 (BANKMAP's index)
pgl:    .byte <pg4, <pg5, <pg6, <pg7 ; patch: pg4 .. pg7
pgh:    .byte >pg4, >pg5, >pg6, >pg7
.else
; gpanel (32K): the top frame: FUEL, the rest black, and the map (64 lines of
; 32 pixels, a pixel two tiles: x = 2t - MAPX, z = MAPZ - y): the pad black,
; the sea colour 1, land 3.  The corners are mcl's, two map columns at a time
; in MC (all 128 slots).  Clobbers A, X, Y, ptr, the overlay.
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
@np:    lda MC,x                   ; land if either corner is above the sea
        ora MC+64,x
        and #15
.else
@np:    lda MC,x                   ; land unless these corners and the two a
        ora MC+64,x                ; row on are all 0
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
:       lda #MRING                 ; the ring's own size again
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
gpt:    .byte 0                    ; gpanel: the pixel t
gpm:    .byte 0                    ; its mask
gpo:    .byte 0                    ; its byte column's offset
gpc:    .byte 0                    ; scratch
gpx:    .byte 0                    ; its first map column

; chst: timer 1 started a known time after a vertical sync, for Ez first: the
; field's last event but Ev, so the display is the land's frame, whole, until
; Ez makes the top's.  The wait's loop is 4us a pass, and CHL, the time from
; the sync to the timer's start, is for the middle of that, so the first Ez's
; switch is within 2us of its time (its line that much long or short, and Ev's
; NOPs still meet the sync).  The sync's flag is cleared again: the next sync
; is E0's first, and every line from the first Eb's on is exact.
CHL     = 149
chst:   lda #$02
        sta SVIA_IFR
:       bit SVIA_IFR
        beq :-
        sta SVIA_IFR
        lda #$40
        sta UVIA_ACR
        lda #<(TZ-CHL)
        sta UVIA_T1L
        lda #>(TZ-CHL)
        sta UVIA_T1H
        lda #<(IZV-2)
        sta UVIA_T1LL
        lda #>(IZV-2)
        sta UVIA_T1LH
        lda #2
        sta evn
        rts

.endif

crtc_regs:                         ; the land's frame, 64 bytes wide (the 32K
        .byte 0, 127               ; build's irq makes the field's two)
        .byte 1, 64
        .byte 2, 90
        .byte 3, $28
        .byte 4, CR_TOTAL-1
        .byte 5, 0
        .byte 6, CR_ROWS
        .byte 7, CR_VSYNC
        .byte 8, 0
        .byte 9, 7
        .byte 10, $20              ; no cursor
        .byte 12, >(LAND1/8)
        .byte 13, <(LAND1/8)
crtc_end:

.ifdef MODE2
.ifdef SWR
palv:   P2PAL                      ; MODE 2 (SWR): the screen's colours
.endif
.ifdef NULA
nulapal: NULAPAL                   ; the VideoNULA's 16 colours
.endif
.else
palv:   .repeat 16, e              ; MODE 1: black, cyan, magenta, yellow
        .byte e << 4 | ((($3560 >> (4 * (((e >> 3) & 1) * 2 + ((e >> 1) & 1)))) & 7) ^ 7)
        .endrepeat
.endif
        .import __DATA_LAST__, __BOOT_LOAD__, __BOOT_SIZE__
        .import __TABLES_LOAD__, __TABLES_RUN__, __TABLES_SIZE__, __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
        .import __T0_LOAD__, __T0_RUN__, __T0_SIZE__, __T1_LOAD__, __T1_RUN__, __T1_SIZE__
        .import __T2_LOAD__, __T2_RUN__, __T2_SIZE__, __T3_LOAD__, __T3_RUN__, __T3_SIZE__
        .import __T4_LOAD__, __T4_RUN__, __T4_SIZE__
.ifdef SWR
        .import __T5_LOAD__, __T5_RUN__, __T5_SIZE__
        .import __T6_LOAD__, __T6_RUN__, __T6_SIZE__, __T7_LOAD__, __T7_RUN__, __T7_SIZE__
.endif
        .include "tabgen.s"
.ifdef SWR
patches: .byte 0                   ; patch's records (tools/mkdisc.py puts the
.endif                             ; version's in place of this end mark)
