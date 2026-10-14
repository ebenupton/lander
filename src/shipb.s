; ============================================================================
; shipb.s -- LAND's bank 6 (SHIPB, sideways RAM at $8000): the keys and the
; ship.  LAND calls B6_KEYS ($8000) before projecting and B6_SHIP ($8003)
; after the strips (call6 pages this bank in, and bank 4 back after).
;
; The keys (moved here from land.s): the arrows pan the camera a step, and
; steer the ship: it turns (a step a frame, the shortest way) to face the way
; the camera moves and tilts to SHIP_TILT while moving, back to level when not
; (a pitch step a frame).
;
; The ship: drawn at (shx, shy) on the screen just drawn (scrb), over the land
; (shiprast.s); then that screen's TOPS, BOTS (the set the strips recorded in:
; sidx) widened over its box, so the strips that next draw this screen take it
; off as they take off land that has gone.  It must stay within lines
; YSKY..YGND (the STABs') and on the screen: |dx| <= 17, |dy| <= 18.
;
; Zero page: LAND's spare ($8E-$9F) and TRL, TRB (split columns' scratch).
; DQT, DRT (D div a, mod a): this bank's own, as tools/landgen.py's.
; ============================================================================
        .setcpu "6502"
        .include "landsyms.inc"    ; (LAND's symbols, L_ before each)

scrb    = L_scrb
ve      = $8E                      ; (LAND's spare: $8E-$9F)
vo      = $8F
ax      = $90
ay      = $91
bx      = $92
by      = $93
cx      = $94
cy      = $95
lx      = $96
le      = $97
lq      = $98
lr      = $99
ldy_    = $9A
sx      = $9B
se      = $9C
sq      = $9D
sr      = $9E
sdy     = $9F
nn      = L_TRL                    ; (TRL, TRB: 24 bytes)
xr      = L_TRL+1
msk0    = L_TRL+2
lbl     = L_TRL+3
lbh     = L_TRL+4
colx    = L_TRL+5
col     = L_TRL+6
msk     = L_TRL+7
dvd     = L_TRL+8
dv      = L_TRL+9
tmp     = L_TRL+10
ptr     = L_TRL+11
dq      = L_TRL+13
dr      = L_TRL+15
        .assert dr+2 <= L_TRL+24, error, "TRL, TRB: 24 bytes"
        .assert L_TRB = L_TRL+12, error, "TRL, TRB together"

SHIP_TILT = 3                      ; the pitch while moving
SVIA_ORB = $FE40
SVIA_DDRA = $FE43
SVIA_ORA_NH = $FE4F

        .code
        .assert * = $8000, error, "bank 6 at $8000"
        jmp keys                   ; B6_KEYS
        jmp ship                   ; B6_SHIP

; ---------------------------------------------------------------- keys
; Arrows: left and right in x, up and down (away and towards) in z.  Read
; from the keyboard directly (the system VIA, its auto-scan off a moment).
.macro KEY code, routine
        .local no
        lda #code
        sta SVIA_ORA_NH
        lda SVIA_ORA_NH            ; (bit 7: pressed)
        bpl no
        jsr routine
no:
.endmacro
keys:   lda #0
        sta kmv
        sei
        lda #$7F                   ; bits 0-6 out: the key to test
        sta SVIA_DDRA
        lda #3                     ; keyboard auto-scan off
        sta SVIA_ORB
        KEY $19, left
        KEY $79, right
        KEY $39, away
        KEY $29, towards
        lda #$0B                   ; and on
        sta SVIA_ORB
        cli
        ldx kmv                    ; the ship: the way it moves, if one
        ldy KDIR,x
        bmi @lv
        tya                        ; turn a step towards it
        sec
        sbc shk
        and #SHIP_NDIR-1
        beq @tl
        cmp #SHIP_NDIR/2
        lda shk
        bcs :+
        adc #1                     ; (C clear) less than half round: + 1
        bcc :++
:       sbc #1                     ; (C set) else - 1
:       and #SHIP_NDIR-1
        sta shk
@tl:    lda #SHIP_TILT             ; and tilt
        .byte $2C                  ; (BIT abs: skip the lda #0)
@lv:    lda #0                     ; or level
        cmp shp
        beq @d
        bcs :+
        dec shp
        rts
:       inc shp
@d:     rts
left:   lda #1
        jsr mv
        dec L_cxs
        bpl :+
        lda #15
        sta L_cxs
        dec L_cxt
:       rts
right:  lda #2
        jsr mv
        inc L_cxs
        lda L_cxs
        cmp #16
        bne :+
        lda #0
        sta L_cxs
        inc L_cxt
:       rts
towards:
        lda #8
        jsr mv
        dec L_czs
        bpl :+
        lda #15
        sta L_czs
        dec L_czt
:       rts
away:   lda #4
        jsr mv
        inc L_czs
        lda L_czs
        cmp #16
        bne :+
        lda #0
        sta L_czs
        inc L_czt
:       rts
mv:     ora kmv
        sta kmv
        rts

; The ship's direction (k) for the keys held (left 1, right 2, away 4,
; towards 8), $FF for none or a contradiction.  k 0 faces right (+x), 8
; towards, 16 left, 24 away: Lander's direction, the way its thrust pushes.
KDIR:   .byte $FF, 16, 0, $FF, 24, 20, 28, $FF
        .byte 8, 12, 4, $FF, $FF, $FF, $FF, $FF

; ---------------------------------------------------------------- ship
ship:   jsr shipdraw
        ldx #8                     ; its box: VX, VY's least and most
        lda VX+8
        sta bxl
        sta bxr
        lda VY+8
        sta byt
        sta byb
@b:     dex
        bmi @w
        lda VX,x
        cmp bxl
        bcs :+
        sta bxl
:       cmp bxr
        bcc :+
        sta bxr
:       lda VY,x
        cmp byt
        bcs :+
        sta byt
:       cmp byb
        bcc @b
        sta byb
        bcs @b
@w:     ldx L_back                 ; this screen's TOPS, BOTS: its set
        ldy L_sidx,x
        lda L_setTl,y
        sta ptr
        lda L_setTh,y
        sta ptr+1
        lda L_setBl,y
        sta dq
        lda L_setBh,y
        sta dq+1
        lda bxr                    ; its columns: bxl/4 .. bxr/4
        lsr a
        lsr a
        sta tmp
        lda bxl
        lsr a
        lsr a
        tay
@c:     lda byt                    ; the highest line: the box's if higher
        cmp (ptr),y
        bcs :+
        sta (ptr),y
:       lda byb                    ; the lowest: the box's if lower
        cmp (dq),y
        bcc :+
        sta (dq),y
:       cpy tmp
        iny
        bcc @c
        rts

; ---------------------------------------------------------------- the rest
; DQT, DRT + a*64 + D: D div a, D mod a (a 1..31, D 0..63); DVH, DVR, DVL + a
; their row's pages and offset (tools/landgen.py's layout).
        .align 256
DQT:    .repeat 32, q
        .repeat 64, d
        .byte d / (q + (q = 0))
        .endrepeat
        .endrepeat
DRT:    .repeat 32, q
        .repeat 64, d
        .byte d .mod (q + (q = 0))
        .endrepeat
        .endrepeat
DVH:    .repeat 32, q
        .byte >(DQT + q * 64)
        .endrepeat
DVR:    .repeat 32, q
        .byte >(DRT + q * 64)
        .endrepeat
DVL:    .repeat 32, q
        .byte <(q * 64)
        .endrepeat

kmv:    .byte 0                    ; the keys held (as KDIR)
shk:    .byte 0                    ; the ship: direction, pitch, centre
shp:    .byte 0
shx:    .byte 128
shy:    .byte 98
mir:    .byte 0                    ; (shipdraw's)
vis:    .byte 0
neg:    .byte 0
shd0:   .byte 0
ff:     .byte 0
VX:     .res 9
VY:     .res 9
bxl:    .byte 0                    ; the box
bxr:    .byte 0
byt:    .byte 0
byb:    .byte 0

        .include "shiprast.s"
