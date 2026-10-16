; ============================================================================
; game.s -- the game: Lander's flight over LAND's landscape.  Assembled into
; sideways RAM bank 5 from $A100 (segment B5GAME, .included at the end of
; land.s; build.sh lays the segment into TABLES2, which LANDS loads into bank
; 5).  Four entries, a jump table; land.s's main loop reaches them through
; call5 (bank 5 paged in for the call, bank 4 back after):
;   G_INIT  $A100  once, after LAND's init: the map and the FUEL label on
;                  both screens, the state cleared, the sound chip quiet, the
;                  ship on the pad, the camera set (gout)
;   G_STEP  $A103  first in each frame: the keys, the sound, one step of the
;                  flight model, then the camera for LAND and the ship for
;                  bank 6
;   G_PRE   $A109  after the strips, before the ship: the dots beyond the
;                  ship in z
;   G_POST  $A106  after the ship: the dots nearer than it, the map's ship
;                  marker, the fuel bar
; Between G_STEP and G_PRE LAND projects and draws the land; bank 6 (shipb.s)
; copies GSHK..GSHY at B6_KEYS and draws the ship at B6_SHIP, which land.s
; skips while GSHV is 0 (crashed).  Bank 4 (LAND's tables) is paged out while
; the game runs, so the game carries its own pixel masks (PIXG) and its tables
; (build/gametab.inc, from tools/gamegen.py).  The game's letters sit at GLY5
; ($BE00) in this bank, put there by LANDS's glyphs5: the code and tables must
; end below them.
;
; Shared low RAM, $07D6, $07D7 and $07DB..$07DF: CAME (written here, read by
; LAND's projection:
; the camera raised above CAMH, 0..EMAX height units), HGV (written by LAND's
; hgnd each frame: the ground under the ship in whole height units, read
; here), GSHK, GSHP, GSHX, GSHY (the ship's direction, pitch, screen x and
; line, for bank 6) and GSHV (1: the ship is drawn; land.s reads it).  LAND's
; own used here: cxt, cxs, czt, czs (the camera, written by gout), PY, np, nr
; (the last frame's projected rows, read by landoff), back, scrb, sidx,
; setTl..setBh (the screen being drawn and its TOPS, BOTS), fpson (the
; frame-rate readout's switch).
; Zero page $8E..$9B (g0, g1, gt0..gt5, tsg, bsg) is LAND's spare, scratch
; within a single call.
;
; Controls (the keyboard read directly through the system VIA): Z or left and
; X or right turn the ship (gk: 32 directions, one a frame while held); K or
; up tips the nose down, M or down up (gp: 13 pitches 10 degrees apart, 60
; either way at most, one a frame while held); SPACE or SHIFT thrust (both
; full thrust; thrust goes the way the ship is tilted, so nose down flies
; forward); F toggles LAND's frame-rate readout.  Fuel burns while thrusting.
; With a mouse at $FCAC..$FCAF (ginit's test: mdet) it steers instead, as
; Lander's: its movement moves a pointer (gmx, gmy) whose polar form sets the
; targets (attit), the left button full thrust, the middle hover (a quarter;
; Lander's), the spawn puts the pointer back at its centre.
; Touching the ground over the pad (tiles 0..PADN-1 in x and z) slowly and
; within a pitch step of level lands: the ship sits still and refuels.
; Touching it anywhere else, or too fast or too tilted, crashes: CRASHT steps
; of dots with the ship gone, then the ship back on the pad.
;
; Units.  Positions sx, sz, sy are 24-bit, 65536 a tile (byte 2 the tile,
; byte 1 the 1/256 fraction; x and z wrap at 64 tiles, the map's); y is up,
; in height units of 4096 (16 a tile, LAND's HSCALE; su is y in units, 8.8).
; Velocities gvx, gvy, gvz are 16-bit in Lander's units: 16384 a tile per
; Lander step (a Lander step moves a position 4 v, in 65536ths).  Lander runs a
; step per main-loop iteration; here a step is a frame at 10 a second (LAND's
; flip allows 12.5 at most) and each step is taken as 1.25 of Lander's:
; positions move 5 v, gravity, thrust, drag and fuel are 1.25 times Lander's
; per step, and the velocities stay in Lander's units, so LANDV is Lander's
; unchanged.  Directions k: 0 faces +x, 8 towards the camera (-z), 16 -x, 24
; away (+z).  Pitches p: PFLAT (6) level, more nose down, less nose up.
;
; The camera (gout) is half a tile left of the ship in x (LAND's screen centre
; is half a tile right of its camera x), ZSHIP tiles behind it in z, and
; CAMH + CAME height units above the ground under the ship.  CAME rises with
; the ship so the camera stays at least KOFF units above it, which holds the
; ship at screen line HORIZON + SHYT[KOFF] = 81 once it is CAMH - KOFF (17)
; units above the ground.  Past CAME = EMAX LAND draws every row below the
; screen, so the land vanishes and the ship stays at that line.  The engines
; cut out once the land has left the screen (Lander's HIGHEST_ALTITUDE in
; effect); there is no ceiling: the ship coasts up and falls back.
;
; The top 64 lines of each screen are the game's (LAND draws from YSKY): the
; FUEL bar on character row 0, LAND's frame-rate readout on row 2, the map
; (64 x 64 pixels, a tile each, the pad in the middle) at the top right, with
; the ship a 2 x 2 magenta dot on it.
; ============================================================================

GSHK    = $07DB                    ; the ship for bank 6 (B6_KEYS copies these
GSHP    = $07DC                    ; four): direction, pitch, screen x (128),
GSHX    = $07DD                    ; screen line
GSHY    = $07DE
GSHV    = $07DF                    ; 1: the ship is drawn (0 while crashed)
GLY5    = $BE00                    ; the labels' letters, 16 bytes each, in this
                                   ; bank (LANDS's glyphs5: "FUELANDCRSH")

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
MSXL    = $FCAC                    ; the mouse (where fitted): each read the
MSXH    = $FCAD                    ; movement since the last, 14-bit, 4 a
MSYL    = $FCAE                    ; count, y up; MSXH bits 6, 7 the left and
MSYH    = $FCAF                    ; right buttons, MSYH bit 6 the middle, bit 7
                                   ; the mouse present; read in this order

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
HOVS    = 1                        ; hover: << 1, a quarter of it (Lander's)
LANDV   = 2048                     ; Lander's LANDING_SPEED, 1/8 tile a step:
                                   ; |gvx| + |gvy| + |gvz| must be below it
UNDER   = 4                        ; the ship's centre above its underside, in
                                   ; height units: a quarter tile
EOFF    = 60                       ; CAME below this: the land is on the screen,
                                   ; landoff's scan skipped
KOFF    = 79                       ; the camera's least height above the ship,
                                   ; height units: SHYT[KOFF] = 97, line 81
FUELMX  = 5120                     ; Lander's refuel limit (&1400): full
REFUEL  = 40                       ; a step on the pad (1.25 of Lander's &20)
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
FUELR   = 0                        ; the fuel bar: character row 0, lines 2..5,
FBL     = 2                        ; byte columns 10..29 (80 pixels: fuel >> 6)
FBC     = 10

        .segment "B5GAME"
        .assert * = $A100, error, "the game's entries at $A100 (G_INIT..G_PRE)"
        jmp ginit                  ; G_INIT
        jmp gstep                  ; G_STEP
        jmp gpost                  ; G_POST
        jmp gpre                   ; G_PRE

; ---------------------------------------------------------------- init
; ginit (G_INIT): once, after LAND's init has blacked both screens.  The map
; and the FUEL label on both screens; the marks cleared; every dot dead; the
; sound chip silenced; the ship spawned on the pad; then gout, so LAND's first
; projection has the camera and bank 6 the ship.  Clobbers A, X, Y, g0, g1,
; gt0, gt2..gt4, su, scrg.
ginit:  lda #$30
        jsr gscr
        lda #$58
        jsr gscr
        lda #$FF                   ; $FF: nothing drawn yet on either screen
        sta mkl
        sta mkl+1
        sta fdr
        sta fdr+1
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
        lda MSXL                   ; the mouse: a read clears the counts, so a
        lda MSXH                   ; second straight after reads no movement
        lda MSYL                   ; and the present bit; anything else (an
        lda MSYH                   ; empty bus reads back $FC) is no mouse
        ldx #0
        lda MSXL
        bne :+
        lda MSXH
        and #$3F
        bne :+
        lda MSYL
        bne :+
        lda MSYH
        cmp #$80
        and #$3F
        bne :+
        bcc :+
        inx
:       stx mdet
        jsr spawn
        jmp gout
SINI:   .byte $FF, $DF, $BF, $9F   ; noise, tone 2, 1, 0: attenuation 15 (off)
SININ   = * - SINI

; gscr: the top of screen A (its high byte, $30 or $58): the map, MAPI's 64
; lines of 16 bytes, at byte columns 48..63 of character rows 0..7; then the
; labels (LABT) in GLY5's letters.  Out: scrg = A.  Clobbers A, X, Y, g0, g1,
; gt0, gt2, gt3, gt4.  Called by ginit.
gscr:   sta gt4
        lda #<MAPI
        sta g1
        lda #>MAPI
        sta g1+1
        ldx #0                     ; X: the map line, 0..63
@l:     txa                        ; the line's first byte: screen + $200 (line
        and #7                     ; >> 3) + $180 (column 48) + (line & 7)
        ora #$80
        sta g0
        txa
        lsr a
        lsr a
        and #$FE                   ; 2 (line >> 3), plus 1 for $180's $100
        sec
        adc gt4
        sta g0+1
        ldy #0
:       sty gt0                    ; byte Y to column 48 + Y: 8 Y on
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
        lda gt4                    ; the labels: each LABT entry a row, a column
        sta scrg                   ; and letters up to $FF; a row of $FF ends
        ldx #0                     ; the list
@t:     lda LABT,x
        bmi @td
        sta gt2
        lda LABT+1,x
        sta gt3
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
LABT:   .byte FUELR, 0, 0, 1, 2, 3, $FF                ; "FUEL": row 0, column 0
        .byte $FF

; putl: letter A of GLY5 (16 bytes each) at character row gt2, column gt3
; (0..15, 8 pixels wide) of screen scrg.  Clobbers A, Y, g0, g1.  Called by
; gscr.
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
; putc: the 16 bytes at (g1) to row gt2, column gt3 of screen scrg: the cell
; is two byte columns of 8 lines, 16 consecutive bytes at scrg + $200 row +
; 16 column (the column 0..15: 16 column is a byte).  Clobbers A, Y, g0.
putc:   lda gt3
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
        .assert SPAWNK = 4, error, "the pointer's start is SPAWNK's direction"
        lda #1                     ; the pointer a count off its centre towards
        sta gmx                    ; SPAWNK, so the ship keeps it (Lander puts
        sta gmy                    ; its pointer a unit off centre likewise)
        lda #SPAWNP
        sta gp
        lda #PADH                  ; the ground under it (hgnd's from then on)
        sta HGV
        lda #<FUELMX
        sta fuel
        lda #>FUELMX
        sta fuel+1
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
        and #63
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
        and #63
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
gsy:    tax                        ; the ship's line: HORIZON + SHYT[d] (d R /
        lda SHYT,x                 ; 16, R = 19.7 the land's pixels a tile at
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
; X.  Called by gstep.
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
        lda mdet                   ; the mouse, if found at the start
        beq @f
        lda MSXL                   ; the movement into the pointer, x as it
        sta gt0                    ; is, y reversed (Lander's y is towards the
        lda MSXH                   ; player); the left button full thrust (16,
        tax                        ; SPACE's bit), the middle hover (128); the
        lda MSYL                   ; right (Lander's fire) nothing
        sta gt2
        lda MSYH
        sta gt3
        asl a                      ; (the present bit: attit or the keys)
        lda #0
        rol a
        sta mous
        txa
        and #$40
        beq :+
        lda #16
:       bit gt3
        bvc :+
        ora #128
:       ora gkb
        sta gkb
        txa
        jsr mdel
        ldx #gmx-gmx
        jsr madd
        lda gt2
        sta gt0
        lda gt3
        jsr mdel
        lda #0                     ; (negated)
        sec
        sbc gt0
        sta gt0
        lda #0
        sbc gt1
        sta gt1
        ldx #gmy-gmx
        jsr madd
@f:     lda gkb
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

; mdel: gt1:gt0 = the movement whose bits 8-13 are A's bits 0-5 (sign
; extended) and bits 0-7 gt0, over 4: in counts.  Clobbers A, Y.  Called by
; keys.
mdel:   and #$3F
        cmp #$20
        bcc :+
        ora #$C0
:       ldy #2
:       cmp #$80
        ror a
        ror gt0
        dey
        bne :-
        sta gt1
        rts
; madd: the pointer's byte at gmx + X += gt1:gt0, held within -128..127
; (Lander's pointer box, 1024 units).  Clobbers A, Y, gt0.  Called by keys.
madd:   ldy #0
        lda gmx,x
        bpl :+
        dey
:       clc
        adc gt0
        sta gt0
        tya
        adc gt1
        tay                        ; Y: the sum's high byte; in range if it is
        lda gt0                    ; the low byte's sign
        asl a
        tya
        adc #0
        beq @ok
        lda #$7F                   ; out: the nearer end
        cpy #$80
        bcc @st
        lda #$80
        bne @st
@ok:    lda gt0
@st:    sta gmx,x
        rts

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
; step: one step of the model.  The attitude from gkb: Z/left and X/right
; turn gk one direction (mod NDIR), K/up and M/down move gp a pitch
; towards NPITCH-1 (nose down) or 0 (nose up).  Crashed: ctim counts down,
; spawn at 0, only the dots move.  Flying: thr from SPACE or SHIFT, denied
; without fuel, from 16 tiles up, or once the land has left the screen (CAME
; past EOFF and landoff's scan); thrust lifts off (landed cleared); drag;
; thrust, fuel and an exhaust dot; landed: velocities zeroed and REFUEL a
; step up to FUELMX; else gravity, the move, and the ground test: the ship's
; centre less than UNDER units above HGV (or below it, or y below 0) is a
; touch, a landing
; if over the pad, within a pitch of level and slower than LANDV, else a
; crash (burst, GSHV 0, ctim CRASHT).  Finally parts.  Reads gkb, fuel, sy,
; CAME, HGV; writes gk, gp, ctim, thr, landed, gv*, s*, fuel, GSHV.  Clobbers A, X, Y, g0, g1, gt0..gt5, tt0, tt1.  Called by gstep.
step:   lda mous                   ; the mouse: Lander's attitude from it
        beq :+
        jsr attit
        jmp @att
:       lda gkb
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
@fly:   ldy #1                     ; Y = 1 if SPACE, SHIFT or the left button
        lda gkb                    ; (full thrust), else 2 for the middle
        and #$30                   ; (hover), else 0
        bne :+
        iny
        lda gkb
        bmi :+
        ldy #0
:
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
        lda thr                    ; thrust: gt5 the shift, gt4 the fuel a step:
        beq @nt                    ; full THRS and 5, hover HOVS and 3 (Lander's
        ldx #THRS                  ; 4 and 2, times 1.25)
        ldy #5
        lsr a
        bcs :+
        ldx #HOVS
        ldy #3
:       stx gt5
        sty gt4
        lda fuel                   ; fuel -= gt4, floor 0
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
:       jsr throw                  ; gvx += 1.25 (THX[gp][gk] << gt5), gvz from
        lda (g0),y                 ; THZ, gvy from THY[gp]
        ldx #gvx-gvx
        jsr tadd
        lda (g1),y
        ldx #gvz-gvx
        jsr tadd
        ldy gp
        lda THY,y
        ldx #gvy-gvx
        jsr tadd
        lda thr                    ; a dot a step at full thrust, every fourth
        lsr a                      ; hovering (Lander's 8 and 2)
        bcs :+
        inc hcnt
        lda hcnt
        and #3
        bne @nt
:       jsr emit
@nt:    lda landed                 ; landed: still, refuelling REFUEL a step
        beq @mv                    ; up to FUELMX
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
        and #63
        cmp #PADN
        bcs @crash
        lda sz+2
        and #63
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

; attit: the attitude from the mouse, as Lander's: the pointer (gmx, gmy)
; in polar form, its angle the target direction (atan2(gmy, gmx) in 32nds:
; right 0, towards the player 8, so the ship faces the way the mouse went)
; and its distance r the target pitch, PFLAT + Lander's 11.25 degrees
; sqrt(r*r/64 rounded down) in 10-degree pitches, 6 at most (r from 39.2
; counts); each moves halfway to its target a step, at least a pitch or a
; direction, the direction the short way round and at most 3 (Lander's
; 67.5-degree cap halved).  At the centre the direction stays.  Reads gmx,
; gmy; writes gk, gp.  Clobbers A, X, Y, gt0..gt5.  Called by step.
attit:  lda gmx                    ; gt0 = |gmx|, gt1 = |gmy| (0..128)
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta gt0
        lda gmy
        bpl :+
        eor #$FF
        clc
        adc #1
:       sta gt1
        ldx #6                     ; the pitch: 6 if either is 40 or more,
        lda gt0                    ; else the thresholds R2 that r*r reaches
        cmp #40
        bcs @pt
        lda gt1
        cmp #40
        bcs @pt
        ldx gt0
        ldy gt1
        lda SQL,x
        clc
        adc SQL,y
        sta gt2
        lda SQH,x
        adc SQH,y
        sta gt3
        ldx #0
:       lda gt2
        cmp R2L,x
        lda gt3
        sbc R2H,x
        bcc @pt
        inx
        cpx #6
        bne :-
@pt:    txa
        clc
        adc #PFLAT
        sec
        sbc gp
        jsr half
        clc
        adc gp
        sta gp
        lda gt0                    ; the direction: none at the centre
        ora gt1
        beq @r
        lda gt0                    ; within the octant: atan(small / large)
        cmp gt1
        bcc :+
        sta gt4
        lda gt1
        jsr octj
        jmp @q
:       lda gt1
        sta gt4
        lda gt0
        jsr octj
        eor #$FF                   ; (8 - that: nearer y)
        sec
        adc #8
@q:     ldx gmx                    ; folded by the quadrant: gmx < 0, 16 - a;
        bpl :+                     ; gmy < 0, - a
        eor #$FF
        sec
        adc #16
:       ldx gmy
        bpl :+
        eor #$FF
        clc
        adc #1
:       sec                        ; d = target - gk, -16..15, held to -6..6
        sbc gk
        and #31
        cmp #16
        bcc :+
        ora #$E0
        cmp #<-6
        bcs @h
        lda #<-6
        bne @h
:       cmp #7
        bcc @h
        lda #6
@h:     jsr half
        clc
        adc gk
        and #NDIR-1
        sta gk
@r:     rts
; half: A (signed) halved away from 0, so never 0 unless A is.  Called by
; attit.
half:   tax
        beq @z
        bmi :+
        clc
        adc #1
        lsr a
@z:     rts
:       eor #$FF                   ; -((|A| + 1) >> 1)
        clc
        adc #2
        lsr a
        eor #$FF
        clc
        adc #1
        rts
; octj: A = atan(A / gt4) in 32nds of a turn, 0..4 (A <= gt4, gt4 > 0): the
; quotient's 8 bits (256 A / gt4, a restoring division) against ATT, the
; tangents of the half-way angles.  Clobbers A, X, Y, gt5.  Called by attit.
octj:   cmp gt4
        beq @4
        ldy #8
:       asl a
        cmp gt4
        bcc :+
        sbc gt4
:       rol gt5
        dey
        bne :--
        lda gt5
        ldx #0
:       cmp ATT,x
        bcc :+
        inx
        cpx #4
        bne :-
:       txa
        rts
@4:     lda #4
        rts
ATT:    .byte 26, 78, 137, 211     ; 256 tan 5.625, 16.875, 28.125, 39.375
                                   ; degrees, rounded up
R2L:    .byte <64, <128, <320, <640, <1024, <1536   ; r*r at Lander's 11.25
R2H:    .byte >64, >128, >320, >640, >1024, >1536   ; sqrt 1, 2, 5, 10, 16, 24
                                   ; degrees: 10, 20 .. 60 rounded
SQL:                               ; n * n, n 0..39
        .repeat 40, I
        .byte <(I*I)
        .endrepeat
SQH:
        .repeat 40, I
        .byte >(I*I)
        .endrepeat

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


; throw: g0 = THX's row for pitch gp, g1 = THZ's (THXL/H, THZL/H: 32 bytes a
; pitch, one a direction), Y = gk, so (g0),y and (g1),y are the thrust's x
; and z, 127 a unit.  Out: g0, g1, Y.  Clobbers A; X kept.  Called by step
; and emit.
throw:  ldy gp
        lda THXL,y
        sta g0
        lda THXH,y
        sta g0+1
        lda THZL,y
        sta g1
        lda THZH,y
        sta g1+1
        ldy gk
        rts

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
        lda (g0),y
        jsr exh
        sta gt0                    ; (-THX / 2)
        lda (g1),y
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

; burst: the crash: every dot relaunched from the ship, x and z velocities
; random in -64..63, y random upwards (0..1023, both bytes from one rand).
; Clobbers A, X, Y, su.  Called by step.
burst:  ldx #NPART-1
@b:     jsr dot0
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
; map's ship marker and the fuel bar.  Both clobber A, X, Y, g0, g1,
; gt0..gt5, su, tsg, bsg, scrg, dpass; gpost also mdl, mdp, mdc.
gpre:   jsr dset
        lda #0
        beq dots
gpost:  jsr dset
        lda #$80
        jsr dots
        jsr marker
        jmp status
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
.ifdef NULA
        lda #YELB                  ; (NULA: the colours' bytes in the pixel)
        ldy plife,x
        cpy #6
        bcs :+
        lda #MAGB
:       and gt4
.else
        lda gt4
        ldy plife,x
        cpy #6
        bcs :+
        and #$F0
:
.endif
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

; marker: the ship's dot on the map of the screen being drawn (back): 2 x 2
; pixels, magenta, on the four tiles whose common corner is nearest the ship
; (gamegen's layout: tile x at pixel (x + MAPX) & 63, z at line (MAPZ - z) &
; 63); none while GSHV is 0.  Each screen remembers its dot (mkl line, $FF
; none; mkp pixel): if the new place differs the old dot is restored from
; MAPI first.  Clobbers A, X, Y, g0, g1, gt0..gt5, mdl, mdp, mdc.  Called by
; gpost.
marker: ldx back
        lda #$FF                   ; (no dot)
        sta gt0
        lda GSHV
        beq @h
        lda sz+1                   ; the top line: MAPZ - z's tile, one less if
        eor #$FF                   ; its fraction is 1/2 or more (C clear from
        asl a                      ; the asl of the inverted fraction)
        lda #MAPZ
        sbc sz+2
        and #63
        sta gt0
        lda sx+1                   ; the left pixel: x's tile + MAPX - 1, plus
        asl a                      ; 1 if its fraction is 1/2 or more (C)
        lda sx+2
        adc #MAPX-1
.ifdef NULA
        and #62                    ; (NULA: both of a MODE 2 pixel's two)
.else
        and #63
.endif
        sta gt1
@h:     lda gt0
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
; Clobbers A, Y, g0, g1, gt2..gt5, mdc; mdp, mdl kept.
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
; mpix: pixel mdp & 63 of map line mdl & 63 on screen scrg (the map's bytes as
; gscr lays them): magenta (mdc bit 7: the pixel's high bit only), or the
; colour MAPI holds for it.  Clobbers A, Y, g0, g1, gt2..gt5.
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
        sec                        ; (+ $100 of the $180)
        adc scrg
        sta g0+1
        lda gt3
        and #3
        tay
        lda PIXG,y
        sta gt3                    ; (the pixel's bits)
        bit mdc
        bpl :+
.ifdef NULA
        and #MAGB                  ; magenta
.else
        and #$F0                   ; magenta
.endif
        bne @w
:       lda gt2                    ; the map's: MAPI + 16 line + byte, masked
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

; status: the fuel bar on screen scrg, redrawn when its length differs from
; what this screen shows (fdr, by back): fuel >> 6 pixels (80 full), yellow,
; four lines deep (FBL..FBL+3 of row FUELR), over byte columns FBC..FBC+19,
; each byte BARB by the pixels left for it.  Clobbers A, X, Y, g0, gt0, gt1.
; Called by gpost.
status: ldx back
        lda fuel+1                 ; gt1 = fuel >> 6
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
        sta gt0                    ; (pixels left to draw)
        lda #FBC*8+FBL             ; the first byte, then 8 on a column
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
        ldy #3                     ; the column's four lines
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
.ifdef NULA
BARB:   .byte 0, YELB & $AA, YELB & $AA, YELB, YELB ; (NULA: the even pixels
PIXG:   .byte $AA, $AA, $55, $55   ; decide; a dot's pixel the MODE 2 one it is in)
.else
BARB:   .byte $00, $88, $CC, $EE, $FF   ; 0..4 pixels lit from the left, yellow
PIXG:   .byte $88, $44, $22, $11   ; pixel 0..3's two bits in a byte (LAND's
                                   ; PIXM is in bank 4, unreadable from here)
.endif

; ---------------------------------------------------------------- state
gkb:    .byte 0                    ; the keys down (keys' bits)
gk:     .byte 0                    ; the ship's direction (0..NDIR-1) and pitch
gp:     .byte 0                    ; (0..NPITCH-1, PFLAT level)
thr:    .byte 0                    ; this step's thrust: 0 none, 1 full, 2 hover
mdet:   .byte 0                    ; 1: a mouse found at the start
mous:   .byte 0                    ; 1: the mouse present this frame (attit)
gmx:    .byte 0                    ; the pointer, signed, 4 mouse units a count
gmy:    .byte 0                    ; (x right, y towards the player: Lander's)
hcnt:   .byte 0                    ; hover's steps (a dot every fourth)
landed: .byte 0                    ; 1: sitting on the pad
ctim:   .byte 0                    ; crashed: steps left (0: flying)
sx:     .res 3                     ; position: x, z, y, 24-bit, 65536 a tile (y
sz:     .res 3                     ; 4096 a height unit)
sy:     .res 3
gvx:    .res 2                     ; velocity, 16-bit, 16384 a tile/Lander step
gvy:    .res 2                     ; (consecutive: step runs X over them)
gvz:     .res 2
su:     .res 2                     ; the ship's height in units, 8.8 (units')
fuel:   .res 2                     ; 0..FUELMX
fkey:   .byte 0                    ; (keys': F's bit last time)
sstp:   .byte 0                    ; (snd's: the crash's step)
dpass:  .byte 0                    ; (dots': 0 the far dots, $80 the near)
tt0:    .byte 0                    ; (tadd's)
tt1:    .byte 0
sctl:   .byte $FF                  ; the noise control and attenuation bytes as
satt:   .byte $FF                  ; last written
rnd:    .byte 0                    ; rand's state
scrg:   .byte 0                    ; the screen being written to (high byte)
pnext:  .byte 0                    ; emit's last dot
plife:  .res NPART                 ; the dots: life (0 dead); position x, z (8.8
ppx:    .res NPART                 ; tiles), y (8.8 units); velocity x, z (1/256
ppxh:   .res NPART                 ; tile), y (1/256 unit)
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
mkl:    .res 2                     ; the map's dot, by screen: line ($FF none)
mkp:    .res 2                     ; and left pixel
mdl:    .res 1                     ; (mdot's: line, pixel, colour)
mdp:    .res 1
mdc:    .res 1
fdr:    .res 2                     ; the fuel bar's length drawn, by screen

        .include "gametab.inc"
        .assert * <= GLY5, error, "the game must end below the letters at GLY5"
