; game.s: Lander's flight over the land.  A step is a frame at 12.5 a second at
; most, taken as 1.25 of Lander's steps; velocities keep Lander's units (16384
; a tile a Lander step), positions 65536 a tile (y 4096 a height unit).  Each
; frame: gstep (keys, sound, a step of the model, the camera), then after the
; land gpre (the dots beyond the ship), the ship, and gpost (the nearer dots,
; the map's marker, the fuel gauge).
;
; Small routines fill the parity tables' page tails (segments T0 .. T4).

SVIA_ORB = $FE40                   ; the system VIA: the addressable latch
SVIA_DDRA = $FE43
SVIA_ORA_NH = $FE4F                ; port A without handshake: keys, sound

SPAWNK  = (24+12) & 31             ; the start: facing 135 degrees on, level
SPAWNP  = PFLAT
GRAV    = 240                      ; gravity a step (Lander's, times 1.25)
THRS    = 3                        ; thrust: the tables' << 3
LANDV   = 2048                     ; |gvx| + |gvy| + |gvz| to land below
UNDER   = 4                        ; the ship's centre above its underside
EOFF    = 60                       ; CAME from which the land may be off-screen
KOFF    = 79                       ; the camera's least height above the ship
CRASHT  = 40                       ; steps a crash lasts
PLIFE   = 19                       ; a dot's life, steps
SNTH    = $E6                      ; the engine: white noise, low
SATF    = 13                       ; its attenuation
SNCR    = $E7                      ; the crash: noise clocked by tone 2
PGRAV   = 60                       ; a dot's gravity
PADX    = PADN/2                   ; the pad's middle tile
FUELMX  = 5120                     ; a full tank
REFUEL  = 40                       ; fuel a step on the pad
BURN    = 5                        ; fuel a step of thrust
.ifdef SWR
FBC     = 10                       ; the gauge: byte columns FBC .. FBC+19 of
.else                              ; the panel's row 0 (32K: FBC .. FBC+9),
FBC     = 5                        ; lines FBL .. FBL+3
.endif
FBL     = 2

; ginit: the game's start (the loader's): every dot dead, the sound off, the
; ship on the pad, the camera.
        GSEG "BOOT"
.ifdef SWR
g_init: lda #SCR0                  ; both screens' panels; nothing drawn on
        jsr gscr                   ; them yet
        lda #SCR1
        jsr gscr
        lda #$FF
        sta mkl
        sta mkl+1
        sta fdr
        sta fdr+1
.else
ginit:  lda #$FF                   ; no marker yet
        sta mky
.endif
        lda #$5A                   ; rand's seed
        sta rnd
        ldx #NPART-1
        lda #0
:       sta plife,x
        dex
        bpl :-
        ldx #SININ-1
:       lda SINI,x
        jsr psg
        dex
        bpl :-
        lda #$FF                   ; (as written)
        sta sctl
        sta satt
        lda #128                   ; the ship's screen x, always
        sta GSHX
        jsr spawn
        jmp gout
SINI:   .byte $FF, $DF, $BF, $9F   ; every channel silent
SININ   = * - SINI
        GSEG "CODE"

; spawn: the ship on the pad, landed, level, the tank full.  Clobbers A, X.
spawn:  lda #0                     ; thr .. gvz zeroed
        ldx #gvz+1-thr
@z:     sta thr,x
        dex
        bpl @z
        lda #PADX
        sta sx+2
        sta sz+2
        lda #(PADH+UNDER)<<4 & 255
        sta sy+1
        .assert (PADH+UNDER)>>4 = 0, error, "spawn: sy+2 is 0"
        lda #SPAWNP
        sta gp
        lda #SPAWNK
        sta gk
        .assert SPAWNK = PADH, error, "spawn: gk and HGV share a load"
        sta HGV
        lda #<FUELMX
        sta fuel
        lda #>FUELMX
        sta fuel+1
        lda #1
        sta landed
        sta GSHV
        rts

; gstep: the frame's step; falls into gout.
.ifdef SWR
g_step:
.else
gstep:
.endif
        jsr keys
        jsr snd
        jsr step
; gout: the camera from the ship: cxt, cxs (x less half a tile), czt, czs
; (ZSHIP tiles behind), CAME (raised as the ship climbs), and the ship's line
; GSHY, direction GSHK and pitch GSHP.  Clobbers A, X, Y, gt0.
gout:   lda sx+1                   ; cxs = ((sx+1 - 128) & 255) >> 4
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #8
        eor #8
        sta cxs
        lda sx+2                   ; (C: the borrow's)
        sbc #0
        and #MAPN-1
        sta cxt
        lda sz+2
        sec
        sbc #ZSHIP
        and #MAPN-1
        sta czt
        lda sz+1
        lsr a
        lsr a
        lsr a
        lsr a
        sta czs
        jsr units
        lda sy+2                   ; the height above the ground, 0..255
        bmi gr_0
        cmp #16
        lda #$FF
        bcs gr_st
        lda su+1
        sec
        sbc HGV
        bcs gr_st
gr_0:   lda #0
gr_st:  sta gt0
        sec                        ; CAME = height - (CAMH - KOFF), 0..EMAX
        sbc #CAMH-KOFF
        bcs :+
        lda #0
:       cmp #EMAX+1
        bcc :+
        lda #EMAX
        sta CAME
        lda #KOFF
        bne gsy                    ; (always)
:       sta CAME
        clc                        ; the camera above the ship
        adc #CAMH
        sec
        sbc gt0
gsy:    tay
        lda GSHYT-KOFF,y
        sta GSHY
        lda gk
        sta GSHK
        lda gp
        sta GSHP
        rts
        .pushseg
        GSEG "TABLES"
GSHYT:                             ; the ship's line by the camera's height
        .repeat CAMH-KOFF+1, I
        .byte (((KOFF+I)*RSHIP+2048)>>12)+HORIZON
        .endrepeat
        .assert ((KOFF*RSHIP+2048)>>12) >= YSKY+14-HORIZON, error, "GSHYT: d = KOFF on the land"
        .assert ((CAMH*RSHIP+2048)>>12) <= YGND-16-HORIZON, error, "GSHYT: d = CAMH on the land"
        .popseg

; units: su = sy >> 4, the ship's height in units, 8.8.  X kept; clobbers A.
units:  lda sy+1
        lsr a
        lsr a
        lsr a
        lsr a
        sta su+1
        lda sy+2
        asl a
        asl a
        asl a
        asl a
        ora su+1
        sta su+1
        lda sy
        lsr a
        lsr a
        lsr a
        lsr a
        sta su
        lda sy+1
        asl a
        asl a
        asl a
        asl a
        ora su
        sta su
        rts

; keys: gkb: 1 Z, 2 X, 4 K, 8 M (or the cursor keys), 16 SPACE, 32 SHIFT, read
; from the keyboard with its scan off.  Clobbers A, X.
        .pushseg
        GSEG "T0"
keys:   lda #0
        sta gkb
        lda #$7F                   ; port A: bits 0-6 out, 7 in
        sta SVIA_DDRA
        lda #3                     ; the keyboard's scan off
        sta SVIA_ORB
        ldx #9
@k:     lda kcode,x
        sta SVIA_ORA_NH
        lda SVIA_ORA_NH
        bpl @n
        lda kbit,x
        ora gkb
        sta gkb
@n:     dex
        bpl @k
        lda #$0B                   ; and on again
        sta SVIA_ORB
        rts
        .popseg
        .pushseg
        GSEG "TABLES"
kcode:  .byte $00, $62, $29, $65, $39, $46, $79, $42, $19, $61
kbit:   .byte 32, 16, 8, 8, 4, 4, 2, 2, 1, 1
        .popseg

; snd: the noise channel, written only where it changes.  Crashed: the step's
; crack (tone 2's period, EXNL, EXNH; EXA) with SNCR; thrusting SNTH at SATF;
; else silent.  Clobbers A, X, Y.
snd:    lda ctim
        beq @t
        lda #CRASHT
        sec
        sbc ctim
        tax
        lda EXNL,x
        jsr psg
        lda EXNH,x
        jsr psg
        lda EXA,x
        tax
        lda #SNCR
        bne @c                     ; (always)
@t:     ldx #15
        lda thr
        beq @v
        ldx #SATF
        lda #SNTH
@c:     cmp sctl
        beq @v
        sta sctl
        jsr psg
@v:     txa
        ora #$F0
        cmp satt
        beq :+
        sta satt
        jmp psg
:       rts

        .pushseg
        GSEG "T3"
; psg: A to the sound chip (its write enable pulsed for 11us).  X kept;
; clobbers A, Y.
psg:    ldy #$FF
        sty SVIA_DDRA
        sta SVIA_ORA_NH
        iny
        sty SVIA_ORB
        ldy #3
:       dey
        bne :-
        lda #8
        sta SVIA_ORB
        rts
        .popseg

; step: a step of the model.  The attitude from the keys (held on the pad);
; crashed, the dots only and a new ship at the end; else thrust (none without
; fuel, from 16 tiles up, or with the land gone from the screen), drag,
; gravity and the move, then the ground: a landing on the pad, level and slow,
; or a crash.  Then the dots.  Clobbers A, X, Y, the overlay.
step:   lda landed
        bne @att
        ldy gkb
        tya
        lsr a
        bcc :+
        dec gk
:       lsr a
        bcc :+
        inc gk
:       lda gk
        and #NDIR-1
        sta gk
        tya
        and #4
        beq :+
        lda gp
        cmp #NPITCH-1
        bcs :+
        inc gp
:       tya
        and #8
        beq :+
        lda gp
        beq :+
        dec gp
:
@att:   lda ctim
        beq @fly
        dec ctim
        bne :+
        jsr spawn
:       jmp parts
@fly:   lda gkb                    ; thrust: SPACE or SHIFT
        and #$30
        beq :+
        lda #1
:       tay
        lda fuel
        ora fuel+1
        beq @off
        lda sy+2
        bmi :+
        cmp #16
        bcs @off
        lda CAME
        cmp #EOFF
        bcc :+
        jsr landoff
        bcc :+
@off:   ldy #0
:       tya
        sta thr
        beq :+
        dey                        ; off the ground
        sty landed
:       ldx #0                     ; drag: v -= (v >> 6) + (v >> 8)
@dg:    lda gvx,x
        sta gt0
        ldy #0
        lda gvx+1,x
        bpl :+
        dey
:       sty gt1
        asl gt0
        rol a
        rol gt1
        asl gt0
        rol a
        rol gt1
        clc
        adc gvx+1,x
        sta gt0
        tya
        adc gt1
        sta gt1
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
        lda thr                    ; thrust: fuel, velocity, a dot
        beq @nt
        lda fuel
        sec
        sbc #BURN
        sta fuel
        bcs :+
        dec fuel+1
        bpl :+
        lda #0
        sta fuel
        sta fuel+1
:       jsr throw
        lda tx
        ldx #gvx-gvx
        jsr tadd
        lda tz
        ldx #gvz-gvx
        jsr tadd
        ldy gp
        lda THY,y
        ldx #gvy-gvx
        jsr tadd
        jsr emit
@nt:    lda landed                 ; landed: still, refuelling
        beq @mv
        lda fuel
        clc
        adc #REFUEL
        tax
        lda fuel+1
        adc #0
        cmp #>FUELMX
        bcc :+
        lda #>FUELMX
        ldx #<FUELMX
:       sta fuel+1
        stx fuel
        lda #0
@still: ldx #5
:       sta gvx,x
        dex
        bpl :-
        jmp parts
        .assert (GRAV & 15) = 0 && GRAV > 0 && GRAV <= 2048, error, "step: -GRAV as a signed byte << 4"
@mv:    lda #<(-(GRAV >> 4))       ; gravity, then the move: 5 v each
        ldx #gvy-gvx
        ldy #4
        jsr vadd
        ldx #gvx-gvx
        ldy #sx-sx
        jsr pmove
        ldx #gvz-gvx
        ldy #sz-sx
        jsr pmove
        ldx #gvy-gvx
        ldy #sy-sx
        jsr pmove
        lda sy+2                   ; the ground: below y 0, or the centre
        bmi @gnd                   ; within UNDER of HGV
        cmp #16
        bcs @up
        jsr units
        lda su+1
        sec
        sbc HGV
        bcc @gnd
        cmp #UNDER
        bcs @up
@gnd:   ldx #sz-sx                 ; over the pad?
@pd:    lda sx+2,x
        and #MAPN-1
        cmp #PADN
        bcs @crash
        dex
        dex
        dex
        bpl @pd
        .assert sz-sx = 3, error, "step: sz 3 bytes after sx"
        lda gp                     ; within a pitch of level?
        sbc #PFLAT-2
        cmp #3
        bcs @crash
        jsr speed                  ; and slow enough?
        bcs @crash
        lda #1                     ; landed, on the ground
        sta landed
        lda HGV
        clc
        adc #UNDER
        tax
        asl a
        asl a
        asl a
        asl a
        sta sy+1
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        sta sy+2
        lda #0
        sta sy
        jmp @still
@crash: lda #CRASHT
        sta ctim
        lda #0
        sta GSHV
        jmp burst
@up:    jmp parts

        .pushseg
        GSEG "T2"
; landoff: C set if last frame's points are all below the land's lines.  Y
; kept; clobbers A, X.
landoff:
        tya
        pha
        .assert <PY = 0, error, "landoff: PY page-aligned"
        lda #<PY
        sta @p+1
        ldx nr
@r:     ldy np
        dey
@p:     lda PY,y                   ; (operand: the row)
        cmp #YGND+1
        bcc @v
        dey
        bpl @p
        lda @p+1                   ; (C set: + 16)
        adc #15
        sta @p+1
        dex
        bne @r
        pla
        tay
        sec
        rts
@v:     pla
        tay
        clc
        rts
        .popseg

        .pushseg
        GSEG "T3"
; throw: tx, tz = the thrust at pitch gp and direction gk, 127 a unit, from TQ
; (a quarter of Lander's: the rest by symmetry).  X kept; clobbers A, Y, gt0,
; gt1.
throw:  stx thxs
        lda gk
        jsr thc
        sta tx
        lda gk                     ; THZ(k) = THX(k + 8)
        clc
        adc #8
        jsr thc
        sta tz
        ldx thxs
        rts
; thc: THX for pitch gp and direction A.
thc:    and #31
        cmp #17
        bcc @a
        eor #$FF                   ; 32 - k
        adc #32
@a:     ldx #0                     ; X: the sign
        cmp #9
        bcc @b
        eor #$FF                   ; 16 - k, negated
        adc #16
        inx
@b:     sta gt0
        lda gp                     ; |gp - PFLAT|, negated below level
        sec
        sbc #PFLAT
        bcs @c
        eor #$FF
        adc #1
        inx
@c:     sta gt1
        asl a
        asl a
        asl a
        adc gt1
        adc gt0
        tay
        lda TQ,y
        cpx #1
        bne @d
        eor #$FF
        adc #0                     ; (C set: + 1)
@d:     rts
        .popseg

; tadd: v (X: its offset from gvx) += 1.25 (A << THRS).  vadd: v += A << Y.
; X kept; clobbers A, Y, gt0, gt1.
        .pushseg
        GSEG "T2"
        .assert THRS >= 3, error, "tadd: both shifts at least 1"
tadd:   pha
        ldy #THRS
        jsr vadd
        pla
        ldy #THRS-2
vadd:   sta gt0
        and #$80
        bpl :+
        lda #$FF
:       sta gt1
:       asl gt0
        rol gt1
        dey
        bne :-
        lda gvx,x
        clc
        adc gt0
        sta gvx,x
        lda gvx+1,x
        adc gt1
        sta gvx+1,x
        rts
        .popseg

; pmove: position (Y: its offset from sx) += 5 v (X: its velocity's).  X, Y
; kept; clobbers A, gt0..gt3.
        .pushseg
        GSEG "T1"
pmove:  lda gvx+1,x
        sta gt1
        bpl :+
        lda #$FF
        bne @sgn                   ; (always)
:       lda #0
@sgn:   sta gt2
        sta gt3
        lda gvx,x
        asl a
        rol gt1
        rol gt2
        asl a
        rol gt1
        rol gt2
        clc
        adc gvx,x
        sta gt0
        lda gt1
        adc gvx+1,x
        sta gt1
        lda gt2
        adc gt3
        sta gt2
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
        .popseg

; speed: C clear if |gvx| + |gvy| + |gvz| < LANDV.  Clobbers A, X, Y, gt2, gt3.
        .pushseg
        GSEG "T0"
speed:  lda #0
        sta gt2
        sta gt3
        ldx #gvz-gvx
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
        dex
        dex
        bpl @a
        .assert <LANDV = 0, error, "speed: LANDV's low byte 0"
        cmp #>LANDV
        rts
        .popseg

; rand: A = rnd, the next of an 8-bit LFSR.
        .pushseg
        GSEG "T0"
rand:   lda rnd
        asl a
        bcc :+
        eor #$1D
:       sta rnd
        rts
        .popseg

; The dots: NPART, each a life in steps, a position (x, z 8.8 tiles; y 8.8
; units) and a velocity, moving 1.25 v a step.  The exhaust launches one a
; step; a crash launches them all.

; emit: the next dot from the ship's underside, against the thrust with some
; jitter, plus the ship's velocity.  Clobbers A, X, Y, the overlay.
emit:   ldx pnext
        inx
        cpx #NPART
        bcc :+
        ldx #0
:       stx pnext
        jsr dot0
        lda #PLIFE
        sta plife,x
        jsr throw
        lda tx
        ldy #gvx-gvx
        jsr ejit
        sta pvx,x
        tya
        adc gt3
        sta pvxh,x
        lda tz
        ldy #gvz-gvx
        jsr ejit
        sta pvz,x
        tya
        adc gt3
        sta pvzh,x
        ldy gp                     ; y: -(THY + 1) << 3 + gvy / 4
        lda THY,y
        eor #$FF
        sta gt0
        lda #$FF
        asl gt0
        rol a
        asl gt0
        rol a
        asl gt0
        rol a
        sta gt1
        lda gvy
        sta gt2
        lda gvy+1
        cmp #$80
        ror a
        ror gt2
        cmp #$80
        ror a
        ror gt2
        sta gt3
        lda gt0
        clc
        adc gt2
        sta pvy,x
        lda gt1
        adc gt3
        sta pvyh,x
        rts

; ejit: -A / 2 + a jitter of -16..15 + v >> 6 (Y: v's offset from gvx).  Out:
; A the low byte, Y the high less gt3 and C.  X kept.
        .pushseg
        GSEG "T4"
ejit:   eor #$FF
        clc
        adc #1
        cmp #$80
        ror a
        sta gt0
        lda gvx,y
        sta gt2
        lda gvx+1,y
        ldy #6
:       cmp #$80
        ror a
        ror gt2
        dey
        bne :-
        sta gt3
        jsr rand
        and #31
        sec
        sbc #16
        clc
        adc gt0
        jsr sxadd
        clc
        adc gt2
        rts
; bjit: A = -64..63 at random, Y its sign; sxadd: Y = A's sign.  X kept.
bjit:   jsr rand
        and #127
        sec
        sbc #64
sxadd:  ldy #0
        cmp #$80
        bcc :+
        dey
:       rts
        .popseg

; dot0: dot X at the ship's underside.  X kept; clobbers A.
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
        sbc #UNDER
        sta ppyh,x
        rts

; burst: every dot from the ship, at the ground's height, flung out at
; random; falls into parts.
burst:  ldx #NPART-1
@b:     jsr dot0
        lda HGV
        sta ppyh,x
        lda #0
        sta ppy,x
        lda #PLIFE
        sta plife,x
        jsr bjit
        sta pvx,x
        tya
        sta pvxh,x
        jsr bjit
        sta pvz,x
        tya
        sta pvzh,x
        jsr rand
        sta pvy,x
        and #3
        sta pvyh,x
        dex
        bpl @b
; parts: each live dot a step: older, moved, falling; dead if its height
; leaves its byte.  Clobbers A, X, Y, gt0..gt2.
parts:  ldx #NPART-1
@p:     lda plife,x
        beq @n
        dec plife,x
        lda pvx,x
        ldy pvxh,x
        jsr q5
        lda ppx,x
        clc
        adc gt0
        sta ppx,x
        tya
        adc ppxh,x
        sta ppxh,x
        lda pvz,x
        ldy pvzh,x
        jsr q5
        lda ppz,x
        clc
        adc gt0
        sta ppz,x
        tya
        adc ppzh,x
        sta ppzh,x
        lda pvy,x
        ldy pvyh,x
        jsr q5
        lda ppy,x
        clc
        adc gt0
        sta ppy,x
        tya
        adc ppyh,x
        sta ppyh,x
        ror a                      ; out of range: C differs from the step's
        sty gt1                    ; sign
        eor gt1
        bpl :+
        lda #0
        sta plife,x
        beq @n                     ; (always)
:       lda pvy,x
        sec
        sbc #PGRAV
        sta pvy,x
        bcs @n
        dec pvyh,x
@n:     dex
        bpl @p
        rts

        .pushseg
        GSEG "T2"
; q5: Y:gt0 = 1.25 (Y:A), signed.  X kept; clobbers A, gt1, gt2.
q5:     sta gt2
        sty gt1
        cpy #$80
        ror gt1
        ror a
        cpy #$80
        ror gt1
        ror a
        clc
        adc gt2
        sta gt0
        tya
        adc gt1
        tay
        rts
        .popseg

; gpre: the dots beyond the ship.  gpost: those nearer, the marker and the
; gauge.  Each dot's column records are widened over it, so the strips that
; next draw this screen take it off.
.ifdef SWR
g_pre:
.else
gpre:
.endif
        jsr dset
        jsr units
        lda #0
        beq dots                   ; (always)
.ifdef SWR
g_post:
.else
gpost:
.endif
        jsr dset
        lda #$80
        jsr dots
        jsr marker
.ifdef SWR
        jmp status
.else
; status: the fuel gauge, fuel >> 7 pixels, redrawn when it changes.
status: lda fuel+1
        sta gt1
        lda fuel
        asl a
        rol gt1
        lda gt1
        cmp fdr
        beq @x
        sta fdr
        ldx #FBC*8
@b:     lda gt1                    ; the pixels left
        cmp #4
        bcc :+
        lda #4
:       tay
        lda BARB,y
        sta TOP+FBL,x
        sta TOP+FBL+1,x
        sta TOP+FBL+2,x
        sta TOP+FBL+3,x
        lda gt1
        sbc #4
        bcs :+
        lda #0
:       sta gt1
        txa
        clc
        adc #8
        tax
        cpx #(FBC+10)*8
        bcc @b
@x:     rts
        .assert FBC+10 <= 24, error, "status: the gauge left of the map"
        .pushseg
        GSEG "TABLES"
BARB:   .byte $00, $88, $CC, $EE, $FF   ; 0..4 pixels lit
        .popseg

.endif

; dset: scrg, tsg, bsg: the screen being drawn and its column records.
        .pushseg
        GSEG "T1"
dset:   lda scrb
        sta scrg
        ldx back
        ldy sidx,x
        lda setTl,y
        sta tsg
        lda setTh,y
        sta tsg+1
        lda setBl,y
        sta bsg
        lda setBh,y
        sta bsg+1
        rts
        .popseg

; dots: pdraw for each live dot beyond the ship (A 0) or nearer ($80); none
; from 16 tiles up.
dots:   sta dpass
        lda sy+2
        bmi :+
        cmp #16
        bcc :+
        rts
:       ldx #NPART-1
@d:     lda plife,x
        beq @n
        lda ppz,x
        cmp sz+1
        lda ppzh,x
        sbc sz+2
        eor dpass
        bmi @n
        jsr pdraw
@n:     dex
        bpl @d
        rts

; pdraw: dot X as a pixel: x = 128 + 16 dx, y = GSHY + dy - 4 dz (dx, dz
; tiles, dy units from the ship), on the land's lines; yellow, magenta in its
; last steps.  X kept; clobbers A, Y, g0, gt0..gt4.
pdraw:  lda ppx,x                  ; dx, off unless -8 <= dx < 8
        sec
        sbc sx+1
        sta gt0
        lda ppxh,x
        sbc sx+2
        clc
        adc #8
        cmp #16
        bcc :+
@o1:    jmp @o
:       asl a                      ; screen x
        asl a
        asl a
        asl a
        sta gt2
        lda gt0
        lsr a
        lsr a
        lsr a
        lsr a
        ora gt2
        sta gt2
        lda su                     ; dy, a signed byte
        cmp ppy,x
        lda su+1
        sbc ppyh,x
        sta gt3
        bcc :+
        bmi @o1
        bpl :++                    ; (always)
:       bpl @o1
:       lda ppz,x                  ; 4 dz
        sec
        sbc sz+1
        sta gt0
        lda ppzh,x
        sbc sz+2
        asl gt0
        rol a
        asl gt0
        rol a
        eor #$FF                   ; y
        sec
        adc gt3
        clc
        adc GSHY
        cmp #YSKY
        bcc @o
        cmp #YGND+1
        bcs @o
        sta gt3
        lsr a                      ; the byte: scrg + 2 (y >> 3), 8 (x >> 2) +
        lsr a                      ; (y & 7)
        and #$FE
        tay
        lda gt3
        and #7
        sta g0
        lda gt2
        and #$FC
        asl a
        ora g0
        sta g0
        tya
        adc scrg
        sta g0+1
        lda gt2                    ; the pixel
        and #3
        tay
        lda PIXM,y
        sta gt4
        ldy plife,x
        cpy #6
.ifdef MODE2
        lda #YELB
        bcs :+
        lda #MAGB
.else
        lda #$FF
        bcs :+
        lda #$F0
.endif
:       ldy #0
        eor (g0),y
        and gt4
        eor (g0),y
        sta (g0),y
        lda gt2                    ; the column's records widened
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

.ifndef SWR
; marker: the ship's dot on the map, two lines of one pixel (its two tiles
; across), magenta; the bytes under it kept (mkb) and put back when it moves.
        .assert <MAP = 0, error, "marker: MAP page-aligned"
marker: ldx #$FF                   ; (none while crashed)
        lda GSHV
        beq @h
        lda #MAPZ                  ; its line
        sec
        sbc sz+2
        and #62
        tax
        lda sx+2                   ; its pixel
        clc
        adc #MAPX
        and #MAPN-1
        lsr a
        sta gt0
@h:     cpx mky
        bne @mv
        lda gt0
        cmp mkt
        beq @r
@mv:    stx gt1
        ldx mky                    ; the old one's bytes back
        bmi @n
        lda mkb
        jsr @put
        inx
        lda mkb+1
        jsr @put
@n:     ldx gt1                    ; the new one
        stx mky
        bmi @r
        lda gt0
        sta mkt
        and #3
        tay
.ifdef MODE2
        lda PIX5,y
.else
        lda PIXM,y
.endif
        sta gt2
        and #$F0
        sta gt3
        jsr @mag
        sta mkb
        inx
        jsr @mag
        sta mkb+1
@r:     rts
@mag:   jsr mkad                   ; line X's byte, its pixel magenta: A the
        lda (g0),y                 ; byte as was
        pha
        ora gt2
        eor gt2
        ora gt3
        sta (g0),y
        pla
        rts
@put:   pha
        jsr mkad
        pla
        sta (g0),y
        rts
; mkad: (g0),y = the map's byte for line X, column mkt.  Clobbers A.
mkad:   txa
        and #$38
        asl a
        asl a
        asl a
        sta g0
        lda #>MAP
        adc #0
        sta g0+1
        lda mkt
        and #$1C
        asl a
        ora g0
        sta g0
        txa
        and #7
        tay
        rts
.endif
.ifdef SWR
; status: this screen's fuel gauge, fuel >> 6 pixels over byte columns FBC ..
; FBC+19 of lines FBL .. FBL+3, redrawn when it differs from what the screen
; shows (fdr).  Clobbers A, X, Y, g0, gt1.
status: lda fuel+1
        sta gt1
        lda fuel
        asl a
        rol gt1
        asl a
        rol gt1
        ldx back
        lda gt1
        cmp fdr,x
        beq @x
        sta fdr,x
        lda #FBC*8+FBL
        sta g0
        lda scrg
        sta g0+1
@b:     lda gt1                    ; the pixels left
        cmp #4
        bcc :+
        lda #4
:       tay
        lda BARB,y
        ldy #3
:       sta (g0),y
        dey
        bpl :-
        lda gt1
        sec
        sbc #4
        bcs :+
        lda #0
:       sta gt1
        lda g0
        clc
        adc #8
        sta g0
        cmp #(FBC+20)*8+FBL
        bcc @b
@x:     rts
        .assert FBC >= 8 && FBC+20 <= 48 && (FBC+20)*8+FBL < 256, error, "status: the gauge between FUEL and the map, in row 0's first page"

; gscr: screen A's panel: FUEL (FUELI) at row 0's first eight byte columns,
; the map (MAPI's 64 lines of 16 bytes) at byte columns 48..63 of character
; rows 0..7.  Clobbers A, X, Y, g0, g1, gt0.
gscr:   sta g0+1
        sta gt0
        lda #0
        sta g0
        ldy #63
:       lda FUELI,y
        sta (g0),y
        dey
        bpl :-
        lda #<MAPI
        sta g1
        lda #>MAPI
        sta g1+1
        ldx #0                     ; X: the map line
@l:     txa                        ; its first byte: the screen + $200 (line
        and #7                     ; >> 3) + $180 + (line & 7)
        ora #$80
        sta g0
        txa
        lsr a
        lsr a
        and #$FE
        sec
        adc gt0
        sta g0+1
        ldy #15
:       tya                        ; byte Y to column 48 + Y
        pha
        lda (g1),y
        pha
        tya
        asl a
        asl a
        asl a
        tay
        pla
        sta (g0),y
        pla
        tay
        dey
        bpl :-
        lda g1
        clc
        adc #16
        sta g1
        bcc :+
        inc g1+1
:       inx
        cpx #64
        bne @l
        rts

; marker: the ship's dot on this screen's map: 2 x 2 pixels, magenta, on the
; four tiles whose common corner is nearest the ship (gamegen's layout: tile x
; at pixel (x + MAPX) & 63, z at line (MAPZ - z) & 63); none while crashed.
; Each screen remembers its dot (mkl line, $FF none; mkp pixel); a dot that
; has moved is put back from MAPI first.  Clobbers A, X, Y, g0, g1, gt0..gt5.
marker: lda #$FF                   ; (no dot)
        sta gt0
        lda GSHV
        beq @h
        lda sz+1                   ; the top line: MAPZ - z's tile, one less if
        eor #$FF                   ; its fraction is 1/2 or more
        asl a
        lda #MAPZ
        sbc sz+2
        and #63
        sta gt0
        lda sx+1                   ; the left pixel: x's tile + MAPX - 1, plus
        asl a                      ; 1 if its fraction is 1/2 or more
        lda sx+2
        adc #MAPX-1
.ifdef MODE2
        and #62                    ; (both of a MODE 2 pixel's two)
.else
        and #63
.endif
        sta gt1
@h:     ldx back
        lda gt0
        cmp mkl,x
        bne :+
        lda gt1
        cmp mkp,x
        beq @r                     ; (unmoved on this screen)
:       lda mkl,x                  ; the old dot back to the map's pixels
        bmi :+
        sta mdl
        lda mkp,x
        sta mdp
        lda #0
        jsr mdot
:       ldx back                   ; the new one remembered and drawn
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
; mdot: the four pixels (mdp, mdl), (mdp+1, mdl), (mdp+1, mdl+1), (mdp,
; mdl+1), wrapping at the map's edges, magenta (A $80) or the map's own (A 0).
; Clobbers A, Y, g0, g1, gt2..gt5; mdp, mdl kept.
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
; mpix: pixel mdp & 63 of map line mdl & 63 on screen scrg: magenta (mdc bit
; 7) or MAPI's colour for it.  Clobbers A, Y, g0, g1, gt2..gt5.
mpix:   lda mdl
        and #63
        sta gt2                    ; (the line)
        and #7
        sta g0
        lda mdp
        and #63
        sta gt3                    ; (the pixel)
        lsr a
        lsr a
        sta gt4                    ; (its byte in the line, 0..15)
        asl a                      ; the screen byte: scrg + $200 (line >> 3)
        asl a                      ; + $180 + 8 byte + (line & 7)
        asl a
        ora g0
        ora #$80
        sta g0
        lda gt2
        lsr a
        lsr a
        and #$FE
        sec
        adc scrg
        sta g0+1
        lda gt3
        and #3
        tay
        lda PIXG,y
        sta gt3                    ; (the pixel's bits)
        bit mdc
        bpl :+
.ifdef MODE2
        and #MAGB
.else
        and #$F0
.endif
        bne @w
:       lda gt2                    ; MAPI + 16 line + byte, masked
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
@w:     sta gt5                    ; the pixel's bits replaced in the byte
        lda gt3
        eor #$FF
        ldy #0
        and (g0),y
        ora gt5
        sta (g0),y
        rts
        .include "panel.inc"
.endif

        .pushseg
        GSEG "TABLES"
        .include "gametab.inc"
        .popseg
