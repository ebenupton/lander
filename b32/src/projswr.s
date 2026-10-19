; projswr.s: the projection, sideways RAM build.  As project.s, but the map
; and every tile's colour bytes are stored whole in bank 4 (gen32.py: B4MAP's
; heights, 64 a row; CMAPE, CMAPO's bytes, or the arc build's classes in
; CMAPE), and the rows' points are bank 7's prow7.  The front, proj4, runs in
; bank 4; only the paging is in main RAM.

; project: the frame's rows of points, PX and PY + 16 k + i, and their boxes'
; colours.  In: cxt, cxs, czt, czs, CAME; bank 4 paged.  Out: ZB, RN, FACT,
; nr, np, HT, PX, PY, HGV, EYV, CLE, CLO; bank 4 paged.  Clobbers A, X, Y,
; tmp, rl, rh, syp, lp, MT0, MT1, the overlay.
        .pushseg
        .segment "T2"
project:
        jsr proj4
        jsr pg7
        jsr prow7
        jmp pg4
        .popseg

        .pushseg
        .segment "B4CODE"
; proj4: ZB, RN, FACT, nr; the heights HT (all anew when the columns change
; or the rows move more than one, else zsh4's one row for prow7's hsh); then
; the colour window (pcol5).
proj4:  lda czs                    ; FACT: the far row lerped (czs != 0); ZB
        cmp #1                     ; its map row offset, ZFCLIP + FACT
        lda #0
        rol a
        sta FACT
        adc #ZFCLIP
        sta ZB
        sbc #ZCLIP-1               ; (C clear) RN = ZB - ZCLIP, the near row
        sta RN
        tay
        iny
        sty nr
        lda cxt                    ; the heights still good?
        cmp pkx
        bne @cx
        lda czt
        clc
        adc ZB
        cmp pkz
        beq pcol5
        jsr zsh4                   ; a step of one row: the new row only
        bcs pcol5
        bcc @hl                    ; (always)
@cx:    sta pkx                    ; CX: the map columns cxt-4 .. cxt+6
        sec
        sbc #5-XSKIP
        ldx #0
:       and #63
        sta CX,x
        clc
        adc #1
        inx
        cpx #NX
        bne :-
        .assert ZBACK-ZSKIP-ZCLIP+1 = 8 && ZFCLIP-ZCLIP+1 = 7, error, "nr 7 or 8"
@hl:    lda czt                    ; every row: pkz = czt + ZB; HPZ + 2j the
        clc                        ; map row czt + ZB - j's, row 7's first
        adc ZB
        sta pkz
        sbc #6                     ; (C clear: - 7)
        ldx #14
@hp:    jsr mrow
        sta HPZ,x
        sty HPZ+1,x
        inc tmp
        lda tmp
        dex
        dex
        bpl @hp
        ldx #NX-1                  ; HT + 16 j + i: row j's corner CX[i]
@hc:    ldy CX,x
        .repeat 8, j
        lda (HPZ+2*j),y
        sta HT+16*j,x
        .endrepeat
        dex
        bpl @hc
        ; (falls into pcol5)

; pcol5: the strips' box colours.  Window row m (CLE, CLO + 16 m, m 0..9) holds
; map row WK - m's tiles for the columns at cxt = WX.  The strips need rows o ..
; o+6, o = WK - czt - ZB + 1; with o in 0..3 the missing rows are made (VLO ..
; VHI grows), otherwise the window is remade.  Out: setup's operands for
; window row o.  Clobbers A, X, Y.
pcol5:  lda cxt
        cmp WX
        bne @fx
        lda WK                     ; o
        clc
        sbc czt
        sec
        sbc ZB
        clc
        adc #2
        cmp #4
        bcs @f
@o:     sta WO
        tax                        ; rows o .. VLO-1
:       cpx VLO
        bcs :+
        jsr crow
        inx
        bne :-
:       lda WO                     ; rows VHI+1 .. o+6
        adc #6                     ; (C set: + 7)
        sta WE
        ldx VHI
