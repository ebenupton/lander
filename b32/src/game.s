;============================================================================
; game.s -- the 32K build's game (b32/src/land.s .includes it): Lander's flight
; over LAND's landscape, as src/game.s plays it, less the fuel (no tank, no bar,
; no refuelling: the engines run while the land is in view) and with a 32-tile
; map.  land.s's main loop calls ginit once, then gstep, gpre and gpost each
; frame around its projection, strips and the ship.  No banks: the game's
; tables and LAND's share the one memory.  The map (the panel) is drawn at the
; start; gpost moves the ship's marker on it.
;============================================================================

GSHK    = $07DB                    ; the ship for bank 6 (B6_KEYS copies these
GSHP    = $07DC                    ; four): direction, pitch, screen x (128),
GSHX    = $07DD                    ; screen line
GSHY    = $07DE
GSHV    = $07DF                    ; 1: the ship is drawn (0 while crashed)

g0      = $8E                      ; zero page (LAND's spare $8E..$9F): two
g1      = $90                      ; pointers and six scratch bytes
gt0     = $92
gt1     = $93
gt2     = $94
gt3     = $95
gt4     = $96
gt5     = $97
tsg     = $98                      ; (gpre's and gpost's: this screen's TOPS
bsg     = $9A                      ; and BOTS)

SVIA_ORB = $FE40                   ; the system VIA: port B (bits 0-2 pick a
SVIA_DDRA = $FE43                  ; latch bit, bit 3 sets it), port A's
SVIA_ORA_NH = $FE4F                ; direction and port A without handshake

; Lander's constants are per main-loop step; here a step is a frame at 10 a
; second, taken as 1.25 Lander steps, and the velocities keep Lander's units
; (16384 a tile per Lander step).
SPAWNK  = (24+12) & 31             ; the start direction: 4, 135 degrees on
SPAWNP  = PFLAT                    ; k 24 (facing away), as Lander's; level
GRAV    = 240                      ; gravity a step: Lander's &30000 (of 2^24)
                                   ; a tile per step^2 is 192 here, times 1.25
THRS    = 3                        ; full thrust: THX, THZ, THY (127 a unit)
                                   ; << 3: 1016 at most (Lander's 1024); tadd
                                   ; then makes it 1.25 as much
LANDV   = 2048                     ; Lander's LANDING_SPEED, 1/8 tile a step:
                                   ; |gvx| + |gvy| + |gvz| must be below it
UNDER   = 4                        ; the ship's centre above its underside, in
                                   ; height units: a quarter tile
EOFF    = 60                       ; CAME below this: the land is on the screen,
                                   ; landoff's scan skipped
KOFF    = 79                       ; the camera's least height above the ship,
                                   ; height units: SHYT[KOFF] = 97, line 81
CRASHT  = 40                       ; steps a crash lasts (4 seconds)
PLIFE   = 19                       ; a dot's life, steps: the land's 96 lines at
                                   ; the exhaust's speed (8 THY / 256 units a
                                   ; Lander step, 1.25 a step: about 5 lines)
NPART   = 20                       ; dots (emit uses one a step, each in turn)
SNTH    = $E6                      ; the engine: noise register, white noise at
                                   ; the lowest fixed rate
SATF    = 13                       ; its attenuation (2 dB a step, 15 silent)
SNCR    = $E7                      ; the crash: white noise clocked by tone 2
PGRAV   = 60                       ; a dot's gravity, 256ths of a unit a step^2
                                   ; (GRAV in the dots' units, 4 times coarser)
PADX    = PADN/2                   ; the pad's middle tile: the start


; ---------------------------------------------------------------- init
; ginit (G_INIT): once, after LAND's init has blacked both screens.  The map
; and the FUEL label on both screens; the marks cleared; every dot dead; the
; sound chip silenced; the ship spawned on the pad; then gout, so LAND's first
; projection has the camera and bank 6 the ship.  Clobbers A, X, Y, g0, g1,
; gt0, gt2..gt4, su, scrg.
ginit:  lda #$5A                   ; (the LFSR's seed: never 0)
        sta rnd
        ldx #NPART-1
        lda #0
:       sta plife,x
        dex
        bpl :-
        ldx #SININ-1               ; SINI to the sound chip: the four channels
:       lda SINI,x                 ; off
        jsr psg
        dex
        bpl :-
        lda #$FF                   ; (noise control and attenuation as written:
        sta sctl                   ; $FF is the attenuation off)
        sta satt
        jsr spawn
        jmp gout
SINI:   .byte $FF, $DF, $BF, $9F   ; noise, tone 2, 1, 0: attenuation 15 (off)
SININ   = * - SINI

; spawn: the ship on the pad, still, landed, level, facing SPAWNK, the tank
; full, drawn, no thrust; HGV set to the pad's height for gout before hgnd
; has run.  Clobbers A.  Called by ginit and by step when a crash ends.
spawn:  lda #0
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
        lda #PADX                  ; the pad's middle tile in x and z
        sta sx+2
        sta sz+2
        lda #(PADH+UNDER)<<4 & 255 ; y = (PADH + UNDER) units: bytes 1 and 2 of
        sta sy+1                   ; units * 4096
        lda #(PADH+UNDER)>>4
        sta sy+2
        lda #SPAWNK
        sta gk
        lda #SPAWNP
        sta gp
        lda #PADH                  ; the ground under it (hgnd's from then on)
        sta HGV
        lda #0                     ; (snd's next frame: silence, not the crash's
        sta thr                    ; last step)
        lda #1
        sta landed
        sta GSHV
        rts

