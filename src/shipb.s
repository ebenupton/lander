; shipb.s: the ship, swr's bank 6: every orientation of Lander's ship
; pre-rasterised (tools/shipgen.py's shipspan.inc) and drawn by shipspan.s's
; walker.  Assembled apart from the rest (build.sh), with the main link's
; labels it needs in landsyms.inc (L_ before each), and linked by shipb.cfg
; as the file B6: CODE at $8000, then SPANS, then TAIL and DTAB each from a
; page's start.  Two entries, the JMPs at the bank's start (videoswr.s's ship
; calls both, bank 6 paged in):
;   B6_KEYS ($8000): shk, shp, shx, shy = GSHK, GSHP, GSHX, GSHY (game.s's).
;   B6_SHIP ($8003): the ship on screen scrb, then that screen's column
;     records widened to its box, so that the strips which next draw the
;     screen repaint its lines.
;
; Main RAM: DBUF, the orientation's lines.  Zero page: the overlay (OVL: c0+1
; .. bl; c0 itself is never touched) and TRL's 16 bytes, both free once the
; strips are done.  The bank's own variables (shk .. byb here, FCE .. dsg in
; shipspan.s) are written in place: the bank is RAM.
;
; shk is the direction (0..31, the game's gk), shp the pitch (0..12), shx,
; shy the centre.  The game holds GSHX at 128 and GSHY within YSKY+14 ..
; YGND-16, so the ship's lines stay on the land's and its columns on the
; screen.  The box bxl, bxr, byt, byb: first and last pixel column, first and
; last line, inclusive.  The column records: three sets (strips.s's setTl/h,
; setBl/h hold their tops' and bottoms' addresses); sidx[back] names the set
; the strips have just recorded the screen being drawn in.
        .setcpu "6502"
        .include "landsyms.inc"    ; the main link's labels, L_ before each:
                                   ; TRL, back, scrb, sidx, setTl .. setBh,
                                   ; OVL, DBUF, GSHK

scrb    = L_scrb                   ; the high byte of the screen being drawn
c0      = L_OVL                    ; c0+j, j 1..6: slot j's dither for
x0      = L_OVL+6                  ; the pass; x0+j: its even ^ odd
ptr     = L_OVL+13                 ; the line's screen byte; spdec's stream;
                                   ; ship's tops
dp      = L_OVL+15                 ; the line's slot in DBUF
lim     = L_OVL+17                 ; LIM's for the last boundary (is the next in
bl      = L_OVL+18                 ; its byte?); lines left in the pass
t       = L_TRL                    ; scratch
al      = L_TRL+1                  ; shx & 3
wb      = L_TRL+2                  ; spdec's base for w: al, or 41 + al mirrored
k       = L_TRL+3                  ; scratch
ee      = L_TRL+5                  ; the orientation's entry, 17 shp + kk
tmp     = L_TRL+6                  ; ship's last column
dq      = L_TRL+7                  ; ship's bottoms
pm      = L_TRL+9                  ; $FF if pass A's lines are odd
mk      = L_TRL+10                 ; lk's mask on n: $FF, or 0 mirrored
nb      = L_TRL+12                 ; pass B's lines ($80: none, a one-line band)
ptb     = L_TRL+14                 ; pass B's first line's screen byte
dpb     = L_TRL+4                  ; its slot in DBUF
        .assert ptb+2 <= L_TRL+16, error, "the TRL names must fit TRL: 16 bytes"

; SHPAD: the span walker's patched chains and their tables must each lie in
; one page (shipspan.s's .asserts); this pad after keys puts the code from
; ship on at a page phase that meets them.
SHPAD   = 164
        .code
        .assert * = $8000, error, "bank 6 starts at $8000: B6_KEYS, B6_SHIP"
        jmp keys                   ; B6_KEYS ($8000)
        jmp ship                   ; B6_SHIP ($8003)

; ---------------------------------------------------------------- keys
; keys (B6_KEYS): shk, shp, shx, shy = GSHK, GSHP, GSHX, GSHY, the ship as
; the game's step left it.  Clobbers A, X.
keys:   ldx #3
:       lda L_GSHK,x               ; (the four adjacent, in this order: ram.s)
        sta shk,x
        dex
        bpl :-
        rts
        .res SHPAD

; ---------------------------------------------------------------- ship
; ship (B6_SHIP): the ship drawn, then this screen's column records widened
; to its box: for each byte column c of bxl >> 2 .. bxr >> 2, top[c] =
; min(top[c], byt) and bottom[c] = max(bottom[c], byb), in the set sidx[back]
; names.  In: shk, shp, shx, shy, scrb, back.  Clobbers A, X, Y, shipdraw's
; zero page, and ptr, dq, tmp.
ship:   jsr shipdraw               ; the ship; bxl, bxr, byt, byb its box
        ldx L_back                 ; ptr = this screen's tops, dq its bottoms
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
@c:     lda byt                    ; top[c] up to the box's top
        cmp (ptr),y
        bcs :+
        sta (ptr),y
:       lda byb                    ; bottom[c] down to its bottom
        cmp (dq),y
        bcc :+
        sta (dq),y
:       cpy tmp                    ; (through tmp inclusive)
        iny
        bcc @c
        rts

shk:    .byte 0                    ; the ship: direction (0..31), pitch (0..12),
shp:    .byte 0                    ; centre x, y (keys: the game's copied)
shx:    .byte 128
shy:    .byte 98
mir:    .byte 0                    ; shipdraw's: $FF when drawn mirrored
bxl:    .byte 0                    ; the box: first and last pixel column, first
bxr:    .byte 0                    ; and last line (inclusive)
byt:    .byte 0
byb:    .byte 0

        .include "shipspan.s"      ; the walker (CODE), spdec (TAIL), DTH, DL4
        .include "shipspan.inc"    ; shipgen's tables: DTAB (current after
                                   ; shipspan.s), SPANS, DTAB again
