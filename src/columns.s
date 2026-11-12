; columns.s: a strip drawn a byte column (4 pixels) at a time, xl/4 .. xr/4-1,
; left to right.  Entries, from strips: cols (a strip) and gone (the columns
; the land has left); video's setback patches sethalf's operand sh_b.  Expects
; the rows' lines in ROWA and ROWB (strips.s), the rungs (rungs.s) and the
; boxes' bytes CE, CO; in the swr build, bank 4 paged (runk, s2v, the tables).
;
; A column runs from its top row's highest line (mn) down to the line before
; its floor (flr1: the bottom row's lowest line, which the strip below draws;
; in the near strip nearpost blacks the ground from there).  By the rungs
; that cross it, a column is
;
;   one box     no rung: the top zone a line at a time (zone1: lines mn ..
;               mx-1, each pixel from its top-row line down), then a run;
;   split       one rung: the boundary bpos (pixels left of it) moves at each
;               of the rung's transitions (fsplit, or split when the top is
;               not level);
;   split2      two rungs, likewise;
;   slow        three or more, a line at a time.
;
; A run stores lines X .. Y-1 of a column through generated code (init's):
; STA line,Y for each line, entered at line X's store and ended by an RTS
; planted over line Y's, which the next run makes a STA again.  The base build
; has four parity tables (STAB: one for each screen and half) of the even
; lines' stores, an odd line being the next byte down the character cell, so a
; run is an even pass and an odd pass through one table (run).  The swr build
; has eight store pages (RUNT: the even and the odd lines' for each screen and
; half; run2), and tables that store black in one pass (runk).
;
; A column the land reaches for the first time this frame (outside xlp .. xrp,
; the strip above's) is recorded in CURT, and blacked from its top last time
; on this screen (TOPS) down to this frame's (record).  In the near strip each
; column ends at nearpost: CURB, and black from the floor down to its bottom
; last time (BOTS).  Many routines are patched by the strip and the phase;
; their operands are noted where they are.

; cols: the strip's columns.  In: ns, last, xl, xr, xlp, xrp, topa, bota, TX,
; BX, LO, HI, RTPL, CE, CO.  Clobbers A, X, Y and the columns' zero page.
cols:   lda #$FF                   ; fsplit's tables are no rung's
        sta lastri
        lda topa+1                 ; the top row's page into its readers
        sta pt0+2
        sta pt1+2
        sta pt2+2
        sta pt3+2
        sta zt1+2
        sta zt2+2
        sta zt3+2
        sta ot0+2
        sta ot3+2
        sta oz1+2
        sta oz2+2
        sta oz3a+2
        sta oz3b+2
        sta oz1b+2
        sta oz2b+2
        eor #>ROWA ^ >ROWB         ; the bottom row's
        sta ob0+2
        sta ob3+2
        sta obz+2
        sta pb0+2
        sta pb1+2
        sta pb2+2
        sta pb3+2
        sta zb1+2
        sta zb1+7
        sta zb2+2
        sta zb2+7
        sta zb3+2
        sta zb3+7
        ldx #0                     ; the strip's kind: 0, or 1 the near strip
        bit last
        bpl @kind
        inx
@kind:  cpx #$FF                   ; (operand: the kind patched for)
        beq @kd
        stx @kind+1
        lda zbt0,x                 ; the floor's store: STA flr1, or BNE to
        sta ob_st                  ; ob_n, zb_n
        sta zb_st
        lda zbt1,x
        sta ob_st+1
        sta zb_st+1
        lda npt0,x                 ; a column's end: on to the next, or JMP
        sta c_np                   ; nearpost
        lda npt1,x
        sta c_np+1
        lda npt2,x
        sta c_np+2
        lda #0
        sta flr
@kd:    lda xlp                    ; the phases' bounds (strip 1: all record)
        ldx ns
        dex
        bne :+
        lda xr
:       sta ph_lo+1
        lda xrp
        sta ph_hi+1
        ldx #0                     ; rung 0, the left margin
        stx ri
        jsr rpatch
        lda xl
        sta x4
        jsr phase
        asl a                      ; coff; C: the right half
        sta coff
        lda #0
        rol a
        jsr sethalf
        ldy x4
        jmp c_coly

; phase: the columns from x4 (A, kept) to the next of xlp, xrp and xr: whether
; they record, and c_xe's end (at most 128 from the left half, where the half
; changes).  Clobbers X, Y.
phase:
ph_lo:  cmp #0                     ; (operand: xlp)
        bcs ph_h
        ldx ph_lo+1
        bcc ph_rec                 ; (always)
ph_h:
ph_hi:  cmp #0                     ; (operand: xrp)
        bcs ph_x
        ldx ph_hi+1                ; between: no recording, to xrp
        cpx xr
        bcc ph_n
        ldx xr
ph_n:   ldy #<o_nr
        sty o_rec+1
        sty ob_rj+1
        ldy #>o_nr
        sty o_rec+2
        sty ob_rj+2
        ldy #<c_srx
        sty c_rec+1
        ldy #>c_srx
        sty c_rec+2
        jmp ph_en
ph_rec: cpx xr
        bcc ph_r
ph_x:   ldx xr
ph_r:   ldy #<record               ; recording
        cpy o_rec+1
        beq ph_en
        .assert <record <> <o_nr, error, "ph_r: o_rec's low byte tells record from o_nr"
        sty o_rec+1
        sty ob_rj+1
        ldy #>record
        sty o_rec+2
        sty ob_rj+2
        ldy #<recordc
        sty c_rec+1
        ldy #>recordc
        sty c_rec+2
ph_en:  stx ph_e
        cpx #129
        bcc :+
        cmp #128
        bcs :+
        ldx #128
:       stx c_xe+1
        rts

; c_dbl: rung ri+1 is in the column too (A = x4 | 3): split2, or slow for
; three or more.  A level top (V clear) is made each pixel's top first.
c_dbl:  bvs c_dsl
.ifdef SWR
        cmp LO+2,x                 ; swr: just two rungs, a level top: s2v
        bcs c_dlv                  ; (bank 4), if the top is above the floor
        ldy mx
        cpy flr1
        bcs c_dn
        jmp s2v
c_dlv:
.endif
        tay
        lda mx
        sta mn
        sta ys
        sta ys+1
        sta ys+2
        sta ys+3
        tya
c_dsl:  ldy mn
        cpy flr1
        bcs c_dn
        cmp LO+2,x
        bcs c_d3
        jsr split2
        jmp c_next
c_d3:   jmp slow
c_dn:   jmp c_np

; record: a one-box column the land reaches for the first time this frame:
; CURT is its top (mn, or mx when level: V clear); if its top last time on
; this screen is higher (TOPS < mx), black down to mx-1 first (rc_t).  In:
; Y = x4, V, mn, mx.  On to o_nr.  (pT3, pT5: operands, strips' sets.)
.ifdef SWR
record: ldx DIV4,y
.else
record: tya
        lsr a
        lsr a
        tax
.endif
        lda mx
        bvc :+
        lda mn
:
pT3:    sta CURT,x
pT5:    lda TOPS,x
        cmp mx
        bcs o_nr
        bcc rc_t                   ; (always)

; c_ld: the rung's two boxes alike: one box, ri-1's.
c_ld:   lda CE-1,x
        sta RVE
        lda CO-1,x
        sta RVO
        bvc c_r1
c_z1:   jmp zone1

; c_srx: c_rec's target in a phase that does not record, and recordc's way
; on: to c_split.
c_srx:  ldx ri
        tya
        ora #3
; c_split: rung ri is in the column (A = x4 | 3, X = ri, V set if the top is
; not level): c_dbl, split, or fsplit (its tables made unless they are rung
; ri's: lastri).
c_split: cmp LO+1,x
        bcs c_dbl
        bvs :+
fsplit: lda mx
        cmp flr1
.ifdef SWR
        bcs c_dn                   ; (JMP c_np: c_np is out of reach)
.else
        bcs c_np
.endif
        cpx lastri
        beq :++
        jmp fs_ns
:       jmp split
:       jmp fs_c

; rc_t: black above the column's top: lines TOPS (A) .. mx-1, one line here or
; a run (swr: runk; base: run with ve, vo black, then restored).  V kept; on
; to c_rd.
rc_t:   tax
        inx
        cpx mx
        bne rc_r
        dex
        php
        txa
        and #7
        sta zp_
        lda LAH,x
        clc
        adc scrh
        sta zp_+1
        ldy coff
        lda #0
        sta (zp_),y
        plp
        ldy x4
        jmp c_rd
rc_r:   dex
        ldy mx
.ifdef SWR
        php
        jsr runk
        plp
.else
        lda ve
        sta svE
        lda vo
        sta svO
        lda #0
        sta ve
        sta vo
        php
        jsr run
        plp
        lda svE
        sta ve
        lda svO
        sta vo
.endif
        ldy x4
; c_rd: the rung tests again after the black: rung ri in the column, or not.
c_rd:   ldx ri
        tya
c_rr:   ora #3
        cmp LO,x
        bcs c_split
; o_nr: one box: the top zone if the top is not level (V), then lines mx ..
; flr1-1 by run, RVE and RVO the box's bytes.
o_nr:   bvs c_z1
c_r1:   ldx mx
c_r1x:  cpx flr1                   ; (zone1 returns here, X = mx)
        bcs c_next
        ldy flr1
.ifdef SWR
; run2 (swr): lines X .. Y-1 of the column (X <= Y), ve on even lines and vo
; on odd, then on into c_next.  The half's two store pages (sethalf's) hold
; STA line,Y for each even line and for each odd, 3 bytes a line from R2OFF.
; EINL,y is the slot of the first even line at or after y, EINL-1,y that of
; the first odd.  Each pass is entered at line X's slot (je, jo) and ends at
; an RTS planted over line Y's (pp0, pp1), the last run's made STAs again
; first (pr0, pr1).  The entries stay while X is the last run's, the RTSes
; while Y is.  Clobbers A, X, Y.
run2:
rX:     cpx #$FF                   ; (operand: the last X)
        beq rY
        stx rX+1
        lda EINL,x
        sta je+1
        lda EINL-1,x
        sta jo+1
rY:     cpy #$FF                   ; (operand: the last Y; sethalf's t)
        beq rv
        sty rY+1
        lda #OP_STAY
pr0:    sta RUNT+$FF               ; (operands: the last even RTS, the last
pr1:    sta RUNT+$1FF              ; odd; pages: sethalf's)
        lda #OP_RTS
        ldx EINL,y
        stx pr0+1
pp0:    sta RUNT,x                 ; (page: sethalf's)
        ldx EINL-1,y
        stx pr1+1
pp1:    sta RUNT+$100,x
rv:     lda ve
        ldy coff
je:     jsr RUNT+$FF               ; (operands: the entry; sethalf's page)
        lda vo
jo:     jsr RUNT+$1FF              ; (then on into c_next)
.else
run2:   jsr run                    ; (base)
.endif
; c_next: the column done.  c_np is LDA x4 / CLC on to c_nd1, or in the near
; strip JMP nearpost (cols patches it); its first byte is an RTS while fr, s2v
; or the swr build's run calls run2 or fsplit, which end here.
c_next:
c_np:   jmp nearpost               ; (patched: see above)
c_nd1:  adc #4
        sta x4
c_xe:   cmp #0                     ; (operand: the phase's end)
        beq c_lim
c_xt:   tay
        asl a
        sta coff
; c_coly: the column at Y = x4, V clear.  ri is the first rung not wholly left
; of it; it is in the column if its LO & $FC <= x4.
c_coly:
c_lo:   cpy #0                     ; (operand: rung ri's LO & $FC)
        bcs c_hi
ot0:    lda ROWA,y                 ; one box: each row monotonic across the
ot3:    cmp ROWA+3,y               ; column, so its ends are its extremes
        bne o_zt
        sta mx
o_ft:
ob0:    lda ROWB,y
ob3:    cmp ROWB+3,y
        bne o_zb
        sta flr1
o_rec:  jmp record                 ; (patched: record or o_nr)
c_lim:  cmp xr                     ; the phase's end: the strip's?
        beq c_end
        cmp #128                   ; the right half's start?
        beq c_nh
:       jsr phase
        jmp c_xt
c_end:  rts
c_nh:   lda #1                     ; the right half: the phase goes on to
        jsr sethalf                ; its end (ph_e > 128), or the next starts
        ldx ph_e
        cpx #129
        lda #128
        bcc :-
        stx c_xe+1
        jmp c_xt

; o_zt: a one-box column whose top slopes (A = pixel 0's line; C set: it is
; below pixel 3's, oz_dn): mn, mx, and msk the pixels whose top is line mn,
; counted from pixel 0 (from pixel 3 in oz_dn), the row being monotonic.  V
; set; on to o_ft.
o_zt:   bcs oz_dt
        sta mn
oz3a:   ldx ROWA+3,y
        stx mx
oz1:    ldx ROWA+1,y
        lda #PM($88)
        cpx mn
        bne oz_mu
oz2:    ldx ROWA+2,y
        lda #PM($CC)
        cpx mn
        bne oz_mu
        lda #PM($EE)
oz_mu:  sta msk
        bit c_v1
        bvs o_ft                   ; (always)
oz_dt:  jmp oz_dn

; o_zb: a one-box column whose floor slopes: its lower end is flr1 (ob_st:
; STA flr1), or in the near strip flr, with flr1 = flr + 1, at most YGND+1
; and flr then one less (ob_st: BNE ob_n; TAX leaves Z clear).
o_zb:   bcs :+
obz:    lda ROWB+3,y
:       tax
ob_st:  sta flr1                   ; (patched: STA flr1 or BNE ob_n)
ob_rj:  jmp record                 ; (patched: record or o_nr)
ob_n:   stx flr
        inx
        cpx #YGND+2
        bcc :+
        dex
        dec flr
:       stx flr1
        jmp ob_rj

c_hi:   cpy #0                     ; (operand: rung ri's HI)
        bcc c_sp
; c_rix: rung ri is wholly left of the column: on to the first rung with HI >
; x4; c_lo, c_hi patched for it; then c_sp, or one box (box ri-1's bytes).
c_rix:  ldx ri
        tya
:       inx
        cmp HI,x
        bcs :-
        stx ri
        lda HI,x
        sta c_hi+1
        lda LO,x
        and #$FC
        sta c_lo+1
        cpy c_lo+1
        bcs c_sp
        lda CE-1,x
        sta RVE
        lda CO-1,x
        sta RVO
        jmp ot0

; c_sp: rung ri in the column: the top level (mx) or each pixel's line (ys,
; mn, mx, V set: c_zt); the floor level (c_lv) or its lowest (c_zb).
c_sp:
pt0:    lda ROWA,y
pt1:    cmp ROWA+1,y
        bne c_zt
pt2:    cmp ROWA+2,y
        bne c_zt2
pt3:    cmp ROWA+3,y
        bne c_zt3
        sta mx
c_ft:
pb0:    lda ROWB,y
pb1:    cmp ROWB+1,y
        bne zb1c
pb2:    cmp ROWB+2,y
        bne zb2c
pb3:    cmp ROWB+3,y
        bne zb3c
c_lv:   sta flr1
c_rec:  jmp recordc                ; (patched: recordc or c_srx)

; ZTP n: pixel n's top-row line into ys+n, mn, mx.
.macro ZTP n
        lda ROWA+n,y
        sta ys+n
        cmp mn
        bcs :+
        sta mn
        bcc :++
:       cmp mx
        bcc :+
        sta mx
:
.endmacro
c_zt:   sta ys                     ; pixel 1 differs from pixel 0
        sta mn
        sta mx
        bit c_v1
zt1:    ZTP 1
zt2:    ZTP 2
zt3:    lda ROWA+3,y
        sta ys+3
        cmp mn
        bcs :+
        sta mn
        bcc c_ft
:       cmp mx
        bcc c_ft
        sta mx
        jmp c_ft
c_zt2:  sta ys                     ; pixel 2 is the first to differ
        sta ys+1
        sta mn
        sta mx
        bit c_v1
        jmp zt2
c_zt3:  sta ys                     ; pixel 3
        sta ys+1
        sta ys+2
        sta mn
        sta mx
        bit c_v1
        jmp zt3

; c_zb: the floor slopes: its lowest pixel is flr1, or flr in the near strip,
; as o_zb.  Entered at zb1c, zb2c or zb3c, past the CMP that found the first
; pixel to differ (A = pixel 0's line).
c_zb:
zb1:    cmp ROWB+1,y
zb1c:   bcs :+
        lda ROWB+1,y
:
zb2:    cmp ROWB+2,y
zb2c:   bcs :+
        lda ROWB+2,y
:
zb3:    cmp ROWB+3,y
zb3c:   bcs :+
        lda ROWB+3,y
:       tax
zb_st:  sta flr1                   ; (patched: STA flr1 or BNE zb_n)
        jmp c_rec
zb_n:   stx flr
        inx
        cpx #YGND+2
        bcc :+
        dex
        dec flr
:       stx flr1
        jmp c_rec

; nearpost: the near strip's column, after its land: black below.  A level
; floor (flr 0): line flr1 black; else each pixel black from its bottom-row
; line down to flr-1, and line flr.  Then CURB is that line (YGND at most),
; and black from the line after it down to BOTS.  In: flr, flr1, x4, coff,
; bota, scrh.  Out: flr 0; on to the next column.  (pB4 .. pB8: operands,
; strips' sets.)
.ifdef SWR
np_b:   ldx x4                     ; CURB = A, or YGND below the screen
        ldy DIV4,x
.else
np_b:   pha                        ; CURB = A, or YGND below the screen
        lda x4
        lsr a
        lsr a
        tay
        pla
.endif
        cmp #YGND+1
        bcc pB4
        lda #YGND
        bcs pB4                    ; (always)
nearpost:
        lda flr
        bne np_z
        lda flr1
        cmp #YGND+1
        bcc np_lv
.ifdef SWR
np_hd:  ldx x4                     ; below the screen: nothing to draw
        ldy DIV4,x
.else
np_hd:  lda x4                     ; below the screen: nothing to draw
        lsr a
        lsr a
        tay
.endif
        lda #YGND
        .assert YGND >= $80, error, "np_hd: BMI pB4 needs YGND >= 128"
        bmi pB4                    ; (always)
np_lv:  tax                        ; line flr1 black
        and #7
        sta zp_
.ifdef SWR
np_h:   lda LAHSB0,x               ; (page: sethalf's)
.else
        lda LAH,x                  ; (C clear)
        adc scrh
.endif
        sta zp_+1
        ldy coff
        lda #0
        sta (zp_),y
.ifdef SWR
        txa                        ; A = the line, Y = the column
        ldx x4
        ldy DIV4,x
.else
        lda x4
        lsr a
        lsr a
        tay
        txa
.endif
pB4:    sta CURB,y
pB5:    cmp BOTS,y
        bcc np_d
np_n:   lda x4                     ; the next column (C set: + 4)
        adc #3
        sta x4
        jmp c_xe
np_d:   adc #1                     ; (C clear) black from the next line to BOTS
        tax
pB6:    cmp BOTS,y
        bne np_r
        lda LAH,x                  ; one line
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
        jmp c_nd
np_r:
pB8:    lda BOTS,y                 ; a run (swr: runk; base: run, black)
        tay
        iny
.ifdef SWR
        jsr runk
.else
        lda ve
        sta svE
        lda vo
        sta svO
        lda #0
        sta ve
        sta vo
        jsr run
        lda svE
        sta ve
        lda svO
        sta vo
.endif
        jmp c_nd
np_z:   ldy x4                     ; the floor slopes: each pixel's line
        lda (bota),y
        sta ys
        iny
        lda (bota),y
        sta ys+1
        iny
        lda (bota),y
        sta ys+2
        iny
        lda (bota),y
        sta ys+3
        cmp ys+2                   ; the highest
        bcc :+
        lda ys+2
:       cmp ys+1
        bcc :+
        lda ys+1
:       cmp ys
        bcc :+
        lda ys
:       tax
        cpx flr
        bcs np_e
np_l:                              ; each line, its pixels at or below their
        lda LAH,x                  ; bottom-row line black
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        lda #0
        cpx ys+3
        rol a
        cpx ys+2
        rol a
        cpx ys+1
        rol a
        cpx ys
        rol a
        tay
        lda MASKN,y
        ldy coff
        and (zp_),y
        sta (zp_),y
        inx
        cpx flr
        bcc np_l
        bne np_x
np_e:   cpx #YGND                  ; line flr: masked at YGND (bclip may hold
        beq np_l                   ; pixels' lines below it), else whole
        lda LAH,x
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
np_x:   lda flr
        ldx #0
        stx flr
        jmp np_b

; rpatch: c_lo and c_hi's operands for rung X.  X kept; clobbers A.
rpatch: lda HI,x
        sta c_hi+1
        lda LO,x
        and #$FC
        sta c_lo+1
        rts

.ifdef SWR
; sethalf (swr): the half A (0 left, 1 right) of the screen being drawn, t = 2
; back + A: scrh, run2's store pages (the even lines' >RUNT + 2t, the odd
; lines' the next), runk's table (kpg) and the line pages' table (LAHSBt).
; The RTSes run2 planted in the pages being left are made STAs again, and
; rY's operand is made t, which no end line matches, so that the next run
; plants afresh.  Out: V clear, Y = t.  Clobbers A, X.
        .pushseg
        .segment "T2"
sethalf:
sh_b:   ora #0                     ; (operand: 2 back, setback's)
        tay
        lda shs,y
        sta scrh
        clv
        lda #OP_STAY
        ldx pr0+1
sh_1:   sta RUNT,x                 ; (page: the last run's even lines')
        ldx pr1+1
sh_2:   sta RUNT+$100,x            ; (and odd lines')
        sty rY+1
        tya
        asl a
        tax
        adc #>BLKT                 ; runk's table (C clear, V stays clear)
        sta kpg
        txa
        adc #>RUNT
        sta pr0+2
        sta pp0+2
        sta je+2
        sta sh_1+2
        adc #1
        sta pr1+2
        sta pp1+2
        sta jo+2
        sta sh_2+2
        lda lahsh,y                ; LAHSBt's page into its readers
        sta np_h+2
        sta fs_h+2
        sta z1_h+2
        sta s2_l+2
        rts
        .popseg
.else
; sethalf (base): the half A (0 left, 1 right) of the screen being drawn, t =
; 2 back + A: scrh, and run's parity table (page >STAB + t).  The planted RTS
; is made a STA again and one planted at the table's end slot (PTEND), and
; rY's operand is made 0, which no end line matches, so that the next run
; plants afresh.  Out: V clear, Y = t.  Clobbers A, X.
sethalf:
sh_b:   ora #0                     ; (operand: 2 back, setback's)
        tay
        lda shs,y
        sta scrh
        tya
        clc
        adc #>STAB
        .assert >STAB + 3 < $80, error, "sethalf: its ADC must clear V"
        sta r_e+2
        sta r_o+2
        tax
        lda #OP_STAY
        ldy #0
        sta (pp),y
        stx pp+1
        lda #PTEND
        sta pp
        lda #OP_RTS
        sta (pp),y
        sty rY+1                   ; (0: no line's)
        ldy r_e+2                  ; Y = t
        tya
        sec
        sbc #>STAB
        tay
        rts
.endif
        .pushseg
        .segment "TABLES"
zbt0:   .byte $85, $D0             ; by the strip's kind: STA flr1, BNE +3
zbt1:   .byte flr1, 3
        .assert ob_n = ob_st+5 && zb_n = zb_st+5, error, "ob_n, zb_n: 3 bytes past the branch"
npt0:   .byte $A5, $4C             ; LDA x4 / CLC, JMP nearpost
npt1:   .byte x4, <nearpost
npt2:   .byte $18, >nearpost
shs:    .byte SCR0, SCR0+1, SCR1, SCR1+1   ; scrh by t
.ifdef SWR
lahsh:  .byte >LAHSB0, >LAHSB1, >LAHSB2, >LAHSB3   ; LAHSBt's page by t
        .assert <LAHSB0 = <LAHSB1 && <LAHSB0 = <LAHSB2 && <LAHSB0 = <LAHSB3, error, "LAHSBt: one low byte (sethalf patches pages)"
.endif
; MASKB, MASKN: by a 4-bit index (bit n: pixel n): those pixels' mask, and its
; complement.
MASKB:  .byte PM($00), PM($88), PM($44), PM($CC), PM($22), PM($AA), PM($66), PM($EE)
        .byte PM($11), PM($99), PM($55), PM($DD), PM($33), PM($BB), PM($77), PM($FF)
MASKN:  .byte PM($FF), PM($77), PM($BB), PM($33), PM($DD), PM($55), PM($99), PM($11)
        .byte PM($EE), PM($66), PM($AA), PM($22), PM($CC), PM($44), PM($88), PM($00)
        .popseg

; fsplit: one rung, the top level: lines mx .. flr1-1, the boundary bpos
; (the pixels left of the rung) moving at each transition.  The rung's tables
; (fs_new): BE, BO + bpos the column's bytes for even and odd lines; fl_e,
; fl_o read pixel x4 + bpos's transition (x4 + bpos - 1's leaning left); fst_e,
; fst_o are INX or DEX and fen_e, fen_o compare with 4 or 0, by the lean.  The
; walker stores a character row a line at a time (zp_ the row, Y the line in
; it, rsm its first line - 1, fwe the next transition in it); a transition
; FSRJ lines or more past the row's end is reached by a run (fr), as is a
; floor past the row (fe_r).  Entered at fs_c (X = the rung, C set) or fs_w
; (X = bpos); ends at c_np.
fs_c:   lda #0                     ; (operand: rbl)
rbl     = *-1
        adc x4                     ; (C set: + 1)
        sta fl_e+1
        sta fl_o+1
.ifdef SWR
        clc                        ; bpos at the top: CLMP1,d, d = TX - x4 - 1
        lda TX,x
        sbc x4
        tay
        ldx CLMP1,y
.else
        lda TX,x                   ; bpos at the top: TX - x4, in 0 .. 4
        sec
        sbc x4
        CLAMP4
        tax
.endif
fs_w:   lda coff
        sta zp_
        ldy mx
.ifdef SWR
fs_h:   lda LAHSB0,y               ; (page: sethalf's)
.else
fs_h:   lda LAH,y
        clc
        adc scrh
.endif
        sta zp_+1
.ifdef SWR
        lda RSMT,y                 ; the row's first line - 1
        sta rsm
.else
        tya                        ; the row's first line - 1 (C clear)
        and #$F8
        sbc #0
        sta rsm
.endif
        tya
        and #7
        tay
        lsr a
        bcc fl_e
        bcs fl_o                   ; (always)
fwx_e:  lda BE,x                   ; the transition is past the row: to the
        sta (zp_),y                ; row's end
        iny
fwx_o:  lda BO,x
        sta (zp_),y
        iny
        cpy #8
        bne fwx_e
fw_c:   lda zp_+1                  ; the next row (C set)
        adc #1
        sta zp_+1
        lda rsm
        adc #8
        sta rsm
        ldy #0
        lda fwe
        sbc #7
        sta fwe
        beq fn_e
fw_e:   lda BE,x                   ; lines Y .. fwe-1 at bpos X
        sta (zp_),y
        iny
        cpy fwe
        beq fn_o
fw_o:   lda BO,x
        sta (zp_),y
        iny
        cpy fwe
        bne fw_e
fn_e:                              ; a transition, Y even: bpos moves
fst_e:  inx                        ; (patched: INX or DEX)
fen_e:  cpx #4                     ; (patched: 4 or 0)
        beq fe_x
fl_e:   lda RTBUF,x                ; (operand: the rung's transitions)
        cmp flr1
        bcs fe_x
        sbc rsm                    ; (C clear) its line in the row
        sta fwe
        cpy fwe
        bcs fn_e
        cmp #8
        bcc fw_e
        cmp #8+FSRJ
        bcc fwx_e
        bcs fr                     ; (always)
fn_o:                              ; Y odd
fst_o:  inx                        ; (patched)
fen_o:  cpx #4                     ; (patched)
        beq fe_x
fl_o:   lda RTBUF,x                ; (operand)
        cmp flr1
        bcs fe_x
        sbc rsm
        sta fwe
        cpy fwe
        bcs fn_o
        cmp #8
        bcc fw_o
        cmp #8+FSRJ
        bcc fwx_o
fr:     stx bpos                   ; far: a run to the transition (C set:
        adc rsm                    ; fwu its line, X the walker's)
        sta fwu
        lda BE,x
        sta RVE
        lda BO,x
        sta RVO
        tya
        sec
        adc rsm
        tax
        ldy fwu
        lda c_np                   ; (run2 ends at c_np: an RTS meanwhile)
        pha
        lda #OP_RTS
        sta c_np
        jsr run2
        pla
        sta c_np
        ldy fwu                    ; the walker again from it
        lda LAH,y
        clc
        adc scrh
        sta zp_+1
.ifdef SWR
        lda RSMT,y                 ; the row's first line - 1
        sta rsm
.else
        tya                        ; the row's first line - 1 (C clear)
        and #$F8
        sbc #0
        sta rsm
.endif
        tya
        and #7
        tay
        ldx bpos
        lsr a
        bcc fn_e
        bcs fn_o                   ; (always)
fe_x:   lda flr1                   ; no transition above the floor: to it
        clc
        sbc rsm
        cmp #9
        bcs fe_r
        sta fwe
        cpy fwe
        bcc ff_s
ff_d:   jmp c_np
ff_s:   tya
        lsr a
        bcs ff_o
ff_e:   lda BE,x
        sta (zp_),y
        iny
        cpy fwe
        beq ff_d
ff_o:   lda BO,x
        sta (zp_),y
        iny
        cpy fwe
        bne ff_e
        jmp c_np
fe_r:   lda BE,x                   ; the floor past the row: a run
        sta RVE
        lda BO,x
        sta RVO
        tya
        adc rsm                    ; (C set)
        tax
        ldy flr1
        jmp run2

; fs_new, fs_ns: fsplit's tables for rung X, lastri = X.  fs_ns sends a rung
; whose two boxes are alike to c_r1 as one box; fs_new does not test.  BE +
; bpos: box X's even byte with pixels 0 .. bpos-1 from box X-1's; BO likewise
; the odd; then the lean (rbl, fst_e, fst_o, fen_e, fen_o), patched only when
; it changes.  Ends at fs_nj (fs_c, or sp_r for split), C set.
fs_new: lda CE-1,x
        sta BE+4
        eor CE,x
        bne fs_dif
        beq fs_e0                  ; (always)
fs_s1:  lda CO-1,x                 ; even bytes alike: the odd?
        cmp CO,x
        bne fs_e0
        sta RVO                    ; one box
        lda BE+4
        sta RVE
        jmp c_r1
fs_e0:  stx lastri
        lda BE+4
        sta BE
        sta BE+1
        sta BE+2
        sta BE+3
        jmp fs_co
fs_oe:  lda BO
        sta BO+1
        sta BO+2
        sta BO+3
        jmp fs_ln
fs_ns:  lda CE-1,x
        sta BE+4
        eor CE,x
        beq fs_s1
fs_dif: stx lastri
        tay
        eor BE+4
        sta BE
        tya
        and #PM($88)
        eor BE
        sta BE+1
        tya
        and #PM($CC)
        eor BE
        sta BE+2
        tya
        and #PM($EE)
        eor BE
        sta BE+3
fs_co:  lda CO-1,x
        sta BO+4
        lda CO,x
        sta BO
        eor BO+4
        beq fs_oe
        tay
        and #PM($88)
        eor BO
        sta BO+1
        tya
        and #PM($CC)
        eor BO
        sta BO+2
        tya
        and #PM($EE)
        eor BO
        sta BO+3
fs_ln:  lda BX,x                   ; the lean: left if BX < TX
        cmp TX,x
        lda RTPL,x
        bcc fs_lf
fs_nr:  sta rbl                    ; leaning right or upright
        lda #OP_INX
        cmp fst_e
        beq fs_nj
        sta fst_e
        sta fst_o
        lda #4
        sta fen_e+1
        sta fen_o+1
        bcs fs_nj                  ; (always)
fs_lf:  sbc #0                     ; leaning left: rbl = RTPL - 1 (C clear)
        sta rbl
        lda #OP_DEX
        cmp fst_e
        beq fs_nj
        sta fst_e
        sta fst_o
        lda #0
        sta fen_e+1
        sta fen_o+1
        sec
fs_nj:  jmp fs_c                   ; (patched: fs_c or sp_r)

; zone1: a one-box column's top zone, lines mn .. min(mx, flr1)-1: msk's
; pixels from RVE or RVO by the line's parity, the rest kept.  msk is line
; mn's on entry, then pmask's.  Out: X = mx, to c_r1x; or c_np at the floor.
zone1:  ldx mn
        cpx flr1
        bcs z1_n
.ifdef SWR
z1_h:   lda LAHSB0,x               ; (page: sethalf's)
.else
z1_h:   lda LAH,x                  ; (C clear)
        adc scrh
.endif
        sta zp_+1
        txa
        and #7
        sta zp_
        lsr a
        ldy coff
        lda (zp_),y
        bcs z1_o
        eor RVE
        and msk
        eor (zp_),y
        sta (zp_),y
        inx
        cpx mx
        bcc z1_m
        jmp c_r1x
z1_o:   eor RVO
        and msk
        eor (zp_),y
        sta (zp_),y
        inx
        cpx mx
        bcc z1_m
        jmp c_r1x
z1_m:   ldy x4                     ; each pixel's top, then the next line's
        lda (topa),y               ; mask
        sta ys
        iny
        lda (topa),y
        sta ys+1
        iny
        lda (topa),y
        sta ys+2
        iny
        lda (topa),y
        sta ys+3
z1_l:   cpx flr1
        bcs z1_n
        jsr pmask
        jmp z1_h
z1_n:   jmp c_np

c_nd:   lda x4                     ; nearpost's way on to the next column
        clc
        jmp c_nd1

; oz_dn: o_zt with pixel 0's line (A) below pixel 3's.
oz_dn:  sta mx
oz3b:   ldx ROWA+3,y
        stx mn
oz2b:   ldx ROWA+2,y
        lda #PM($11)
        cpx mn
        bne oz_m
oz1b:   ldx ROWA+1,y
        lda #PM($33)
        cpx mn
        bne oz_m
        lda #PM($77)
oz_m:   sta msk
        bit c_v1
        jmp o_ft

; pmask: msk = line X's pixels at or below their top (ys).  X kept; clobbers
; A, Y.
pmask:  lda #0
        cpx ys+3
        rol a
        cpx ys+2
        rol a
        cpx ys+1
        rol a
        cpx ys
        rol a
        tay
        lda MASKB,y
        sta msk
        rts

; zline: line X of the column: A in msk's pixels, the rest kept.  X kept;
; clobbers A, Y, zv.
zline:  sta zv
        lda LAH,x
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda (zp_),y
        eor zv
        and msk
        eor (zp_),y
        sta (zp_),y
        rts

; split: one rung, the top not level: the zone (lines mn .. mx-1) a line at a
; time, the boundary moving at the rung's transitions ((rtp),y), then fsplit's
; walker from mx (sp_zg).  fsplit's tables are made first unless they are rung
; ri's.  Boxes alike: one box (c_ld, with line mn's mask).
split:  ldx ri
        cpx lastri
        beq sp_c
        lda CE-1,x
        cmp CE,x
        bne :+
        lda CO-1,x
        cmp CO,x
        bne :+
        ldx mn
        jsr pmask
        ldx ri
        jmp c_ld
:       lda #<sp_r                 ; the tables, back to sp_r
        sta fs_nj+1
        lda #>sp_r
        sta fs_nj+2
        jmp fs_new
sp_r:   lda #<fs_c
        sta fs_nj+1
        lda #>fs_c
        sta fs_nj+2
sp_c:   lda rbl                    ; (C set) rtp, fl_e, fl_o: the transitions
        adc x4
        sta rtp
        sta fl_e+1
        sta fl_o+1
.ifdef SWR
        clc                        ; Y = bpos at the top (CLMP1)
        lda TX,x
        sbc x4
        tax
        ldy CLMP1,x
.else
        lda TX,x                   ; Y = bpos at the top
        sec
        sbc x4
        CLAMP4
        tay
.endif
        ldx mn
        lda fst_e
        cmp #OP_INX
        bne sp_lz
sp_rz:  cpx mx                     ; leaning right
        bcs sp_zd
        cpx flr1
        bcs sp_zd
sp_rc:  cpy #4
        beq sp_rb
        txa
        cmp (rtp),y
        bcc sp_rb
        iny
        bne sp_rc
sp_rb:  jsr sp_ln
        inx
        bne sp_rz
sp_lz:  cpx mx                     ; leaning left
        bcs sp_zd
        cpx flr1
        bcs sp_zd
sp_lc:  cpy #0
        beq sp_lb
        txa
        cmp (rtp),y
        bcc sp_lb
        dey
        bpl sp_lc
sp_lb:  jsr sp_ln
        inx
        bne sp_lz
sp_zd:  tya
        tax
        jmp sp_zg

; sp_ln: zone line X at bpos Y.  X, Y kept; clobbers A, bpos, msk, zv.
sp_ln:  sty bpos
        lda #0                     ; (pmask)
        cpx ys+3
        rol a
        cpx ys+2
        rol a
        cpx ys+1
        rol a
        cpx ys
        rol a
        tay
        lda MASKB,y
        sta msk
sl_h:   lda LAH,x                  ; (C clear)
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        lsr a
        ldy bpos
        lda BE,y
        bcc :+
        lda BO,y
:       sta zv
        ldy coff
        lda (zp_),y
        eor zv
        and msk
        eor (zp_),y
        sta (zp_),y
        ldy bpos
        rts

        TAIL "T7"
; mktr: rung X's transitions in the column, top to bottom, into TRL (the
; line) and TRB (the mask of the pixels left of the rung from that line) from
; index A, $FF after in TRL.  Out: A the mask at the top.  Clobbers X, Y, tj,
; p0, p1, rtp.
mktr:   sta tj
        lda RTPL,x
        sec
        adc x4
        sta rtp
.ifdef SWR
        clc                        ; the pixels left of the rung: p1 at the
                                   ; bottom, p0 at the top (CLMP1)
        lda BX,x
        sbc x4
        tay
        lda CLMP1,y
        sta p1
        clc
        lda TX,x
        sbc x4
        tay
        lda CLMP1,y
        sta p0
.else
        lda BX,x                   ; the pixels left of the rung: p1 at the
                                   ; bottom, p0 at the top
        sec
        sbc x4
        CLAMP4
        sta p1
        lda TX,x
        sec
        sbc x4
        CLAMP4
        sta p0
.endif
        ldx tj
        cmp p1
        beq @end
        tay
        bcc @rt
:       dey                        ; leaning left
        lda LM,y
        sta TRB,x
        lda (rtp),y
        sta TRL,x
        inx
        cpy p1
        bne :-
        beq @end                   ; (always)
@rt:    lda (rtp),y                ; leaning right
        sta TRL,x
        lda LM+1,y
        sta TRB,x
        inx
        iny
        cpy p1
        bne @rt
@end:   lda #$FF
        sta TRL,x
        ldy p0
        lda LM,y
        rts

        ENDTAIL

; split2: two rungs (ri, ri+1): boxes L, M, R (ri-1, ri, ri+1), the masks
; bpos (left of rung ri) and bpos2 (left of rung ri+1) changing at each rung's
; transitions (TRL, TRB from 0 and 6; kk, kb the next of each).  The zone a
; line at a time, then runs to each next transition or the floor.  In: mn,
; mx, ys, flr1.  Clobbers A, X, Y, ve, vo, yy, zv, bpos, bpos2, kk, kb, the
; boxes' bytes (le, lo2, me, mo, re, ro) and mktr's.
split2: ldx ri
        lda CE-1,x                 ; L
        sta le
        lda CO-1,x
        sta lo2
        lda CE+1,x                 ; R, and M as M xor R
        sta re
        eor CE,x
        sta me
        lda CO+1,x
        sta ro
        eor CO,x
        sta mo
        lda #0
        jsr mktr
        sta bpos
        ldx ri
        inx
        lda #6
        jsr mktr
        sta bpos2
        lda #0
        sta kk
        lda #6
        sta kb
        ldx mn                     ; the zone
@z:     cpx mx
        bcs @zd
        cpx flr1
        bcs @zd
        jsr catch2
        jsr pmask
        jsr bytes2
        txa
        lsr a
        lda ve
        bcc :+
        lda vo
:       jsr zline
        inx
        bne @z
@zd:    ldx mx                     ; the runs
        cpx flr1
        bcs @rd
        stx yy
@tr:    jsr catch2                 ; (Y = kb)
        lda TRL,y                  ; to the nearer transition or the floor
        ldy kk
        cmp TRL,y
        bcc :+
        lda TRL,y
:       cmp flr1
        bcc :+
        lda flr1
:       tay
        jsr bytes2
        ldx yy
        sty yy
        jsr run
        ldx yy
        cpx flr1
        bcc @tr
@rd:    rts

; catch2: bpos, bpos2 past the transitions at or above line X; kk, kb the
; next.  Out: Y = kb.  X kept; clobbers A.
catch2: ldy kk
:       txa
        cmp TRL,y
        bcc :+
        lda TRB,y
        sta bpos
        iny
        bne :-
:       sty kk
        ldy kb
:       txa
        cmp TRL,y
        bcc :+
        lda TRB,y
        sta bpos2
        iny
        bne :-
:       sty kb
        rts

; bytes2: ve, vo for split2's line: M in bpos2's pixels else R, then L in
; bpos's.  X, Y kept.
bytes2: lda me
        and bpos2
        eor re
        sta ve
        eor le
        and bpos
        eor ve
        sta ve
        lda mo
        and bpos2
        eor ro
        sta vo
        eor lo2
        and bpos
        eor vo
        sta vo
        rts
        .pushseg
        .segment "TABLES"
LM:     .byte PM($00), PM($88), PM($CC), PM($EE), PM($FF)   ; the n leftmost
        .popseg

.ifdef SWR
; run (swr): run2 as a subroutine, c_np's first byte an RTS meanwhile.
; Clobbers A, X, Y.
        .pushseg
        .segment "T3"
run:    lda c_np
        pha
        lda #OP_RTS
        sta c_np
        jsr run2
        pla
        sta c_np
        rts
        .popseg

; runk (swr, bank 4): lines X .. Y-1 of the column black (X <= Y), in one pass
; through the half's black store table (gen.py's; kpg its page): its slot for
; line Y made an RTS, the one runk planted last (kpp) made a STA again first,
; and the table entered at line X's slot (KENL, KENH: the slot's low byte, its
; page less the table's).  run2's RTSes and entries are left alone.  Clobbers
; A, X, Y.
        .pushseg
        .segment "B4CODE"
runk:   sty @y+1
        ldy #0
        lda #OP_STAY               ; the last RTS back
        sta (kpp),y
@y:     ldy #0                     ; (operand: Y)
        lda KENL,y
        sta kpp
        lda KENH,y
        ora kpg
        sta kpp+1
        lda #OP_RTS
        ldy #0
        sta (kpp),y
        lda KENL,x
        sta @j+1
        lda KENH,x
        ora kpg
        sta @j+2
        lda #0
        ldy coff
@j:     jmp $FFFF                  ; (operand: line X's slot; its RTS returns)
        .assert (>BLKT & 1) = 0, error, "runk: each black table at an even page (KENH ORs 0 or 1)"
        .popseg
.else
; run (base): lines X .. Y-1 of the column (X <= Y), ve on even lines and vo
; on odd, through the parity table (r_e, r_o's page: sethalf's).  OL,y is line
; y's entry, that of the even line at or before it.  One RTS, at OL,Y, ends
; both passes: the even from OL+1,X (A = ve, Y = coff), then the odd from OL,X
; (A = vo, Y = coff + 1), whose RTS returns.  For Y odd the even pass stops a
; line short and line Y-1 is stored here, through the STA the RTS covers.  An
; RTS already in the slot stays (pp), as do the entries while X is the last
; run's and the end while Y is (rX, rY).  Clobbers A, X, Y, rodd, rl, rh.
run:
rX:     cpx #$FF                   ; (operand: the last X)
        beq rY
        stx rX+1
        lda OL+1,x
        sta r_e+1
        lda OL,x
        sta r_o+1
rY:     cpy #$FF                   ; (operand: the last Y; sethalf's 0)
        beq @k
        sty rY+1
        lda OL+1,y
        sta rodd
        lda OL,y
        cmp pp
        beq @k
        ldx #0
        pha
        lda #OP_STAY               ; the last RTS back
        sta (pp,x)
        pla
        sta pp
        ldy #1                     ; the covered STA's operand
        lda (pp),y
        sta rl
        iny
        lda (pp),y
        sta rh
        lda #OP_RTS
        sta (pp,x)
@k:     lda ve
        ldy coff
r_e:    jsr $FF00                  ; (operand: the even entry)
        ldx rodd
        cpx pp
        beq @o
        sta (rl),y
@o:     lda vo
        iny
r_o:    jmp $FF00                  ; (operand: the odd entry)

.endif

; recordc: record for a column a rung is in: on to c_srx, or rc_t.  (pT3c,
; pT5c: operands, strips' sets.)
.ifdef SWR
recordc: ldx DIV4,y
.else
recordc: tya
        lsr a
        lsr a
        tax
.endif
        lda mx
        bvc :+
        lda mn
:
pT3c:   sta CURT,x
pT5c:   lda TOPS,x
        cmp mx
        bcc :+
        jmp c_srx
:       jmp rc_t

; gone: the columns outside the near strip's (xl/4 .. xr/4-1) that had land
; last time on this screen (TOPS not $FF) are blacked (gn_d), and all of them
; marked empty this frame (CURT $FF, CURB 0).  In: xl, xr, tsp, bsp.  Clobbers
; A, X, Y, tsy, tj, coff and sethalf's.  (pT6, pT4, pB7: operands, strips'
; sets.)
.macro GONE1 lt, lc, lb
        .local nd
lt      = *
        lda TOPS,x
        cmp #$FF
        beq nd
        jsr gn_d
nd:     lda #$FF
lc      = *
        sta CURT,x
        lda #0
lb      = *
        sta CURB,x
.endmacro
gone:   lda xr                     ; columns 63 down to 0, the near strip's
        lsr a                      ; jumped over
        lsr a
        sta tsy
        lda xl
        lsr a
        lsr a
        sta gn_lo+1
        ldx #63
gn_c:   cpx tsy
        bcs gn_1
gn_lo:  cpx #0                     ; (operand: xl / 4)
        bcc gn_1
        ldx gn_lo+1
        bcs gn_n                   ; (always)
gn_1:   GONE1 pT6, pT4, pB7
gn_n:   dex
        bpl gn_c
        rts
; gn_d: column X black from its TOPS to its BOTS ((tsp), (bsp)), by runk
; (swr) or run (base).  X kept.
gn_d:   stx tj
        txa
        asl a
        asl a
        asl a
        sta coff
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        jsr sethalf
        ldy tj
        lda (tsp),y
        tax
        lda (bsp),y
        tay
        iny
.ifdef SWR
        jsr runk
.else
        lda #0
        sta ve
        sta vo
        jsr run
.endif
        ldx tj
        rts

; sp_zg: split's way into the walker at bpos X, unless the zone has moved the
; boundary out of the column (fen_e's edge): then the rest is one box, the
; rung's bytes at that edge, by run.
sp_zg:  cpx fen_e+1
        beq :+
        jmp fs_w
:       lda mx
        cmp flr1
        bcc :+
        jmp c_np
:       lda BE,x
        sta RVE
        lda BO,x
        sta RVO
        ldy flr1
        ldx mx
        jmp run2

; slow: three or more rungs.  Each pixel's box at its top line (SPB: ri - 1, +1
; for each rung whose top is at or left of it) and the lines at which a rung
; crosses it (STL, four a pixel, $FF after; STD the box's change there), then
; slow2.  In: C set, ys, mn, flr1.
slow:   lda x4                     ; (C set: x4p4 = x4 + 4)
        sta tx1
        adc #3
        sta x4p4
        ldx #0
@p:     stx tj                     ; pixel p
        ldy ri
        dey
        tya
        sta SPB,x
        txa
        asl a
        asl a
        tay
        lda #$FF
        sta STL,y
        sta STL+1,y
        sta STL+2,y
        sta STL+3,y
        ldx ri
@r:     lda LO,x                   ; each rung reaching the column
        cmp x4p4
        bcs @pd
        lda tx1
        cmp TX,x
        bcc :+
        stx tmp
        ldx tj
        inc SPB,x
        ldx tmp
:       lda tx1                    ; crossing the pixel: its transition
        cmp LO,x
        bcc @rn
        cmp HI,x
        bcs @rn
        lda RTPL,x
        sec
        adc tx1
        sty tmp
        tay
        lda RTBUF,y
        ldy tmp
        sta STL,y
        lda BX,x                   ; +1 leaning left, -1 right
        cmp TX,x
        lda #1
        bcc :+
        lda #$FF
:       sta STD,y
        iny
@rn:    inx
        bne @r
@pd:    inc tx1
        ldx tj
        inx
        cpx #4
        bne @p
; slow2: lines mn .. flr1-1, each pixel at or below its top in its box's byte
; for the line's parity.  On to c_next.
slow2:  ldx mn
@l:     stx yy
        txa
        lsr a
        lda #<CE
        bcc :+
        lda #<CO
:       sta @cl+1
        lda #0
        sta msk
        sta zv
        ldy #3
@lp:    lda yy                     ; pixel Y
        cmp ys,y
        bcc @skip
        lda PIXM,y
        ora msk
        sta msk
        sty tj
        lda SPB,y                  ; its box
        sta tmp
        tya
        asl a
        asl a
        tax
@s:     ldy STL,x
        cpy #$FF
        beq @sd
        cpy yy
        beq @sa
        bcs @sn
@sa:    lda tmp
        clc
        adc STD,x
        sta tmp
@sn:    inx
        bne @s
@sd:    ldx tmp
@cl:    lda CE,x                   ; (operand: CE or CO)
        ldy tj
        and PIXM,y
        ora zv
        sta zv
@skip:  dey
        bpl @lp
        ldx yy
        lda zv
        jsr zline
        inx
        cpx flr1
        bcc @l
        jmp c_next
        .pushseg
        .segment "TABLES"
PIXM:   .byte PM($88), PM($44), PM($22), PM($11)
        .popseg

; The base build's parity tables: generated code (init), at the start of four
; pages; the pages' tails hold code (segments T0 .. T3).
.ifndef SWR
        .segment "STAB0"
STAB:   .res PTN
        .segment "STAB1"
        .res PTN
        .segment "STAB2"
        .res PTN
        .segment "STAB3"
        .res PTN
        .code
.endif

.ifdef SWR
; s2v (swr, bank 4): a level-topped column that two rungs split, ri and ri+1:
; boxes L, M, R are ri-1, ri, ri+1.  fsplit first draws the column from mx
; down as rung ri+1 splits it (M left of it, R right: fs_c, or fs_new first),
; c_np's first byte an RTS so that its exits return here; then L is written
; over the pixels left of rung ri a line at a time from mx, between its
; transitions (mktr's TRL, TRB), the other pixels kept.  In: X = ri, mx,
; flr1, lastri, CE, CO, coff.  Ends at c_np.  Clobbers A, X, Y, le, lo2,
; bpos2, kb, tj, zp_, fsplit's and mktr's.
        .pushseg
        .segment "B4CODE"
s2v:    lda CE-1,x                 ; L's bytes
        sta le
        lda CO-1,x
        sta lo2
        lda #0                     ; rung ri's transitions into TRL, TRB from 0;
                                   ; A = its mask at the top
        jsr mktr
        sta bpos2
        lda #0
        sta kb                     ; (TRL's index)
        lda c_np                   ; c_np an RTS while fsplit runs: its exits
                                   ; return to s2ov
        pha
        lda #OP_RTS
        sta c_np
        ldx ri
        inx
        cpx lastri                 ; rung ri+1: fsplit's tables are its (fs_c,
                                   ; C set), or are made (fs_new)
        bne :+
        jsr fs_c
        jmp s2ov
:       jsr fs_new
s2ov:   pla                        ; c_np's opcode back
        sta c_np
        lda #0
        sta zp_                    ; ((zp_),y is the line's byte: zp_+1 its
                                   ; page, Y its offset)
        ldx mx                     ; from the top, if above the floor
        cpx flr1
        bcs s2_d
        ldy kb
        jmp s2_c
s2_d:   jmp c_np
s2_c:   txa                        ; line X: bpos2 the mask past the
                                   ; transitions at or above it
        cmp TRL,y
        bcc s2_e
:       lda TRB,y
        sta bpos2
        iny
        txa
        cmp TRL,y
        bcs :-
s2_e:   sty kb
        lda TRL,y                  ; the stretch ends (tj) at the next
                                   ; transition or the floor
        cmp flr1
        bcc :+
        lda flr1
:       sta tj
        lda bpos2
        beq s2_n                   ; (no pixel left of the rung: no stores)
        jmp s2_l
s2_n:   ldx tj                     ; on from the stretch's end
        cpx flr1
        bcs s2_x
        ldy kb
        jmp s2_c
s2_x:   jmp c_np
s2_l:   lda LAHSB0,x               ; lines X .. tj-1: L into the mask's pixels
                                   ; (page: sethalf's)
        sta zp_+1
        txa
        and #7
        ora coff                   ; Y: the line in its row | coff
        tay
        txa
        lsr a
        bcs s2_o
s2_v:   lda (zp_),y                ; an even line
        eor le
        and bpos2
        eor (zp_),y
        sta (zp_),y
        iny
        inx
        cpx tj
        beq s2_m
s2_o:   lda (zp_),y                ; an odd line (a row's last: the row test
                                   ; follows)
        eor lo2
        and bpos2
        eor (zp_),y
        sta (zp_),y
        iny
        inx
        cpx tj
        beq s2_m
        txa
        and #7
        bne s2_v
        inc zp_+1                  ; the next character row: two pages on, Y
                                   ; back to the column
        inc zp_+1
        ldy coff
        jmp s2_v
s2_m:   jmp s2_n
        .popseg
.endif
