; ship.s: Lander's ship at the game's attitude, rasterised from the model
; whenever the attitude (or the centre's pixel in its byte) changes, and drawn
; every frame from the result.  b32/tools/ship32.py is the reference.
;
; rast: the model's 9 vertices and 8 face normals pitched and turned (8 x 8
; multiplies), each vertex's pixel offset, each face's visibility and shade,
; then the faces, later over earlier, a line at a time into LB (the face at
; each pixel).  Each line's boundaries go to DBUF in bands: a band is a run of
; lines with the same faces left to right (a pattern: PATN, PATON, PATF), its
; header P (the pattern) and L (its lines), then a slot of 8 boundaries a line.
;
; The walker draws a band's lines in two passes (alternate lines, so that a
; face's dither byte flips once a pass), each segment of a line masked into
; the screen up to its boundary, whole bytes stored between.  Its code is
; patched for the band's number of segments.

; ship: the ship drawn, then this screen's column records widened over its
; box.  In: GSHK, GSHP, GSHX, GSHY, scrb, back.  Clobbers A, X, Y, the overlay.
ship:   jsr shipdraw
        ldx back
        ldy sidx,x
        lda setTl,y
        sta sptr
        lda setTh,y
        sta sptr+1
        lda setBl,y
        sta dp
        lda setBh,y
        sta dp+1
        lda bxr                    ; columns bxl/4 .. bxr/4
        lsr a
        lsr a
        sta st
        lda bxl
        lsr a
        lsr a
        tay
        ldx byb
@c:     lda byt                    ; TOPS up, BOTS down, to the box
        cmp (sptr),y
        bcs :+
        sta (sptr),y
:       txa
        cmp (dp),y
        bcc :+
        sta (dp),y
:       cpy st
        iny
        bcc @c
        rts

; shipdraw: DBUF remade if the attitude or al (GSHX & 3) has changed, the
; box, then the walker.  Out: bxl, bxr, byt, byb.
shipdraw:
        lda GSHX
        and #3
        sta al
        ldx GSHK
        ldy GSHP
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
@d:     ldx #1                     ; the box from its offsets
@bx:    lda GSHX
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
        lda #<DBUF
        sta dp
        lda #>DBUF
        jsr page
        lda byt                    ; sptr: line byt's byte, the column 5
        lsr a                      ; left of the centre's
        lsr a
        lsr a
        asl a
        adc scrb
        sta sptr+1
        lda GSHX
        and #$FC
        asl a
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
; band: the band at dp, or $FF: done.  The walker patched for its n segments,
; its lines split into two passes (pass A from sptr, B from ptb).
band:   ldy #1
        lda (dp),y                 ; L
        sta bl
        dey
        lda (dp),y                 ; P
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
        sta lk+1
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
        lda sptr+1                 ; ptb: the line after sptr's
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
        lda bl                     ; the passes: nb lines in B, bl in A
        lsr a
        sta nb
        bcc @ev
        adc #0
        sta bl
        lda nb
        bne @cl
        lda #$80
        sta nb
        bne @cl                    ; (always)
@ev:    sta bl                     ; even: A starts a line on
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
@cl:    lda sptr                   ; pm: $FF if pass A's lines are odd
        and #1
        beq :+
        lda #$FF
:       sta pm
        lda PATON,y
        tay
bcj:    jmp cn1                    ; (patched: cn(7-n))

; page: DBUF's page into the walker's reads.
page:   sta dp+1
        .repeat 6, j
        sta .ident(.sprintf("rd%d", j + 1))+2
        .endrepeat
        sta in+2
        rts

; CS base, j: segment j's dither for the pass, and its flip.
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

