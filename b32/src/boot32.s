; ============================================================================
; boot32.s -- the 32K build's loader (.included by land.s into segment BOOT,
; the file L32 at $7000, inside land buffer 1: go clears it).  !BOOT has set
; MODE 1 with every colour black and the cursor off, then *RUN L32.
;
; start, with the MOS still there: *LOAD L32M (the program and its data, $1900
; up to the land buffers), close !BOOT (the filing system is then idle: its
; workspace is the program's), the readout's characters from the MOS's font
; (glyphs, OSWORD 10, into GLY).  Then the MOS is done with: interrupts off,
; every VIA interrupt disabled, IRQ1V ours (irq: the MOS ROM's entry still
; saves A in $FC and jumps through it), low RAM zeroed, an RTI at $0D00 for a
; stray NMI.  The tables (init), the map drawn on the panel (mappix), land
; buffer 0 and the rest below the loader cleared, the CRTC set to a one-frame MODE 1
; with the sync at row 28 (irq takes it from there), the palette, the
; interrupts on: the sync (CA1) and the user VIA's timer 1; then go.
; ============================================================================

IRQ1V   = $0204

        .segment "BOOT"
start:  ldx #<cmd_main             ; the program
        ldy #>cmd_main
        jsr OSCLI
        lda #119                   ; !BOOT closed: no filing system call
        jsr OSBYTE                 ; follows
        jsr glyphs                 ; GLY
        sei                        ; the MOS's interrupts off for good
        jsr takeover
        lda #$82                   ; the sync (CA1) and timer 1 on
        sta SVIA_IER
        lda #$C0
        sta UVIA_IER
        cli
        jmp go

; takeover: the machine taken from the MOS (interrupts off), as above: the VIAs,
; IRQ1V, low RAM zeroed (all but the stack, IRQ1V and GLY), the NMI's RTI,
; init, the map, the land buffers below the loader, the CRTC and palette.  (The tests
; call it in place of the loader.)  Clobbers A, X, Y.
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
        lda #0                     ; zeroed: zero page, page 1 below the stack,
        ldx #<__ZP_SIZE__          ; page 2 past IRQ1V, then $0300 up to GLY
:       dex                        ; (the panel, MID, STAB...: the MOS's
        sta $00,x                  ; leftovers otherwise; init makes the
        bne :-                     ; tables over it)
        ldx #$C0
:       dex
        sta $0100,x
        bne :-
        ldx #$100-6
:       dex
        sta $0206,x
        bne :-
        tay
        ldx #>$0300
        stx ptr+1
        sta ptr
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        ldx ptr+1
        cpx #>GLY
        bne :-
        lda #$40                   ; RTI: a stray NMI
        sta $0D00
        jsr init
        lda #0                     ; the map on the panel
        sta mdc
        sta mdl
@ml:    lda #0
        sta mdp
@mp:    jsr mappix
        inc mdp
        lda mdp
        cmp #2*MAPN
        bne @mp
        inc mdl
        lda mdl
        cmp #MAPN
        bne @ml
        lda #0                     ; land buffer 0 and buffer 1 below here
        tay                        ; black (go clears the rest)
        ldx #>LAND0
        stx ptr+1
        sta ptr
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        ldx ptr+1
        cpx #>start
        bne :-
        ldx #0                     ; the CRTC: one frame, 64 wide, 20 rows, the
:       lda crtc_regs,x            ; sync at row 28, land buffer 0 shown
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne :-
        ldx #15                    ; the palette (MODE 1: logical colour c's
:       lda palv,x                 ; four entries; black, cyan, magenta,
        sta $FE21                  ; yellow)
        dex
        bpl :-
        rts

; glyphs: the readout's characters (gchars) into GLY: each from OSWORD 10, its
; 8 rows as MODE 1 bytes, colour 3 where set: the left 4 pixels at GLY + 16 i
; + row, the right 4 at + 8.  Clobbers A, X, Y, tcol, tmp.
glyphs: ldx #0
@c:     stx tcol
        lda gchars,x
        sta oswblk
        lda #10
        ldx #<oswblk
        ldy #>oswblk
        jsr OSWORD
        lda tcol
        asl a
        asl a
        asl a
        asl a
        tax
        ldy #0
@l:     lda oswblk+1,y
        and #$F0
        sta tmp
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp
        sta GLY,x
        lda oswblk+1,y
        and #$0F
        sta tmp
        asl a
        asl a
        asl a
        asl a
        ora tmp
        sta GLY+8,x
        inx
        iny
        cpy #8
        bne @l
        ldx tcol
        inx
        cpx #gchars_end-gchars
        bne @c
        rts
gchars: .byte "0123456789. FPS"    ; (G_DOT 10, G_SP 11, G_F 12: readout's)
gchars_end:
oswblk: .res 9

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
        .import __ZP_SIZE__
