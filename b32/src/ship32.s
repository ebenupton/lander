; ============================================================================
; ship32.s -- the 32K build's ship (.included by land.s): Lander's ship drawn
; at the game's attitude, rasterised from the model whenever the attitude (or
; the centre's pixel in its byte) changes, as b32/tools/ship32.py's model
; does, into DBUF in the form src/shipspan.s's span walker draws, which then
; draws it (every frame) exactly as src/shipspan.s does an unmirrored stored
; orientation.
;
; Entry: ship (land.s's main loop, while GSHV is set): shipdraw, then this
; screen's column records widened over the ship's box.  In: GSHK, GSHP, GSHX,
; GSHY (the game's: direction 0..31, pitch 0..12, centre x, y), scrb, back.
;
; rast (b32/tools/ship32.py's docstring has the arithmetic):
;   - the 17 points (vertices 0..8, the faces' normals 9..16) pitched and
;     turned (xform): each vertex's pixel offset (SXV, SYV), each normal's
;     shown and "negative x" bits and its pitched y (the brightness);
;   - FCE, FCX: each face's dither for this attitude (RAMPE, RAMPO by its
;     hue's ramp and green + brightness);
;   - each shown face (in face order) set up as tri() steps it (FST: its
;     sorted corners, the long edge and the short one's x by floor steps),
;     then line by line: the faces covering the line fill LB with their
;     numbers, later over earlier; LB read back as boundaries and faces; a
;     line whose faces differ from the line before's starts a band (a new
;     pattern: PATN, PATON, PATF); its boundaries w (pixels from the column 5
;     left of the centre's: offset + 20 + al) into its DBUF slot;
;   - the box's offsets (OYT, OYB, OXL, OXR).
; ============================================================================

        .include "ship32.inc"
        .pushseg                   ; (shtab's) by boundary w: the mask of the
        .segment "LOWD"            ; pixels before w in its byte, the byte's
KTN:    .res 48                    ; offset, the next byte's first pixel
        .segment "SG0"             ; (b32.cfg's packing)
BYN:    .res 48
        .segment "SG1"
LIM:    .res 48
        .popseg

; zero page: the walker's (src/shipb.s's names, LAND's spare $8D-$9F and TRL;
; all dead when the ship is drawn)
c0      = $8D                      ; c0+j, j 1..6: slot j's dither for the pass
x0      = $93                      ; x0+j: its even ^ odd
sptr    = $9A                      ; the line's screen byte
dp      = $9C                      ; the line's bytes in DBUF
lim     = $9E                      ; LIM's for the last boundary
bl      = $9F                      ; lines left in the pass
st      = TRL                      ; scratch
al      = TRL+1                    ; shx & 3
dpb     = TRL+4                    ; pass B's first line's DBUF slot
pm      = TRL+9                    ; $FF if pass A's lines are odd
nb      = TRL+12                   ; pass B's lines ($80: none)
ptb     = TRL+14                   ; pass B's first line's screen byte
        .assert ptb+2 <= TRL+24, error, "the walker's names in TRL, TRB"

; ---------------------------------------------------------------- ship
; ship: draw the ship (shipdraw), then widen this screen's TOPS, BOTS over its
; box (src/shipb.s's).  Clobbers A, X, Y, the walker's zero page.
ship:   jsr shipdraw
        ldx back                   ; sptr = this screen's TOPS, dq its BOTS
        ldy sidx,x
        lda setTl,y
        sta sptr
        lda setTh,y
        sta sptr+1
        lda setBl,y
        sta dp
        lda setBh,y
        sta dp+1
        lda bxr                    ; columns bxl / 4 .. bxr / 4
        lsr a
        lsr a
        sta st
        lda bxl
        lsr a
        lsr a
        tay
        ldx byb                    ; (X: byb through the loop)
@c:     lda byt                    ; TOPS[c] up to the box's top if higher
        cmp (sptr),y
        bcs :+
        sta (sptr),y
:       txa                        ; BOTS[c] down to its bottom if lower
        cmp (dp),y
        bcc :+
        sta (dp),y
:       cpy st
        iny
        bcc @c
        rts

; ---------------------------------------------------------------- shipdraw
; shipdraw: the ship at GSHK, GSHP centred at (GSHX, GSHY) on screen scrb:
; DBUF remade (rast) when the attitude or the centre's pixel in its byte has
; changed, the box set, then the walker from DBUF's first band.  Out: bxl,
; bxr, byt, byb.
shipdraw:
        lda GSHX
        and #3
        sta al
        ldx GSHK                   ; (A = al) DBUF's unless al, GSHK, GSHP
        ldy GSHP                   ; differ from dal, dk, dpi
        cmp dal
        bne @r
        cpx dk
        bne @r
        cpy dpi
        beq @d
@r:     sta dal
        stx dk
        sty dpi
        jsr rast
@d:     ldx #1                     ; the box: bxr, bxl = GSHX + OXR, OXL; byb,
@bx:    lda GSHX                   ; byt = GSHY + OYB, OYT
        clc
        adc OXL,x
        sta bxl,x
        lda GSHY
        clc
        adc OYT,x
        sta byt,x
        dex
        bpl @bx
        .assert bxr = bxl+1 && byb = byt+1 && OXR = OXL+1 && OYB = OYT+1, error, "shipdraw: the box's pairs adjacent"
        lda #<DBUF                 ; dp = DBUF; its page into the reads
        sta dp
        lda #>DBUF
        jsr page
        lda byt                    ; high: scrb + 2 (byt >> 3) + the column's
        lsr a
        lsr a
        and #$FE
        clc
        adc scrb
        sta sptr+1
        lda GSHX                   ; sptr = line byt's byte in the column 5
        and #$FC                   ; left of the centre's: 8 (x >> 2) - 40, its
        asl a                      ; carry and borrow into the high byte
        bcc :+
        inc sptr+1
:       sec
        sbc #40
        bcs :+
        dec sptr+1
:       sta st
        lda byt
        and #7
        ora st
        sta sptr
        ; falls into band

; ---------------------------------------------------------------- the walker
; src/shipspan.s's, unmirrored: see there.  band: the band at dp (its P, L),
; or at $FF return.
band:   ldy #1
        lda (dp),y                 ; L
        sta bl
        dey
        lda (dp),y                 ; P, or $FF
        bpl :+
        rts
:       tay
        ldx PATN,y                 ; n
        lda dp
        clc
        adc #2
        sta dp
        adc #8
        sta dpb
        txa
        eor #7
        sta lk+1                   ; the first read's slot byte, 7 - n
        lda PNL,x
        sta lj+1
        lda PNH,x
        sta lj+2
        lda SGL,x
        sta ij+1
        lda SGH,x
        sta ij+2
        lda FLL,x
        sta fj+1
        lda FLH,x
        sta fj+2
        lda CNL,x
        sta bcj+1
        lda CNH,x
        sta bcj+2
        lda sptr+1                 ; ptb = the line after sptr's
        sta ptb+1
        ldx sptr
        inx
        txa
        and #7
        bne :+
        txa
        sec
        sbc #8
        tax
        inc ptb+1
        inc ptb+1
:       stx ptb
        lda bl                     ; the passes: nb = L >> 1, bl A's
        lsr a
        sta nb
        bcc @ev
        adc #0
        sta bl
        lda nb
        bne @cl
        lda #$80
        sta nb
        bne @cl
@ev:    sta bl                     ; L even: sptr, ptb and dp, dpb swapped
        lda sptr
        ldx ptb
        stx sptr
        sta ptb
        lda sptr+1
        ldx ptb+1
        stx sptr+1
        sta ptb+1
        lda dp
        ldx dpb
        stx dp
        sta dpb
@cl:    lda sptr                   ; pm = $FF if pass A's lines are odd
        and #1
        beq :+
        lda #$FF
:       sta pm
        lda PATON,y                ; Y: the pattern's end in PATF
        tay
bcj:    jmp cn1                    ; (patched: cn_(7-n))

page:   sta dp+1                   ; A, DBUF's page, into the reads
        .repeat 6, j
        sta .ident(.sprintf("rd%d", j + 1))+2
        .endrepeat
        sta in+2
        rts

.macro CS base, j
        ldx base,y
        lda FCX,x
        sta x0+j
        and pm
        eor FCE,x
        sta c0+j
.endmacro
cn1:    CS PATF-6, 1
cn2:    CS PATF-5, 2
cn3:    CS PATF-4, 3
cn4:    CS PATF-3, 4
cn5:    CS PATF-2, 5
cn6:    CS PATF-1, 6
        lda dp
        clc
        jmp line

.macro PC j
        sta .ident(.sprintf("rd%d", j))+1
        adc #1
.endmacro
pn1:    PC 1
pn2:    PC 2
pn3:    PC 3
pn4:    PC 4
pn5:    PC 5
pn6:    sta rd6+1
in:     ldx $FFFF                  ; (operand: the line's first read)
        lda LIM,x
        sta lim
        ldy BYN,x
        lda (sptr),y
ij:     jmp $FFFF                  ; (operand: seg_(7-n))

.macro SEG j
        .local fl, fd
.ident(.sprintf("seg%d", j)):
        eor c0+j
        and KTN,x
        eor c0+j
.ident(.sprintf("rd%d", j)):
        ldx $FFFF
        cpx lim
        bcc .ident(.sprintf("seg%d", j + 1))
        sta (sptr),y
        lda LIM,x
        sta lim
        tya
        adc #7
        cmp BYN,x
        bcs fd
fl:     tay
        lda c0+j
        sta (sptr),y
        tya
        adc #8
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
seg7:   eor (sptr),y
        and KTN,x
        eor (sptr),y
        sta (sptr),y
        lda sptr                   ; the pass's next line, y + 2
        clc
        adc #2
        sta sptr
        and #6
        beq slrow
lnx:    lda dp
        clc
        adc #16
        sta dp
        dec bl
        bne line
        lda nb
        beq pstb
        bmi psrb
        sta bl
        lda #0
        sta nb
fj:     jmp fl1                    ; (patched: fl_(7-n))
psrb:   lda ptb
        sta sptr
        lda ptb+1
        sta sptr+1
        lda dpb
        sta dp
pstb:   jmp band
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
        lda ptb
        sta sptr
        lda ptb+1
        sta sptr+1
        lda dpb
        sta dp                     ; (A = dp: into line)
        clc
line:
lk:     adc #0                     ; (operand: 7 - n)
        sta in+1
        adc #1
lj:     jmp pn1                    ; (patched: pn_(7-n))
slrow:   lda sptr
        sec
        sbc #8
        sta sptr
        inc sptr+1
        inc sptr+1
        jmp lnx
PNL:    .byte 0, <pn6, <pn5, <pn4, <pn3, <pn2, <pn1
CNL:    .byte 0, <cn6, <cn5, <cn4, <cn3, <cn2, <cn1
SGL:    .byte 0, <seg6, <seg5, <seg4, <seg3, <seg2, <seg1
SGH:    .byte 0, >seg6, >seg5, >seg4, >seg3, >seg2, >seg1
FLL:    .byte 0, <fl6, <fl5, <fl4, <fl3, <fl2, <fl1
PNH:    .byte 0, >pn6, >pn5, >pn4, >pn3, >pn2, >pn1
CNH:    .byte 0, >cn6, >cn5, >cn4, >cn3, >cn2, >cn1
FLH:    .byte 0, >fl6, >fl5, >fl4, >fl3, >fl2, >fl1

; ---------------------------------------------------------------- rast
; rast: DBUF, PATN, PATON, PATF, FCE, FCX and the box's offsets for GSHK,
; GSHP and al (the module's header).  Clobbers A, X, Y, the scratch below.
rast:   ldy GSHP                   ; the angles
        lda PCOS,y
        sta ca
        lda PSIN,y
        sta sa
        lda GSHK
        tay
        lda SINT,y
        sta sb
        tya
        clc
        adc #8
        and #31
        tay
        lda SINT,y
        sta cb
        lda #0
        sta NVIS
        sta NNEG
        ldx #16                    ; the 17 points, 16 down to 0
@pt:    lda VQX,x                  ; px = ca X - sa Y, py = sa X + ca Y
        ldy ca                     ; (X: the point throughout; smul, tq8
        jsr smul                   ; keep X)
        sta pxl
        sty pxh
        lda VQY,x
        ldy sa
        jsr smul
        sta st
        lda pxl
        sec
        sbc st
        sta pxl
        sty st
        lda pxh
        sbc st
        sta pxh
        lda VQX,x
        ldy sa
        jsr smul
        sta pyl
        sty pyh
        lda VQY,x
        ldy ca
        jsr smul
        clc
        adc pyl
        sta pyl
        tya
        adc pyh
        sta pyh
        lda pxl                    ; px8 = (px + 32) >> 6: ((px + 32) << 2)'s
        clc                        ; high byte
        adc #32
        sta pxl
        lda pxh
        adc #0
        asl pxl
        rol a
        asl pxl
        rol a
        sta px8
        ldy cb                     ; Xr = cb px8 + sb Z
        jsr smul
        sta xrl
        sty xrh
        lda VQZ,x
        ldy sb
        jsr smul
        clc
        adc xrl
        sta xrl
        tya
        adc xrh
        sta xrh
        lda VQZ,x                  ; Zr = cb Z - sb px8
        ldy cb
        jsr smul
        sta zrl
        sty zrh
        lda px8
        ldy sb
        jsr smul
        sta st
        lda zrl
        sec
        sbc st
        sta zrl
        sty st
        lda zrh
        sbc st
        sta zrh
        cpx #9
        bcs @nm
        lda zrl                    ; a vertex: T = (Zr TQ) >> 8; sy = (py - T
        ldy zrh                    ; + 128) >> 8, sx = (Xr + 128) >> 8
        jsr tq8
        lda pyl
        sec
        sbc tql
        tay
        lda pyh
        sbc tqh
        cpy #$80                   ; (+ 128: the low byte's carry)
        adc #0
        sta SYV,x
        lda xrl
        cmp #$80
        lda xrh
        adc #0
        sta SXV,x
        jmp @nx
@nm:    lda pyl                    ; a normal: shown if (py TQ >> 8) + Zr < 0
        ldy pyh
        jsr tq8
        lda tql
        clc
        adc zrl
        lda tqh
        adc zrh                    ; (the sum's sign: no overflow here)
        asl a                      ; (its sign into C; bit f of NVIS, NNEG:
        rol NVIS                   ; normal f, point 9 + f, rolled in from
        lda xrh                    ; point 16 down)
        asl a                      ; "negative x": Xr < 0
        rol NNEG
        lda #0                     ; brightness: (4096 - py) >> 9 (before the
        cmp pyl                    ; sign and the less 5): the high byte less
        lda #$10                   ; a borrow from the low (4096's is 0; C =
        sbc pyh                    ; 1, no borrow, only if pyl = 0)
:       lsr a
        sta NBR-9,x
@nx:    dex
        bmi :+
        jmp @pt
:       ldx #8                     ; FCE, FCX: each face's dither (face 8 as 7)
@fc:    txa
        cmp #8
        bcc :+
        lda #7
:       tay
:       lda NNEG                   ; NBR + "negative x" - 5, at least 0
        and BIT8,y
        cmp #1                     ; (C: "negative x")
        lda NBR,y
        adc #<-5                   ; (C set unless below 0: NBR <= 127)
        bcs :+
        lda #0
:       clc
        adc FGRN,x                 ; green + brightness, at most 15
        cmp #16
        bcc :+
        lda #15
:       ora FHUE,x                 ; the ramp's row (FHUE: 16 x the ramp)
        tay
        lda RAMPE,y
        sta FCE,x
        eor RAMPO,y
        sta FCX,x
        dex
        bpl @fc
        lda #0                     ; the faces shown, in face order, set up
        sta NFL                    ; (fset)
        tax
@fs:    stx fi
        cpx #8
        bcc :+
        ldx #7
:       lda NVIS
        and BIT8,x
        beq @fn
        jsr fset                   ; (C set: a face of no height, skipped)
        bcs @fn
        inc NFL
@fn:    ldx fi
        inx
        cpx #9
        bne @fs
        lda #64                    ; YLO .. YHI-1: the faces' lines (64, -64:
        sta YLO                    ; the coordinates are within -20..20, so a
        sta OXL                    ; signed compare with these cannot overflow)
        lda #<-64
        sta YHI
        sta OXR
        ldx NFL
        dex
        bmi @ny
@yr:    lda FAY,x
        cmp YLO
        bpl :+
        sta YLO
:       lda FCY,x
        cmp YHI
        bmi :+
        sta YHI
:       dex
        bpl @yr
@ny:    lda #0                     ; DBUF: no band yet
        sta db
        sta PATTOP
        lda #$FF
        sta bh
        sta NPAT
        lda al                     ; st: 20 + al, the slots' offset (rast's
        clc                        ; lines: al and st not touched again)
        adc #20
        sta st
        lda YLO
        sta yc
        sta OYT
@ln:    lda yc                     ; each line
        cmp YHI
        bne :+
        jmp @end
:       lda #48                    ; the line's extent: lx0 .. lx1-1 (48, -48:
        sta lx0                    ; their difference too stays a byte)
        lda #<-48
        sta lx1
        ldx #0                     ; each face in order: its span, a step on
        cpx NFL                    ; (X = 0: none set up)
        beq @scan
@fl:    jsr fline                  ; (fline keeps X: ecore restores it)
        inx
        cpx NFL
        bcc @fl
@scan:  lda lx0                    ; no pixels: before the first band, the box
        cmp lx1                    ; starts lower; after, the ship has ended
        bmi @px
        ldy bh
        cpy #$FF
        bne @en
        inc OYT
        inc yc
        jmp @ln
@en:    lda yc
        sta YHI
        jmp @end
@px:    sta WB                     ; LB read back: boundaries into WB, faces
        clc                        ; into WF
        adc #20
        tay
        lda LB,y
        sta WF
        lda lx0
        cmp OXL
        bpl :+
        sta OXL
:       lda lx1
        cmp OXR
        bmi :+
        sta OXR
:       clc                        ; (A = lx1 on both paths here) the end,
        adc #20                    ; lx1 + 20, into @se's compare
        sta @se+1
        ldx #0                     ; (Y = lx0 + 20 still, from @px)
@sc:    iny                        ; Y = lxs + 20
@se:    cpy #$00                   ; (lx1 + 20: patched above)
        beq @sd
        lda LB,y
        cmp WF,x
        beq @sc
        inx                        ; a change of face at lxs
        sta WF,x
        tya                        ; lxs = Y - 20
        sec
        sbc #20
        sta WB,x
        jmp @sc
@sd:    inx                        ; the end, lx1: X = n, the faces
        lda lx1
        sta WB,x
        stx wn
        ldy bh                     ; the open band's faces again?
        iny                        ; ($FF: none)
        beq @nb
        cpx PEND
        bne @nb
        ldy NPAT                   ; X = wn still (stx wn, cpx PEND): compare
        lda PATON,y                ; from the end down, Y = the pattern's end
        tay
:       lda WF-1,x
        cmp PATF-1,y
        bne @nb
        dey
        dex
        bne :-
        jmp @sl
@nb:    ldy bh                     ; no: close the open band (its L), open one
        iny                        ; ($FF: none)
        beq :+
        lda bln
        sta DBUF,y
:       inc NPAT                   ; pattern NPAT: WF's faces at PATF from
        ldx NPAT                   ; PATTOP
        lda wn
        sta PATN,x
        sta PEND
        ldy PATTOP
        ldx #0
:       lda WF,x
        sta PATF,y
        iny
        inx
        cpx wn
        bne :-
        sty PATTOP
        ldx NPAT
        tya
        sta PATON,x
        ldy db                     ; the band's header: P (L when closed)
        sty bh
        txa
        sta DBUF,y
        iny
        iny
        sty db
        lda #0
        sta bln
@sl:    inc bln                    ; the line's slot: its n + 1 boundaries as
        lda db                     ; w = offset + 20 + al, the slot's last n + 1
        clc                        ; bytes, the last first: db + 7 down
        adc #8                     ; (db moved on to the next slot first)
        sta db
        tay
        dey
        ldx wn
:       lda WB,x
        clc
        adc st                     ; (st = 20 + al: set at @ny)
        sta DBUF,y
        dey
        dex
        bpl :-
        inc yc
        jmp @ln
@end:   ldy bh                     ; the last band's L; $FF ends DBUF
        iny                        ; (bh $FF: none)
        beq :+
        lda bln
        sta DBUF,y
:       ldy db
        lda #$FF
        sta DBUF,y
        lda YHI                    ; the box: lines OYT .. YHI-1, pixels OXL
        sec                        ; .. OXR-1
        sbc #1
        sta OYB
        dec OXR
        rts

; fset: face fi (its normal's bit tested by the caller) set up for tri() as
; the NFL'th: its corners sorted by y, stably (a, b, c), the long edge a-c and
; the short a-b at their tops; C set (nothing kept) if a and c share a line.
; Clobbers A, X, Y.
fset:   ldx fi
        ldy FV0,x                  ; the corners' (x, y) into cx3, cy3
        lda SXV,y
        sta cx3
        lda SYV,y
        sta cy3
        ldy FV1,x
        lda SXV,y
        sta cx3+1
        lda SYV,y
        sta cy3+1
        ldy FV2,x
        lda SXV,y
        sta cx3+2
        lda SYV,y
        sta cy3+2
        ldx #0                     ; a stable sort by y: a swap on a strict less
        jsr csw                    ; (0, 1), (1, 2), (0, 1)
        inx
        jsr csw
        dex
        jsr csw
        lda cy3                    ; a, c on one line: nothing
        cmp cy3+2
        bne :+
        sec
        rts
:       ldx NFL
        lda fi
        sta FID,x
        lda cy3
        sta FAY,x
        lda cy3+1
        sta FBY,x
        lda cy3+2
        sta FCY,x
        lda cx3+1
        sta FBX,x
        lda cx3+2
        sta FCX3,x
        txa                        ; the long edge a-c
        tay
        lda cx3
        sta EX,y
        lda cx3+2
        sec
        sbc cx3
        sta edx
        lda cy3+2
        sec
        sbc cy3
        jsr ecore
        txa                        ; the short a-b
        clc
        adc #EOFS
        tay
        lda cx3
        sta EX,y
        lda cx3+1
        sec
        sbc cx3
        sta edx
        lda cy3+1
        sec
        sbc cy3
        jsr ecore
        clc
        rts
csw:    lda cy3+1,x                ; corners X and X + 1 swapped if X + 1's y
        cmp cy3,x                  ; is the less (signed: small values)
        bpl @x
        ldy cy3,x                  ; (A: cy3+1,x still)
        sta cy3,x
        tya
        sta cy3+1,x
        lda cx3,x
        ldy cx3+1,x
        sta cx3+1,x
        tya
        sta cx3,x
@x:     rts
; ecore: edge slot Y (EX set: its x at its top line) for dx = edx, dy = A:
; the error 0, ED = dy, EQ, ER = floor(dx / dy), dx - EQ dy (dy 0: no steps).
; X, Y kept.  Clobbers A, dvx, dvd.
ecore:  sta ED,y
        beq @z                     ; dy 0 (Z: every caller's SBC just before)
        sta dvx
        lda #0                     ; (EQ, ER: stored below on every path)
        sta EE,y
        stx ef
        sty ey
        lda edx
        bpl @p
        eor #$FF                   ; dx < 0: |dx| div dy = q', rem; q = -q' -
        clc                        ; (rem > 0), r = dy - rem (or 0)
        adc #1
@p:     sta dvd                    ; (dx >= 0: q, rem)
        jsr div8
        ldy ey
        sta ER,y
        lda dvd
        bit edx                    ; dx's sign again (div8 keeps edx)
        bpl @q
        eor #$FF                   ; -q' - 1
        ldx ER,y
        beq :+
        sta EQ,y
        lda ED,y
        sec
        sbc ER,y                   ; (rem < dy: no borrow, C set)
        sta ER,y
        bcs @r
:       clc
        adc #1                     ; (rem 0: -q')
@q:     sta EQ,y
@r:     ldx ef
        ldy ey
        rts
@z:     sta EE,y                   ; dy 0: A = 0; no steps
        sta EQ,y
        sta ER,y
@x:     rts

; fline: face slot X's span on line yc into LB, if yc is among its lines
; (FAY .. FCY-1): its short edge first moved to b-c at b's line; the span
; between the two edges' x (empty if they meet); then both a line on.
; Keeps X (rast relies on it).  Clobbers A, Y.
fline:  lda yc
        cmp FAY,x
        bmi @x                     ; above its top
        cmp FCY,x
        bpl @x                     ; at or below its bottom
        cmp FBY,x                  ; at b's line: the short edge b-c
        bne :+
        txa
        clc
        adc #EOFS
        tay
        lda FBX,x
        sta EX,y
        lda FCX3,x
        sec
        sbc FBX,x
        sta edx
        lda FCY,x
        sec
        sbc FBY,x
        jsr ecore
:       lda EX,x                   ; sxl (A), sxr (Y): the two edges' x in order
        ldy EX+EOFS,x
        cmp EX+EOFS,x
        bmi :+
        beq @st                    ; (no pixels: the CMP's Z)
        tay
        lda EX+EOFS,x
:       sta sxl
        cmp lx0
        bpl :+
        sta lx0
:       cpy lx1
        bmi :+
        sty lx1
:       tya                        ; LB + 20 + sxl .. 20 + sxr - 1: the face
        clc
        adc #20
        sta @sr+1                  ; (the loop's end)
        lda sxl
        clc
        adc #20
        tay
        lda FID,x
:       sta LB,y
        iny
@sr:    cpy #0                     ; operand: 20 + sxr
        bne :-
@st:    txa                        ; both edges a line on
        jsr estep
        txa
        clc
        adc #EOFS
        jmp estep                  ; (tail call: its RTS is fline's)
@x:     rts
; estep: edge slot A a line on: x += q, error += r; past dy, x + 1 and error
; - dy.  X kept; clobbers A, Y.
estep:  tay
        lda EE,y                   ; the error first: C = the step past dy
        clc
        adc ER,y
        cmp ED,y
        bcc :+                     ; (C clear: no step)
        sbc ED,y                   ; (C set, A >= ED: stays set, the x + 1)
:       sta EE,y
        lda EX,y                   ; x += q + the step
        adc EQ,y
        sta EX,y
        rts

; smul: A:Y (low, high) = A times Y, signed 8 x 8: the unsigned product of the
; bytes, less 256 B where A < 0 and 256 A where B < 0.  X kept.
smul:   sta smA
        sty smB0
        tya                        ; smB = B >> 1, C its bit 0
        lsr a
        sta smB
        lda #0                     ; (C kept)
        bcc @m1                    ; bit 0: 0 + smA has no carry, so LSR
        lda smA                    ; is the ROR
@m1:    lsr a
        ror smB
        bcc @m2                    ; bits 1..7, unrolled
        clc
        adc smA
@m2:    ror a
        ror smB
        bcc @m3
        clc
        adc smA
@m3:    ror a
        ror smB
        bcc :+
        clc
        adc smA
:       ror a
        ror smB
        bcc @m5
        clc
        adc smA
@m5:    ror a
        ror smB
        bcc @m6
        clc
        adc smA
@m6:    ror a
        ror smB
        bcc @m7
        clc
        adc smA
@m7:    ror a
        ror smB
        bcc @m8
        clc
        adc smA
@m8:    ror a
        ror smB
        bit smA                    ; (A high, smB low)
        bpl :+
        sec
        sbc smB0
:       bit smB0
        bpl :+
        sec
        sbc smA
:       tay
        lda smB
        rts

BIT8:   .byte 1, 2, 4, 8, 16, 32, 64, 128

; tq8: tql, tqh = (V TQ) >> 8, V = A:Y (low, high) signed, TQ = 100: 25 V,
; then << 2, its top two bytes.  X, Y kept; clobbers A, tqa, tqb.
tq8:    sta tqa                    ; V, sign-extended to 24 bits; tqb = V
        sta tqb
        sty tqa+1
        sty tqb+1
        lda #0
        cpy #$80
        bcc :+
        lda #$FF
:       sta tqa+2
:       asl tqb                    ; tqb = 8 V (its high byte in A)
        rol tqb+1
        rol a
:       asl tqb                    ; (the : lines keep the file's count)
        rol tqb+1
        rol a
:       asl tqb
        rol tqb+1
        rol a
        sta tqb+2
        clc                        ; tqa = 9 V
        lda tqa
        adc tqb
        sta tqa
        lda tqa+1
        adc tqb+1
        sta tqa+1
        lda tqa+2
        adc tqb+2
        sta tqa+2
        asl tqb                    ; tqb = 16 V
        rol tqb+1
        rol tqb+2
        clc                        ; 25 V: tqa, tqa+1, A
        lda tqa
        adc tqb
        sta tqa
        lda tqa+1
        adc tqb+1
        sta tqa+1
        lda tqa+2
        adc tqb+2
        asl tqa                    ; << 2: 100 V
        rol tqa+1
        rol a
        asl tqa
        rol tqa+1
        rol a
        sta tqh
        lda tqa+1
        sta tql
        rts

; ---------------------------------------------------------------- state
dk:     .byte $FF                  ; the attitude DBUF holds ($FF: none)
        .segment "P2B"             ; (scratch, uninitialised: low RAM)
dpi:    .res 1
dal:    .res 1
bxl:    .res 1                    ; the box (inclusive)
bxr:    .res 1
byt:    .res 1
byb:    .res 1
OYT:    .res 1                    ; its offsets from the centre
OYB:    .res 1
OXL:    .res 1
OXR:    .res 1
FCE:    .res 9                     ; faces' dithers: even line, even ^ odd
FCX:    .res 9
ca:     .res 1                    ; the angles' cosines, sines
sa:     .res 1
cb:     .res 1
sb:     .res 1
px8:    .res 1
tql:    .res 1
tqh:    .res 1
SXV:    .res 9                     ; the vertices' pixel offsets
SYV:    .res 9
NVIS:   .res 1                    ; normals: shown, "negative x" (bit f)
NNEG:   .res 1
NBR:    .res 8                     ; (4096 - py) >> 9
fi:     .res 1
cx3:    .res 3                     ; fset's corners
cy3:    .res 3
EOFS    = 9                        ; the edges' arrays: long edges by face slot
FID:    .res 9                     ; 0..8, short ones at + EOFS; face slot data
FAY:    .res 9
FBY:    .res 9
FCY:    .res 9
FBX:    .res 9
FCX3:   .res 9
EX:     .res 18
EE:     .res 18
EQ:     .res 18
ER:     .res 18
ED:     .res 18
ef:     .res 1
ey:     .res 1
edx:    .res 1
YLO:    .res 1
YHI:    .res 1
        .segment "SG0"             ; (scratch: b32.cfg's SG0, G1B, G1A, P1)
WB:     .res 8                     ; its boundaries and faces
bh:     .res 1                    ; the open band's header ($FF: none)
bln:    .res 1                    ; its lines
NPAT:   .res 1                    ; the patterns: the last made
PEND:   .res 1                    ; the open band's faces
PATTOP: .res 1                    ; PATF's next
        .segment "G1B"
PATN:   .res 16
        .segment "G1A"
PATON:  .res 16
        .segment "P1"
PATF:   .res 96
        .segment "G1B"
LB:     .res 48                    ; the line's pixels' faces, by offset + 20

; shtab: KTN, BYN, LIM + w for w 0..47 ($00, $88, $CC, $EE by w & 3; 8 (w
; >> 2); 4 ((w >> 2) + 1)).  Run once (init).  Clobbers A, X.
        .segment "BOOT"
shtab:  ldx #47
:       txa
        and #3
        tay
        lda ktv,y
        sta KTN,x
        txa
        and #$FC
        asl a
        sta BYN,x
        lsr a
        clc
        adc #4
        sta LIM,x
        dex
        bpl :-
        rts
ktv:    .byte $00, $88, $CC, $EE
