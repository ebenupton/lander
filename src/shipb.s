; ============================================================================
; shipb.s -- SHIPB, LAND's bank 6: sideways RAM at $8000.  build.sh assembles
; it (ca65; it includes landsyms.inc, shipspan.s and shipspan.inc) and links
; it with shipb.cfg (CODE at $8000, then SPANS, then TAIL and DTAB each on a
; page boundary); LANDS loads the file into bank 6.  Two entry points, the
; jmps at the bank's start, each reached through LAND's call6 (A = the low
; byte; bank 6 paged in for the call, bank 4 back after):
;   B6_KEYS ($8000): each frame after the game's step (bank 5, game.s) and
;     before LAND projects.  Copies the ship's direction, pitch and screen
;     centre from the game's low-RAM bytes GSHK, GSHP, GSHX, GSHY ($07DB-
;     $07DE) into shk, shp, shx, shy.  (GSHV, $07DF, is read by LAND, which
;     calls B6_SHIP only while it is nonzero.)  No zero page.
;   B6_SHIP ($8003): after the strips have drawn screen scrb and the game has
;     drawn its dots beyond the ship.  Draws the ship there (shipspan.s's
;     shipdraw), then widens that screen's column records to the ship's box
;     so the strips repaint its rows the next time they draw the screen.
;
; Memory: CODE $8000-$869E (keys and ship here, then shipspan.s's walker, its
; tables and FCE, FCX); SPANS $869F-$B3AE (the orientations' streams); TAIL
; $B400-$B57B (spdec); DTAB $B600-$BF8E (DTH, DL4, shipspan.inc's tables).
; Main RAM: DBUF ($2F00, under 256 bytes), the current orientation's lines,
; kept across frames (dlast, dmir, dal).  Zero page, shipdraw's only: LAND's
; $8E-$9F (project's HPZ, bank 7's and the strips' scratch, all finished when
; B6_SHIP runs and set afresh each frame) for c0+1..6, x0+1..6, ptr, dp, lim,
; bl and spdec's dl; TRL+0..15 (LAND's TRL and the first four of TRB:
; a split column's transitions, dead after the strips) for the rest; $8D,
; c0 itself, is never touched.
;
; Data: shk the direction (0..31, the game's gk), shp the pitch (0..12), shx,
; shy the centre.  The game holds GSHX at 128 and GSHY within YSKY+14 ..
; YGND-16, so the ship's lines (shy - 14 .. shy + 16 at most) stay on the
; land's lines YSKY..YGND and its columns (shx - 17 .. shx + 16) on the
; screen.  The box bxl, bxr, byt, byb: first and last pixel column, first
; and last line, inclusive.  LAND's column records: three sets (TOPS, BOTS;
; TOPS+64, BOTS+64; CURT, CURB), each column's highest and lowest land line,
; their addresses in setTl/h, setBl/h; sidx[back] names the set the strips
; have just recorded the screen being drawn in.
; ============================================================================
        .setcpu "6502"
        .include "landsyms.inc"    ; LAND's labels, L_ before each (build.sh):
                                   ; TRL, back, scrb, sidx, setTl, setTh,
                                   ; setBl, setBh (TRB is reached as TRL+12)

scrb    = L_scrb                   ; the high byte of the screen being drawn
c0      = $8D                      ; c0+j, j 1..6 ($8E-$93): slot j's dither for
x0      = $93                      ; the pass; x0+j ($94-$99): its even ^ odd
ptr     = $9A                      ; the line's screen byte; spdec's stream;
                                   ; ship's TOPS pointer
dp      = $9C                      ; the line's bytes in DBUF
lim     = $9E                      ; LIM's for the last boundary (is the next in
bl      = $9F                      ; its byte?); lines left in the pass
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
:       lda $07DB,x                ; GSHK, GSHP, GSHX, GSHY (game.s)
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
