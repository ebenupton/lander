; ============================================================================
; boot32.s -- the 32K build's loader (.included by land.s into segment BOOT,
; the file L32 at $7000, inside land buffer 1: go clears it).  !BOOT has set
; MODE 1 with every colour black and the cursor off, then *RUN L32.
;
; start, with the MOS still there: *LOAD L32M (the program: the map, the panel,
; the code, loaded at $1900 to run from $1400), close !BOOT (the filing system
; is then idle: its workspace is the program's).  Then the MOS is done with:
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
LOADAT  = $1900                    ; where DFS loads L32M (b32/build32.sh's)
start:  ldx #<cmd_main             ; the program, at LOADAT
        ldy #>cmd_main
        jsr OSCLI
        lda #119                   ; !BOOT closed: no filing system call
        jsr OSBYTE                 ; follows
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
; clr: run from the free block (relative branches only): $7000-$7FFF black (the
; loader's pages: takeover cleared the rest of the land buffers), then loop.
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
        .assert >start = $70, error, "clr: the loader's pages, $7000-$7FFF"

; takeover: the machine taken from the MOS (interrupts off, the stack at $01FF),
; as above: the VIAs, IRQ1V; the program copied down from LOADAT to its place
; ($1400: b32.cfg's IMG, ascending, so the overlap is safe); then every hole the
; uninitialised data lives in zeroed (zero page below $FC, page 1 below the
; stack, page 2 past IRQ1V, $0300-$13FF), the NMI's RTI, init's tables, the
; memory from the program's end through land buffer 0 to the loader cleared;
; the CRTC (one MODE 1 frame) and palette.  (The tests call it in place of the
; loader, with L32M at LOADAT.)  Clobbers A, X, Y.
takeover:
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
        ldy #0                     ; the program: whole pages, LOADAT to
        sty ptr                    ; __IMG_START__ (what follows its end is
        sty z:g0                   ; cleared below)
        lda #>LOADAT
        sta ptr+1
        lda #>__IMG_START__
        sta z:g0+1
        ldx #>(__IMG_LAST__-__IMG_START__)+1
@cp:    lda (ptr),y
        sta (g0),y
        iny
        bne @cp
        inc ptr+1
        inc z:g0+1
        dex
        bne @cp
        lda #0                     ; zeroed: zero page, page 1 below the stack,
        ldx #$FC                   ; page 2 past IRQ1V, $0300-$13FF (the MOS's
@z0:    dex                        ; leftovers otherwise; init makes the tables
        sta $00,x                  ; over it)
        bne @z0
        ldx #<__P1_SIZE__
@z1:    dex
        sta $0100,x
        bne @z1
        ldx #<__P2B_SIZE__
@z2:    dex
        sta $0206,x
        bne @z2
        .assert __P1_START__ = $0100 && __P2B_START__ = $0206 && __P2B_SIZE__ = $FA, error, "takeover: P1, P2B"
        .assert __P1_START__ + __P1_SIZE__ + 19 = $0200, error, "takeover: the stack's 19 bytes"
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
        jsr init
        lda #0                     ; the pages after the program's to the loader
        tay                        ; black (the free block, land buffer 0; go
        ldx #>__IMG_LAST__+1       ; clears the rest)
        stx ptr+1
        sta ptr
@z4:    sta (ptr),y
        iny
        bne @z4
        inc ptr+1
        ldx ptr+1
        cpx #>start
        bne @z4
        ldx #0                     ; the CRTC: one frame, 64 wide, 20 rows, the
@cr:    lda crtc_regs,x            ; sync at row 28, land buffer 0 shown
        sta CRTC_IDX
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

crtc_regs:                         ; (register, value) pairs
        .byte 1, 64                ; 64 characters displayed
        .byte 2, 90                ; the horizontal sync, centring the 64
        .byte 6, 20                ; 20 rows displayed
        .byte 7, 28                ; the vertical sync at row 28
        .byte 8, 0                 ; not interlaced (the rupture wants whole
                                   ; frames)
        .byte 12, >(LAND0/8)
        .byte 13, <(LAND0/8)
        .byte 10, $20              ; the cursor off
crtc_end:
; palv: the ULA's palette writes, (entry << 4) | (colour ^ 7), MODE 1's
; logical colour c in the entries with c's high bit at bit 3, its low at 1
palv:   .repeat 16, e
        .byte e << 4 | ((($3560 >> (4 * (((e >> 3) & 1) * 2 + ((e >> 1) & 1)))) & 7) ^ 7)
        .endrepeat
cmd_main: .byte "LOAD L32M", 13
        .import __P1_START__, __P1_SIZE__, __P2B_START__, __P2B_SIZE__
        .import __IMG_START__, __IMG_LAST__
