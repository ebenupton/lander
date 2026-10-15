; ============================================================================
; shipspan.s -- the ship's drawing for LAND's bank 6.  Included by shipb.s:
; the span walker and its tables go into the bank's CODE segment after keys
; and ship ($8105-$869E), the decoder spdec into TAIL ($B400-$B58A, the page
; after the SPANS streams) and the nibble tables DTH, DL4 open DTAB ($B600),
; where shipspan.inc's tables follow.  tools/shipgen.py writes shipspan.inc: every
; stored orientation's lines, rasterised by its reference tri() and
; compressed; test/shipbtest.py runs shipdraw under py65 for every
; orientation and checks each screen byte against that reference.
; Addresses quoted here are build/shipb_labels.txt's.
;
; Entry: shipdraw (jsr from shipb.s's ship; the test calls it directly).
; In: shk the direction (0..31), shp the pitch (0..12), shx, shy the centre,
; scrb the high byte of the screen to draw on (LAND's zero page).  Out: the
; ship's pixels on that screen, every other pixel untouched; bxl, bxr, byt,
; byb its box (first and last pixel column and line, inclusive); DBUF holding
; the orientation's lines and dlast naming it.  Clobbers A, X, Y, zero page
; $8E-$9F and TRL+0..15 (shipb.s's names), FCE, FCX, and the patched
; operands named below.  LAND's own uses of that zero page (project's HPZ,
; bank 7's CX2.., the strips' BE, BO) and of TRL, TRB (a split column's
; transitions) are over when B6_SHIP runs and are set afresh before each use.
;
; Orientation: entry e = 17 shp + kk, kk the stored direction (shipgen's
; kmap): (shk + 8) & 31 when that is under 17 (mir 0), else (24 - shk) & 31
; with mir $FF, the stored picture drawn as its mirror image about shx
; (pixel shx + d at shx - d) and each face's "normal's x < 0" bit (SNEG + e)
; inverted, which picks the other shade.
;
; A line: m = n + 1 boundaries u = pixel offset from shx + SHIP_U0 (20): the
; first pixel, then where each of the band's n faces ends, left to right on
; the stored picture (a face the line lacks ends where it starts).  The
; screen pixel of u is w = u + al (normal) or 41 + al - u (mirrored), al =
; shx & 3, counted from the column five left of shx's (ptr's column): spdec
; stores w, and a mirrored line's boundaries are read from its last to its
; first and the faces' slots are filled from the pattern's end.
;
; Bands: an orientation's lines run top to bottom in bands, each band's lines
; sharing a pattern P (SPATN + P faces: n, 1..6, listed in SPATF from SPATO +
; P to SPATON + P) and each boundary moving by at most a nibble (-8..7) a
; line.  The stream (SPANS; ELO, EHI + e): per band P, L (its lines), line
; 0's m bytes, then lines 1 .. L-1 each as m nibbles, high nibble first, a
; byte a pair (an odd m's first high nibble zero, unused): each boundary's
; change from the line before, the high nibble rotated to put its sign bit
; lowest; $FF after the last band.  spdec expands it
; into DBUF ($2F00, main RAM): P, L, then the lines in order, each as its w's
; (below) in the last m bytes of an eight-byte slot; $FF the end.  An
; orientation's DBUF image is under 256 bytes (shipgen asserts), so it never
; leaves page $2F: dp and the reads' low bytes alone move.
;
; Drawing (band, line, SEG): a band's lines in two passes of alternate lines,
; A then B (dp stepping two slots a line), each pass with the faces' dithers
; for its lines' parity (c0+j slot j's byte for this pass, x0+j its even ^
; odd, to flip for pass B).  A line: Y = the first boundary's byte (its
; offset from ptr: 8 a column), acc (A) = that screen byte; then for each
; face in turn acc's pixels from the
; boundary on become the face's dither (eor c, and KT, eor c: KT the mask of
; the pixels before w in its byte); when the next boundary lies in a later
; byte, acc is stored, the whole bytes between are filled with the dither
; and acc restarts as a byte of it.  The last boundary leaves the pixels from
; it on as the screen's.  The screen is MODE 1 cut to 64 bytes a line: 4
; pixels a byte (masks $88, $44, $22, $11), 8 bytes a column cell, 512 a
; character row; line y's byte of column c is at base + 512 (y >> 3) + (y &
; 7) + 8 c.
;
; Tables for w (shipgen's write(), in DTAB): KTN + w the mask of the pixels
; before w in its byte, BYN + w the byte's offset from ptr, 8 (w >> 2), LIM +
; w the first pixel of the byte after, 4 ((w >> 2) + 1): the next boundary
; is in the same byte when it is under that, read in rising w either way.
;
; Self-modification: shipdraw patches the mirror-dependent opcode and
; operands (lop; lk's mask mk), band's table bases (bpcl, bccl, bso) and the
; lines' page (rd_j, in: page).  band patches the first read's offset (lk)
; and the chains' entries (lj, ij, fj, bcj); each line patches its m reads
; (in, rd_j) through the pn_j or pm_j chain.  The
; chains pn_j/pm_j, cn_j/cm_j, seg_j, fl_j are six entries each running on
; into the next; a band of n faces enters at entry 7 - n (tables PNL, PML,
; CNL, CML, SGL, SGH, FLL + n), so the faces occupy slots 7 - n .. 6, slot 6
; is always the last face, and seg6 falls into seg7, the line's end.
; ============================================================================

; Zero page (shipb.s's names): c0+j, x0+j (j 1..6) the slots; ptr the line's
; screen byte, dp its DBUF bytes, lim, bl (lines left in the pass); and in
; TRL: t, k (scratch), al, wb (spdec's base for w), ee, pm, mk, nb, ptb, dpb
; (pass B's first line: its screen byte and its DBUF slot).

        .assert SHIP_MAXN <= 6, error, "six slots: no pattern may have more faces"

; CS base, j: slot j's dithers from the pattern face SPATF[base + Y]: x0+j =
; its even ^ odd (FCX), c0+j = its byte for this pass's parity (FCE, or FCE ^
; FCX when pm is $FF).  In: Y from bso (normal SPATON + P, one past the
; pattern's last face; mirrored SPATO + P, its first), pm.  Clobbers A, X.
.macro CS base, j
        ldx base,y
        lda FCX,x
        sta x0+j
        and pm
        eor FCE,x
        sta c0+j
.endmacro
; The dithers' chains, reached by bcj's patched jmp with Y from bso.  A band
; of n faces enters at cn_(7-n): slot j gets the pattern's face j - (7 - n)
; (SPATF-6 .. SPATF-1 from its end); or at cm_(7-n): slot j gets face 6 - j
; (SPATF+5 .. SPATF+0 from its start), the pattern reversed.  Slots 7 - n ..
; 6 set, the chain runs on to lnx2, the pass's first line.
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
; shipdraw: draw the ship (shk, shp) centred at (shx, shy) on screen scrb;
; In, Out and Clobbers as the file header.  Sets mir, ee, the faces' dithers
; FCE, FCX, the box, al, wb, every per-drawing patch, DBUF (spdec, unless it
; holds this entry as drawn with this mir and al: dlast, dmir, dal), dp =
; DBUF and ptr = line byt's byte in column (shx >> 2) - 5, then falls into
; band; band's rts at the $FF ends the drawing.
shipdraw:
        lda shk                    ; kk = (shk + 8) & 31 if under 17: as stored
        clc
        adc #SHIP_NDIR/4
        and #SHIP_NDIR-1
        ldx #0                     ; (X: mir)
        cmp #SHIP_ND2
        bcc :+
        lda #SHIP_NDIR*3/4         ; else kk = (24 - shk) & 31 mirrored: mir $FF
        sec
        sbc shk
        and #SHIP_NDIR-1
        dex
:       stx mir
        sta ee
        lda shp                    ; ee = 17 shp + kk: 16 shp (the asls leave C
        asl a                      ; clear: shp < 16) + shp + kk, no carry out
        asl a
        asl a
        asl a
        adc shp
        .assert SHIP_ND2 = 17, error, "the entry is 17 shp + kk: SHIP_ND2 is 17"
        adc ee
        sta ee
        tax
        lda SNEG,x                 ; bit f: face f's normal's x < 0, inverted if
        eor mir                    ; mirrored (t shifted out below; k: face 7's)
        sta t
        sta k
        lda shp                    ; Y = 18 shp: SHDE, SHDO's row for the pitch
        asl a                      ; (8 shp + shp, doubled; no carries)
        asl a
        asl a
        adc shp
        asl a
        tay
        .repeat 8, f               ; face f: FCE+f = SHDE[18 shp + 2 f + sign],
        lsr t                      ; its even byte (the lsr's C, the sign, is
        tya                        ; the adc's carry in); FCX+f = that ^ SHDO's,
        adc #2*f                   ; the odd line's
        tax
        lda SHDE,x
        sta FCE+f
        eor SHDO,x
        sta FCX+f
        .endrepeat
        asl k                      ; the exhaust (face 8) has face 7's sign (k's
        tya                        ; bit 7 into C)
        adc #2*8
        tax
        lda SHDE,x
        sta FCE+8
        eor SHDO,x
        sta FCX+8

        ldx ee                     ; the box (EYS, EXB: two nibbles each)
        lda EYS,x                  ; low nibble: the first line's offset + 14
        and #$0F
        clc
        adc shy
        sec
        sbc #14
        sta byt                    ; byt = shy + the first line's offset
        lda EYS,x                  ; high nibble: the last line's offset - 4
        lsr a
        lsr a
        lsr a
        lsr a
        sec                        ; (+ 4: adc #3 with C set)
        adc #3
        adc shy
        sta byb                    ; byb = shy + the last line's offset
        lda shx
        and #3
        sta al                     ; al = shx & 3, the centre's pixel in byte
        sta wb                     ; wb = al (normal) or 41 + al (mirrored):
        lda EXB,x                  ; spdec's base for w
        and #$0F                   ; low nibble: the leftmost pixel's offset + 1
        sta t
        lda EXB,x                  ; high nibble: the rightmost's offset - 4
        lsr a
        lsr a
        lsr a
        lsr a
        bit mir
        bmi @mi
        sec                        ; normal: bxr = shx + the rightmost's offset
        adc #3
        adc shx
        sta bxr
        lda shx                    ; bxl = shx + the leftmost's offset
        sec
        sbc #17
        clc
        adc t
        sta bxl
        ldx #0                     ; X = 0: the P* tables' normal entry
        beq @pt
@mi:    eor #$FF                   ; mirrored: bxl = shx - the rightmost's
        sec                        ; offset (A = -(hi + 1), + shx + 1, - 4)
        adc shx
        sec
        sbc #4
        sta bxl
        lda shx                    ; bxr = shx - the leftmost's offset
        clc
        adc #17
        sec
        sbc t
        sta bxr
        lda al                     ; wb = 41 + al: w = wb + (u ^ $FF) + 1
        clc
        adc #2*SHIP_U0+1
        sta wb
        ldx #1                     ; X = 1: the P* tables' mirrored entry
@pt:    lda PLO,x                  ; lop: adc #1 (normal: the reads step up the
        sta lop                    ; line's bytes) or sbc #0 (mirrored: down; C
        lda PLV,x                  ; clear makes it - 1)
        sta lop+1
        lda PMK,x                  ; mk: lk's mask on n: $FF (the first read is
        sta mk                     ; the line's first byte) or 0 (its last)
        lda PPL,x                  ; bpcl's table: PNL or PML (lj's entry)
        sta bpcl+1
        lda PCL,x                  ; bccl's: CNL or CML (bcj's entry)
        sta bccl+1
        lda PSO,x                  ; bso's: SPATON (normal, the pattern's end)
        sta bso+1                  ; or SPATO (mirrored: its start)
        lda PSOH,x
        sta bso+2
        ldx ee                     ; DBUF holds entry dlast's lines as drawn
        cpx dlast                  ; mirrored dmir at pixel dal: expand ee's
        bne :+                     ; unless it already does
        lda mir
        cmp dmir
        bne :+
        lda al
        cmp dal
        beq :++
:       stx dlast
        lda mir
        sta dmir
        lda al
        sta dal
        jsr spdec
:
        lda #<DBUF                 ; dp = DBUF; its page into dp+1, rd_j, in
        sta dp
        lda #>DBUF
        jsr page
        lda shx                    ; ptr = line byt's byte in the column 5 left
        and #$FC                   ; of shx's: X:A = 8 (shx >> 2) - 40 (the
        asl a                      ; asl's carry into X, the sbc's borrow out)
        ldx #0
        bcc :+
        inx
:       sec
        sbc #40
        bcs :+
        dex
:       sta t
        stx k
        lda byt                    ; low byte: byt & 7 | the column part (a
        and #7                     ; multiple of 8)
        ora t
        sta ptr
        lda byt                    ; high byte: scrb + 2 (byt >> 3) + the column
        lsr a                      ; part's
        lsr a
        and #$FE
        clc
        adc scrb
        clc
        adc k
        sta ptr+1

; ---------------------------------------------------------------- a band
; band: start the band at dp (its P, L), or at $FF return (the rts is
; shipdraw's: the drawing is done).  In: dp the band's bytes, ptr its first
; line's screen byte, the per-drawing patches.  Sets lk (the first read's
; slot byte: 7 - n, or 7 mirrored), lj, ij, fj, bcj (the chains' entries for
; n), ptr and ptb, dp and dpb (pass A's and pass B's first lines' screen
; bytes and DBUF slots: the band's first two lines, swapped when L is even),
; bl and nb (the passes' lines), pm (pass A's parity), then enters the
; dithers' chain, which runs on to lnx2.
; Reached by falling in from shipdraw and by jmp from pstb, psrb after a
; band.
band:   ldy #1
        lda (dp),y                 ; L, the band's lines
        sta bl
        dey
        lda (dp),y                 ; P, its pattern, or $FF (bit 7: P < 128)
        bpl :+
        rts
:       tay
        ldx SPATN,y                ; n, the pattern's faces
        lda dp                     ; dp past P, L (no page crossing: the DBUF
        clc                        ; image is within its page), dpb = the
        adc #2                     ; second line's slot (pass B's first, or
        sta dp                     ; swapped)
        adc #8
        sta dpb
        txa
        and mk
        eor #7
        sta lk+1                   ; lk: the first read's slot byte, 7 - n (the
                                   ; line's first) or 7 (its last, mirrored)
bpcl:   lda PNL,x                  ; (operand patched: PNL or PML) lj's target,
        sta lj+1                   ; pn_(7-n) or pm_(7-n)
        lda SGL,x                  ; ij's target, seg_(7-n): the first face's
        sta ij+1
        lda SGH,x
        sta ij+2
        lda FLL,x                  ; fj's target, fl_(7-n)
        sta fj+1
bccl:   lda CNL,x                  ; (operand patched: CNL or CML) bcj's target,
        sta bcj+1                  ; cn_(7-n) or cm_(7-n)
        lda ptr+1                  ; ptb = the line after ptr's: + 1, or at a
        sta ptb+1                  ; character row's end ((ptr + 1) & 7 = 0) + 1
        ldx ptr                    ; - 8 + 512 (the inx's lost carry, if any,
        inx                        ; and the sbc's borrow cancel: the two incs
        txa                        ; are the high byte's whole change)
        and #7
        bne :+
        txa
        sec
        sbc #8
        tax
        inc ptb+1
        inc ptb+1
:       stx ptb
        lda bl                     ; the passes: nb = L >> 1 lines in B, bl in A
        lsr a
        sta nb
        bcc @ev
        adc #0                     ; L odd (C set): A has L/2 + 1 lines 0, 2, ..
        sta bl                     ; from ptr; B lines 1, 3, .. from ptb
        lda nb
        bne @cl
        lda #$80                   ; L = 1: no pass B; nb $80 sends lnx to psrb,
        sta nb                     ; ptr = ptb the band's end
        bne @cl
@ev:    sta bl                     ; L even: A has L/2 lines 1, 3, .. from ptb,
        lda ptr                    ; B lines 0, 2, .. from ptr: ptr, ptb swapped
        ldx ptb
        stx ptr
        sta ptb
        lda ptr+1
        ldx ptb+1
        stx ptr+1
        sta ptb+1
        lda dp                     ; and dp, dpb: A reads from the second line
        ldx dpb
        stx dp
        sta dpb
@cl:    lda ptr                    ; pm = $FF if pass A's lines are odd (a
        and #1                     ; line's byte address has its y's bit 0)
        beq :+
        lda #$FF
:       sta pm
bso:    lda SPATO,y                ; (operand patched: SPATON; SPATO mirrored)
        tay                        ; Y for CS: the pattern's end, or its start
bcj:    jmp cn1                    ; (low byte patched: cn_(7-n) or cm_(7-n))



; page: A, the lines' page (DBUF's), into dp+1 and the boundary reads' high
; bytes (rd_j+2, in+2).  One call a drawing, from shipdraw.
page:   sta dp+1
        .repeat 6, j
        sta .ident(.sprintf("rd%d", j + 1))+2
        .endrepeat
        sta in+2
        rts


; PC j, op: the reads' chain's entry j: A (a line byte's address, low) into
; rd_j's operand, then op #1: adc (normal; C clear from lop) steps to the
; next byte, sbc (mirrored; C set from lop's sbc) to the one before.
.macro PC j, op
        sta .ident(.sprintf("rd%d", j))+1
        op #1
.endmacro
; The reads' chains, reached by lj's patched jmp with A = the second read's
; byte (in's + 1, normal; - 1 mirrored).  A band of n faces enters at
; pn_(7-n) or pm_(7-n): rd_(7-n) .. rd6 get the line's bytes 1 .. n (normal)
; or n - 1 .. 0 (mirrored); then in draws the line (pm6 falls into it).
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

; in: draw the line whose reads are patched.  X = the first boundary u
; (operand from lk), lim = LIM's for it, Y = its byte's offset from ptr, A =
; that screen byte (acc); then into seg_(7-n), the first face's slot.
in:     ldx $FFFF                  ; (operand: the line's first read, lk's)
        lda LIM,x
        sta lim
        ldy BYN,x
        lda (ptr),y
ij:     jmp $FFFF                  ; (operand: seg_(7-n), band's)

; SEG j: slot j's face, from boundary X (acc A is its byte Y so far) to the
; next boundary.  acc's pixels from w on become c0+j (KT: those before w
; stay).  rd_j reads the next boundary; if it is in acc's byte (w < lim) the
; next slot continues with the same acc; else acc is stored, lim becomes the
; new boundary's, Y steps by 8 a byte, the whole bytes before the boundary's
; are filled with c0+j (cmp its BY) and acc restarts as c0+j with Y its byte.
; Runs into seg_(j+1); seg6 into seg7.  Patched: rd_j's low byte a line, its
; high byte a drawing (page).
.macro SEG j
        .local fl, fd
.ident(.sprintf("seg%d", j)):
        eor c0+j                   ; acc = (acc ^ c) & KT ^ c: KT's pixels keep
        and KTN,x                  ; acc, the rest become c
        eor c0+j
.ident(.sprintf("rd%d", j)):
        ldx $FFFF                  ; (operand: the line's byte 1 + j - (7 - n),
        cpx lim                    ; or n - 1 - (j - (7 - n)) mirrored): next w
        bcc .ident(.sprintf("seg%d", j + 1))   ; the same byte: the next slot
        sta (ptr),y                ; acc complete
        lda LIM,x                  ; lim for the new w
        sta lim
        tya
        adc #7                     ; (C set: the cpx's) Y + 8
        cmp BYN,x                  ; the w's byte reached: nothing between
        bcs fd
fl:     tay                        ; a whole byte of c
        lda c0+j
        sta (ptr),y
        tya
        adc #8                     ; (C clear: the cmp's)
        cmp BYN,x
        bcc fl
fd:     tay                        ; Y = the boundary's byte, acc = c, into the
        lda c0+j                   ; next slot
.endmacro
        SEG 1
        SEG 2
        SEG 3
        SEG 4
        SEG 5
        SEG 6
seg7:                              ; the last boundary: acc's pixels before it,
        eor (ptr),y                ; the screen's from it: (acc ^ s) & KT ^ s
        and KTN,x
        eor (ptr),y
        sta (ptr),y
lend:   lda ptr                    ; ptr to the pass's next line, y + 2; into a
        clc                        ; new character row (y & 7 of 6 or 7: the
        adc #2                     ; sum's bits 1-2 clear) via lrow
        sta ptr
        and #6
        beq lrow
lnx:    lda dp                     ; dp to the pass's next line: two slots on
        clc
        adc #16
        sta dp
        dec bl                     ; the pass's lines left (C clear, for lk)
        bne line
        lda nb                     ; pass A done: pass B's lines (0: none left,
        beq pstb                   ; the band is done; $80: a one-line band)
        bmi psrb
        sta bl
        lda #0
        sta nb
fj:     jmp fl1                    ; (operand low byte patched: fl_(7-n))
; FLIP j: slot j's dither to the other parity's (c0 ^= its even ^ odd).  The
; chain fl_(7-n) .. fl6 flips every slot in use, then pass B starts at ptb.
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
        lda ptb                    ; pass B's first line: ptr = ptb, dp = dpb
        sta ptr
        lda ptb+1
        sta ptr+1
        lda dpb
        sta dp
        jmp lnx2
psrb:   lda ptb                    ; a one-line band: ptr = ptb, the band's end,
        sta ptr                    ; dp = dpb, the next band's P
        lda ptb+1
        sta ptr+1
        lda dpb
        sta dp
pstb:   jmp band                   ; (pass B's last line is L - 2: ptr is at
                                   ; line L, the next band's first, and dp at
                                   ; the band's end)
; ---------------------------------------------------------------- a line
; line: patch the line's m boundary reads, then draw it (in).  In: A = dp,
; the line's slot in DBUF, C clear.  in reads slot byte lk (7 - n, or 7
; mirrored); lop makes the second read's byte and lj's chain patches the
; rest.  lnx2 enters with a pass's first line, lnx with A from its adc.
lnx2:   lda dp
        clc
line:
lk:     adc #0                     ; (operand: 7 - n, or 7 mirrored) in's byte
        sta in+1
lop:    adc #1                     ; (adc #1; or sbc #0 mirrored, C clear: - 1)
lj:     jmp pn1                    ; (low byte patched: pn_(7-n) or pm_(7-n))
lrow:   lda ptr                    ; into the next character row: - 8 + 512 (the
        sec                        ; adc #2's lost carry, if any, and this sbc's
        sbc #8                     ; borrow cancel: the two incs are the whole
                                   ; high-byte change)
        sta ptr
        inc ptr+1
        inc ptr+1
        jmp lnx
; ---------------------------------------------------------------- tables
; The chains' entries by n (1..6: entry 7 - n at index n) and, in pairs
; indexed 0 normal, 1 mirrored, the P* values shipdraw patches in.
        .align 32                  ; (PNL .. CML, 28 bytes, in one page: bpcl
                                   ; and bccl are patched in the low byte only)
PNL:    .byte 0, <pn6, <pn5, <pn4, <pn3, <pn2, <pn1
PML:    .byte 0, <pm6, <pm5, <pm4, <pm3, <pm2, <pm1
CNL:    .byte 0, <cn6, <cn5, <cn4, <cn3, <cn2, <cn1
CML:    .byte 0, <cm6, <cm5, <cm4, <cm3, <cm2, <cm1
PLO:    .byte $69, $E9             ; lop: adc #1, or sbc #0
PLV:    .byte 1, 0
PMK:    .byte $FF, 0               ; mk: lk's mask on n
PPL:    .byte <PNL, <PML           ; bpcl's table
PCL:    .byte <CNL, <CML           ; bccl's
PSO:    .byte <SPATON, <SPATO      ; bso's: the pattern's end, or its start
PSOH:   .byte >SPATON, >SPATO
SGL:    .byte 0, <seg6, <seg5, <seg4, <seg3, <seg2, <seg1   ; ij: the first slot
SGH:    .byte 0, >seg6, >seg5, >seg4, >seg3, >seg2, >seg1
FLL:    .byte 0, <fl6, <fl5, <fl4, <fl3, <fl2, <fl1     ; fj: the flips' entry
SDP:    .byte 0, <pr1, <hf3, <pr2, <hf5, <pr3, <hf7   ; spdec: sd_ln's entry for
                                   ; m = n + 1
SDR:    .byte 0, <sd_r6, <sd_r5, <sd_r4, <sd_r3, <sd_r2, <sd_r1   ; and sd_r0's,
                                   ; RAW 8 - m
        .assert >PNL = >PML && >CNL = >CML, error, "PNL, PML and CNL, CML each in one page: bpcl, bccl patch the low byte"
        .assert >pn1 = >pm6 && >cn1 = >(cm6+12) && >fl1 = >fl6, error, "each chain in one page: lj, bcj, fj patch the low byte"

FCE:    .res 9                     ; faces 0-7, the exhaust (8), this drawing's
FCX:    .res 9                     ; even-line dither byte, and even ^ odd

        .segment "TAIL"
; ---------------------------------------------------------------- spdec
; spdec: expand entry X's stream (ELO, EHI + X, in SPANS) into DBUF as the
; drawing reads it: per band P, L copied, then its L lines in order, each in
; an eight-byte slot (X) as its last m = SPATN[P] + 1 bytes, slot bytes 8 - m
; .. 7, each boundary as its pixel w: line 0's from the stream's u (wb + u
; normal, wb + (u ^ $FF) + 1 = 41 + al - u mirrored: C, sd_c's, is mir's bit
; 0 and the adds keep it; the RAW chain, entered at its byte 8 - m: sd_r0's
; operand, SDR + n, patched a band), each later line's the line before's
; (the slot before: eight bytes back) plus (normal) or minus (mirrored: the
; adds' opcodes and sd_c, patched when mir differs from dsg) its nibble, a
; pair a stream byte: the PAIR chain pr3 (slot bytes 2, 3), pr2 (4, 5), pr1
; (6, 7), entered at pr(m / 2) for an even m, or through a HALF (hf7: byte
; 1, hf5: 3, hf3: 5, the first byte's low nibble alone) for an odd one
; (sd_ln's operand, SDP + n, patched a band).  A nibble's signed value comes
; from DTH (the high one: the whole byte as the operand's low byte) or DL4
; (the low one, masked, with the high one's sign bit).  $FF, copied, ends
; the entry.
; In: X the entry; mir, wb.  Out: DBUF.  Clobbers A, X, Y, ptr (the stream
; pointer, Y indexing it: an entry is under 256 bytes), $8E (dl: a walker
; slot byte, which it sets after this runs), sd_y, the patched opcodes and
; operands.  Called by shipdraw when dlast, dmir or dal changes.  TAIL
; starts a page (shipb.cfg) so that the chains, laid first, each lie in one.
dl      = $8E                      ; lines left in the band
; RAW k: line 0's slot byte k from the stream's u: wb + u, or wb + (u ^ $FF)
; + 1 mirrored (C, mir's bit 0 from sd_c, kept by the add: w is in 3 .. 41).
.macro RAW k
.ident(.sprintf("sd_r%d", k)):
        lda (ptr),y
        iny
        eor mir
        adc wb
        sta DBUF+k,x
.endmacro
        RAW 1
        RAW 2
        RAW 3
        RAW 4
        RAW 5
        RAW 6
        RAW 7
        jmp sd_le
; HALF k: a stream byte's low nibble alone, taken from (or added to) the
; line before's slot byte k into this line's.
.macro HALF k
        lda (ptr),y                ; hl_k: adc DL4 + the low nibble
        iny
        and #15
        sta .ident(.sprintf("hl%d", k))+1
        lda DBUF-8+k,x             ; the boundary in the line before
.ident(.sprintf("hc%d", k)):
        clc                        ; (opcode: clc, or sec)
.ident(.sprintf("hl%d", k)):
        adc DL4                    ; (opcode: adc, or sbc; operand: the entry)
        sta DBUF+k,x
.endmacro
; PAIR k: a stream byte's two nibbles added to (or taken from) the line
; before's slot bytes k, k + 1 into this line's.  The first add's carry out
; (adc: set by a negative nibble; sbc: clear by one) feeds the second, whose
; entry (DL4 + b & $1F: the low nibble and the high one's sign, bit 4) makes
; up for it.
.macro PAIR k
        lda (ptr),y                ; h_k: adc DTH + b, the high nibble's entry
        iny
        sta .ident(.sprintf("h%d", k))+1
        and #$1F                   ; l_k: adc DL4 + the low nibble, with the
        sta .ident(.sprintf("l%d", k))+1   ; high one's sign
        lda DBUF-8+k,x             ; the boundary in the line before
.ident(.sprintf("ca%d", k)):
        clc                        ; (opcode: clc, or sec)
.ident(.sprintf("h%d", k)):
        adc DTH                    ; (opcode: adc, or sbc; operand: the entry)
        sta DBUF+k,x
        lda DBUF-8+k+1,x
.ident(.sprintf("l%d", k)):
        adc DL4                    ; (opcode and operand likewise)
        sta DBUF+k+1,x
.endmacro
hf7:    HALF 1                     ; m = 7: byte 1, then pairs 2 .. 7
pr3:    PAIR 2                     ; m = 6
pr2:    PAIR 4                     ; m = 4
pr1:    PAIR 6                     ; m = 2
sd_le:  txa                        ; X to the next slot
        clc
        adc #8
        tax
        dec dl
        beq :+
sd_ln:  jmp pr3                    ; (low byte patched: the entry for m) a line
:       jmp sd_bd
hf5:    HALF 3                     ; m = 5: byte 3, then pairs 4 .. 7
        jmp pr2
hf3:    HALF 5                     ; m = 3: byte 5, then the pair 6, 7
        jmp pr1
        .assert >hf7 = >hf3 && >sd_r1 = >sd_r7, error, "the PAIR and RAW chains each in one page: sd_ln, sd_r0 patch the low byte"
spdec:  lda mir                    ; the adds' opcodes for mir: clc, adc
        cmp dsg                    ; (normal) or sec, sbc (mirrored), unless
        beq :+                     ; they are already
        sta dsg
        and #$20
        ora #$18                   ; clc $18, sec $38
        sta sd_c
        sta hc1
        sta hc3
        sta hc5
        .repeat 3, i
        sta .ident(.sprintf("ca%d", 2 * i + 2))
        .endrepeat
        lda mir
        and #$80
        ora #$6D                   ; adc abs $6D, sbc abs $ED
        sta hl1
        sta hl3
        sta hl5
        .repeat 3, i
        sta .ident(.sprintf("h%d", 2 * i + 2))
        sta .ident(.sprintf("l%d", 2 * i + 2))
        .endrepeat
:       lda ELO,x                  ; ptr = the entry's stream
        sta ptr
        lda EHI,x
        sta ptr+1
        ldy #0                     ; Y: the stream's next byte
        ldx #0                     ; X: DBUF's next byte
sd_bd:  lda (ptr),y                ; a band's P, or $FF (bit 7: P < 128): copied
        sta DBUF,x
        bmi sd_end
        iny
        inx
        sty sd_y                   ; (Y lent to index SPATN)
        tay
        lda SPATN,y                ; n: the chains' entries
        tay
        lda SDP,y
        sta sd_ln+1
        lda SDR,y
        sta sd_r0+1
        ldy sd_y
        lda (ptr),y                ; L: copied
        iny
        sta DBUF,x
        inx
        sta dl
sd_c:   clc                        ; (opcode: clc, or sec mirrored) the RAW
sd_r0:  jmp sd_r1                  ; adds' carry in; (low byte patched: RAW 8
                                   ; - m) line 0
sd_end: rts
sd_y:   .byte 0                    ; Y, while Y indexes SPATN
dlast:  .byte $FF                  ; the entry DBUF holds ($FF: none yet), as
dmir:   .byte 0                    ; drawn mirrored or not,
dal:    .byte 0                    ; at al
dsg:    .byte 0                    ; the mir the adds' opcodes are for

        .code
        .segment "DTAB"
; DTH, DL4: a nibble's signed value, -8 .. 7, as a byte, laid out so spdec's
; adc operands take the stream byte as their low byte.  DTH, a page, by the
; whole byte: the high nibble's value, that nibble stored rotated (shipgen:
; its sign bit lowest, so the byte's bit 4).  DL4, 32 bytes opening a page,
; by the low nibble with that sign bit: the low nibble's value, less one when
; the sign is set (the first add's carry out, into the second).
DTH:    .repeat 256, b
        .byte <(((((b >> 4) & 1) << 3 | (b >> 5)) ^ 8) - 8)
        .endrepeat
DL4:    .repeat 32, b
        .byte <(((b & 15) ^ 8) - 8 - (b >> 4))
        .endrepeat
        .assert <DTH = 0 && <DL4 = 0, error, "DTH, DL4 open pages: spdec patches a byte, a nibble in as the low byte"
; shipspan.inc's tables follow in this segment, which is left current for
; it: LIM, SPATN, SPATO, SPATON, SPATF, SNEG, EYS, EXB, SHDE, SHDO, ELO,
; EHI, and after its SPANS segment KTN, BYN.

DBUF    = $2F00                    ; main RAM: the page below screen 0 ($3000),
                                   ; above LAND's end (land.s asserts <= $2F00);
                                   ; entry dlast's lines, in the order the
                                   ; walker reads them (under 256 bytes)
