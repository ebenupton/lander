;============================================================================
; game.s -- the 32K build's game (b32/src/land.s .includes it): Lander's flight
; over LAND's landscape, as src/game.s plays it, on the 64-tile map mapgen.s
; makes.  land.s's main loop calls ginit once, then gstep, gpre and gpost each
; frame around its projection, strips and the ship.  No banks: the game's
; tables and LAND's share the one memory.  The panel (the map, FUEL) is drawn
; at the start; gpost moves the ship's marker on it and redraws the gauge.
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
FUELMX  = 5120                     ; Lander's refuel limit (&1400): full
REFUEL  = 40                       ; a step on the pad (1.25 of Lander's &20)
BURN    = 5                        ; a step of thrust (1.25 of Lander's 4)
FBC     = 10                       ; the gauge: the FUEL row's byte columns
FBL     = 2                        ; FBC..FBC+19 (80 pixels: fuel >> 6), lines
                                   ; FBL..FBL+3


; ---------------------------------------------------------------- init
; ginit: once, by the loader (it is the loader's, BOOT: discarded after).
; Every dot dead; the sound chip silenced; the ship spawned on the pad; then
; gout, so the first projection has the camera.  Clobbers A, X, Y, g0, g1, gt0,
; gt2..gt4, su, scrg.
        .segment "BOOT"
ginit:  lda #$FF                   ; (the map's dot: none yet)
        sta mkl
        lda #$5A                   ; (the LFSR's seed: never 0)
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
        lda #128                   ; GSHX: the ship's screen x, always 128 (set
        sta GSHX                   ; once here, no longer by gout)
        jsr spawn
        jmp gout
SINI:   .byte $FF, $DF, $BF, $9F   ; noise, tone 2, 1, 0: attenuation 15 (off)
SININ   = * - SINI
        .segment "GAME"

; spawn: the ship on the pad, still, landed, level, facing SPAWNK, the tank
; full, drawn, no thrust; HGV set to the pad's height for gout before hgnd
; has run.  Clobbers A, X.  Called by ginit and by step when a crash ends.
spawn:  lda #0                     ; thr .. gvz+1 (P1's order: thr, landed, ctim,
        ldx #gvz+1-thr             ; sx, sz, sy, gv*) all 0; thr 0: snd's next
@z:     sta thr,x                  ; frame silence, not the crash's last step
        dex                        ; (landed, sx+2, sz+2, sy+1 set below)
        bpl @z
        lda #PADX                  ; the pad's middle tile in x and z
        sta sx+2
        sta sz+2
        lda #(PADH+UNDER)<<4 & 255 ; y = (PADH + UNDER) units: bytes 1 and 2 of
        sta sy+1                   ; units * 4096 (byte 2 is 0: zeroed above)
        .assert (PADH+UNDER)>>4 = 0, error, "spawn: sy+2 0, zeroed with thr .. gvz+1"
        lda #SPAWNP
        sta gp
        lda #SPAWNK
        sta gk
        .assert SPAWNK = PADH, error, "spawn: gk and HGV share SPAWNK's load"
        sta HGV                    ; PADH: the ground under it (hgnd's from then on)
        lda #<FUELMX               ; the tank full
        sta fuel
        lda #>FUELMX
        sta fuel+1
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
gout:   lda sx+1                   ; cxs = ((sx+1 - 128) & 255) >> 4 = (sx+1 >> 4)
        lsr a                      ; ^ 8; the CMP's C (sx+1 >= 128: no borrow
        lsr a                      ; from the subtraction of 128) into cxt's
        lsr a                      ; SBC (EOR keeps it)
        lsr a
        cmp #8
        eor #8
        sta cxs
        lda sx+2
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
        lda sy+2                   ; rel: the ship above the ground under it, in
        bmi gr_0                   ; whole units, 0..255: 255 from 16 tiles up
        cmp #16                    ; (su's whole byte has wrapped), 0 when below
        lda #$FF                   ; HGV or below y = 0 (both only while
        bcs gr_st                  ; crashed; LDA keeps the CMP's C)
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
gsy:                               ; the ship's line: HORIZON + (d R + 2048) >>
:       tay                        ; 12 (d R / 16, R = 19.7 the land's pixels a
:       lda GSHYT-KOFF,y           ; tile at depth ZSHIP), from GSHYT: d is
:       sta GSHY                   ; KOFF..CAMH (79..96: lines 81..102, inside
:                                  ; the old holds YSKY+14..YGND-16; the ':'s
                                   ; keep the anonymous label count)

        lda gk
        sta GSHK
        lda gp
        sta GSHP
        rts

; GSHYT: the ship's line, HORIZON + (d RSHIP + 2048) >> 12, for the camera d
; units above it, d = KOFF..CAMH (gout's d: never outside them; tools/
; gamegen.py's SHYT plus HORIZON; RSHIP the land's r at depth ZSHIP).  Its
; ends inside the holds YSKY+14 .. YGND-16, so those never bite.
GSHYT:
        .repeat CAMH-KOFF+1, I
        .byte (((KOFF+I)*RSHIP+2048)>>12)+HORIZON
        .endrepeat
        .assert ((KOFF*RSHIP+2048)>>12) >= YSKY+14-HORIZON, error, "GSHYT: d = KOFF within the hold"
        .assert ((CAMH*RSHIP+2048)>>12) <= YGND-16-HORIZON, error, "GSHYT: d = CAMH within the hold"

; units: su = sy >> 4, the ship's height in units as 8.8 (su+1 whole units,
; valid below 16 tiles).  Clobbers A, Y; X kept.
units:  lda sy+1                   ; su+1 = sy+2 << 4 | sy+1 >> 4
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
:       lda sy                     ; su = sy+1 << 4 | sy >> 4 (this : keeps the
        lsr a                      ; anonymous labels' count)
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
; down, 16 SPACE, 32 SHIFT.  Interrupts stay on (irq never touches port A, port
; B or DDRA, and a late E1 would cost the land a field).  Clobbers A,
; X.  DP11_MOUSE: with mdet set, also the mouse: 16 the left button, 128 the
; middle; writes mous, gmx, gmy; clobbers Y, gt0..gt3 too.  Called by gstep.
keys:   lda #0
        sta gkb
        lda #$7F                   ; port A: bits 0-6 out (the key's number),
        sta SVIA_DDRA              ; bit 7 in (pressed)
        lda #3                     ; latch bit 3 low: keyboard auto-scan off
        sta SVIA_ORB
        ldx #9                     ; the keys from kcode's end down: the same
@k:     lda kcode,x                ; order as before (Z first, SHIFT last)
        sta SVIA_ORA_NH
        lda SVIA_ORA_NH
        bpl @n
        lda kbit,x
        ora gkb
        sta gkb
@n:     dex
        bpl @k
        lda #$0B                   ; auto-scan back on
        sta SVIA_ORB
        rts
; kcode, kbit: keys' keys (internal numbers, bit 7 clear) and their gkb bits,
; scanned from the last entry down: Z, X:19, X, :79, K, :39, M, :29, SPACE,
; SHIFT.
kcode:  .byte $00, $62, $29, $65, $39, $46, $79, $42, $19, $61
kbit:   .byte 32, 16, 8, 8, 4, 4, 2, 2, 1, 1


; ---------------------------------------------------------------- sound
; snd: the noise channel of the SN76489 for this frame, written only where it
; changes (sctl, satt hold the control and attenuation bytes last written).
; Crashed (ctim): the step's crack-to-rumble, tone 2's period from EXNL, EXNH
; (written every step) and its attenuation from EXA, with SNCR (noise clocked
; by tone 2).  Flying: SNTH at SATF while thr is set, else attenuation 15.
; Reads ctim, thr.  Clobbers A, X, Y.  Called by gstep.
snd:    lda ctim
        beq @t
        lda #CRASHT                ; X = the crash's step, 0..CRASHT-1 (psg
        sec                        ; keeps X)
        sbc ctim
        tax
        lda EXNL,x                 ; tone 2's period: latch byte, then data byte
        jsr psg
        lda EXNH,x
        jsr psg
        lda EXA,x
        tax
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
; about 11us (longer if an interrupt comes: harmless; interrupts stay on, irq
; never touches port A, port B or DDRA).
; Leaves DDRA $FF (keys resets it).  Clobbers A, Y; X kept.
psg:
        ldy #$FF
        sty SVIA_DDRA
        sta SVIA_ORA_NH
        iny                        ; Y $FF -> 0: latch bit 0 low: write enable
        sty SVIA_ORB
        ldy #3
:       dey
        bne :-
        lda #8                     ; and high again
        sta SVIA_ORB
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
        ldy gkb                    ; (Y: gkb, for the four tests)
        tya
        lsr a                      ; bit 0: gk - 1
        bcc :+
        dec gk
:       lsr a                      ; bit 1: gk + 1 (A kept by the dec)
        bcc :+
        inc gk
:       lda gk                     ; gk mod NDIR (a power of 2 dividing 256),
        and #NDIR-1                ; after either or both
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
@att:   lda ctim                   ; crashed: the dots only, then the pad
        beq @fly
        dec ctim
        bne :+
        jsr spawn
:       jmp parts
@fly:
        lda gkb                    ; Y = 1 if SPACE or SHIFT (both full thrust)
        and #$30                   ; (bits 4, 5)
        beq :+
        lda #1
:       tay
        lda fuel                   ; none without fuel
        ora fuel+1
        beq @off
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
:       tya                        ; (Z: thr = 0)
        sta thr
        beq :+
        dey                        ; thrusting: off the ground (Y = thr = 1)
        sty landed
:       ldx #0                     ; drag, each of gvx, gvy, gvz (X 0, 2, 4):
@dg:                               ; v -= (v >> 6) + (v >> 8), 1.25 of Lander's
        lda gvx,x                  ; (one 16-bit subtract of the sum: the same
        sta gt0                    ; mod 65536).  Y = v's sign: v >> 8's high
        ldy #0                     ; byte, and the 24-bit extension of v << 2
        lda gvx+1,x
        bpl :+
        dey
:       sty gt1                    ; gt1:A:gt0 = (Y:hi:lo) << 2, so gt1:A =
        asl gt0                    ; v >> 6, arithmetic
        rol a
        rol gt1
        asl gt0
        rol a
        rol gt1
        clc                        ; + v >> 8 (Y:hi)
        adc gvx+1,x
        sta gt0
        tya
        adc gt1
        sta gt1
        lda gvx,x                  ; v (X) -= gt1:gt0
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
@th:
        lda thr                    ; thrust: BURN fuel, floor 0
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
:       jsr throw                  ; gvx += 1.25 (THX[gp][gk] << THRS), gvz from
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
@nt:    lda landed                 ; landed: still, refuelling REFUEL a step up
        beq @mv                    ; to FUELMX
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
@still: ldx #5                     ; (the landing joins here, A = 0)
:       sta gvx,x
        dex
        bpl :-
        jmp parts
        .assert (GRAV & 15) = 0 && GRAV > 0 && GRAV <= 2048, error, "step: -GRAV as a signed byte << 4"
@mv:    lda #<(-(GRAV >> 4))       ; gravity: gvy -= GRAV (y is up), as
        ldx #gvy-gvx               ; vadd's gvy += (-GRAV / 16) << 4
        ldy #4
        jsr vadd
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
        bcs @up                    ; (@up: jmp parts)
:       jsr units                  ; the centre less than UNDER units above HGV
        lda su+1                   ; (or below it): the ground
        sec
        sbc HGV
        bcc @gnd
        cmp #UNDER
        bcs @up
@gnd:   ldx #sz-sx                 ; over the pad: tiles 0..PADN-1 in z and x
@pd:    lda sx+2,x
        and #MAPN-1
        cmp #PADN
        bcs @crash
        dex
        dex
        dex
        bpl @pd
        .assert sz-sx = 3, error, "step's pad test: sz 3 bytes after sx"
        lda gp                     ; within a pitch of level: PFLAT-1..PFLAT+1
        sbc #PFLAT-2               ; (C clear from cmp #PADN: - (PFLAT-1))
        cmp #3
        bcs @crash
        jsr speed                  ; and slower than LANDV
        bcs @crash
        lda #1                     ; landed: y = (HGV + UNDER) units, still
        sta landed
        lda HGV
        clc
        adc #UNDER
        tax                        ; (X free: ldx #5 below)
        asl a                      ; (units * 4096: bytes 1 and 2)
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
:       jmp @still                 ; gv* 0 as when landed (A = 0), then parts
@crash: lda #CRASHT                ; crashed: CRASHT steps, the ship not drawn,
        sta ctim                   ; every dot from the ship
        lda #0
        sta GSHV
        jmp burst                  ; (it falls into parts)
@up:    jmp parts                  ; (@up: in the air, no ceiling)


; landoff: C set if the last frame's projection has the land wholly below the
; screen: every point (np a row) of every row (nr, 16 bytes apart in PY) past
; YGND; C clear at the first point on the screen.  Clobbers A, X, gt0, gt1; Y
; kept (step's thrust).  Called by step.
landoff:
        tya
        pha
        .assert <PY = 0, error, "landoff: PY page-aligned"
        lda #<PY                   ; @p's operand: row 0's (patched: PY + 16 k)
        sta @p+1
        ldx nr                     ; X the rows left, Y the row's points
@r:     ldy np                     ; left, np-1 down to 0 (Y saved on the stack)
        dey
@p:     lda PY,y
        cmp #YGND+1
        bcc @v
        dey
        bpl @p
        lda @p+1                   ; the next row (C set: the CMP's)
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
        lda gk                     ; THZ(k) = -THX(k - 8) = THX(k + 8): thc(m + 16)
        clc                        ; = -thc(m) (same j, opposite sign; TQ's j 8
        adc #8                     ; entries, both signs positive, are all 0)
        jsr thc
        sta tz
        ldx thxs
        rts
; thc: THX for pitch gp and direction A & 31.  Clobbers X, Y, gt0, gt1.
thc:    and #31
        cmp #17                    ; 17..31: 32 - k (cos even)
        bcc @a
        eor #$FF                   ; (C set: ~k + 32 + 1)
        adc #32
@a:     ldx #0                     ; X: the negations, 0..2 (1: negative)
        cmp #9                     ; 9..16: 16 - k, negated
        bcc @b
        eor #$FF                   ; (C set: ~k + 16 + 1)
        adc #16
        inx
@b:     sta gt0                    ; j, 0..8
        lda gp                     ; |gp - PFLAT|, negated below level
        sec
        sbc #PFLAT
        bcs @c
        eor #$FF                   ; (C clear: + 1)
        adc #1
        inx
@c:     sta gt1                    ; TQ + 9 |gp - PFLAT| + j
        asl a
        asl a
        asl a
        adc gt1                    ; (C clear: 8 |p| < 256)
        adc gt0
        tay
        lda TQ,y
        cpx #1                     ; (negative: equal, C set, so ~v + 0 + 1)
        bne @d
        eor #$FF
        adc #0
@d:     rts
        .segment "P1L"
thxs:   .res 1                     ; throw's X
tx:     .res 1                     ; throw's thrust, x and z
tz:     .res 1
        .segment "GAME"

; tadd: v (X: gvx, gvy or gvz's offset) += 1.25 (A << THRS), as A << THRS
; then A << (THRS - 2).  Clobbers A, Y (0), gt0, gt1; X kept.  Called by
; step.
        .assert THRS >= 3, error, "tadd: both of vadd's shifts at least 1"
tadd:   pha
        ldy #THRS
        jsr vadd
        pla
:       ldy #THRS-2                ; (falls into vadd; the label keeps the
                                   ; anonymous labels' count)
; vadd: v (X: gvx, gvy or gvz's offset) += A (signed) << Y (1..255), 16-bit.
; Clobbers A, Y (0), gt0, gt1; X kept.  Called by tadd and step.
vadd:   sta gt0
        and #$80                   ; gt1: A's sign extension (0 or $FF)
        bpl :+
        lda #$FF
:       sta gt1
:       asl gt0
        rol gt1
        dey
        bne :-
:       lda gvx,x
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
pmove:  lda gvx+1,x
        sta gt1
        bpl :+                     ; gt2 (and gt3): v's sign extension
        lda #$FF
        bne @sgn                   ; (always)
:       lda #0
@sgn:   sta gt2
        sta gt3
        lda gvx,x                  ; gt2:gt1:A = 4 v
        asl a
        rol gt1
        rol gt2
        asl a
        rol gt1
        rol gt2
        clc                        ; + v
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
        ldx #gvz-gvx               ; (z, y, x: the 16-bit sum is the same)
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
        dex
        dex
        bpl @a
        .assert <LANDV = 0, error, "speed: LANDV's low byte 0 (gt3 alone compared)"
        cmp #>LANDV                ; (A = gt3)
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
        lda tx                     ; x: -THX / 2 + jitter, sign-extended, +
        ldy #gvx-gvx               ; gvx >> 6 (16384ths of a tile to 256ths)
        jsr ejit
        sta pvx,x
        tya
        adc gt3
        sta pvxh,x
        lda tz                     ; z likewise
        ldy #gvz-gvx
        jsr ejit
        sta pvz,x
        tya
        adc gt3
        sta pvzh,x
        ldy gp                     ; y: gt1:gt0 = -(THY + 1) << 3 (gt1 built
        lda THY,y                  ; in A: $FF, three bits rolled in)
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
        lda gvy                    ; gt3:gt2 = gvy asr 2 (1024ths of a unit to
        sta gt2                    ; 256ths): the high byte kept in A
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
; ejit: emit's x or z velocity: -A / 2 (A the thrust, signed: negate, then
; asr) + a jitter of -16..15 (rand), sign-extended, + v >> 6 (Y: gvx or
; gvz's offset).  Out: A the low byte, C its carry, Y the jitter's sign
; extension (the high byte is Y + gt3 + C).  Clobbers gt0, gt2, gt3; X kept.
; Called by emit.
ejit:   eor #$FF
        clc
        adc #1
        cmp #$80
        ror a
        sta gt0
        lda gvx,y                  ; gt3:gt2 = v >> 6, arithmetic (the high
        sta gt2                    ; byte shifted in A)
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
; bjit: burst's x or z velocity: A = (rand & 127) - 64, -64..63, Y its sign
; extension (falls into sxadd).  Clobbers A, Y; X kept.  Called by burst.
bjit:   jsr rand
        and #127
        sec
        sbc #64
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
        jsr bjit                   ; x: -64..63 (rand), Y its sign
        sta pvx,x
        tya
        sta pvxh,x
        jsr bjit                   ; z likewise
        sta pvz,x
        tya
        sta pvzh,x
        jsr rand
        sta pvy,x
        and #3
        sta pvyh,x
        dex
        bpl @b                     ; (falls into parts: step's crash)

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
        tya                        ; (Y: q5's high byte)
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
        ror a                      ; bit 7 = C eor the step's sign: set when a
        sty gt1                    ; (the step's high byte)
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

; q5: Y:gt0 = 1.25 (Y:A), signed: Y:A + (Y:A asr 2).  Clobbers A, gt1,
; gt2; X kept.  Called by parts.
q5:     sta gt2                    ; Y:A kept: gt2 the low byte, Y the high
        sty gt1                    ; gt1:A = Y:A asr 2 (cpy #$80: C = the sign)
        cpy #$80
        ror gt1
        ror a
:       cpy #$80
        ror gt1
        ror a
        clc                        ; + Y:A
        adc gt2
        sta gt0
        tya
        adc gt1
        tay                        ; (the high byte returned in Y)
        rts

; ---------------------------------------------------------------- post
; gpre (G_PRE, after the strips, before the ship): the live dots beyond the
; ship in z, each a pixel on the screen being drawn, the column's TOPS and
; BOTS widened over it so the strips that next draw this screen take it off.
; gpost (G_POST, after the ship): the dots nearer than the ship, then the
; map's ship marker.  Both clobber A, X, Y, g0, g1,
; gt0..gt5, su, tsg, bsg, scrg, dpass.
gpre:   jsr dset
        jsr units                  ; (su once a frame: sy and su are unchanged
        lda #0                     ; from here through the ship to gpost)
        beq dots
gpost:  jsr dset
        lda #$80
        jsr dots
        jsr marker
        ; falls into status
; status: the fuel gauge on the top frame's row 0 (TOP), as the full build's:
; redrawn when its length differs from what it shows (fdr): fuel >> 6 pixels (80
; full), yellow, four lines deep (FBL..FBL+3) over byte columns FBC..FBC+19,
; each byte BARB by the pixels left for it.  Clobbers A, X, Y, gt1.
status: lda fuel+1                 ; gt1 = fuel >> 6
        sta gt1
        lda fuel
        asl a
        rol gt1
        asl a
        rol gt1
        lda gt1
        cmp fdr
        beq @x
        sta fdr
        ldx #FBC*8                 ; X: the column's first byte in the row
@b:     lda gt1                    ; (pixels left to draw)
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
        sbc #4                     ; (C: the CMP's; set only for 4 or more)
        bcs :+
        lda #0
:       sta gt1
        txa
        clc
        adc #8
        tax
        cpx #(FBC+20)*8
        bcc @b
@x:     rts
        .assert FBC+20 <= 48, error, "status: the gauge left of the map"
BARB:   .byte $00, $88, $CC, $EE, $FF   ; 0..4 pixels lit from the left, colour 3
; dset: scrg = the screen being drawn (scrb); tsg, bsg = its TOPS and BOTS
; (the set sidx picks for back).  Clobbers A, X, Y.  (gpre computes su.)
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
        clc                        ; off unless -8 <= dx < 8
        adc #8
        cmp #16
        bcc :+
@o1:    jmp @o
:       asl a                      ; screen x = 128 + 16 dx: A = dx + 8 (0..15,
        asl a                      ; dx's whole byte -8..7), so A << 4 is the
        asl a                      ; whole byte's << 4 with bit 7 flipped (the
        asl a                      ; + 128), then or dx's fraction >> 4
        sta gt2
:       lda gt0                    ; (this : keeps the anonymous labels' count)
        lsr a
        lsr a
        lsr a
        lsr a
        ora gt2
        sta gt2                    ; (screen x)
        lda su                     ; dy = the ship's height less the dot's,
        cmp ppy,x                  ; whole units (the fraction only borrows: C)
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
        eor #$FF                   ; y = GSHY + dy - 4 dz, within YSKY..YGND:
        sec                        ; dy - 4 dz first (~A + 1 = -A, A = 4 dz),
        adc gt3                    ; then + GSHY (all mod 256)
        clc
        adc GSHY
        cmp #YSKY
        bcc @o
        cmp #YGND+1
        bcs @o
        sta gt3                    ; (screen y)
        ; the byte: scrg + $200 (y >> 3) + 8 (x >> 2) + (y & 7)
        lsr a
        lsr a
        and #$FE                   ; 2 (y >> 3), held in Y
        tay
        lda gt3
        and #7
        sta g0
        lda gt2
        and #$FC
        asl a                      ; (8 (x >> 2): its carry is the $100 bit,
        ora g0                     ; kept by ora, sta and tya into the adc)
        sta g0
        tya
        adc scrg
        sta g0+1
        lda gt2                    ; the pixel's bits (PIXG by x & 3) masked
        and #3                     ; out of the byte, then set: both for yellow,
        tay                        ; the high one only for magenta (life < 6)
        lda PIXG,y
        sta gt4                    ; the byte with gt4's bits set to V ($FF
        ldy plife,x                ; yellow, $F0 magenta): b ^ ((b ^ V) & gt4)
        cpy #6
        lda #$FF
        bcs :+
        lda #$F0
:
        ldy #0
        eor (g0),y
        and gt4
        eor (g0),y
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

; marker: the ship's dot on the map, as the full build's: 2 x 2 pixels,
; magenta, while GSHV is set -- its top line MAPZ - z's tile, one less if z's
; fraction is 1/2 or more; its left pixel x's tile + MAPX - 1, one more if x's
; fraction is 1/2 or more; both mod 64 (the map wraps), its pixels (p, l), (p+1,
; l), (p+1, l+1), (p, l+1).  The bytes it covers are kept (mka, mkb: four, the
; same byte possibly more than once) and put back, last first, when it moves
; (mkl, mkp: its place; mkl $FF none: ginit's).  Clobbers A, X, Y, g0, gt0..gt3.
; Called by gpost.
marker: lda #$FF                   ; (no dot)
        sta gt0
        lda GSHV
        beq @h
        lda sz+1                   ; the top line (C clear from the ASL of the
        eor #$FF                   ; inverted fraction: z's 1/2 or more)
        asl a
        lda #MAPZ
        sbc sz+2
        and #63
        sta gt0
        lda sx+1                   ; the left pixel (C: x's fraction 1/2 or more)
        asl a
        lda sx+2
        adc #MAPX-1
        and #63
        sta gt1
@h:     lda gt0
        cmp mkl
        bne :+
        lda gt1
        cmp mkp
        bne :+
        rts                        ; (unmoved)
:       ldx mkl                    ; the old dot's bytes back, the last first
        bmi :+
        ldx #3
@b:     lda mka,x
        sta g0
        lda mkah,x
        sta g0+1
        ldy #0
        lda mkb,x
        sta (g0),y
        dex
        bpl @b
:       lda gt0                    ; the new one: its place, its bytes kept, its
        sta mkl                    ; pixels magenta (colour 2: the pixel's high
        bmi @r                     ; bit)
        lda gt1
        sta mkp
        ldx #0                     ; (X: the pixel, 0..3)
        jsr @px
        inc gt1
        jsr @px
        inc gt0
        jsr @px
        dec gt1
@px:    lda gt0                    ; pixel (gt1, gt0) & 63: MAP + 128 (l >> 3) +
        and #8                     ; 8 (p >> 2) + (l & 7)
        asl a
        asl a
        asl a
        asl a
        sta g0
        lda gt0
        and #7
        ora g0
        sta g0
        lda gt1
        and #$3C
        asl a
        ora g0
        sta g0
        sta mka,x
        lda gt0
        and #$30
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #>MAP
        sta g0+1
        sta mkah,x
        lda gt1
        and #3
        tay
        lda PIXG,y
        sta gt2                    ; (the pixel's bits)
        and #$F0
        sta gt3                    ; (its magenta)
        ldy #0
        lda (g0),y
        sta mkb,x
        ora gt2
        eor gt2
        ora gt3
        sta (g0),y
        inx
@r:     rts
        .assert <MAP = 0, error, "marker: MAP page-aligned"

PIXG    = PIXM                     ; pixel 0..3's bits (LAND's)

; ---------------------------------------------------------------- state
        .segment "P1L"              ; (uninitialised: the loader zeroes it)
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
fuel:   .res 2                    ; 0..FUELMX
fdr:    .res 1                    ; (status's: the gauge's length shown)
sstp:   .res 1                    ; (snd's: the crash's step)
dpass:  .res 1                    ; (dots': 0 the far dots, $80 the near)
tt0:    .res 1                    ; (tadd's)
tt1:    .res 1
sctl:   .res 1                     ; the noise control and attenuation bytes as
satt:   .res 1                     ; last written (ginit's: $FF)
rnd:    .res 1                    ; rand's state
scrg:   .res 1                    ; the screen being written to (high byte)
pnext:  .res 1                    ; emit's last dot
mkl:    .res 1                     ; marker's: the dot's top line ($FF: none),
mkp:    .res 1                     ; its left pixel
        .segment "P2T"
mka:    .res 4                     ; marker's: its four pixels' bytes' addresses
mkah:   .res 4                     ; (low, high) and what they held
mkb:    .res 4
        .segment "GAME"
        .include "gametab.inc"
        .segment "GA0"             ; (the dots: b32.cfg's GA0, GA1, P1L, LOWP)
plife:  .res NPART                 ; the dots: life (0 dead); position x, z (8.8
ppx:    .res NPART                 ; tiles), y (8.8 units); velocity x, z (1/256
ppxh:   .res NPART                 ; tile), y (1/256 unit)
ppz:    .res NPART
        .segment "GA1"
ppzh:   .res NPART
ppy:    .res NPART
ppyh:   .res NPART
pvx:    .res NPART
        .segment "P1L"
pvxh:   .res NPART
        .segment "LOWP"
pvz:    .res NPART
pvzh:   .res NPART
pvy:    .res NPART
pvyh:   .res NPART
