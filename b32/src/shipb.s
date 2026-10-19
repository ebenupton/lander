; shipb.s: the ship, bank 6 of the sideways RAM build: every orientation of
; Lander's ship pre-rasterised (tools/shipgen.py's shipspan.inc) and drawn by
; shipspan.s's walker.  Assembled apart from the rest (build32.sh), with the
; labels it needs from the main link in landsyms.inc (L_ before each), and
; linked by shipb.cfg: CODE at $8000, then SPANS, then TAIL and DTAB each on a
; page boundary.  Two entries, the JMPs at the bank's start (videoswr.s's ship
; calls both, bank 6 paged in):
;   B6_KEYS ($8000): shk, shp, shx, shy = GSHK, GSHP, GSHX, GSHY (the game's).
;   B6_SHIP ($8003): the ship on screen scrb, then that screen's column records
;     widened to its box, so the strips repaint its lines the next time they
;     draw the screen.
;
; Main RAM: DBUF, the orientation drawn last (dlast, dmir, dal: kept across
; frames).  Zero page: the overlay (OVL: c0+1 .. bl; c0 itself is never
; touched) and TRL, TRB (dead after the strips) for the rest.
;
; shk is the direction (0..31, the game's gk), shp the pitch (0..12), shx,
; shy the centre.  The game holds GSHX at 128 and GSHY within YSKY+14 ..
; YGND-16, so the ship's lines stay on the land's and its columns on the
; screen.  The box bxl, bxr, byt, byb: first and last pixel column, first and
; last line, inclusive.  The column records: three sets (TOPS, BOTS; TOPS+64,
; BOTS+64; CURT, CURB), their addresses in setTl/h, setBl/h; sidx[back] names
; the set the strips have just recorded the screen being drawn in.
        .setcpu "6502"
        .include "landsyms.inc"    ; the main link's labels, L_ before each:
                                   ; TRL, back, scrb, sidx, setTl .. setBh,
                                   ; OVL, DBUF, GSHK (TRB is TRL+12)

scrb    = L_scrb                   ; the high byte of the screen being drawn
c0      = L_OVL                    ; c0+j, j 1..6: slot j's dither for
x0      = L_OVL+6                  ; the pass; x0+j: its even ^ odd
ptr     = L_OVL+13                 ; the line's screen byte; spdec's stream;
                                   ; ship's TOPS pointer
dp      = L_OVL+15                 ; the line's bytes in DBUF
lim     = L_OVL+17                 ; LIM's for the last boundary (is the next in
bl      = L_OVL+18                 ; its byte?); lines left in the pass
t       = L_TRL                    ; scratch
al      = L_TRL+1                  ; shx & 3
wb      = L_TRL+2                  ; spdec's base for w: al, or 41 + al mirrored
k       = L_TRL+3                  ; scratch
ee      = L_TRL+5                  ; the orientation's entry, 17 shp + kk
tmp     = L_TRL+6                  ; ship's last column
dq      = L_TRL+7                  ; BOTS (ship)
pm      = L_TRL+9                  ; $FF if pass A's lines are odd
mk      = L_TRL+10                 ; lk's mask on n: $FF, or 0 mirrored
nb      = L_TRL+12                 ; pass B's lines ($80: none, a one-line band)
ptb     = L_TRL+14                 ; pass B's first line's screen byte
dpb     = L_TRL+4                  ; its bytes in DBUF
        .assert ptb+2 <= L_TRL+24, error, "the TRL names must fit TRL, TRB: 24 bytes"

; SHPAD: the span walker's patch chains and tables must each sit within one
; page (shipspan.s's .asserts); this pad after `keys` puts the code from
; `ship` on at a page phase that satisfies them (the smallest that links).
SHPAD   = 164
        .code
        .assert * = $8000, error, "bank 6 starts at $8000: B6_KEYS, B6_SHIP"
        jmp keys                   ; B6_KEYS ($8000)
        jmp ship                   ; B6_SHIP ($8003)

; ---------------------------------------------------------------- keys
; keys (B6_KEYS): shk, shp, shx, shy = GSHK, GSHP, GSHX, GSHY, the ship as
; the game's step left it.  Clobbers A, X.
keys:   ldx #3
:       lda L_GSHK,x               ; GSHK, GSHP, GSHX, GSHY (game.s)
        sta shk,x
        dex
        bpl :-
        rts
        .res SHPAD                 ; (layout: see SHPAD above)

; ---------------------------------------------------------------- ship
; ship (B6_SHIP): draw the ship, then widen this screen's column records to
; its box: for each column c of bxl >> 2 .. bxr >> 2, TOPS[c] = min(TOPS[c],
; byt) and BOTS[c] = max(BOTS[c], byb), TOPS and BOTS the set sidx[back]
; names.  In: shk, shp, shx, shy, scrb, back.  Clobbers A, X, Y, shipdraw's
; zero page, and ptr, dq, tmp.
ship:   jsr shipdraw               ; the ship; bxl, bxr, byt, byb its box
        ldx L_back                 ; ptr = this screen's TOPS, dq its BOTS
        ldy L_sidx,x
        lda L_setTl,y
        sta ptr
        lda L_setTh,y
        sta ptr+1
        lda L_setBl,y
        sta dq
        lda L_setBh,y
        sta dq+1
        lda bxr                    ; columns bxl / 4 .. bxr / 4 (tmp the last)
        lsr a
        lsr a
        sta tmp
        lda bxl
        lsr a
        lsr a
        tay
@c:     lda byt                    ; TOPS[c] up to the box's top if higher
        cmp (ptr),y
        bcs :+
        sta (ptr),y
:       lda byb                    ; BOTS[c] down to its bottom if lower
        cmp (dq),y
        bcc :+
        sta (dq),y
:       cpy tmp                    ; (through tmp inclusive)
        iny
        bcc @c
        rts

shk:    .byte 0                    ; the ship: direction (0..31), pitch (0..12),
shp:    .byte 0                    ; centre x, y (B6_KEYS: the game's copied)
shx:    .byte 128
shy:    .byte 98
mir:    .byte 0                    ; shipdraw's: $FF when drawn mirrored
bxl:    .byte 0                    ; the box: first and last pixel column, first
bxr:    .byte 0                    ; and last line (inclusive)
byt:    .byte 0
byb:    .byte 0

        .include "shipspan.s"      ; the walker (CODE), spdec (TAIL), DTH, DL4
        .include "shipspan.inc"    ; shipgen's tables: DTAB (still current),
                                   ; SPANS, DTAB again