; ---------------------------------------------------------------- step
; gstep (G_STEP): first in each frame.  The keys; the sound for the state the
; last step left (thr, ctim); a step of the model; then gout.  Clobbers A, X,
; Y, g0, g1, gt0..gt5, su, tt0, tt1.
gstep:  jsr keys
        jsr snd
        jsr step
        ; falls into gout
; gout: the camera and the ship's place on the screen, from the ship.  Out:
; cxt, cxs (camera x: the ship's less 128/256 tile, as a tile 0..63 and a
; sixteenth 0..15), czt, czs (camera z: ZSHIP tiles behind the ship), su (the
; ship's height in units, 8.8), CAME, GSHY, GSHX (128), GSHK, GSHP.  Reads
; sx, sz, sy, gk, gp, HGV.  Clobbers A, X, Y, gt0.  Called by gstep and ginit.
gout:   lda sx+1
        sec
        sbc #128
        sta gt0
        lda sx+2
        sbc #0
        and #MAPN-1
        sta cxt
        lda gt0
        lsr a
        lsr a
        lsr a
        lsr a
        sta cxs
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
        lda sy+2                   ; rel: the ship above the ground under it, in
        bmi gr_0                   ; whole units, 0..255: 255 from 16 tiles up
        cmp #16                    ; (su's whole byte has wrapped), 0 when below
        bcc gr_lo                  ; HGV or below y = 0 (both only while
        lda #$FF                   ; crashed)
        bne gr_st
gr_lo:  lda su+1
        sec
        sbc HGV
        bcs gr_st
gr_0:   lda #0
gr_st:  sta gt0
        sec                        ; CAME = rel - (CAMH - KOFF), in 0..EMAX:
        sbc #CAMH-KOFF             ; the camera is then max(CAMH - rel, KOFF)
        bcs :+                     ; above the ship
        lda #0
:       cmp #EMAX+1
        bcc :+
        lda #EMAX                  ; past EMAX: LAND drawn at EMAX (every row
        sta CAME                   ; below the screen) and the ship kept at KOFF
        lda #KOFF                  ; below the camera
        bne gsy
:       sta CAME
        clc                        ; d = CAME + CAMH - rel: the camera above the
        adc #CAMH                  ; ship, units
        sec
        sbc gt0
gsy:    jsr shyt                   ; the ship's line: HORIZON + (d R + 2048) >>
                                   ; 12 (d R / 16, R = 19.7 the land's pixels a tile at
        cmp #YSKY+14-HORIZON       ; depth ZSHIP), held so 14 lines up, 16 down,
        bcs :+                     ; stay within YSKY..YGND (d is 79..96 in
        lda #YSKY+14-HORIZON       ; play: lines 81..102, so the holds never
:       cmp #YGND-16-HORIZON       ; bite)
        bcc :+
        lda #YGND-16-HORIZON
:       clc
        adc #<HORIZON
        sta GSHY
        lda #128
        sta GSHX
        lda gk
        sta GSHK
        lda gp
        sta GSHP
        rts

; shyt: A = min(255, (A RSHIP + 2048) >> 12), the ship's line less HORIZON
; for the camera A units above it (tools/gamegen.py's SHYT; RSHIP the land's
; r at depth ZSHIP).  Clobbers A, Y, gt1..gt4.
shyt:   sta gt4                    ; A RSHIP, 8 x 16: the multiplier's bits
        lda #0                     ; from the top, the sum shifted up
        sta gt1
        sta gt2
        sta gt3
        ldy #8
@m:     asl gt1
        rol gt2
        rol gt3
        asl gt4
        bcc :+
        lda gt1
        clc
        adc #<RSHIP
        sta gt1
        lda gt2
        adc #>RSHIP
        sta gt2
        bcc :+
        inc gt3
:       dey
        bne @m
        lda gt2                    ; + 2048, bits 12..19
        clc
        adc #8
        sta gt2
        bcc :+
        inc gt3
:       lda gt3
        cmp #16
        bcs @x                     ; (past 255: 255)
        asl a
        asl a
        asl a
        asl a
        sta gt1
        lda gt2
        lsr a
        lsr a
        lsr a
        lsr a
        ora gt1
        rts
@x:     lda #255
        rts

; units: su = sy >> 4, the ship's height in units as 8.8 (su+1 whole units,
; valid below 16 tiles).  Clobbers A, Y; X kept.
units:  lda sy
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
; KEYB code, bit: key `code` (its internal number, bit 7 clear) written to
; port A with the auto-scan off; bit 7 reads back set if it is down, and then
; `bit` is set in gkb.
.macro KEYB code, bit
        .local no
        lda #code
        sta SVIA_ORA_NH
        lda SVIA_ORA_NH
        bpl no
        lda gkb
        ora #bit
        sta gkb
no:
.endmacro
; keys: gkb from the keyboard: 1 Z or left, 2 X or right, 4 K or up, 8 M or
; down, 16 SPACE, 32 SHIFT, 64 F; F toggles fpson as it goes down (fkey:
; its state last time).  Interrupts off while the VIA is ours.  Clobbers A,
; X.  DP11_MOUSE: with mdet set, also the mouse: 16 the left button, 128 the
; middle; writes mous, gmx, gmy; clobbers Y, gt0..gt3 too.  Called by gstep.
keys:   lda #0
        sta gkb
        sei
        lda #$7F                   ; port A: bits 0-6 out (the key's number),
        sta SVIA_DDRA              ; bit 7 in (pressed)
        lda #3                     ; latch bit 3 low: keyboard auto-scan off
        sta SVIA_ORB
        KEYB $61, 1                ; Z, left
        KEYB $19, 1
        KEYB $42, 2                ; X, right
        KEYB $79, 2
        KEYB $46, 4                ; K, up
        KEYB $39, 4
        KEYB $65, 8                ; M, down
        KEYB $29, 8
        KEYB $62, 16               ; SPACE
        KEYB $00, 32               ; SHIFT
        KEYB $43, 64               ; F
        lda #$0B                   ; auto-scan back on
        sta SVIA_ORB
        cli
        lda gkb
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
; snd: the noise channel of the SN76489 for this frame, written only where it
; changes (sctl, satt hold the control and attenuation bytes last written).
; Crashed (ctim): the step's crack-to-rumble, tone 2's period from EXNL, EXNH
; (written every step) and its attenuation from EXA, with SNCR (noise clocked
; by tone 2).  Flying: SNTH at SATF while thr is set, else attenuation 15.
; Reads ctim, thr.  Clobbers A, X, Y, sstp.  Called by gstep.
snd:    lda ctim
        beq @t
        lda #CRASHT                ; sstp = the crash's step, 0..CRASHT-1
        sec
        sbc ctim
        sta sstp
        tay
        lda EXNL,y                 ; tone 2's period: latch byte, then data byte
        jsr psg
        ldy sstp
        lda EXNH,y
        jsr psg
        ldy sstp
        ldx EXA,y
        lda #SNCR
        bne @c
@t:     ldx #15                    ; silent unless thrusting
        lda thr
        beq @v
        ldx #SATF
        lda #SNTH
@c:     cmp sctl                   ; the noise control byte, if changed
        beq @v
        sta sctl
        jsr psg
@v:     txa                        ; noise attenuation, %1111aaaa, if changed
        ora #$F0
        cmp satt
        beq :+
        sta satt
        jmp psg
:       rts
; psg: byte A to the sound chip: port A all outputs with the byte on it, the
; chip's write-enable (latch bit 0, active low) pulsed low for 22 cycles,
; about 11us.
; Leaves DDRA $FF (keys resets it).  Clobbers A, Y; X kept.
psg:    sei
        ldy #$FF
        sty SVIA_DDRA
        sta SVIA_ORA_NH
        lda #0                     ; latch bit 0 low: write enable
        sta SVIA_ORB
        ldy #3
:       dey
        bne :-
        lda #8                     ; and high again
        sta SVIA_ORB
        cli
        rts

; ---------------------------------------------------------------- a step
; step: one step of the model.  The attitude from gkb, unless landed (on the
; pad it is held): Z/left and X/right turn gk one direction (mod NDIR), K/up
; and M/down move gp a pitch towards NPITCH-1 (nose down) or 0 (nose up).
; Crashed: ctim counts down, spawn at 0, only the dots move.  Flying: thr
; from SPACE or SHIFT, denied without fuel, from 16 tiles up, or once the
; land has left the screen (CAME past EOFF and landoff's scan); thrust lifts
; off (landed cleared); drag; thrust, fuel and an exhaust dot; landed:
; velocities zeroed and REFUEL a step up to FUELMX; else gravity, the move,
; and the ground test: the ship's centre less than UNDER units above HGV (or
; below it, or y below 0) is a touch, a landing if over the pad, within a
; pitch of level and slower than LANDV, else a crash (burst, GSHV 0, ctim
; CRASHT).  Finally parts.  DP11_MOUSE: with mous set, attit sets the
; attitude in place of the keys (held likewise while landed); thr 2 is hover
; (the middle button: HOVS, 3 fuel, a dot every fourth step: hcnt).  Reads
; gkb, landed, fuel, sy, CAME, HGV (mous); writes gk, gp, ctim, thr, landed,
; gv*, s*, fuel, GSHV (hcnt).  Clobbers A, X, Y, g0, g1, gt0..gt5, tt0, tt1.
; Called by gstep.
step:   lda landed                 ; on the pad: the attitude held
        bne @att
        lda gkb
        lsr a
        bcc :+
        lda gk
        sbc #1                     ; (C set: a plain decrement)
        and #NDIR-1
        sta gk
:       lda gkb
        and #2
        beq :+
        lda gk
        clc
        adc #1
        and #NDIR-1
        sta gk
:       lda gkb
        and #4
        beq :+
        lda gp
        cmp #NPITCH-1
        bcs :+
        inc gp
:       lda gkb
        and #8
        beq :+
        lda gp
        beq :+
        dec gp
:
@att:   lda ctim                   ; crashed: the dots only, then the pad
        beq @fly
        dec ctim
        bne :+
        jsr spawn
:       jmp parts
@fly:
        lda gkb                    ; Y = 1 if SPACE or SHIFT (both full thrust)
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        beq :+
        lda #1
:       tay
        lda sy+2                   ; nor 16 tiles up (su's byte wrapped), nor
        bmi :+                     ; with the land gone from the screen: CAME
        cmp #16                    ; under EOFF means in view; from EOFF up,
        bcs @off                   ; landoff checks last frame's rows
        lda CAME
        cmp #EOFF
        bcc :+
        jsr landoff
        bcc :+
@off:   ldy #0
:       tya
        sta thr
        cmp #0
        beq :+
        lda #0                     ; thrusting: off the ground
        sta landed
:       ldx #0                     ; drag, each of gvx, gvy, gvz (X 0, 2, 4):
@dg:                               ; v -= (v >> 6) + (v >> 8), 1.25 of Lander's
        ldy #6                     ; v >> 6; gt1:gt0 = v >> 6, arithmetic
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
        jsr @ds
        lda gt1                    ; then >> 2 more: v >> 8
        cmp #$80
        ror gt1
        ror gt0
        lda gt1
        cmp #$80
        ror gt1
        ror gt0
        jsr @ds
        inx
        inx
        cpx #6
        bne @dg
        beq @th
@ds:    lda gvx,x                  ; v (X) -= gt1:gt0
        sec
        sbc gt0
        sta gvx,x
        lda gvx+1,x
        sbc gt1
        sta gvx+1,x
        rts
@th:
        lda thr                    ; thrust: gt5 the shift (THRS)
        beq @nt
        lda #THRS
        sta gt5
        jsr throw                  ; gvx += 1.25 (THX[gp][gk] << gt5), gvz from
        lda tx                     ; THZ, gvy from THY[gp]
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
@nt:    lda landed                 ; landed: still
        beq @mv
        lda #0
        ldx #5
:       sta gvx,x
        dex
        bpl :-
        jmp parts
@mv:    lda gvy                    ; gravity: gvy -= GRAV (y is up)
        sec
        sbc #<GRAV
        sta gvy
        lda gvy+1
        sbc #>GRAV
        sta gvy+1
        ldx #gvx-gvx               ; the move: each position += 5 v
        ldy #sx-sx
        jsr pmove
        ldx #gvz-gvx
        ldy #sz-sx
        jsr pmove
        ldx #gvy-gvx
        ldy #sy-sx
        jsr pmove
        lda sy+2                   ; y below 0: the ground
        bmi @gnd
        cmp #16                    ; 16 tiles up or more: nowhere near it
        bcc :+
        jmp parts
:       jsr units                  ; the centre less than UNDER units above HGV
        lda su+1                   ; (or below it): the ground
        sec
        sbc HGV
        bcc @gnd
        cmp #UNDER
        bcs @up
@gnd:   lda sx+2                   ; over the pad: tiles 0..PADN-1 in x and z
        and #MAPN-1
        cmp #PADN
        bcs @crash
        lda sz+2
        and #MAPN-1
        cmp #PADN
        bcs @crash
        lda gp                     ; within a pitch of level: PFLAT-1..PFLAT+1
        sec
        sbc #PFLAT-1
        cmp #3
        bcs @crash
        jsr speed                  ; and slower than LANDV
        bcs @crash
        lda #1                     ; landed: y = (HGV + UNDER) units, still
        sta landed
        lda HGV
        clc
        adc #UNDER
        sta gt0
        asl a                      ; (units * 4096: bytes 1 and 2)
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
        jmp parts
@crash: lda #CRASHT                ; crashed: CRASHT steps, the ship not drawn,
        sta ctim                   ; every dot from the ship
        lda #0
        sta GSHV
        jsr burst
        jmp parts
@up:    jmp parts                  ; in the air: no ceiling


; landoff: C set if the last frame's projection has the land wholly below the
; screen: every point (np a row) of every row (nr, 16 bytes apart in PY) past
; YGND; C clear at the first point on the screen.  Clobbers A, X, gt0, gt1; Y
; kept (step's thrust).  Called by step.
landoff:
        tya
        pha
        ldx #0
        ldy nr
@r:     stx gt0
        lda np
        sta gt1
@p:     lda PY,x
        cmp #YGND+1
        bcc @v
        inx
        dec gt1
        bne @p
        lda gt0
        clc
        adc #16
        tax
        dey
        bne @r
        pla
        tay
        sec
        rts
@v:     pla
        tay
        clc
        rts


; throw: tx, tz = the thrust for pitch gp and direction gk, x and z, 127 a
; unit (tools/gamegen.py's THX and THZ: round(127 sin a cos t), -round(127
; sin a sin t)), from TQ, a quarter of them: THX by pitches 0..PFLAT from
; level and directions 0..8 (sin a is odd in the pitch from level, cos t even
; in t and cos (180 - t) = -cos t, and the rounding keeps both); THZ for
; direction k is -THX for k - 8.  X kept (in tx's call); clobbers A, Y, gt0,
; gt1, thxs.  Called by step and emit.
throw:  stx thxs
        lda gk
        jsr thc
        sta tx
        lda gk
        sec
        sbc #8
        jsr thc
        eor #$FF
        clc
        adc #1
        sta tz
        ldx thxs
        rts
; thc: THX for pitch gp and direction A & 31.  Clobbers X, Y, gt0, gt1.
thc:    and #31
        cmp #17                    ; 17..31: 32 - k (cos even)
        bcc @a
        eor #$FF                   ; (C set: ~k + 32 + 1)
        adc #32
@a:     ldx #0                     ; X: the sign, bit 7
        cmp #9                     ; 9..16: 16 - k, negated
        bcc @b
        eor #$FF                   ; (C set: ~k + 16 + 1)
        adc #16
        ldx #$80
@b:     sta gt0                    ; j, 0..8
        lda gp                     ; |gp - PFLAT|, negated below level
        sec
        sbc #PFLAT
        bcs @c
        eor #$FF                   ; (C clear: + 1)
        adc #1
        tay
        txa
        eor #$80
        tax
        tya
@c:     sta gt1                    ; TQ + 9 |gp - PFLAT| + j
        asl a
        asl a
        asl a
        adc gt1                    ; (C clear: 8 |p| < 256)
        adc gt0
        tay
        lda TQ,y
        cpx #$80                   ; (negative: C set, so ~v + 0 + 1)
        bcc @d
        eor #$FF
        adc #0
@d:     rts
        .segment "HIB"
thxs:   .res 1                     ; throw's X
tx:     .res 1                     ; throw's thrust, x and z
tz:     .res 1
        .segment "GAME"

; tadd: v (X: gvx, gvy or gvz's offset) += 1.25 (A << gt5), as A << gt5 then
; A << (gt5 - 2); for gt5 below 2 the second term is A asr 1 (right for gt5
; 1).  Clobbers A, gt0, gt1, gt2, tt0, tt1; X, Y and gt5 kept.  Called by
; step.
tadd:   sta tt0
        jsr vadd
        lda gt5
        sta tt1
        sec
        sbc #2
        bcs :+
        lda tt0                    ; A asr 1
        cmp #$80
        ror a
        sta tt0
        lda #0
:       sta gt5
        lda tt0
        jsr vadd
        lda tt1
        sta gt5
        rts

; vadd: v (X: gvx, gvy or gvz's offset) += A (signed) << gt5, 16-bit.
; Clobbers A, gt0, gt1, gt2; Y kept (through gt2).  Called by tadd.
vadd:   sta gt0
        lda #0
        bit gt0                    ; gt1: A's sign extension
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

; pmove: position (Y: sx, sy or sz's offset) += 5 v (X: its velocity's
; offset), 24-bit: 4 v is Lander's step, 5 v is 1.25 of it.  Clobbers A,
; gt0..gt3; X, Y kept.  Called by step.
pmove:  lda gvx,x
        sta gt0
        lda gvx+1,x
        sta gt1
        lda #0                     ; gt2 (and gt3): v's sign extension
        bit gt1
        bpl :+
        lda #$FF
:       sta gt2
        sta gt3
        asl gt0                    ; gt2:gt1:gt0 = 4 v
        rol gt1
        rol gt2
        asl gt0
        rol gt1
        rol gt2
        lda gt0                    ; + v
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

; speed: C clear if |gvx| + |gvy| + |gvz| < LANDV, set if not.  Clobbers A,
; X, Y, gt2, gt3.  Called by step.
speed:  lda #0
        sta gt2
        sta gt3
        ldx #0
@a:     lda gvx,x                  ; Y:A = |v|
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
; The dots: NPART of them, each a life in steps (plife, 0 dead), a position
; (ppx, ppz: 8.8 tiles as ppxh:ppx, ppzh:ppz; ppy: height units 8.8) and a
; velocity (pvx, pvz: 1/256 tile per Lander step; pvy: 1/256 unit), each
; advancing 1.25 v a step.  The exhaust (emit) adds one a step while
; thrusting; a
; crash (burst) relaunches them all.

; rand: A = rnd, the next state of an 8-bit LFSR (x^8 + x^4 + x^3 + x^2 + 1,
; period 255).  Clobbers A.
rand:   lda rnd
        asl a
        bcc :+
        eor #$1D
:       sta rnd
        rts

; emit: the next dot (pnext, each in turn) relaunched from the ship's
; underside with velocity the thrust's opposite: x and z -THX/2, -THZ/2 for
; (gp, gk) plus a jitter of -16..15, plus the ship's v >> 6 (its units); y
; -8 (THY + 1) plus the ship's gvy / 4.  Reads gp, gk, sx, sz, sy, gv*.
; Clobbers A, X, Y, g0, g1, gt0..gt3, su.  Called by step.
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
        jsr exh
        sta gt0                    ; (-THX / 2)
        lda tz
        jsr exh
        sta gt1                    ; (-THZ / 2)
        jsr rand                   ; x: + jitter, sign-extended into pvxh:pvx
        and #31
        sec
        sbc #16
        clc
        adc gt0
        jsr sxadd
        sta pvx,x
        tya
        sta pvxh,x
        ldy #gvx-gvx               ; + gvx >> 6 (16384ths of a tile to 256ths)
        jsr vsh6
        lda pvx,x
        clc
        adc gt2
        sta pvx,x
        lda pvxh,x
        adc gt3
        sta pvxh,x
        jsr rand                   ; z likewise
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
        ldy gp                     ; y: gt1:gt0 = -(THY + 1) << 3
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
        lda gvy+1                  ; gt3:gt2 = gvy asr 2 (1024ths of a unit to
        cmp #$80                   ; 256ths)
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
; vsh6: gt3:gt2 = v (Y: gvx, gvy or gvz's offset) >> 6, arithmetic.
; Clobbers A, Y; X kept.
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
; exh: A = -A / 2, signed (negate, then asr).
exh:    eor #$FF
        clc
        adc #1
        cmp #$80
        ror a
        rts
; sxadd: Y = A's sign extension ($00 or $FF); A kept.
sxadd:  ldy #0
        cmp #$80
        bcc :+
        dey
:       rts

; dot0: dot X placed at the ship: x and z the ship's (8.8 tiles), y the
; ship's height (su, 8.8 units) less UNDER whole units: its underside.
; Clobbers A, Y, su; X kept.  Called by emit and burst.
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

; burst: the crash: every dot relaunched from the ship, but at the ground's
; height under it (HGV: by the crash the ship's underside is below it, and
; under 0 too where the ground is low, where a dot would die at once), x and
; z velocities random in -64..63, y random upwards (0..1023, both bytes from
; one rand).  Clobbers A, X, Y, su.  Called by step.
burst:  ldx #NPART-1
@b:     jsr dot0
        lda HGV
        sta ppyh,x
        lda #0
        sta ppy,x
        lda #PLIFE
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

; parts: each live dot a step: its life down one, each position += 1.25 v
; (q5), then gravity PGRAV off pvy.  A dot whose height leaves its byte (below
; 0, or past 255 units) dies rather than wrapping.  Clobbers A, X, Y,
; gt0..gt3.  Called by step (every path).
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
        lda ppxh,x
        adc gt1
        sta ppxh,x
        lda pvz,x
        ldy pvzh,x
        jsr q5
        lda ppz,x
        clc
        adc gt0
        sta ppz,x
        lda ppzh,x
        adc gt1
        sta ppzh,x
        lda pvy,x
        ldy pvyh,x
        jsr q5
        lda ppy,x
        clc
        adc gt0
        sta ppy,x
        lda ppyh,x
        adc gt1
        sta ppyh,x
        ror a                      ; bit 7 = C eor the step's sign: set when a
        eor gt1                    ; rise carried out of the byte or a fall
        bpl :+                     ; borrowed past 0: the dot dies
        lda #0
        sta plife,x
        beq @n
:
        lda pvy,x                  ; pvy -= PGRAV
        sec
        sbc #PGRAV
        sta pvy,x
        bcs @n
        dec pvyh,x
@n:     dex
        bpl @p
        rts

; q5: gt1:gt0 = 1.25 (Y:A), signed: Y:A + (Y:A asr 2).  Clobbers A, Y,
; gt2, gt3; X kept.  Called by parts.
q5:     sta gt2
        sty gt3
        sta gt0
        sty gt1
        ldy #2
:       lda gt1
        cmp #$80
        ror gt1
        ror gt0
        dey
        bne :-
        lda gt0
        clc
        adc gt2
        sta gt0
        lda gt1
        adc gt3
        sta gt1
        rts

; ---------------------------------------------------------------- post
; gpre (G_PRE, after the strips, before the ship): the live dots beyond the
; ship in z, each a pixel on the screen being drawn, the column's TOPS and
; BOTS widened over it so the strips that next draw this screen take it off.
; gpost (G_POST, after the ship): the dots nearer than the ship, then the
; map's ship marker.  Both clobber A, X, Y, g0, g1,
; gt0..gt5, su, tsg, bsg, scrg, dpass.
gpre:   jsr dset
        lda #0
        beq dots
gpost:  jsr dset
        lda #$80
        jsr dots
        jmp marker
; dset: scrg = the screen being drawn (scrb); tsg, bsg = its TOPS and BOTS
; (the set sidx picks for back); su from sy.  Clobbers A, X, Y.
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
        jmp units
; dots: pdraw for each live dot whose z less the ship's has the sign A
; selects: A 0 for z at or beyond the ship's, $80 for nearer.  None at all
; from 16 tiles up (su's whole byte has wrapped).  Clobbers A, X, Y, dpass
; and pdraw's.
dots:   sta dpass
        lda sy+2
        bmi :+
        cmp #16
        bcc :+
        rts
:
        ldx #NPART-1
@d:     lda plife,x
        beq @n
        lda ppz,x                  ; the sign of (its z - the ship's), 16-bit
        cmp sz+1
        lda ppzh,x
        sbc sz+2
        eor dpass
        bmi @n
        jsr pdraw
@n:     dex
        bpl @d
        rts

; pdraw: dot X on screen scrg if it fits: x = 128 + 16 dx (dx its x less the
; ship's, tiles; |dx| under 8), y = GSHY + dy - 4 dz (dy the ship's height
; less its, whole units, one line each, -128..127; dz its z less the ship's,
; tiles), y within YSKY..YGND.  The pixel is yellow, or magenta in its last
; five steps; then the column's TOPS and BOTS (tsg, bsg) widened to it.
; Reads ppx.., sx, sz, su, GSHY, plife.  Clobbers A, Y, g0, gt0..gt5; X
; kept.  Called by dots.
pdraw:  lda ppx,x                  ; dx, 8.8 tiles
        sec
        sbc sx+1
        sta gt0
        lda ppxh,x
        sbc sx+2
        sta gt1
        clc                        ; off unless -8 <= dx < 8
        adc #8
        cmp #16
        bcc :+
@o1:    jmp @o
:       ldy #4                     ; dx >> 4: 16 pixels a tile
:       lda gt1
        cmp #$80
        ror gt1
        ror gt0
        dey
        bne :-
        lda gt0
        eor #$80                   ; + 128
        sta gt2                    ; (screen x)
        lda su                     ; dy = the ship's height less the dot's,
        sec                        ; whole units (the fraction only borrows)
        sbc ppy,x
        lda su+1
        sbc ppyh,x
        sta gt3
        bcc :+                     ; no borrow: off if >= 128; a borrow: off
        bmi @o1                    ; unless the byte is -128..-1
        bpl :++
:       bpl @o1
:       lda ppz,x                  ; 4 dz: dz (8.8) >> 6, as a byte
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
        lda GSHY                   ; y = GSHY + dy - 4 dz, within YSKY..YGND
        clc
        adc gt3
        sec
        sbc gt1
        cmp #YSKY
        bcc @o
        cmp #YGND+1
        bcs @o
        sta gt3                    ; (screen y)
        ; the byte: scrg + $200 (y >> 3) + 8 (x >> 2) + (y & 7)
        and #7
        sta g0
        lda gt2
        and #$FC
        asl a                      ; (8 (x >> 2): its carry is the $100 bit)
        php
        ora g0
        sta g0
        lda gt3
        lsr a
        lsr a
        and #$FE                   ; 2 (y >> 3)
        plp
        adc scrg
        sta g0+1
        lda gt2                    ; the pixel's bits (PIXG by x & 3) masked
        and #3                     ; out of the byte, then set: both for yellow,
        tay                        ; the high one only for magenta (life < 6)
        lda PIXG,y
        sta gt4
        eor #$FF
        ldy #0
        and (g0),y
        sta gt5
        lda gt4
        ldy plife,x
        cpy #6
        bcs :+
        and #$F0
:
        ora gt5
        ldy #0
        sta (g0),y
        lda gt2                    ; the column (x >> 2): TOPS no lower than y,
        lsr a                      ; BOTS no higher
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

; marker: the ship's tile on the map (the panel, loaded with the map drawn):
; its pixel pair magenta while GSHV is set -- line MAPZ - z, pair x + MAPX
; (the tile the ship is over, mod 32: PANEL + 128 (line >> 3) + 8 (pair >> 1)
; + (line & 7), the byte's left or right pair).  The byte it covers is kept
; (mkb) and put back when it moves (mka: its address, high byte 0 for none).
; Clobbers A, X, Y, g0, g1, gt0..gt2.  Called by gpost.
        .assert <PANEL = 0 && (>PANEL & 1) = 0, error, "marker: PANEL page-aligned, even"
marker: lda #0                     ; (no tile: address 0)
        sta gt0
        sta gt1
        lda GSHV
        beq @h
        lda #MAPZ                  ; the line, MAPZ - z (mod 32)
        sec
        sbc sz+2
        and #MAPN-1
        tax
        lsr a
        lsr a
        lsr a
        lsr a                      ; line >> 4 (C: bit 3)
        ora #>PANEL
        sta gt1
        txa
        and #7
        bcc @l
        ora #$80
@l:     sta gt0
        lda sx+2                   ; the pair, x + MAPX (mod 32): its byte, 8
        clc                        ; (pair >> 1), and which half (gt2: 0 left)
        adc #MAPX
        and #MAPN-1
        lsr a
        ror gt2
        asl a
        asl a
        asl a
        ora gt0
        sta gt0
@h:     lda gt0
        cmp mka
        bne @mv
        lda gt1
        cmp mka+1
        beq @r                     ; (unmoved)
@mv:    ldy #0
        lda mka+1                  ; the old tile's byte back
        beq @n
        sta g0+1
        lda mka
        sta g0
        lda mkb
        sta (g0),y
@n:     lda gt0                    ; the new one's address and byte kept, its
        sta mka                    ; pair made magenta (colour 2: the pair's
        sta g0                     ; high-nibble bits)
        lda gt1
        sta mka+1
        beq @r
        sta g0+1
        lda (g0),y
        sta mkb
        bit gt2
        bmi @rt
        and #$33                   ; the left pair
        ora #$C0
        sta (g0),y
@r:     rts
@rt:    and #$CC                   ; the right pair
        ora #$30
        sta (g0),y
        rts

PIXG    = PIXM                     ; pixel 0..3's bits (LAND's)

; ---------------------------------------------------------------- state
        .segment "HIB"             ; (uninitialised: the loader zeroes it)
gkb:    .res 1                    ; the keys down (keys' bits)
gk:     .res 1                    ; the ship's direction (0..NDIR-1) and pitch
gp:     .res 1                    ; (0..NPITCH-1, PFLAT level)
thr:    .res 1                    ; this step's thrust: 0 none, 1 full (2
                                   ; hover: DP11_MOUSE)
landed: .res 1                    ; 1: sitting on the pad
ctim:   .res 1                    ; crashed: steps left (0: flying)
sx:     .res 3                     ; position: x, z, y, 24-bit, 65536 a tile (y
sz:     .res 3                     ; 4096 a height unit)
sy:     .res 3
gvx:    .res 2                     ; velocity, 16-bit, 16384 a tile/Lander step
gvy:    .res 2                     ; (consecutive: step runs X over them)
gvz:     .res 2
su:     .res 2                     ; the ship's height in units, 8.8 (units')
fkey:   .res 1                    ; (keys': F's bit last time)
sstp:   .res 1                    ; (snd's: the crash's step)
dpass:  .res 1                    ; (dots': 0 the far dots, $80 the near)
tt0:    .res 1                    ; (tadd's)
tt1:    .res 1
sctl:   .res 1                     ; the noise control and attenuation bytes as
satt:   .res 1                     ; last written (ginit's: $FF)
rnd:    .res 1                    ; rand's state
scrg:   .res 1                    ; the screen being written to (high byte)
pnext:  .res 1                    ; emit's last dot
mka:    .res 2                     ; marker's: the tile's byte ($xx00: none)
mkb:    .res 1                     ; and what it held
        .segment "GAME"
        .include "gametab.inc"
        .segment "LOW1"            ; (the dots: page 1, and LOWP)
plife:  .res NPART                 ; the dots: life (0 dead); position x, z (8.8
ppx:    .res NPART                 ; tiles), y (8.8 units); velocity x, z (1/256
ppxh:   .res NPART                 ; tile), y (1/256 unit)
ppz:    .res NPART
ppzh:   .res NPART
ppy:    .res NPART
ppyh:   .res NPART
pvx:    .res NPART
pvxh:   .res NPART
        .segment "LOWP"
pvz:    .res NPART
pvzh:   .res NPART
pvy:    .res NPART
pvyh:   .res NPART
