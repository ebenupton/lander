; ============================================================================
; game.s -- the game (bank 5, from $A100; .included by land.s, segment B5GAME):
; Lander's flight over LAND's landscape.  ref/lander/NOTES.md has Lander's
; model; this is it at a 25Hz step (each frame runs a step for every two
; vertical syncs since the last), scaled to LAND's units.
;
; Controls: a virtual mouse (K or up, M or down: forward and back; Z or left,
; X or right: left and right), whose offset is the ship's target attitude as
; Lander's mouse: its distance the pitch, its direction the way the thrust
; pushes; SPACE full thrust, SHIFT hover.  Fuel burns while thrusting; landing
; slowly on the pad (tiles 0..PADN-1 in x and z; Lander's 8) refuels.  Touching the
; ground anywhere else, or the pad too fast, crashes: a burst of dots, then the
; ship back on the pad.
;
; Units: positions 24 bits, 65536 a tile (x, z: the tile byte the map's, mod
; 64; y up, its height units 4096 each: LAND's 16 a tile); velocities 16 bits,
; 16384 a tile a step.
;
; The camera: Lander's, at the ship's x, ZSHIP (13) tiles behind it in z (LAND's camera
; point is the ship less 128 in x, ZSHIP tiles in z); its height Lander's rule
; (min(ship, 0): it follows the ship up) within what the strips allow: CAMH
; (6 tiles) above the ground under the ship, or more to keep the ship KOFF
; units below it (so the ship stays at line ~90 on screen as it climbs), at
; most EMAX more (CAME: LAND's y's within a byte).  The ship's ceiling is
; height YTOP (the camera can follow it all the way).
;
; The screen's top 64 lines are the game's (LAND draws from YSKY, 64): the
; FUEL (a bar, row 0), the frame rate (row 2: F toggles it, LAND's readout); the
; map (64 x 64 pixels, a tile each, the pad in the middle) at the top right, the
; ship a 2 x 2 magenta dot on it.
; ============================================================================

GSHK    = $07DB                    ; the ship for bank 6's B6_SHIP (B6_KEYS copies
GSHP    = $07DC                    ; these four into its own): direction, pitch,
GSHX    = $07DD                    ; centre
GSHY    = $07DE
GSHV    = $07DF                    ; drawn (0: crashed)
GLY5    = $BE00                    ; the labels' letters (LANDS's glyphs5): FUELANDCRSH

g0      = $8E                      ; (zero page: the ship's scratch, free between parts)
g1      = $90
gt0     = $92
gt1     = $93
gt2     = $94
gt3     = $95
gt4     = $96
gt5     = $97
tsg     = $98                      ; (gpost's: this screen's TOPS, BOTS)
bsg     = $9A

SVIA_ORB = $FE40
SVIA_DDRA = $FE43
SVIA_ORA_NH = $FE4F

MSTEP   = 2                        ; the virtual mouse: a step a key a game step, to
MMAX    = 63                       ; at most this either way
GRAV    = 192                      ; Lander's gravity (&30000: 0.0117 tiles a step^2)
THRS    = 3                        ; full thrust: THX.. << THRS (1016: 0.062, Lander's)
HOVS    = 1                        ; hover: << HOVS (Lander's quarter)
LANDV   = 2048                     ; Lander's LANDING_SPEED: |gvx| + |gvy| + |gvz| below
UNDER   = 6                        ; Lander's UNDERCARRIAGE_Y (0.39 tiles), height units
YTOP    = 63                       ; the ship's ceiling, height units
KOFF    = 79                       ; the camera this far above the ship, or more
FUEL0   = 3413                     ; Lander's fuel: at the start; most (refuelling)
FUELMX  = 5120
REFUEL  = 32                       ; on the pad, a step
CRASHT  = 50                       ; steps the crash lasts
NPART   = 10                       ; dots
SNTH    = $E6                      ; the engine: white noise, the low rate
SATF    = 2                        ; its attenuation: full thrust, hover
SATH    = 7
SNCR    = $E7                      ; the crash: white noise at tone 2's rate,
SCRN    = $180                     ; this (4MHz / 32 / SCRN: 650 shifts a second)
PGRAV   = 48                       ; a dot's gravity (height units / 256 a step^2)
PADX    = PADN/2                   ; the pad's middle: the start
FUELR   = 0                        ; FUEL's row (lines 0..7), its bar's lines and
FBL     = 2                        ; columns (bytes 10..29: 80 pixels, fuel >> 6)
FBC     = 10

        .segment "B5GAME"
        .assert * = $A100, error, "the game's entries at $A100"
        jmp ginit                  ; G_INIT
        jmp gstep                  ; G_STEP
        jmp gpost                  ; G_POST

; ---------------------------------------------------------------- init
; (after LAND's init: the screens black) The map and labels on both screens;
; the counts; the ship on the pad.
ginit:  lda #$30
        jsr gscr
        lda #$58
        jsr gscr
        lda #0
        sta nland
        sta ncrash
        sta gmx
        sta gmz
        sta vacc
        lda #$FF
        sta mkl
        sta mkl+1
        sta fdr
        sta fdr+1
        sta dl
        sta dl+1
        sta dc
        sta dc+1
        lda #$5A
        sta rnd
        ldx #NPART-1
        lda #0
:       sta plife,x
        dex
        bpl :-
        lda vcount
        sta vlastg
        ldx #SININ-1               ; the sound chip: all quiet, tone 2 the
:       lda SINI,x                 ; crash noise's clock
        jsr psg
        dex
        bpl :-
        lda #$FF
        sta sctl
        sta satt
        jsr spawn
        jmp gout
SINI:   .byte $18, $C0|SCRN & 15   ; (written last first) tone 2: SCRN
        .byte $FF, $DF, $BF, $9F   ; the four channels silent
SININ   = * - SINI

; Screen A's top: the map (MAPI) at columns 48..63, lines 0..63; the labels.
gscr:   sta gt4
        lda #<MAPI
        sta g1
        lda #>MAPI
        sta g1+1
        ldx #0                     ; (the line)
@l:     txa
        and #7
        ora #$80                   ; (+ 48 * 8 = $180)
        sta g0
        txa
        lsr a
        lsr a
        and #$FE
        sec                        ; (+ 1)
        adc gt4
        sta g0+1
        ldy #0
:       sty gt0
        lda (g1),y
        pha
        tya
        asl a
        asl a
        asl a
        tay
        pla
        sta (g0),y
        ldy gt0
        iny
        cpy #16
        bne :-
        lda g1
        clc
        adc #16
        sta g1
        bcc :+
        inc g1+1
:       inx
        cpx #64
        bne @l
        lda gt4                    ; the labels
        sta scrg
        ldx #0
@t:     lda LABT,x
        bmi @td
        sta gt2                    ; (row)
        lda LABT+1,x
        sta gt3                    ; (column)
        inx
        inx
:       lda LABT,x
        bmi :+
        jsr putl
        inc gt3
        inx
        bne :-
:       inx
        bne @t
@td:    rts
LABT:   .byte FUELR, 0, 0, 1, 2, 3, $FF                ; FUEL
        .byte $FF

; Letter A (GLY5) at row gt2, column gt3 (8 pixels) of screen scrg.
putl:   asl a
        asl a
        asl a
        asl a
        clc
        adc #<GLY5
        sta g1
        lda #>GLY5
        adc #0
        sta g1+1
        jmp putc
; Digit A (LAND's GLY) likewise.
putd:   asl a
        asl a
        asl a
        asl a
        sta g1                     ; (GLY: page-aligned)
        lda #>GLY
        sta g1+1
putc:   lda gt3                    ; 16 bytes: (g1) to row gt2, column gt3
        asl a
        asl a
        asl a
        asl a
        sta g0
        lda gt2
        asl a
        adc scrg
        sta g0+1
        ldy #15
:       lda (g1),y
        sta (g0),y
        dey
        bpl :-
        rts

; The ship on the pad, still, landed, fuelled.
spawn:  lda #0
        sta gmx                    ; (the mouse back in the middle)
        sta gmz
        sta sx
        sta sx+1
        sta sz
        sta sz+1
        sta sy
        sta gvx
        sta gvx+1
        sta gvy
        sta gvy+1
        sta gvz
        sta gvz+1
        sta ctim
        sta gp
        lda #PADX
        sta sx+2
        sta sz+2
        lda #(PADH+UNDER)<<4 & 255 ; y: (PADH + UNDER) units
        sta sy+1
        lda #(PADH+UNDER)>>4
        sta sy+2
        lda #24                    ; (facing away)
        sta gk
        lda #<FUEL0
        sta fuel
        lda #>FUEL0
        sta fuel+1
        lda #1
        sta landed
        sta GSHV
        rts

; ---------------------------------------------------------------- step
; Before projecting: the keys; a step for each two vertical syncs since the
; last frame (at most 6); then the camera and the ship for LAND and bank 6.
gstep:  jsr keys
        jsr snd                    ; (last frame's thrust or crash)
        lda vcount
        sec
        sbc vlastg
        clc
        adc vacc
        ldx vcount
        stx vlastg
        tax
        and #1
        sta vacc
        txa
        lsr a
        cmp #7
        bcc :+
        lda #6
:       sta nstep
        beq gout
:       jsr step
        dec nstep
        bne :-
        ; fall into gout
; The camera from the ship: x less 128 (1/256 tiles), z less 15 tiles; CAME;
; the ship's place on the screen.
gout:   lda sx+1                   ; camera x (8.8): ship's less 128
        sec
        sbc #128
        sta gt0
        lda sx+2
        sbc #0
        and #63
        sta cxt
        lda gt0
        lsr a
        lsr a
        lsr a
        lsr a
        sta cxs
        lda sz+2                   ; z: less ZSHIP tiles
        sec
        sbc #ZSHIP
        and #63
        sta czt
        lda sz+1
        lsr a
        lsr a
        lsr a
        lsr a
        sta czs
        jsr units                  ; (su: the ship's height, units 8.8)
        lda su+1                   ; above the ground under it: rel (signed)
        sec
        sbc HGV
        sta gt0
        sec                        ; CAME: rel - (KOFF - CAMH), 0..EMAX
        sbc #CAMH-KOFF
        bvc :+
        eor #$80
:       bpl :+
        lda #0
:       cmp #EMAX+1
        bcc :+
        lda #EMAX
:       sta CAME
        clc                        ; the ship's line: HORIZON + SHYT (camera - ship),
        adc #CAMH                  ; the camera CAMH + CAME above the ground (d R / 16,
        sec                        ; R the landscape's at ZSHIP)
        sbc gt0
        tax
        lda SHYT,x
        clc
        adc #HORIZON
        cmp #YSKY+18
        bcs :+
        lda #YSKY+18
:       cmp #YGND-18
        bcc :+
        lda #YGND-18
:       sta GSHY
        lda #128
        sta GSHX
        lda gk
        sta GSHK
        lda gp
        sta GSHP
        rts

; su: the ship's height in units, 8.8 (sy >> 4).
units:  lda sy                     ; (X kept)
        sta su
        lda sy+1
        sta su+1
        lda sy+2
        ldy #4
:       lsr a
        ror su+1
        ror su
        dey
        bne :-
        rts

; ---------------------------------------------------------------- keys
.macro KEYB code, bit
        .local no
        lda #code
        sta SVIA_ORA_NH
        lda SVIA_ORA_NH            ; (bit 7: pressed)
        bpl no
        lda gkb
        ora #bit
        sta gkb
no:
.endmacro
keys:   lda #0
        sta gkb
        sei
        lda #$7F                   ; bits 0-6 out: the key to test
        sta SVIA_DDRA
        lda #3                     ; keyboard auto-scan off
        sta SVIA_ORB
        KEYB $61, 1                ; Z, left: mouse left
        KEYB $19, 1
        KEYB $42, 2                ; X, right
        KEYB $79, 2
        KEYB $46, 4                ; K, up: forward
        KEYB $39, 4
        KEYB $65, 8                ; M, down: back
        KEYB $29, 8
        KEYB $62, 16               ; SPACE: thrust
        KEYB $00, 32               ; SHIFT: hover
        KEYB $43, 64               ; F: the frame rate on / off
        lda #$0B                   ; and on
        sta SVIA_ORB
        cli
        lda gkb                    ; (F: toggles as it goes down)
        and #64
        cmp fkey
        beq :+
        sta fkey
        tax
        beq :+
        lda fpson
        eor #1
        sta fpson
:       rts

; ---------------------------------------------------------------- sound
; Zarch's two (Lander has none): the engine a low white-noise roar while
; thrusting (hover quieter), the crash a deeper rumble dying away.  The noise
; channel only, the SN76489 written directly (through the system VIA's port A)
; and only when what it should play changes: nothing most frames.
snd:    lda ctim
        beq @t
        lda #CRASHT                ; crashed: SNCR, louder the newer
        sec
        sbc ctim
        lsr a
        lsr a
        tax
        lda #SNCR
        bne @c
@t:     ldx #15                    ; (silent)
        lda thr
        beq @v
        ldx #SATF                  ; full thrust
        lsr a
        bcs :+
        ldx #SATH                  ; hover
:       lda #SNTH
@c:     cmp sctl
        beq @v
        sta sctl
        jsr psg
@v:     txa                        ; the noise channel's attenuation
        ora #$F0
        cmp satt
        beq :+
        sta satt
        jmp psg
:       rts
; A to the sound chip (X kept).
psg:    sei
        ldy #$FF
        sty SVIA_DDRA
        sta SVIA_ORA_NH
        lda #0                     ; (the latch's 0: the chip's write enable, low)
        sta SVIA_ORB
        ldy #3                     ; (8us)
:       dey
        bne :-
        lda #8
        sta SVIA_ORB
        cli
        rts

; ---------------------------------------------------------------- a step
step:   lda gkb                     ; the virtual mouse
        lsr a
        bcc :+
        ldx #gmx-gmx
        jsr mdec
:       lda gkb
        and #2
        beq :+
        ldx #gmx-gmx
        jsr minc
:       lda gkb
        and #4
        beq :+
        ldx #gmz-gmx
        jsr minc
:       lda gkb
        and #8
        beq :+
        ldx #gmz-gmx
        jsr mdec
:       lda ctim                   ; crashed: the dots only, then the pad
        beq @fly
        dec ctim
        bne :+
        jsr spawn
:       jmp parts
@fly:   jsr attit
        lda gkb                     ; thrust (none without fuel)
        lsr a
        lsr a
        lsr a
        lsr a
        and #3                     ; (1 full, 2 hover)
        ldx fuel
        bne :+
        ldx fuel+1
        bne :+
        lda #0
:       sta thr
        cmp #0
        beq :+
        lda #0                     ; (thrust: off the ground)
        sta landed
:       ldx #0                     ; drag: each v less v >> 6
@dg:
        ldy #6                     ; (gt1:gt0 = v >> 6, arithmetic)
        lda gvx+1,x
        sta gt1
        lda gvx,x
        sta gt0
:       lda gt1
        cmp #$80
        ror gt1
        ror gt0
        dey
        bne :-
        lda gvx,x
        sec
        sbc gt0
        sta gvx,x
        lda gvx+1,x
        sbc gt1
        sta gvx+1,x
        inx
        inx
        cpx #6
        bne @dg
        lda thr                    ; thrust: THX, THY, THZ for (gp, gk), << THRS
        beq @nt                    ; (full) or HOVS (hover), fuel 4 or 2 a step
        lsr a
        lda #THRS
        ldy #4
        bcs :+
        lda #HOVS
        ldy #2
:       sta gt5
        sty gt4
        lda fuel
        sec
        sbc gt4
        sta fuel
        lda fuel+1
        sbc #0
        sta fuel+1
        bcs :+
        lda #0
        sta fuel
        sta fuel+1
:       lda gp
        asl a
        asl a
        asl a
        asl a
        asl a
        ora gk
        tay
        lda THX,y
        ldx #gvx-gvx
        jsr vadd
        lda THZ,y
        ldx #gvz-gvx
        jsr vadd
        ldy gp
        lda THY,y
        ldx #gvy-gvx
        jsr vadd
        jsr emit
@nt:    lda landed                 ; landed: still, refuelling
        beq @mv
        lda #0
        ldx #5
:       sta gvx,x
        dex
        bpl :-
        lda fuel
        clc
        adc #REFUEL
        sta gt0
        lda fuel+1
        adc #0
        cmp #>FUELMX
        bcc :+
        lda #>FUELMX
        ldx #<FUELMX
        stx gt0
:       sta fuel+1
        lda gt0
        sta fuel
        jmp parts
@mv:    lda gvy                     ; gravity
        sec
        sbc #<GRAV
        sta gvy
        lda gvy+1
        sbc #>GRAV
        sta gvy+1
        ldx #gvx-gvx                 ; move: each position += 4 v
        ldy #sx-sx
        jsr pmove
        ldx #gvz-gvx
        ldy #sz-sx
        jsr pmove
        ldx #gvy-gvx
        ldy #sy-sx
        jsr pmove
        lda sy+2                   ; below 0: the ground
        bmi @gnd
        jsr units                  ; the ground: the ship below the ground under
        lda su+1                   ; it (HGV) + UNDER
        sec
        sbc HGV
        bcc @gnd
        cmp #UNDER
        bcs @up
@gnd:   lda sx+2                   ; on the pad, slowly: landed
        and #63
        cmp #PADN
        bcs @crash
        lda sz+2
        and #63
        cmp #PADN
        bcs @crash
        jsr speed
        bcs @crash
        lda #1
        sta landed
        lda HGV                    ; on it: y (HGV + UNDER) units
        clc
        adc #UNDER
        sta gt0
        asl a
        asl a
        asl a
        asl a
        sta sy+1
        lda gt0
        lsr a
        lsr a
        lsr a
        lsr a
        sta sy+2
        lda #0
        sta sy
        ldx #5
:       sta gvx,x
        dex
        bpl :-
        sei
        sed
        lda nland
        clc
        adc #1
        sta nland
        cld
        cli
        jmp parts
@crash: lda #CRASHT
        sta ctim
        lda #0
        sta GSHV
        sei
        sed
        lda ncrash
        clc
        adc #1
        sta ncrash
        cld
        cli
        jsr burst
        jmp parts
@up:    lda sy+1                   ; the ceiling: YTOP units
        cmp #(YTOP<<4)&255
        lda sy+2
        sbc #YTOP>>4
        bcc :+
        lda #YTOP>>4
        sta sy+2
        lda #(YTOP<<4)&255
        sta sy+1
        lda #0
        sta sy
        lda gvy+1
        bmi :+
        lda #0
        sta gvy
        sta gvy+1
:       jmp parts

; The virtual mouse (gmx or gmz: X) a step either way, within MMAX.
minc:   lda gmx,x
        clc
        adc #MSTEP
        cmp #MMAX+1
        bmi :+
        lda #MMAX
:       sta gmx,x
        rts
mdec:   lda gmx,x
        sec
        sbc #MSTEP
        cmp #<-MMAX
        bpl :+
        lda #<-MMAX
:       sta gmx,x
        rts

; The ship's attitude towards the mouse's: Lander's halving (at least a step).
attit:  lda gmx                     ; |gmx| >> 2, |gmz| >> 2: ATQ, MAGT's index
        bpl :+
        eor #$FF
        clc
        adc #1
:       lsr a
        lsr a
        asl a
        asl a
        asl a
        asl a
        sta gt0
        lda gmz
        bpl :+
        eor #$FF
        clc
        adc #1
:       lsr a
        lsr a
        ora gt0
        tay
        lda MAGT,y                 ; the pitch: a step towards
        cmp gp
        beq :++
        bcc :+
        inc gp
        bcs :++
:       dec gp
:       lda ATQ,y                  ; the angle (32nds, from +x towards +z):
        ldx gmx                     ; folded by the quadrant
        bpl :+
        eor #$FF                   ; (gmx < 0: 16 - a)
        sec
        adc #16
:       ldx gmz
        bpl :+
        eor #$FF                   ; (gmz < 0: - that)
        clc
        adc #1
:       eor #$FF                   ; the direction: - angle (k 8 faces -z)
        clc
        adc #1
        and #31
        sec                        ; the shortest way, half of it (at least 1)
        sbc gk
        and #31
        beq @d
        cmp #16
        bcs @n
        lsr a
        adc #0
        clc
        adc gk
        and #31
        sta gk
        rts
@n:     eor #31                    ; (32 - d - 1)
        lsr a
        adc #0
        sta gt0
        lda gk
        sec
        sbc gt0
        and #31
        sta gk
@d:     rts

; v (X: gvx, gvy or gvz's offset) += A (signed) << gt5.
vadd:   sta gt0
        lda #0
        bit gt0
        bpl :+
        lda #$FF
:       sta gt1
        lda gt5
        sty gt2
        tay
        beq :++
:       asl gt0
        rol gt1
        dey
        bne :-
:       ldy gt2
        lda gvx,x
        clc
        adc gt0
        sta gvx,x
        lda gvx+1,x
        adc gt1
        sta gvx+1,x
        rts

; Position (Y: sx, sy or sz's offset) += 4 v (X: its v's offset), 24 bits.
pmove:  lda gvx,x
        sta gt0
        lda gvx+1,x
        sta gt1
        lda #0
        bit gt1
        bpl :+
        lda #$FF
:       sta gt2
        asl gt0
        rol gt1
        rol gt2
        asl gt0
        rol gt1
        rol gt2
        lda sx,y
        clc
        adc gt0
        sta sx,y
        lda sx+1,y
        adc gt1
        sta sx+1,y
        lda sx+2,y
        adc gt2
        sta sx+2,y
        rts

; C clear if |gvx| + |gvy| + |gvz| < LANDV.
speed:  lda #0
        sta gt2
        sta gt3
        ldx #0
@a:     lda gvx,x
        ldy gvx+1,x
        bpl :+
        eor #$FF
        clc
        adc #1
        pha
        tya
        eor #$FF
        adc #0
        tay
        pla
:       clc
        adc gt2
        sta gt2
        tya
        adc gt3
        sta gt3
        inx
        inx
        cpx #6
        bne @a
        lda gt2
        cmp #<LANDV
        lda gt3
        sbc #>LANDV
        rts

; ---------------------------------------------------------------- dots
rand:   lda rnd
        asl a
        bcc :+
        eor #$1D
:       sta rnd
        rts

; A dot from the exhaust: the ship's place, a little below; its velocity the
; ship's less the thrust's way, jittered.
emit:   ldx pnext
        inx
        cpx #NPART
        bcc :+
        ldx #0
:       stx pnext
        jsr dot0
        jsr rand
        and #7
        adc #8
        sta plife,x
        lda gp                     ; the exhaust: - thrust / 2 (x, z), - 8 thrust (y)
        asl a
        asl a
        asl a
        asl a
        asl a
        ora gk
        tay
        lda THX,y
        jsr exh
        sta gt0                    ; (x)
        lda THZ,y
        jsr exh
        sta gt1
        jsr rand                   ; jitter, + the ship's (v >> 6)
        and #31
        sec
        sbc #16
        clc
        adc gt0
        jsr sxadd
        sta pvx,x
        tya
        sta pvxh,x
        ldy #gvx-gvx
        jsr vsh6
        lda pvx,x
        clc
        adc gt2
        sta pvx,x
        lda pvxh,x
        adc gt3
        sta pvxh,x
        jsr rand
        and #31
        sec
        sbc #16
        clc
        adc gt1
        jsr sxadd
        sta pvz,x
        tya
        sta pvzh,x
        ldy #gvz-gvx
        jsr vsh6
        lda pvz,x
        clc
        adc gt2
        sta pvz,x
        lda pvzh,x
        adc gt3
        sta pvzh,x
        ldy gp                     ; y: - THY * 8, + the ship's (gvy / 4)
        lda THY,y
        eor #$FF
        sta gt0
        lda #$FF
        sta gt1
        asl gt0
        rol gt1
        asl gt0
        rol gt1
        asl gt0
        rol gt1
        lda gvy+1
        cmp #$80
        ror a
        sta gt3
        lda gvy
        ror a
        sta gt2
        lda gt3
        cmp #$80
        ror gt3
        ror gt2
        lda gt0
        clc
        adc gt2
        sta pvy,x
        lda gt1
        adc gt3
        sta pvyh,x
        rts
; gt3:gt2 = v (Y: its offset) >> 6, arithmetic (X kept).
vsh6:   lda gvx,y
        sta gt2
        lda gvx+1,y
        sta gt3
        ldy #6
:       lda gt3
        cmp #$80
        ror gt3
        ror gt2
        dey
        bne :-
        rts
exh:    eor #$FF                   ; - A / 2 (signed)
        clc
        adc #1
        cmp #$80
        ror a
        rts
; A (signed) sign-extended into Y:A.
sxadd:  ldy #0
        cmp #$80
        bcc :+
        dey
:       rts

; Dot X at the ship: x, z (8.8 tiles), y (units 8.8) less 6 units.
dot0:   lda sx+1
        sta ppx,x
        lda sx+2
        sta ppxh,x
        lda sz+1
        sta ppz,x
        lda sz+2
        sta ppzh,x
        jsr units
        lda su
        sta ppy,x
        lda su+1
        sec
        sbc #6
        sta ppyh,x
        rts

; The crash: every dot from the ship, every way.
burst:  ldx #NPART-1
@b:     jsr dot0
        jsr rand
        and #15
        adc #20
        sta plife,x
        jsr rand
        and #127
        sec
        sbc #64
        jsr sxadd
        sta pvx,x
        tya
        sta pvxh,x
        jsr rand
        and #127
        sec
        sbc #64
        jsr sxadd
        sta pvz,x
        tya
        sta pvzh,x
        jsr rand
        sta pvy,x
        and #3
        sta pvyh,x
        dex
        bpl @b
        rts

; Each live dot a step: moved, gravity.
parts:  ldx #NPART-1
@p:     lda plife,x
        beq @n
        dec plife,x
        lda ppx,x
        clc
        adc pvx,x
        sta ppx,x
        lda ppxh,x
        adc pvxh,x
        sta ppxh,x
        lda ppz,x
        clc
        adc pvz,x
        sta ppz,x
        lda ppzh,x
        adc pvzh,x
        sta ppzh,x
        lda ppy,x
        clc
        adc pvy,x
        sta ppy,x
        lda ppyh,x
        adc pvyh,x
        sta ppyh,x
        lda pvy,x
        sec
        sbc #PGRAV
        sta pvy,x
        bcs @n
        dec pvyh,x
@n:     dex
        bpl @p
        rts

; ---------------------------------------------------------------- post
; After the ship: the dots (each a pixel, the column's TOPS, BOTS widened over
; it so the strips take it off), the map's dot, the status.
gpost:  lda scrb
        sta scrg
        ldx back                   ; this screen's TOPS, BOTS
        ldy sidx,x
        lda setTl,y
        sta tsg
        lda setTh,y
        sta tsg+1
        lda setBl,y
        sta bsg
        lda setBh,y
        sta bsg+1
        jsr units
        ldx #NPART-1
@d:     lda plife,x
        beq @n
        jsr pdraw
@n:     dex
        bpl @d
        jsr marker
        jmp status

; Dot X: x 128 + (its x less the ship's) * 16, y the ship's + its height under
; the ship's (a unit a line) - its z beyond the ship's * 4.
pdraw:  lda ppx,x                  ; dx (8.8)
        sec
        sbc sx+1
        sta gt0
        lda ppxh,x
        sbc sx+2
        sta gt1                    ; (|dx| < 8 tiles: then >> 4, + 128)
        clc
        adc #8
        cmp #16
        bcc :+
        jmp @o
:       ldy #4
:       lda gt1
        cmp #$80
        ror gt1
        ror gt0
        dey
        bne :-
        lda gt0
        eor #$80
        sta gt2                    ; (screen x)
        lda su                     ; dy: the ship's height less its (units 8.8)
        sec
        sbc ppy,x
        lda su+1
        sbc ppyh,x                 ; (lines: whole units, signed)
        sta gt3
        lda ppz,x                  ; dz (8.8) >> 6: lines up
        sec
        sbc sz+1
        sta gt0
        lda ppzh,x
        sbc sz+2
        asl gt0
        rol a
        asl gt0
        rol a
        sta gt1
        lda GSHY
        clc
        adc gt3
        sec
        sbc gt1
        cmp #YSKY
        bcc @o
        cmp #YGND+1
        bcs @o
        sta gt3                    ; (screen y)
        ; the byte: scrg + 2 (y >> 3), (y & 7) + 8 (x >> 2)
        and #7
        sta g0
        lda gt2
        and #$FC
        asl a
        php
        ora g0
        sta g0
        lda gt3
        lsr a
        lsr a
        and #$FE
        plp
        adc scrg
        sta g0+1
        lda gt2
        and #3
        tay
        lda PIXG,y
        sta gt4
        eor #$FF
        ldy #0
        and (g0),y
        sta gt5
        lda gt4                    ; yellow young, magenta old
        ldy plife,x
        cpy #6
        bcs :+
        and #$F0
:       ora gt5
        ldy #0
        sta (g0),y
        lda gt2                    ; the column's TOPS, BOTS over it
        lsr a
        lsr a
        tay
        lda gt3
        cmp (tsg),y
        bcs :+
        sta (tsg),y
:       cmp (bsg),y
        bcc @o
        sta (bsg),y
@o:     rts

; The ship's dot on the map: 2 x 2 pixels, magenta, on the four tiles nearest
; it, on both screens (each its own, put back from MAPI as it moves); none
; while crashed.
marker: ldx back
        lda #$FF                   ; (none)
        sta gt0
        lda GSHV
        beq @h
        lda sz+1                   ; the top line: MAPZ - z, less 1 if z's
        eor #$FF                   ; fraction >= 1/2 (gamegen's)
        asl a
        lda #MAPZ
        sbc sz+2
        and #63
        sta gt0
        lda sx+1                   ; the left pixel: x + MAPX - 1, + 1 if x's
        asl a                      ; fraction >= 1/2
        lda sx+2
        adc #MAPX-1
        and #63
        sta gt1
@h:     lda gt0
        cmp mkl,x
        bne :+
        lda gt1
        cmp mkp,x
        beq @r                     ; (unmoved)
:       lda mkl,x                  ; the old one off
        bmi :+
        sta mdl
        lda mkp,x
        sta mdp
        lda #0
        jsr mdot
:       ldx back                   ; the new one on
        lda gt1
        sta mkp,x
        sta mdp
        lda gt0
        sta mkl,x
        bmi @r
        sta mdl
        lda #$80
        jmp mdot
@r:     rts
; Pixels (mdp, mdl), the next right and the next down (round the map), magenta
; (A $80) or the map's (A 0).
mdot:   sta mdc
        jsr mpix
        inc mdp
        jsr mpix
        inc mdl
        jsr mpix
        dec mdp
        jsr mpix
        dec mdl
        rts
; Pixel mdp & 63 of the map's line mdl & 63 on screen scrg (as gscr's).
mpix:   lda mdl
        and #63
        sta gt2                    ; (line)
        and #7
        sta g0
        lda mdp
        and #63
        sta gt3                    ; (pixel)
        lsr a
        lsr a
        sta gt4                    ; (byte)
        asl a
        asl a
        asl a
        ora g0
        ora #$80                   ; (+ 48 * 8 = $180)
        sta g0
        lda gt2
        lsr a
        lsr a
        and #$FE
        sec                        ; (+ 1)
        adc scrg
        sta g0+1
        lda gt3
        and #3
        tay
        lda PIXG,y
        sta gt3                    ; (its bits)
        bit mdc
        bpl :+
        and #$F0                   ; magenta
        bne @w
:       lda gt2                    ; the map's: MAPI + 16 line + byte
        lsr a
        lsr a
        lsr a
        lsr a
        sta g1+1
        lda gt2
        asl a
        asl a
        asl a
        asl a
        ora gt4
        clc
        adc #<MAPI
        sta g1
        lda g1+1
        adc #>MAPI
        sta g1+1
        ldy #0
        lda (g1),y
        and gt3
@w:     sta gt5
        lda gt3
        eor #$FF
        ldy #0
        and (g0),y
        ora gt5
        sta (g0),y
        rts

; The fuel bar, on this screen if changed.
status: ldx back
        lda fuel+1                 ; the bar: fuel >> 6 pixels
        sta gt1
        lda fuel
        asl a
        rol gt1
        asl a
        rol gt1
        lda gt1
        cmp fdr,x
        beq @c
        sta fdr,x
        sta gt0                    ; (pixels left)
        lda #FBC*8+FBL             ; the bytes, left to right: 4 lines each
        sta g0
        lda scrg
        clc
        adc #FUELR*2
        sta g0+1
@b:     lda gt0
        cmp #4
        bcc :+
        lda #4
:       tay
        lda BARB,y
        ldy #3
:       sta (g0),y
        dey
        bpl :-
        lda gt0
        sec
        sbc #4
        bcs :+
        lda #0
:       sta gt0
        lda g0
        clc
        adc #8
        sta g0
        cmp #(FBC+20)*8+FBL
        bcc @b
@c:     rts
BARB:   .byte $00, $88, $CC, $EE, $FF
PIXG:   .byte $88, $44, $22, $11   ; a pixel's bits (LAND's PIXM is in bank 4)

; ---------------------------------------------------------------- state
gmx:     .byte 0                    ; the virtual mouse (signed)
gmz:     .byte 0
gkb:     .byte 0                    ; the keys held
gk:     .byte 0                    ; the ship's direction (0..31), pitch (0..7)
gp:     .byte 0
thr:    .byte 0                    ; this step's thrust (1 full, 2 hover)
landed: .byte 0
ctim:   .byte 0                    ; crashed: steps left
sx:     .res 3                     ; position: x, z, y (lo, mid, hi)
sz:     .res 3
sy:     .res 3
gvx:     .res 2                     ; velocity
gvy:     .res 2
gvz:     .res 2
su:     .res 2                     ; (units' height, 8.8)
fuel:   .res 2
fkey:   .byte 0                    ; (F held last time)
sctl:   .byte $FF                  ; (the noise channel as last written)
satt:   .byte $FF
nland:  .byte 0                    ; (BCD)
ncrash: .byte 0
vlastg: .byte 0
vacc:   .byte 0
nstep:  .byte 0
rnd:    .byte 0
scrg:   .byte 0
pnext:  .byte 0
plife:  .res NPART
ppx:    .res NPART
ppxh:   .res NPART
ppz:    .res NPART
ppzh:   .res NPART
ppy:    .res NPART
ppyh:   .res NPART
pvx:    .res NPART
pvxh:   .res NPART
pvz:    .res NPART
pvzh:   .res NPART
pvy:    .res NPART
pvyh:   .res NPART
mkl:    .res 2                     ; the map's dot, by screen: its line ($FF none),
mkp:    .res 2                     ; pixel
mdl:    .res 1                     ; (mdot's)
mdp:    .res 1
mdc:    .res 1
fdr:    .res 2                     ; the bar and counts drawn, by screen
dl:     .res 2
dc:     .res 2

        .include "gametab.inc"
        .assert * <= GLY5, error, "the game over GLY5"
