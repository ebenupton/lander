; game.s: Lander's flight over the land: the keys, the sound, the ship's
; motion, the exhaust's dots, the panel's fuel gauge and the map's marker.
;
; Entries: ginit, once, from the loader; then each frame gstep (keys, sound, a
; step of the model, the camera), after the land gpre (the dots beyond the
; ship), then the ship (ship.s; swr: shipb.s), and gpost (the nearer dots, the
; map's marker, the fuel gauge).
;
; base: main RAM's, small routines filling the parity tables' page tails
; (GSEG: segments T0 .. T4).  swr: bank 5's (GSEG: B5CODE throughout), entered
; as g_init, g_step, g_pre, g_post from videoswr.s's ginit, gstep, gpre,
; gpost, which page bank 5 in.  Tables: gametab.inc (tools/gen.py, from
; tools/gamegen.py); swr: panel.inc (tools/gen.py) as well.
;
; A step is a frame, 12.5 a second at most, taken as 1.25 of Lander's steps;
; velocities keep Lander's units (16384 a tile a Lander step), positions are
; 65536 a tile (y 4096 a height unit, 16 to a tile).

SVIA_ORB = $FE40                   ; the system VIA: the addressable latch
SVIA_DDRA = $FE43
SVIA_ORA_NH = $FE4F                ; port A without handshake: keys, sound

SPAWNK  = (24+12) & 31             ; the start: 135 degrees on from direction
SPAWNP  = PFLAT                    ; 24 (+z, away), level
GRAV    = 240                      ; gravity a step (Lander's, times 1.25)
THRS    = 3                        ; thrust: the tables' << 3
LANDV   = 2048                     ; |gvx| + |gvy| + |gvz| to land below
UNDER   = 4                        ; the ship's centre above its underside
EOFF    = 60                       ; CAME from which the land may be off-screen
KOFF    = 79                       ; the camera's least height above the ship
                                   ; as drawn (GSHYT)
CRASHT  = 40                       ; steps a crash lasts
PLIFE   = 19                       ; a dot's life, steps, its launch's included
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
.else                              ; the panel's row 0 (base: FBC .. FBC+9),
FBC     = 5                        ; lines FBL .. FBL+3
.endif
FBL     = 2

; ginit: the game's start, called once by the loader: every dot dead, the
; sound off, the ship on the pad, the camera.  swr: both screens' panels drawn
; as well.  base: in BOOT, the loader's segment.
        GSEG "BOOT"
.ifdef SWR
g_init: lda #SCR0                  ; both screens' panels; neither has a
        jsr gscr                   ; marker or a gauge
        lda #SCR1
        jsr gscr
        lda #$FF
        sta mkl
        sta mkl+1
        sta fdr
        sta fdr+1
.else
ginit:  lda #$FF                   ; no marker (fdr is the loader's 0, so the
        sta mky                    ; full gauge is drawn)
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
        lda #$FF                   ; the noise channel as written: silent, no
        sta sctl                   ; control
        sta satt
        lda #128                   ; the ship's screen x, always
        sta GSHX
        jsr spawn
        jmp gout
SINI:   .byte $FF, $DF, $BF, $9F   ; every channel's attenuation: silent
SININ   = * - SINI
        GSEG "CODE"

; spawn: the ship on the pad, landed, level, at rest, the tank full, and
; drawn (GSHV).  Clobbers A, X.
spawn:  lda #0                     ; thr .. gvz zeroed: landed, ctim, the
        ldx #gvz+1-thr             ; position and the velocity among them
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

; gstep: the frame's step: the keys, the sound, the model; falls into gout.
.ifdef SWR
g_step:
.else
gstep:
.endif
        jsr keys
        jsr snd
        jsr step
; gout: the camera from the ship: cxt, cxs (x less half a tile), czt, czs
; (ZSHIP tiles behind), CAME (raised as the ship climbs past CAMH - KOFF above
; the ground, as far as EMAX), and the ship's line GSHY, direction GSHK and
; pitch GSHP.  Uses HGV, the last frame's.  Clobbers A, Y, gt0, su.
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
        lda #KOFF                  ; (past EMAX: drawn as at KOFF)
        bne gsy                    ; (always)
:       sta CAME
        clc                        ; the camera above the ship: CAMH + CAME -
        adc #CAMH                  ; height, KOFF..CAMH
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
                                   ; above it, KOFF..CAMH
        .repeat CAMH-KOFF+1, I
        .byte (((KOFF+I)*RSHIP+2048)>>12)+HORIZON
        .endrepeat
        .assert ((KOFF*RSHIP+2048)>>12) >= YSKY+14-HORIZON, error, "GSHYT: d = KOFF on the land"
        .assert ((CAMH*RSHIP+2048)>>12) <= YGND-16-HORIZON, error, "GSHYT: d = CAMH on the land"
        .popseg

; keys: gkb = the keys down: 1 Z or left, 2 X or right, 4 K or up, 8 M or
; down, 16 SPACE, 32 SHIFT, read from the keyboard's matrix with its scan off.
; Clobbers A, X.
; KEYT c: N = key c (its internal number) down.  KEYS b: X |= b.  KEY1 c, b:
; bit b if key c is down.  KEY2 c, d, b: if either of two.
.macro KEYT c
        lda #c
        sta SVIA_ORA_NH
        lda SVIA_ORA_NH
.endmacro
.macro KEYS b
        txa
        ora #b
        tax
.endmacro
.macro KEY1 c, b
        .local no
        KEYT c
        bpl no
        KEYS b
no:
.endmacro
.macro KEY2 c, d, b
        .local no, yes
        KEYT c
        bmi yes
        KEYT d
        bpl no
yes:    KEYS b
no:
.endmacro
keys:   lda #$7F                   ; port A: bits 0-6 out, 7 in
        sta SVIA_DDRA
        lda #3                     ; the keyboard's scan off
        sta SVIA_ORB
        ldx #0
        KEY2 $61, $19, 1
        KEY2 $42, $79, 2
        KEY2 $46, $39, 4
        KEY2 $65, $29, 8
        KEY1 $62, 16
        KEY1 $00, 32
        stx gkb
        lda #$0B                   ; and on again
        sta SVIA_ORB
        rts

; snd: the noise channel, its control and attenuation written only when they
; change.  Crashed: step CRASHT - ctim of the crash (tone 2's period, EXNL and
; EXNH, written every step; attenuation EXA) with SNCR; thrusting SNTH at
; SATF; else silent.  Clobbers A, X, Y.
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
; psg: A to the sound chip (its write enable low for at least 11us).  Leaves
; port A all outputs.  X kept; clobbers A, Y.
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

; step: a step of the model.  The attitude from the keys (held while landed);
; crashed, the dots only, and spawn when ctim runs out; else thrust (none
; without fuel, from 16 tiles up, or with the land gone from the screen),
; drag, gravity and the move, then the ground: a landing on the pad, level and
; slow, or a crash.  Then the dots.  Clobbers A, X, Y, gt0..gt3.
step:   lda landed
        bne @att
        ldy gkb                    ; bits 0, 1: the direction, mod NDIR
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
        tya                        ; bits 2, 3: the pitch, 0..NPITCH-1
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
        lda CAME                   ; (below EOFF the land is on the screen)
        cmp #EOFF
        bcc :+
        jsr landoff
        bcc :+
@off:   ldy #0
:       tya
        sta thr
        beq :+
        dey                        ; thrusting: off the ground (Y 0)
        sty landed
:       ldx #0                     ; drag: v -= (v >> 6) + (v >> 8), each of
                                   ; gvx, gvy, gvz
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
        lda thr                    ; thrust: BURN of fuel (not below 0), the
                                   ; velocity, a dot
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
@nt:    lda landed                 ; landed: at rest, refuelling to FUELMX
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
@mv:    lda gvy                    ; gravity, then the move: 5 v each
        sec
        sbc #<GRAV
        sta gvy
        lda gvy+1
        sbc #>GRAV
        sta gvy+1
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
        lda gp                     ; within a pitch of level?  (C clear: gp -
        sbc #PFLAT-2               ; PFLAT + 1)
        cmp #3
        bcs @crash
        jsr speed                  ; and slow enough?
        bcs @crash
        lda #1                     ; landed: sy = HGV + UNDER units, at rest
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
        lda #0                     ; no ship drawn until spawn
        sta GSHV
        jmp burst
@up:    jmp parts

        .pushseg
        GSEG "T2"
; landoff: C set if every point of the last frame's rows (PY: nr rows, 16 a
; row, np used) is below the land's last line, YGND.  Y kept; clobbers A, X.
landoff:
        tya
        pha
        .assert <PY = 0, error, "landoff: PY page-aligned"
        lda #<PY
        sta @p+1
        ldx nr
@r:     ldy np
        dey
@p:     lda PY,y                   ; (operand's low byte: the row's)
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
; throw: tx, tz = full thrust's x and z at pitch gp and direction gk, signed,
; 127 a unit, from TQ (THX for pitches PFLAT up and directions 0..8, nine a
; pitch: the rest by symmetry).  Clobbers A, X, Y, gt0, gt1.
throw:  lda gk
        jsr thc
        sta tx
        lda gk                     ; THZ(k) = THX(k + 8)
        clc
        adc #8
        jsr thc
        sta tz
        rts
; thc: A = THX for pitch gp and direction A.
thc:    and #31
        cmp #17
        bcc @a
        eor #$FF                   ; 32 - k (C set)
        adc #32
@a:     ldx #0                     ; X: the negations, done if just one
        cmp #9
        bcc @b
        eor #$FF                   ; 16 - k (C set), negated
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
@c:     sta gt1                    ; TQ + 9 pitch + direction
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

; tadd: v (X: its offset from gvx) += 1.25 (A << THRS), A signed.  vadd: v +=
; A << Y, Y at least 1.  X kept; clobbers A, Y, gt0, gt1.
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

; pmove: position (Y: its offset from sx) += 5 v (X: its velocity's offset
; from gvx): 1.25 Lander steps of 4 v.  X, Y kept; clobbers A, gt0..gt3.
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

; rand: A = rnd = the next of an 8-bit LFSR (never 0).  X, Y kept.
        .pushseg
        GSEG "T0"
rand:   lda rnd
        asl a
        bcc :+
        eor #$1D
:       sta rnd
        rts
        .popseg

; The dots: NPART, each a life in steps (0: dead), a position (x, z 8.8 tiles;
; y 8.8 units) and a 16-bit velocity, moving 1.25 v a step.  The exhaust
; launches one a step; a crash launches them all.

; emit: the next dot from the ship's underside, thrown against the thrust (tx,
; tz: step's throw) with some jitter, plus the ship's velocity.  Clobbers A,
; X, Y, gt0..gt3.
emit:   ldx pnext
        inx
        cpx #NPART
        bcc :+
        ldx #0
:       stx pnext
        jsr dot0
        lda #PLIFE
        sta plife,x
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
        ldy gp                     ; y: (-THY - 1) << 3 + gvy / 4 (THY is
                                   ; never negative)
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
; A the low byte, and the high byte as Y + gt3 + C.  X kept; clobbers gt0,
; gt2, gt3.
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
; bjit: A = -64..63 at random, Y its sign ($FF or 0); sxadd: Y = A's sign.
; X kept.
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

; dot0: dot X's position: the ship's, UNDER units down.  X kept; clobbers A,
; su.
        .pushseg
        GSEG "T0"
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
        .popseg

; burst: every dot launched from the ship's x and z at the ground's height,
; flung out and up at random; falls into parts.
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
; parts: each live dot a step: its life one less, its position += 1.25 v, its
; vy -= PGRAV; dead if its height leaves 0..255 units.  Clobbers A, X, Y,
; gt0..gt2.
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

; gpre: the dots beyond the ship.  gpost: those nearer (by gpre's su), the
; marker and the gauge.  Each dot's column records are widened over it, so
; the strips that next draw this screen take it off.
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
; status (base): the fuel gauge, fuel >> 7 pixels over byte columns FBC ..
; FBC+9 of TOP's lines FBL .. FBL+3, redrawn when it differs from fdr, the
; length drawn.  Clobbers A, X, Y, gt1.
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

; dset: scrg, tsg, bsg: the page of the screen being drawn and its column
; records' tops and bottoms.  Clobbers A, X, Y.
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

; dots: pdraw for each live dot at or beyond the ship's z (A 0) or nearer
; (A $80); none with the ship 16 tiles up or more.  Clobbers A, X, Y, g0,
; gt0, gt2..gt4.
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
; tiles from the ship, dy units below it), if on the land's lines; yellow,
; magenta in its last five steps.  X kept; clobbers A, Y, g0, gt0, gt2..gt4.
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
        lda su                     ; dy = su - the dot's y, off unless a
                                   ; signed byte of units
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
        lsr a                      ; the byte: page scrg + 2 (y >> 3), offset
        lsr a                      ; 8 (x >> 2) + (y & 7)
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
        lda gt2                    ; the pixel's mask
        and #3
        tay
        lda PIXD,y
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
        lda gt2                    ; the column's records widened to line y
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
; marker (base): the ship's dot on the map, two lines of one MODE 5 pixel
; (two tiles across), magenta; none while crashed.  mky is its first line
; ($FF: none), mkt its pixel, mkb the two bytes under it, put back when it
; moves.  Clobbers A, X, Y, g0, gt0..gt3.
        .assert <MAP = 0, error, "marker: MAP page-aligned"
marker: ldx #$FF                   ; (none while crashed)
        lda GSHV
        beq @h
        lda #MAPZ                  ; its line: (MAPZ - z) & 63, even
        sec
        sbc sz+2
        and #62
        tax
        lda sx+2                   ; its pixel: ((x + MAPX) & 63) / 2
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
        ldx mky                    ; the bytes under the one drawn put back
        bmi @n
        lda mkb
        jsr @put
        inx
        lda mkb+1
        jsr @put
@n:     ldx gt1                    ; this one's kept, and it drawn
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
        lda (g0),y                 ; byte before
        pha
        ora gt2
        eor gt2
        ora gt3
        sta (g0),y
        pla
        rts
@put:   pha                        ; A to line X's byte
        jsr mkad
        pla
        sta (g0),y
        rts
.endif
.ifdef SWR
; status (swr): this screen's fuel gauge, fuel >> 6 pixels over byte columns
; FBC .. FBC+19 of lines FBL .. FBL+3, redrawn when it differs from what the
; screen shows (fdr).  Clobbers A, X, Y, g0, gt1.
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

; gscr (swr): the panel of the screen at page A: FUEL (FUELI) at row 0's first
; eight byte columns, the map (MAPI's 64 lines of 16 bytes) at byte columns
; 48..63 of character rows 0..7.  Clobbers A, X, Y, g0, g1, gt0.
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

; marker (swr): the ship's dot on this screen's map: 2 x 2 pixels, magenta,
; on the four tiles whose common corner is nearest the ship (gamegen's layout:
; tile x at pixel (x + MAPX) & 63, z at line (MAPZ - z) & 63); none while
; crashed.  Each screen remembers its dot (mkl its top line, $FF none; mkp its
; left pixel); where the dot differs, the one drawn is first put back from
; MAPI.  Clobbers A, X, Y, g0, g1, gt0..gt5.
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
:       lda mkl,x                  ; the dot drawn back to the map's pixels
        bmi :+
        sta mdl
        lda mkp,x
        sta mdp
        lda #0
        jsr mdot
:       ldx back                   ; this one remembered and drawn
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
        bit mdc                    ; magenta's bits of it, or the map's
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
; PIXD: a dot's pixel in its byte, by x & 3.  (PIXM, the land's, samples a
; MODE 2 pixel at its even x alone.)
.ifdef SWR
PIXD    = PIXG
.elseif .defined(MODE2)
PIXD:   .byte $AA, $AA, $55, $55
.else
PIXD    = PIXM
.endif
        .popseg
