; ============================================================================
; shipb.s -- LAND's bank 6 (SHIPB, sideways RAM at $8000): the keys and the
; ship.  LAND calls B6_KEYS ($8000) before projecting and B6_SHIP ($8003)
; after the strips (call6 pages this bank in, and bank 4 back after).
;
; B6_KEYS (once the keys; now the game's, game.s, in bank 5): the ship's
; direction, pitch and centre copied in from low RAM (GSHK..GSHY).
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
c0      = $8D                      ; (LAND's spare: $8E-$9F; c0, x0 + 1..6)
x0      = $93
ptr     = $9A
dp      = $9C
lim     = $9E
bl      = $9F
t       = L_TRL                    ; (TRL, TRB: 24 bytes)
al      = L_TRL+1
alx     = L_TRL+2
k       = L_TRL+3
nn      = L_TRL+4
ee      = L_TRL+5
tmp     = L_TRL+6
dq      = L_TRL+7
pm      = L_TRL+9
mk      = L_TRL+10
np1     = L_TRL+11
nb      = L_TRL+12
dpb     = L_TRL+13
ptb     = L_TRL+14
        .assert ptb+2 <= L_TRL+24, error, "TRL, TRB: 24 bytes"

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
keys:   ldx #3                     ; (B6_KEYS) the ship as the game left it (game.s:
:       lda $07DB,x                ; GSHK, GSHP, GSHX, GSHY)
        sta shk,x
        dex
        bpl :-
        rts
        .res $E0-(*-keys)             ; (keeps the ship's layout: its chains' pages)

; ---------------------------------------------------------------- ship
ship:   jsr shipdraw               ; (and its box: bxl, bxr, byt, byb)
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

kmv:    .byte 0                    ; (unused: keeps the layout)
shk:    .byte 0                    ; the ship: direction, pitch, centre
shp:    .byte 0
shx:    .byte 128
shy:    .byte 98
mir:    .byte 0                    ; (shipdraw's)
bxl:    .byte 0                    ; the box
bxr:    .byte 0
byt:    .byte 0
byb:    .byte 0

        .include "shipspan.s"
        .include "shipspan.inc"
