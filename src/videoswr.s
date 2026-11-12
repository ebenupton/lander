; videoswr.s: the display and the banks, sideways RAM build.  One CRTC frame a
; field, MODE 1 or 2 throughout: 20 rows of 64 bytes from LAND0 or LAND1 (R12
; flips them; R13 is 0 for both), the panel in each screen's top 8 rows.  The
; only interrupt is the vertical sync's: it counts the fields and restarts
; timer 2, so the flip and the strips can tell where the beam is.
;
; The sideways banks 4..7 are wherever the loader's find_ram found them
; (BANKMAP); pg4 .. pg7 page one in for reads and select it for writes (pwN:
; BIT wrt, made the board's write select by boot.s's wpatch).  Bank 4 (the
; renderer's tables and code, the map) is in while the renderer runs; the
; colours and the game (5), the ship (6) and the rows' points (7) page their
; own in and bank 4 back.  The code here is in store pages 0 and 1's heads (T0,
; T1).

CR_ROWS = 20                       ; rows shown (R6)
CR_VSYNC = 28                      ; the sync's row (R7)
CR_TOTAL = 39                      ; rows a frame (R4 + 1), 512us each
T2ROW0  = $FF - ((CR_TOTAL-CR_VSYNC)*512 - 1280)/256 ; timer 2's high
                                   ; byte: at or above this, the display's
                                   ; row 0 is yet to come;
T2DEND  = $FF - (CR_TOTAL-CR_VSYNC+CR_ROWS)*512/256 ; below this, it has ended
ROMSEL  = $FE30
WRSEL_WATFORD = $FF30              ; a Watford board's write select: + socket
WRSEL_SOLIDISK = $FE60             ; a Solidisk's: the user VIA's port B
B6_KEYS = $8000                    ; bank 6's entries: the ship's attitude and
B6_SHIP = $8003                    ; place taken; the ship drawn

        .pushseg
        .segment "T0"
; irq: IRQ1V's target.  The MOS's entry has saved A in $FC; X, Y are not used.
irq:    lda #$02
        sta SVIA_IFR               ; (the sync's the only source)
        inc vcount
        lda #$FF                   ; timer 2: the time since the sync
        sta UVIA_T2H
        lda $FC
        rti

; flip: once FMIN fields have passed since the last flip, shows the screen just
; drawn and makes the other the one to draw.  vflip is the field of the flip,
; one less if the display's row 0 is yet to come (that screen is then shown
; from this field, so the strips need not wait).  Falls into setback.
; Clobbers A.
flip:   lda vcount
        sec
        sbc vlast
        cmp #FMIN
        bcc flip
        lda #12
        sta CRTC_IDX
        lda back
        beq :+
        lda #>(LAND1/8) - >(LAND0/8)
:       clc
        adc #>(LAND0/8)
        sta CRTC_DAT
        lda vcount
        sta vflip
        sta vlast
        lda UVIA_T2H
        cmp #T2ROW0
        bcc :+
        dec vflip
:       lda back
        eor #1
        sta back
; setback: scrb and sethalf's screen bits for back.  Clobbers A.
setback:
        lda back
        beq :+
        lda #SCR1-SCR0
:       clc
        adc #SCR0
        sta scrb
        lda back
        asl a
        sta sh_b+1
        rts
        .assert <(LAND0/8) = 0 && <(LAND1/8) = 0, error, "flip: R13 is 0"

        .segment "T1"
; ginit, gstep, gpre, gpost: the game's entries (bank 5's g_init, g_step,
; g_pre, g_post), bank 4 back after.  ship: bank 6's: the ship's attitude and
; place taken (B6_KEYS), the ship drawn (B6_SHIP), bank 4 back after.  Clobber
; what those do.
ginit:  jsr pg5
        jsr g_init
        jmp pg4
gstep:  jsr pg5
        jsr g_step
        jmp pg4
gpre:   jsr pg5
        jsr g_pre
        jmp pg4
gpost:  jsr pg5
        jsr g_post
        jmp pg4
ship:   jsr pg6
        jsr B6_KEYS
        jsr B6_SHIP
        ; (falls into pg4)

; pg4 .. pg7: bank 4 .. 7 paged in and selected for writes.  Out: A its
; socket; X, Y kept.
.repeat 4, k
        .ident(.sprintf("pg%d", k+4)):
        lda BANKMAP+k
        sta ROMSEL
        .ident(.sprintf("pw%d", k+4)):
        bit wrt
        rts
.endrepeat
wrt:    .byte 0                    ; (pwN's BIT reads it: nothing is written)
        .popseg
