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
        .pushseg
        .segment "HIB"
KTN:    .res 48                    ; (shtab's) by boundary w: the mask of the
BYN:    .res 48                    ; pixels before w in its byte, the byte's
LIM:    .res 48                    ; offset, the next byte's first pixel
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
@c:     lda byt                    ; TOPS[c] up to the box's top if higher
        cmp (sptr),y
        bcs :+
        sta (sptr),y
:       lda byb                    ; BOTS[c] down to its bottom if lower
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
        lda GSHK
        cmp dk
        bne @r
        lda GSHP
        cmp dpi
        bne @r
        lda al
        cmp dal
        beq @d
@r:     lda GSHK
        sta dk
        lda GSHP
        sta dpi
        lda al
        sta dal
        jsr rast
@d:     lda GSHY                   ; the box
        clc
        adc OYT
        sta byt
        lda GSHY
        clc
        adc OYB
        sta byb
        lda GSHX
        clc
        adc OXL
        sta bxl
        lda GSHX
        clc
        adc OXR
        sta bxr
        lda #<DBUF                 ; dp = DBUF; its page into the reads
        sta dp
        lda #>DBUF
        jsr page
        lda GSHX                   ; sptr = line byt's byte in the column 5
        and #$FC                   ; left of the centre's: 8 (x >> 2) - 40, its
        asl a                      ; carry into the high byte
        ldx #0
        bcc :+
        inx
:       sec
        sbc #40
        bcs :+
        dex
:       sta st
        stx dpb                    ; (scratch: the column part's high byte)
        lda byt
        and #7
        ora st
        sta sptr
        lda byt                    ; high: scrb + 2 (byt >> 3) + the column's
        lsr a
        lsr a
        and #$FE
        clc
        adc scrb
        clc
        adc dpb
        sta sptr+1
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
        jmp lnx2

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
        sta dp
        jmp lnx2
psrb:   lda ptb
        sta sptr
        lda ptb+1
        sta sptr+1
        lda dpb
        sta dp
pstb:   jmp band
lnx2:   lda dp
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
@pt:    stx pi
        lda VQX,x                  ; px = ca X - sa Y, py = sa X + ca Y
        ldy ca
        jsr smul
        sta pxl
        sty pxh
        ldx pi
        lda VQY,x
        ldy sa
        jsr smul
        sta st
        lda pxl
        sec
        sbc st
        sta pxl
        tya
        sta st
        lda pxh
        sbc st
        sta pxh
        ldx pi
        lda VQX,x
        ldy sa
        jsr smul
        sta pyl
        sty pyh
        ldx pi
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
        ldx pi
        lda VQZ,x
        ldy sb
        jsr smul
        clc
        adc xrl
        sta xrl
        tya
        adc xrh
        sta xrh
        ldx pi                     ; Zr = cb Z - sb px8
        lda VQZ,x
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
        tya
        sta st
        lda zrh
        sbc st
        sta zrh
        ldx pi
        cpx #9
        bcs @nm
        lda zrl                    ; a vertex: T = (Zr TQ) >> 8; sy = (py - T
        ldy zrh                    ; + 128) >> 8, sx = (Xr + 128) >> 8
        jsr tq8
        ldx pi
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
        ldx pi
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
        lda #$10                   ; brightness: (4096 - py) >> 9 (before the
        sec                        ; sign and the less 5): the high byte less
        sbc pyh                    ; a borrow from the low (4096's is 0)
        ldy pyl
        beq :+
        sec
        sbc #1
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
        lda NBR,y                  ; + "negative x" - 5, at least 0
        sta st
        lda NNEG
        and BIT8,y
        beq :+
        inc st
:       lda st
        sec
        sbc #5
        bcs :+
        lda #0
:       clc
        adc FGRN,x                 ; green + brightness, at most 15
        cmp #16
        bcc :+
        lda #15
:       sta st
        lda FHUE,x                 ; the ramp's row
        asl a
        asl a
        asl a
        asl a
        ora st
        tay
        lda RAMPE,y
        sta FCE,x
        eor RAMPO,y
        sta FCX,x
        dex
        bpl @fc
        lda #0                     ; the faces shown, in face order, set up
        sta NFL                    ; (fset)
        sta fi
@fs:    ldx fi
        cpx #8
        bcc :+
        ldx #7
:       lda NVIS
        and BIT8,x
        beq @fn
        jsr fset                   ; (C set: a face of no height, skipped)
        bcs @fn
        inc NFL
@fn:    inc fi
        lda fi
        cmp #9
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
@fl:    cpx NFL
        bcs @scan
        stx fj2
        jsr fline
        ldx fj2
        inx
        bne @fl
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
:       ldx #0
        lda lx0
        sta lxs
@sc:    inc lxs
        lda lxs
        cmp lx1
        beq @sd
        clc
        adc #20
        tay
        lda LB,y
        cmp WF,x
        beq @sc
        inx                        ; a change of face at lxs
        sta WF,x
        lda lxs
        sta WB,x
        jmp @sc
@sd:    inx                        ; the end, lx1: X = n, the faces
        lda lx1
        sta WB,x
        stx wn
        ldy bh                     ; the open band's faces again?
        cpy #$FF
        beq @nb
        cpx PEND
        bne @nb
        ldy NPAT
        lda PATON,y
        sec
        sbc wn
        tay
        ldx #0
:       lda WF,x
        cmp PATF,y
        bne @nb
        iny
        inx
        cpx wn
        bne :-
        jmp @sl
@nb:    ldy bh                     ; no: close the open band (its L), open one
        cpy #$FF
        beq :+
        lda bln
        sta DBUF+1,y
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
        lda db                     ; the band's header: P (L when closed)
        sta bh
        tay
        txa
        sta DBUF,y
        iny
        iny
        sty db
        lda #0
        sta bln
@sl:    inc bln                    ; the line's slot: its n + 1 boundaries as
        lda db                     ; w = offset + 20 + al, the slot's last n + 1
        clc                        ; bytes
        adc #7
        sec
        sbc wn
        tay
        lda al                     ; (st: 20 + al)
        clc
        adc #20
        sta st
        ldx #0
:       lda WB,x
        clc
        adc st
        sta DBUF,y
        iny
        inx
        cpx wn
        bcc :-
        beq :-
        lda db
        clc
        adc #8
        sta db
        inc yc
        jmp @ln
@end:   ldy bh                     ; the last band's L; $FF ends DBUF
        cpy #$FF
        beq :+
        lda bln
        sta DBUF+1,y
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
        lda cy3,x
        ldy cy3+1,x
        sta cy3+1,x
        tya
        sta cy3,x
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
        lda #0
        sta EE,y
        sta EQ,y
        sta ER,y
        lda ED,y
        beq @x
        sta dvx
        stx ef
        sty ey
        lda edx
        bpl @p
        eor #$FF                   ; dx < 0: |dx| div dy = q', rem; q = -q' -
        clc                        ; (rem > 0), r = dy - rem (or 0)
        adc #1
        sta dvd
        jsr div8
        ldy ey
        sta ER,y
        lda dvd
        eor #$FF                   ; -q' - 1
        ldx ER,y
        bne :+
        clc
        adc #1                     ; (rem 0: -q')
        sta EQ,y
        jmp @r
:       sta EQ,y
        lda ED,y
        sec
        sbc ER,y
        sta ER,y
        jmp @r
@p:     sta dvd
        jsr div8
        ldy ey
        sta ER,y
        lda dvd
        sta EQ,y
@r:     ldx ef
        ldy ey
@x:     rts

; fline: face slot X's span on line yc into LB, if yc is among its lines
; (FAY .. FCY-1): its short edge first moved to b-c at b's line; the span
; between the two edges' x (empty if they meet); then both a line on.
; Clobbers A, X, Y.
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
        tay
        lda EX+EOFS,x
:       sta sxl
        sty sxr
        cmp sxr
        beq @st                    ; (no pixels)
        cmp lx0
        bpl :+
        sta lx0
:       cpy lx1
        bmi :+
        sty lx1
:       lda sxr                     ; LB + 20 + sxl .. 20 + sxr - 1: the face
        clc
        adc #20
        sta sxr
        lda sxl
        clc
        adc #20
        tay
        lda FID,x
:       sta LB,y
        iny
        cpy sxr
        bne :-
@st:    txa                        ; both edges a line on
        jsr estep
        txa
        clc
        adc #EOFS
        jsr estep
@x:     rts
; estep: edge slot A a line on: x += q, error += r; past dy, x + 1 and error
; - dy.  X kept; clobbers A, Y.
estep:  tay
        lda EX,y
        clc
        adc EQ,y
        sta EX,y
        lda EE,y
        clc
        adc ER,y
        cmp ED,y
        bcc :+
        sbc ED,y
        sta EE,y
        lda EX,y
        clc
        adc #1
        sta EX,y
        rts
:       sta EE,y
        rts

; smul: A:Y (low, high) = A times Y, signed 8 x 8: the unsigned product of the
; bytes, less 256 B where A < 0 and 256 A where B < 0.  X kept.
smul:   sta smA
        sty smB
        sty smB0
        lda #0
        ldy #8
        lsr smB
@m:     bcc :+
        clc
        adc smA
:       ror a
        ror smB
        dey
        bne @m
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
; then << 2, its top two bytes.  X kept; clobbers A, Y, tqa, tqb.
tq8:    sta tqa                    ; V, sign-extended to 24 bits
        sty tqa+1
        lda #0
        cpy #$80
        bcc :+
        lda #$FF
:       sta tqa+2
        ldy #2                     ; tqb = 8 V
:       lda tqa,y
        sta tqb,y
        dey
        bpl :-
        ldy #3
:       asl tqb
        rol tqb+1
        rol tqb+2
        dey
        bne :-
        jsr @add                   ; tqa = 9 V
        asl tqb                    ; tqb = 16 V
        rol tqb+1
        rol tqb+2
        jsr @add                   ; tqa = 25 V
        ldy #2                     ; << 2: 100 V
:       asl tqa
        rol tqa+1
        rol tqa+2
        dey
        bne :-
        lda tqa+1
        sta tql
        lda tqa+2
        sta tqh
        rts
@add:   clc
        lda tqa
        adc tqb
        sta tqa
        lda tqa+1
        adc tqb+1
        sta tqa+1
        lda tqa+2
        adc tqb+2
        sta tqa+2
        rts

; ---------------------------------------------------------------- state
dk:     .byte $FF                  ; the attitude DBUF holds ($FF: none)
        .segment "LOW2"            ; (scratch, uninitialised: low RAM)
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
pi:     .res 1                    ; xform's point and its sums
pxl:    .res 1
pxh:    .res 1
pyl:    .res 1
pyh:    .res 1
px8:    .res 1
xrl:    .res 1
xrh:    .res 1
zrl:    .res 1
zrh:    .res 1
tql:    .res 1
tqh:    .res 1
SXV:    .res 9                     ; the vertices' pixel offsets
SYV:    .res 9
NVIS:   .res 1                    ; normals: shown, "negative x" (bit f)
NNEG:   .res 1
NBR:    .res 8                     ; (4096 - py) >> 9
NFL:    .res 1                    ; the faces set up
fi:     .res 1
fj2:    .res 1
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
sxl:     .res 1
sxr:     .res 1
yc:     .res 1                    ; the line
YLO:    .res 1
YHI:    .res 1
lx0:    .res 1                    ; its extent
lx1:    .res 1
lxs:    .res 1
tqa:    .res 3                     ; tq8's
tqb:    .res 3
smA:    .res 1                     ; smul's
smB:    .res 1
smB0:   .res 1
        .segment "LOWD"            ; (scratch: page $0D)
wn:     .res 1
WB:     .res 8                     ; its boundaries and faces
WF:     .res 8
db:     .res 1                    ; DBUF's next byte
bh:     .res 1                    ; the open band's header ($FF: none)
bln:    .res 1                    ; its lines
NPAT:   .res 1                    ; the patterns: the last made
PEND:   .res 1                    ; the open band's faces
PATTOP: .res 1                    ; PATF's next
PATN:   .res 16
PATON:  .res 16
PATF:   .res 96
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