; PC j: segment j's boundary read from the line's slot.
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
in:     ldx $FFFF                  ; (operand: the line's first boundary)
        lda LIM,x
        sta lim
        ldy BYN,x
        lda (sptr),y
ij:     jmp $FFFF                  ; (patched: seg(7-n))

; SEG j: segment j: its first byte masked in, whole bytes to its end.
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
seg7:   eor (sptr),y               ; the last byte, then the pass's next line
        and KTN,x
        eor (sptr),y
        sta (sptr),y
        lda sptr
        clc
        adc #2
        sta sptr
        and #6
        beq slrow
lnx:    lda dp                     ; (C clear)
        adc #16
        sta dp
        dec bl
        bne line
        lda nb                     ; the pass done: pass B, or the next band
        beq pstb
        bmi psrb
        sta bl
        lda #0
        sta nb
fj:     jmp fl1                    ; (patched: fl(7-n))
psrb:   lda ptb
        sta sptr
        lda ptb+1
        sta sptr+1
        lda dpb
        sta dp
pstb:   jmp band

; FLIP j: segment j's dither for the other pass.
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
        clc
line:
lk:     adc #0                     ; (operand: 7 - n)
        sta in+1
        adc #1
lj:     jmp pn1                    ; (patched: pn(7-n))
slrow:  lda sptr                   ; the next character row
        sec
        sbc #8
        sta sptr
        inc sptr+1
        inc sptr+1
        clc
        jmp lnx
        .pushseg
        .segment "TABLES"
        .include "ship32.inc"
PNL:    .byte 0, <pn6, <pn5, <pn4, <pn3, <pn2, <pn1   ; the walker's entries by n
CNL:    .byte 0, <cn6, <cn5, <cn4, <cn3, <cn2, <cn1
SGL:    .byte 0, <seg6, <seg5, <seg4, <seg3, <seg2, <seg1
SGH:    .byte 0, >seg6, >seg5, >seg4, >seg3, >seg2, >seg1
FLL:    .byte 0, <fl6, <fl5, <fl4, <fl3, <fl2, <fl1
PNH:    .byte 0, >pn6, >pn5, >pn4, >pn3, >pn2, >pn1
CNH:    .byte 0, >cn6, >cn5, >cn4, >cn3, >cn2, >cn1
FLH:    .byte 0, >fl6, >fl5, >fl4, >fl3, >fl2, >fl1
        .popseg

; rast: DBUF and the box's offsets for GSHK, GSHP and al.
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
        ldy #0                     ; the pitched points kept unless the pitch
        lda GSHP                   ; has changed (cmiss bit 7)
        cmp cpi
        beq :+
        dey
:       sty cmiss
        sta cpi
        ldx #16                    ; the points, 16 down to 0
@pt:    bit cmiss
        bpl @kp
        ldy TWIN,x                 ; a mirror twin made already: the same
        bmi @mk
        lda CPX8,y
        sta CPX8,x
        lda CPYL,y
        sta CPYL,x
        lda CPYH,y
        sta CPYH,x
@kp:    lda CPX8,x
        sta px8
        lda CPYL,x
        sta pyl
        lda CPYH,x
        sta pyh
        jmp @yw
@mk:    lda VQY,x                  ; pitched: px = ca X - sa Y, py = sa X +
        ldy sa                     ; ca Y
        jsr smul
        sta pxl
        sty pxh
        lda VQX,x
        ldy ca
        jsr smul
        sec
        sbc pxl
        sta pxl
        tya
        sbc pxh
        asl pxl                    ; px8 = (px + 32) >> 6
        rol a
        asl pxl
        rol a
        asl pxl
        adc #0
        sta px8
        sta CPX8,x
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
        sta CPYL,x
        tya
        adc pyh
        sta pyh
        sta CPYH,x
@yw:    ldy TWIN,x                 ; turned: Xr = cb px8 + sb Z, Zr = cb Z -
        bmi @ow                    ; sb px8; a twin's from its products
        lda PAL,y
        sec
        sbc PCL,y
        sta xrl
        lda PAH,y
        sbc PCH,y
        sta xrh
        lda PDL,y
        clc
        adc PBL,y
        sta zrl
        lda PDH,y
        adc PBH,y
        sta zrh
        lda #0
        sec
        sbc zrl
        sta zrl
        lda #0
        sbc zrh
        sta zrh
        jmp @xz
@ow:    lda px8                    ; its own, the products kept
        ldy cb
        jsr smul
        sta xrl
        sta PAL,x
        tya
        sta xrh
        sta PAH,x
        lda px8
        ldy sb
        jsr smul
        sta PBL,x
        tya
        sta PBH,x
        lda VQZ,x
        beq @z0
        ldy sb
        jsr smul
        sta PCL,x
        clc
        adc xrl
        sta xrl
        tya
        sta PCH,x
        adc xrh
        sta xrh
        lda VQZ,x
        ldy cb
        jsr smul
        sta PDL,x
        sec
        sbc PBL,x
        sta zrl
        tya
        sta PDH,x
        sbc PBH,x
        sta zrh
        jmp @xz
@z0:    lda #0                     ; Z 0: Zr = -PB
        sec
        sbc PBL,x
        sta zrl
        lda #0
        sbc PBH,x
        sta zrh
@xz:    cpx #9
        bcs @nm
        lda zrl                    ; a vertex: sy = (py - T + 128) >> 8, T =
        ldy zrh                    ; (Zr TQ) >> 8; sx = (Xr + 128) >> 8
        jsr tq8
        lda pyl
        sec
        sbc tql
        tay
        lda pyh
        sbc tqh
        cpy #$80
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
        adc zrh
        asl a
        rol NVIS
        lda xrh                    ; lit from the left: Xr < 0
        asl a
        rol NNEG
        lda #0                     ; the brightness: (4096 - py) >> 9
        cmp pyl
        lda #$10
        sbc pyh
        lsr a
        sta NBR-9,x
@nx:    dex
        bmi :+
        jmp @pt
:       ldx #8                     ; each face's dither (face 8 as 7)
@fc:    txa
        cmp #8
        bcc :+
        lda #7
:       tay
        lda NNEG                   ; the brightness + lit - 5, at least 0
        and BIT8,y
        cmp #1
        lda NBR,y
        adc #<-5
        bcs :+
        lda #0
:       clc
        adc FGRN,x                 ; + green, at most 15
        cmp #16
        bcc :+
        lda #15
:       ora FHUE,x                 ; the ramp
        tay
        lda RAMPE,y
        sta FCE,x
        eor RAMPO,y
        sta FCX,x
        dex
        bpl @fc
        lda #0                     ; the faces shown, set up
        sta NFL
        tax
@fs:    stx fi
        cpx #8
        bcc :+
        ldx #7
:       lda NVIS
        and BIT8,x
        beq @fn
        jsr fset
        bcs @fn
        inc NFL
@fn:    ldx fi
        inx
        cpx #9
        bne @fs
        lda #64                    ; their lines, YLO .. YHI-1
        sta YLO
        sta OXL
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
        lda al                     ; st: the slots' offset
        clc
        adc #20
        sta st
        lda YLO
        sta yc
        sta OYT
@ln:    lda yc                     ; each line
        cmp YHI
        bne :+
        jmp @end
:       lda #48                    ; its extent lx0 .. lx1-1
        sta lx0
        lda #<-48
        sta lx1
        ldx #0                     ; each face on it, in order
        cpx NFL
        beq @scan
@fl:    lda yc
        cmp FAY,x
        bmi @fz
        cmp FCY,x
        bpl @fz
        jsr fline
@fz:    inx
        cpx NFL
        bcc @fl
@scan:  lda lx0                    ; no pixels: before the ship, the box
        cmp lx1                    ; starts lower; after, it has ended
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
@px:    sta WB                     ; LB as boundaries (WB) and faces (WF)
        cmp OXL
        bpl :+
        sta OXL
:       clc
        adc #20
        tay
        lda lx1
        cmp OXR
        bmi :+
        sta OXR
:       clc
        adc #20
        sta @se+1
        lda LB,y
        sta WF
        ldx #0
@sc:    iny
@se:    cpy #$00                   ; (operand: lx1 + 20)
        beq @sd
        cmp LB,y
        beq @sc
        tya
        sec
        sbc #20
        inx
        sta WB,x
        lda LB,y
        sta WF,x
        jmp @sc
@sd:    inx
        lda lx1
        sta WB,x
        stx wn
        ldy bh                     ; the open band's faces again?
        iny
        beq @nb
        cpx PEND
        bne @nb
        ldy NPAT
        lda PATON,y
        tay
:       lda WF-1,x
        cmp PATF-1,y
        bne @nb
        dey
        dex
        bne :-
        jmp @sl
@nb:    ldy bh                     ; no: close it, open another
        iny
        beq :+
        lda bln
        sta DBUF,y
:       inc NPAT
        ldx NPAT
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
        ldy db
        sty bh
        txa
        sta DBUF,y
        iny
        iny
        sty db
        lda #0
        sta bln
@sl:    inc bln                    ; the line's slot: its boundaries + st,
        lda db                     ; last first
        clc
        adc #8
        sta db
        tay
        dey
        ldx wn
:       lda WB,x
        clc
        adc st
        sta DBUF,y
        dey
        dex
        bpl :-
        inc yc
        jmp @ln
@end:   ldy bh                     ; the last band's L; $FF ends DBUF
        iny
        beq :+
        lda bln
        sta DBUF,y
:       ldy db
        lda #$FF
        sta DBUF,y
        lda YHI                    ; the box
        sec
        sbc #1
        sta OYB
        dec OXR
        rts

; fset: face fi set up as the NFL'th: its corners sorted by y (a, b, c), the
; long edge a-c and the short a-b.  C set (nothing kept) if a and c share a
; line.  Clobbers A, X, Y.
fset:   ldx fi
        ldy FV0,x
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
        ldx #0                     ; a stable sort
        jsr csw
        inx
        jsr csw
        dex
        jsr csw
        lda cy3
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
        txa                        ; the long edge (slot NFL), then the short
        ldx #2                     ; (NFL + EOFS)
@ed:    tay
        lda cx3
        sta EX,y
        lda cx3,x
        sec
        sbc cx3
        sta edx
        lda cy3,x
        sec
        sbc cy3
        jsr ecore
        tya
        clc
        adc #EOFS
        dex
        bne @ed
        clc
        rts
csw:    lda cy3+1,x                ; corners X, X + 1 swapped if out of order
        cmp cy3,x
        bpl @x
        ldy cy3,x
        sta cy3,x
        tya
        sta cy3+1,x
        lda cx3,x
        ldy cx3+1,x
        sta cx3+1,x
        tya
        sta cx3,x
@x:     rts

; ecore: edge slot Y for dx = edx, dy = A: the error 0, ED = dy, EQ, ER =
; floor(dx / dy) and the remainder.  X, Y kept; clobbers A.
ecore:  sta ED,y
        beq @z
        sta dvx
        lda #0
        sta EE,y
        sty ey
        lda edx
        bpl @p
        eor #$FF
        clc
        adc #1
@p:     sta dvd
        jsr div8
        ldy ey
        bit edx
        bpl @pp
        cmp #0                     ; dx < 0: q = -q' - (rem > 0), r = dy - rem
        beq :+
        eor #$FF
        adc ED,y
        sta ER,y
        bcc @c
        lda dvd
        eor #$FF
        bcs @q                     ; (always)
:       sta ER,y
        sbc dvd
        .byte $2C                  ; (BIT abs: skips the ADC)
@c:     adc #1
@q:     sta EQ,y
        rts
@pp:    sta ER,y
        lda dvd
        sta EQ,y
        rts
@z:     sta EE,y
        sta EQ,y
        sta ER,y
        rts

; fline: face slot X's span on line yc into LB, its short edge moved to b-c
; at b's line, then both edges a line on.  X kept; clobbers A, Y.
fline:  cmp FBY,x
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
:       lda EX,x                   ; the edges' x in order
        ldy EX+EOFS,x
        cmp EX+EOFS,x
        bmi :+
        beq @st
        tay
        lda EX+EOFS,x
:       sta sxl
        cmp lx0
        bpl :+
        sta lx0
:       cpy lx1
        bmi :+
        sty lx1
:       tya                        ; the span
        clc
        adc #20
        sta @sr+1
        lda sxl
        clc
        adc #20
        tay
        lda FID,x
:       sta LB,y
        iny
@sr:    cpy #0                     ; (operand: the end)
        bne :-
@st:    lda EE,x                   ; both edges a line on
        clc
        adc ER,x
        cmp ED,x
        bcc :+
        sbc ED,x
:       sta EE,x
        lda EX,x
        adc EQ,x
        sta EX,x
        lda EE+EOFS,x
        clc
        adc ER+EOFS,x
        cmp ED+EOFS,x
        bcc :+
        sbc ED+EOFS,x
:       sta EE+EOFS,x
        lda EX+EOFS,x
        adc EQ+EOFS,x
        sta EX+EOFS,x
        rts

; smul: A:Y (low, high) = A times Y, signed: the bytes' unsigned product less
; 256 Y if A < 0 and 256 A if Y < 0.  X kept.
smul:   sta smA
        asl a
        sty smB0
        tya
        ror a
        sta smB
        lda #0
        bcc @m1
        lda smA
@m1:    lsr a
        ror smB
        bcc @m2
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
        bcc :+
        sbc smB0
:       cpy #$80
        bcc :+
        sbc smA
:       tay
        lda smB
        rts
        .pushseg
        .segment "TABLES"
BIT8:   .byte 1, 2, 4, 8, 16, 32, 64, 128
        .popseg

; tq8: tql, tqh = (V TQ) >> 8, V = A:Y signed, TQ = 100 (%01100100) by shifts
; and adds, 100 less if V < 0.  X kept; clobbers A, Y, tqa, tqb.
tq8:    sta tqa
        sty tqa+1
        sty tqb
        lsr tqb                    ; bit 2
        ror a
        lsr tqb                    ; bit 3
        ror a
        lsr tqb                    ; bit 4
        ror a
        clc                        ; bit 5
        adc tqa
        tay
        lda tqb
        adc tqa+1
        ror a
        sta tqb
        tya
        ror a
        clc                        ; bit 6
        adc tqa
        tay
        lda tqb
        adc tqa+1
        ror a
        sta tqb
        tya
        ror a
        lsr tqb                    ; bit 7
        ror a
        sta tql
        lda tqb
        ldy tqa+1
        bpl :+
        sec
        sbc #100
:       sta tqh
        rts
        .pushseg
        .segment "TABLES"
dk:     .byte $FF                  ; the attitude DBUF holds
        .popseg

; shtab: KTN, BYN, LIM by boundary w (0..47): the mask of the pixels before w
; in its byte, the byte's offset, the next byte's first boundary.
        .segment "BOOT"
shtab:  lda #$FF                   ; no pitched points kept
        sta cpi
        ldx #47
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
ktv:    .byte PM($00), PM($88), PM($CC), PM($EE)
        .code