:       inx
        cpx WE
        bcs :+
        jsr crow
        jmp :-
:       lda WO
        cmp VLO
        bcs :+
        sta VLO
:       ldx WE
        dex
        cpx VHI
        bcc @pt
        stx VHI
@pt:    lda WO                     ; setup reads CLE, CLO + 16 o
        asl a
        asl a
        asl a
        asl a
        sta ldCLE
        rts
@f:     lda cxt
@fx:    sta WX                     ; anew: rows 1..7, o 1
        lda czt
        clc
        adc ZB
        sta WK
        ldx #8
        stx VLO
        dex
        stx VHI
        lda #1
        bne @o                     ; (always)
        .assert <CLE = 0 && <CLO + 48 < $100, error, "crow: CLE page-aligned; CLO + 48 in its page"
        .assert <CMAPE = 0 && <CMAPO = 0 && (>CMAPE & 15) = 0 && (>CMAPO & 15) = 0, error, "crow: CMAPE, CMAPO on 4K boundaries"

; crow: window row X from map row (WK - X) & 63: each tile's bytes, CMAPE and
; CMAPO + 64 z + CX (the arc build: its class, CMAPE's; setup adds the strip's
; brightness).  X kept; clobbers A, Y.
crow:   stx WM
        txa
        asl a
        asl a
        asl a
        asl a
        sta @se+1
.ifndef ARC
        clc
        adc #<CLO
        sta @so+1
        lda #>CLO
        adc #0
        sta @so+2
.endif
        lda WK                     ; the map row: CMAPE + 64 z
        sec
        sbc WM
        and #63
        tay
        lsr a
        lsr a
        ora #>CMAPE
        sta @le+2
.ifndef ARC
        eor #>CMAPE ^ >CMAPO
        sta @lo+2
.endif
        tya
        lsr a
        ror a
        ror a
        and #$C0
        sta @le+1
.ifndef ARC
        sta @lo+1
.endif
        ldx #NX-2
@c:     ldy CX,x
@le:    lda CMAPE,y
@se:    sta CLE,x
.ifndef ARC
@lo:    lda CMAPO,y
@so:    sta CLO,x
.endif
        dex
        bpl @c
        ldx WM
        rts

; zsh4: the heights' map rows moved by A - pkz (A = czt + ZB).  For one row on
; (SHF 1) or back (SHF $FF) the new row's heights go to HTN for hsh, C set;
; otherwise C clear.  pkz = A.  Clobbers A, X, Y.
zsh4:   tay
        sec
        sbc pkz
        sty pkz
        cmp #1
        beq @ld
        cmp #$FF
        bne @no
        tya                        ; one back: the new row is row 7
        sbc #7
        tay
        lda #$FF
@ld:    sta SHF
        tya
        jsr mrow
        sta HPZ
        sty HPZ+1
        ldx #NX-1
:       ldy CX,x
        lda (HPZ),y
        sta HTN,x
        dex
        bpl :-
        sec
        rts
@no:    clc
        rts

; mrow: map row A & 63's address in B4MAP: A low, Y high; tmp = the row.
; X kept.
mrow:   and #63
        sta tmp
        lsr a
        lsr a
        ora #>B4MAP
        tay
        lda tmp
        lsr a
        ror a
        ror a
        and #$C0
        rts
        .assert <B4MAP = 0 && (>B4MAP & 15) = 0, error, "mrow: B4MAP on a 4K boundary"

WX:     .byte $FF                  ; the window's cxt ($FF: none yet)
WK:     .byte 0                    ; its row 0's map row
WO:     .byte 0                    ; o
VLO:    .byte 0                    ; the rows made: VLO .. VHI
VHI:    .byte 0
WE:     .byte 0                    ; o + 7
WM:     .byte 0                    ; crow's row
pkx:    .byte $FF                  ; the cxt and czt + ZB the heights are for
pkz:    .byte $FF
        .popseg
.ifdef ARC
        .pushseg
        .segment "TABLES"
        .include "colours.inc"
        .popseg
.endif
