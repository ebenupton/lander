; ============================================================================
; shipspan.s -- LAND's bank 6 ship drawing (included by shipb.s): `shipdraw`
; from tools/shipgen.py's shipspan.inc, the ship's every line pre-rasterised.
;
; shipdraw: direction shk, pitch shp, centre (shx, shy) on the screen whose
; high byte is scrb; its box to bxl, bxr, byt, byb.  Entry e = shp *
; SHIP_ND2 + the stored direction (k + 8, or 24 - k mirrored: its pixel
; mirror image about the centre, the normals' x signs inverted).  Its lines
; in bands, each band's lines with one pattern of faces left to right (a face
; a line lacks: no pixels); each line its boundaries u (offsets + SHIP_U0:
; the first pixel, each face's end), drawn left to right on the screen (a
; mirrored line's boundaries read from its end).  A band in two passes,
; alternate lines (each pass one dither): the lines' bytes in that order.
; A line: the byte holding its first pixel read (acc), then each face: acc's
; pixels from the boundary's on set to the face's dither (eor c; and KT; eor
; c: KT the pixels before the boundary's in its byte); if the next boundary
; is in a later byte (X >= lim (normal; mirrored X < lim): lim the first u
; there), acc stored, the whole bytes between filled, acc = c.  Then the last
; byte: acc's pixels before the last boundary, the screen's after.
;
; X = the boundary u, Y = acc's byte's offset from ptr (the line's address +
; 8 * the column 5 left of shx's).  Byte offset, KT and lim by u through
; tables (KT, BY, LIM: normal or mirrored, for shx & 3: patched in per
; drawing); the boundaries' reads (rd_j, in) patched per line (pn_j, pm_j);
; the faces in slots 7 - n .. 6 (seg_j: n the band's faces).
; ============================================================================

; zero page (shipb.s's): c0+j, x0+j (j 1..6) the slots' dithers (this pass's)
; and their even ^ odd; ptr, dp (the line's bytes), lim, bl (lines left in
; the pass), nb (in pass B), ptb (pass B's first line), t, al (shx & 3), ...

        .assert SHIP_MAXN <= 6, error, "six faces a line at most"

; The dithers: slot j's face's (the pattern's j - (7 - n)'th, or mirrored its
; 6 - j'th), for this line, and its even ^ odd.
.macro CS base, j
        ldx base,y
        lda FCX,x
        sta x0+j
        and pm
        eor FCE,x
        sta c0+j
.endmacro
cn1:    CS SPATF-6, 1
cn2:    CS SPATF-5, 2
cn3:    CS SPATF-4, 3
cn4:    CS SPATF-3, 4
cn5:    CS SPATF-2, 5
cn6:    CS SPATF-1, 6
        jmp lnx2
cm1:    CS SPATF+5, 1
cm2:    CS SPATF+4, 2
cm3:    CS SPATF+3, 3
cm4:    CS SPATF+2, 4
cm5:    CS SPATF+1, 5
cm6:    CS SPATF+0, 6
        jmp lnx2

; ---------------------------------------------------------------- shipdraw
shipdraw:
        lda shk                    ; the stored direction: k + 8, or 24 - k
        clc                        ; mirrored (tools/shipgen.py's kmap)
        adc #SHIP_NDIR/4
        and #SHIP_NDIR-1
        ldx #0
        cmp #SHIP_ND2
        bcc :+
        lda #SHIP_NDIR*3/4
        sec
        sbc shk
        and #SHIP_NDIR-1
        dex
:       stx mir
        sta ee
        lda shp
        asl a
        asl a
        asl a
        asl a
        adc shp                    ; (C clear: shp < 16)
        .assert SHIP_ND2 = 17, error, "shp * 17"
        adc ee
        sta ee                     ; the entry
        tax
        lda SNEG,x                 ; the faces' dithers (FCE, FCO; FCX their eor)
        eor mir
        sta t
        sta k
        lda shp                    ; shp * 18
        asl a
        asl a
        asl a
        adc shp
        asl a
        tay
        .repeat 8, f
        lsr t                      ; (C: face f's normal's x < 0)
        tya
        adc #2*f
        tax
        lda SHDE,x
        sta FCE+f
        eor SHDO,x
        sta FCX+f
        .endrepeat
        asl k                      ; the exhaust: as face 7
        tya
        adc #2*8
        tax
        lda SHDE,x
        sta FCE+8
        eor SHDO,x
        sta FCX+8

        ldx ee                     ; its box
        lda EYS,x                  ; (its first line + 14, low; last - 4)
        and #$0F
        clc
        adc shy
        sec
        sbc #14
        sta byt
        lda EYS,x
        lsr a
        lsr a
        lsr a
        lsr a
        sec
        adc #3
        adc shy
        sta byb
        lda shx
        and #3
        sta al
        sta alx                    ; (+ al, normal; - al mirrored)
        lda EXB,x                  ; its leftmost pixel + 17 (low), rightmost - 4
        and #$0F
        sta t
        lda EXB,x
        lsr a
        lsr a
        lsr a
        lsr a
        bit mir
        bmi @mi
        sec                        ; (+ 4)
        adc #3
        adc shx
        sta bxr
        lda shx
        sec
        sbc #17
        clc
        adc t
        sta bxl
        ldx #0                     ; (the normal patches)
        beq @pt
@mi:    eor #$FF                   ; (mirrored: - rightmost, - leftmost)
        sec
        adc shx
        sec
        sbc #4
        sta bxl
        lda shx
        clc
        adc #17
        sec
        sbc t
        sta bxr
        lda #0
        sec
        sbc al
        sta alx
        ldx #1
@pt:    lda PKT,x                  ; KT, BY, H (normal, or mirrored) for shx & 3
        clc
        adc alx
        .repeat 6, j
        sta .ident(.sprintf("kt%d", j + 1))+1
        .endrepeat
        sta ktf+1
        lda PBY,x
        clc
        adc alx
        .repeat 6, j
        sta .ident(.sprintf("bya%d", j + 1))+1
        sta .ident(.sprintf("byb%d", j + 1))+1
        .endrepeat
        sta iby+1
        lda al                     ; LIM's (for shx & 3, normal or mirrored)
        asl a
        asl a
        asl a
        adc al
        asl a
        asl a                      ; (36 al)
        adc PLM,x
        php
        .repeat 6, j
        sta .ident(.sprintf("hl%d", j + 1))+1
        .endrepeat
        sta ihl+1
        plp
        lda PLMH,x
        adc #0
        .repeat 6, j
        sta .ident(.sprintf("hl%d", j + 1))+2
        .endrepeat
        sta ihl+2
        lda PAD,x
        .repeat 6, j
        sta .ident(.sprintf("ad%d", j + 1))+1
        .endrepeat
        lda PBR,x                  ; bcc (normal) or bcs: the same byte
        .repeat 6, j
        sta .ident(.sprintf("br%d", j + 1))
        .endrepeat
        lda PLO,x                  ; the line's second read: + 1 or - 1
        sta lop
        lda PLV,x
        sta lop+1
        lda PMK,x                  ; (mirrored: the first read + n)
        sta mk
        lda PPL,x                  ; the patch chain's entries
        sta bpcl+1
        lda PCL,x                  ; the dithers' chain's
        sta bccl+1
        lda PSO,x                  ; the pattern's faces (+ n, normal)
        sta bso+1
        lda PSOH,x
        sta bso+2
        ldx ee                     ; its lines
        lda ELO,x
        sta dp
        lda EHI,x
        jsr page
        lda shx                    ; ptr: line byt, column (shx >> 2) - 5
        and #$FC
        asl a
        ldx #0
        bcc :+
        inx
:       sec
        sbc #40
        bcs :+
        dex
:       sta t
        stx k
        lda byt
        and #7
        ora t
        sta ptr
        lda byt
        lsr a
        lsr a
        and #$FE
        clc
        adc scrb
        clc
        adc k
        sta ptr+1

; ---------------------------------------------------------------- a band
band:   ldy #0
        lda (dp),y                 ; B, or $FF: the end, $FE: the next page
        cmp #$FE
        bcc :++
        beq :+
        rts
:       sty dp
        lda dp+1
        adc #0                     ; (C set: + 1)
        jsr page
        jmp band
:       inc dp
        tax
        lda BANDL,x
        sta bl
        ldy BANDP,x                ; its pattern
        ldx SPATN,y                ; n faces
        inx                        ; its lines: n + 1 bytes
        stx stp+1
        dex
        txa
        and mk
        sta lk+1
bpcl:   lda PNL,x                  ; the line's patch chain (normal or mirrored)
        sta lj+1
        lda SGL,x                  ; the first face's slot: 7 - n
        sta ij+1
        lda SGH,x
        sta ij+2
        lda FLL,x                  ; the dithers' flip
        sta fj+1
bccl:   lda CNL,x                  ; the dithers' chain
        sta bcj+1
        lda ptr+1                  ; ptb: the next line
        sta ptb+1
        ldx ptr
        inx
        txa
        and #7
        bne :+
        txa                        ; (+ 512 - 8: the inx's carry, if any, the
        sec                        ; sbc's borrow)
        sbc #8
        tax
        inc ptb+1
        inc ptb+1
:       stx ptb
        lda bl                     ; two passes: alternate lines (one dither
        lsr a                      ; each), the one with the last line first
        sta nb                     ; (B's lines; the lines' bytes in that order)
        bcc @ev
        adc #0                     ; (C set) odd: A lines 0, 2, .., B 1, 3, ..
        sta bl
        lda nb
        bne @cl
        lda #$80                   ; (one line: no B, ptb the band's end)
        sta nb
        bne @cl
@ev:    sta bl                     ; even: A lines 1, 3, .., B 0, 2, ..
        lda ptr
        ldx ptb
        stx ptr
        sta ptb
        lda ptr+1
        ldx ptb+1
        stx ptr+1
        sta ptb+1
@cl:    lda ptr                    ; pass A's dithers: even or odd lines
        and #1
        beq :+
        lda #$FF
:       sta pm
bso:    lda SPATO,y                ; (normal: SPATON)
        tay
bcj:    jmp cn1                    ; (lo patched: cn_j or cm_j)



; The lines' page: dp's high byte and the boundaries' reads'.
page:   sta dp+1
        .repeat 6, j
        sta .ident(.sprintf("rd%d", j + 1))+2
        .endrepeat
        sta in+2
        rts


.macro PC j, op
        sta .ident(.sprintf("rd%d", j))+1
        op #1
.endmacro
pn1:    PC 1, adc
pn2:    PC 2, adc
pn3:    PC 3, adc
pn4:    PC 4, adc
pn5:    PC 5, adc
pn6:    sta rd6+1
        jmp in
pm1:    PC 1, sbc
pm2:    PC 2, sbc
pm3:    PC 3, sbc
pm4:    PC 4, sbc
pm5:    PC 5, sbc
pm6:    sta rd6+1

; The first boundary: acc its byte's (from the screen).
in:     ldx $FFFF
ihl:    lda LIM-3,x
        sta lim
iby:    ldy BYN,x
        lda (ptr),y
ij:     jmp $FFFF                  ; (seg_j, j = 7 - n)

; The faces: slot j's from boundary X (acc A, its byte Y) to the next.
.macro SEG j
        .local fl, fd
.ident(.sprintf("seg%d", j)):
        eor c0+j
.ident(.sprintf("kt%d", j)):
        and KTN,x
        eor c0+j
.ident(.sprintf("rd%d", j)):
        ldx $FFFF
        cpx lim
.ident(.sprintf("br%d", j)):
        bcc .ident(.sprintf("seg%d", j + 1))
        sta (ptr),y
.ident(.sprintf("hl%d", j)):
        lda LIM-3,x
        sta lim
        tya
.ident(.sprintf("ad%d", j)):
        adc #7                     ; (+ 8: adc #7 with C set, normal; #8 mirrored)
.ident(.sprintf("bya%d", j)):
        cmp BYN,x
        bcs fd
fl:     tay
        lda c0+j
        sta (ptr),y
        tya
        adc #8
.ident(.sprintf("byb%d", j)):
        cmp BYN,x
        bcc fl
fd:     tay
        lda c0+j
.endmacro
        SEG 1
        SEG 2
        SEG 3
        SEG 4
        SEG 5
        SEG 6
seg7:                              ; the last byte: acc's pixels, the screen's after
        eor (ptr),y
ktf:    and KTN,x
        eor (ptr),y
        sta (ptr),y
lend:   lda ptr                    ; the next line but one
        clc
        adc #2
        sta ptr
        and #6
        beq lrow
lnx:    lda dp
        clc
stp:    adc #0                     ; (n + 1)
        sta dp
        dec bl
        bne line                   ; (C clear)
        lda nb                     ; pass B, if any lines
        beq pstb
        bmi psrb
        sta bl
        lda #0
        sta nb
fj:     jmp fl1                    ; (lo patched: the dithers' flip, fl_j)
.macro FLIP j
.ident(.sprintf("fl%d", j)):
        lda c0+j
        eor x0+j
        sta c0+j
.endmacro
        FLIP 1
        FLIP 2
        FLIP 3
        FLIP 4
        FLIP 5
        FLIP 6
        lda ptb                    ; pass B's first line
        sta ptr
        lda ptb+1
        sta ptr+1
        jmp lnx2
psrb:   lda ptb                    ; (or the band's end)
        sta ptr
        lda ptb+1
        sta ptr+1
pstb:   jmp band
; ---------------------------------------------------------------- a line
; The boundaries' reads: in the first, rd_j the end of slot j's face (slots
; 7 - n .. 6): normal, the line's bytes in turn; mirrored, from its end.
lnx2:   lda dp
        clc
line:
lk:     adc #0                     ; (mirrored: n)
        sta in+1
lop:    adc #1                     ; (adc #1, or sbc #0: C clear, - 1)
lj:     jmp pn1                    ; (lo patched: pn_j or pm_j)
lrow:   lda ptr                    ; (+ 512 - 8: the adc's carry, if any,
        sec                        ; the sbc's borrow)
        sbc #8
        sta ptr
        inc ptr+1
        inc ptr+1
        jmp lnx
; ---------------------------------------------------------------- tables
PNL:    .byte 0, <pn6, <pn5, <pn4, <pn3, <pn2, <pn1
PML:    .byte 0, <pm6, <pm5, <pm4, <pm3, <pm2, <pm1
CNL:    .byte 0, <cn6, <cn5, <cn4, <cn3, <cn2, <cn1
CML:    .byte 0, <cm6, <cm5, <cm4, <cm3, <cm2, <cm1
PKT:    .byte <KTN, <KTR           ; (+ al, or - al)
PBY:    .byte <BYN, <BYR
PLM:    .byte <(LIM-3), <(LIM-3+144)
PLMH:   .byte >(LIM-3), >(LIM-3+144)
PBR:    .byte $90, $B0             ; bcc, bcs
PAD:    .byte 7, 8
PLO:    .byte $69, $E9             ; adc #, sbc #
PLV:    .byte 1, 0
PMK:    .byte 0, $FF
PPL:    .byte <PNL, <PML
PCL:    .byte <CNL, <CML
PSO:    .byte <SPATON, <SPATO
PSOH:   .byte >SPATON, >SPATO
SGL:    .byte 0, <seg6, <seg5, <seg4, <seg3, <seg2, <seg1
SGH:    .byte 0, >seg6, >seg5, >seg4, >seg3, >seg2, >seg1
FLL:    .byte 0, <fl6, <fl5, <fl4, <fl3, <fl2, <fl1
        .assert >PNL = >PML && >CNL = >CML, error, "the n tables' pages"
        .assert >pn1 = >pm6 && >cn1 = >(cm6+12) && >fl1 = >fl6, error, "the chains: each in a page"

FCE:    .res 9                     ; the faces' dithers: even lines, and even ^ odd
FCX:    .res 9

; KT, BY (normal: N, mirrored: R): tools/shipgen.py's, in the lines' first page.
        .assert >KTR = >(BYN+41) && <KTR >= 3, error, "the u tables: one page"
