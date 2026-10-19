; video.s: the display.  Each field is two CRTC frames (a vertical rupture):
;
;   the top     rows 0-7, MODE 5 (1MHz, R0 63): FUEL, the gauge and the map, from
;               TOP.  Row 0 is 32 characters wide; rows 1-7 are 8 wide at the right
;               (the rest of the map), their sync moved from 45 to 21.
;   the land    rows 8-38, MODE 1 or 2 (2MHz, R0 127): 12 rows shown from the land
;               buffer being displayed (lfront), the vertical sync at its row 20.
;
; Every line is exactly 64us from hsync to hsync, which is what a real display
; (or b2's TV) needs: the two clock switches happen at exact microseconds, inside
; lines whose R0 is chosen to end them on time.  Timer 1 of the user VIA runs
; free through a chain of events, each one loading the latch for the event after
; next:
;
;   Ez   land line EZL: R0 63+EZS, the clock to 1MHz at EZS us, the top's frame
;   Ea   top row 0's last line: 88 characters, so rows 1-7 start 24us on
;   Eb   the land's first (black) line: R0 79-EBS, the clock to 2MHz at EBS us
;   Ev   just before the vertical sync: waits for it in NOPs, interrupts on
;   E0   the vertical sync (system VIA CA1): restarts the chain
;
; Ev's NOPs fix E0's latency, so the chain restarts at the same microsecond
; every field; a free-running chain would drift, because a switch line's length
; depends on when its switch lands.  The switch events measure their own
; latency from the timer and pad it out (dejit).  Every write to the CRTC lands
; in the right line by the pace of crws (13.5us a register).

PROWS   = 8                        ; the top frame's rows
CR_VSYNC = 28                      ; the field's vertical sync row
CR_TOTAL = 39                      ; rows a field (8 lines, 512us each)
CR_ROWS = PROWS+12                 ; the row where the land's display ends
FIELD   = 312*64                   ; us a field

EZL     = 4                        ; Ez's line, after the sync
EZS     = 54                       ; Ez's switch, us into its line
EBS     = 38                       ; Eb's switch, us into its line
TZ      = 242                      ; the events, us after the sync
TA      = 6016
TB      = 9686
TV      = FIELD+52
IZA     = TA-TZ                    ; the intervals between them
IAB     = TB-TA
IBV     = TV-TB
RSL     = 163                      ; E0's latency to its timer write
EVN     = 16                       ; Ev's NOPs
DJK     = 39                       ; dejit's greatest latency (as measured)

T2ROW0  = $FF - TA/256 + 3         ; timer 2 high byte before the land's frame
T2DEND  = $FF - (CR_TOTAL-CR_VSYNC+CR_ROWS)*512/256   ; ... after its display

; CRW r, v: CRTC register r = v (or lfront).
.macro CRW r, v
        lda #r
        sta CRTC_IDX
.ifnblank v
        lda #v
.else
        lda lfront
.endif
        sta CRTC_DAT
.endmacro

; flip: once FMIN fields have passed since the last flip, shows the screen just
; drawn and makes the other the one to draw.  vflip is the field of the flip, one
; less if the land's frame has yet to start (the new screen is then shown
; from it, so the strips need not wait).  Falls into setback.  Clobbers A, X.
        .assert <(LAND0/8) = 0 && <(LAND1/8) = 0, error, "the land buffers' R13 is 0"
        .assert >(LAND1/8) - >(LAND0/8) = 3, error, "flip: R12 is LAND0's + 3 back"
flip:   lda vcount
        sec
        sbc vlast
        cmp #FMIN
        bcc flip
        lda back                   ; R12 = >(LAND0/8) + 3 back
        asl a
        adc back
        adc #>(LAND0/8)
        sta lfront
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

; irq: IRQ1V's target.  The MOS's entry has saved A in $FC; X is saved here and
; Y is never used.  Dispatches E0 (the sync) or the next timer event (evn).
irq:    txa
        pha
        lda #$02                   ; CA1: the vertical sync
        bit SVIA_IFR
        beq :+
        jmp @e0
:       lda UVIA_IFR
        and #$40
        beq @x
        lda UVIA_T1LL              ; the latency: latch less count
        sec
        sbc UVIA_T1L
        ldx evn
        beq @ez
@d1:    dex
        beq @ea
@d2:    dex
        beq @eb1
@d3:    jsr dejit                  ; Ev: wait for E0 with interrupts on, so
        lda #0                     ; that it always interrupts a NOP
        sta evn
        lda $FC                    ; (E0's entry overwrites $FC)
        pha
        cli
        .repeat EVN
        nop
        .endrepeat
        sei
        pla
        sta $FC
        jmp @x
@nx:    sta UVIA_T1LL              ; the latch: the event after next
        stx UVIA_T1LH
        lda evn
        clc
        adc #1
        and #3
        sta evn
@x:     pla
        tax
        lda $FC
        rti
@eb1:   jmp @eb
        .assert >@d1 = >@ez && >@d2 = >@ea && >@d3 = >@eb1, error, "irq: the dispatch's branches in their page (the events' timing)"
@ez:    jsr dejit                  ; Ez: this line ends at 64us at 1MHz
        CRW 0, 63+EZS
        lda #$C4                   ; MODE 5
        sta ULA_CTL
        ldx #CTZ-CRT
        jsr crws
.ifdef MODE2
        jsr pal5
.endif
        lda #<(IAB-2)
        ldx #>(IAB-2)
        jmp @nx
@ea:    jsr dejit                  ; Ea: rows 1-7 narrow, shifted right
        ldx #CTA-CRT
        jsr crws
        lda #<(IBV-2)
        ldx #>(IBV-2)
        bne @nx                    ; (always)
@eb:    jsr dejit                  ; Eb: this line ends at 40us at 2MHz
        ldx #CTB0-CRT
        jsr crws
        lda #ULAL                  ; the land's mode
        sta ULA_CTL
        ldx #CTB-CRT
        jsr crws
.ifdef MODE2
        jsr pal2
.endif
        lda #$FF                   ; (E0 restarts the chain first)
        tax
        jmp @nx
@e0:    sta SVIA_IFR               ; E0: the chain restarted, Ez next
        lda #<(TZ-RSL)
        sta UVIA_T1L
        lda #>(TZ-RSL)
        sta UVIA_T1H
        lda #<(IZA-2)
        sta UVIA_T1LL
        lda #>(IZA-2)
        sta UVIA_T1LH
        lda #0
        sta evn
        inc vcount
        lda #$FF                   ; timer 2: the time since the sync
        sta UVIA_T2H
        jmp @x

; crws: CRTC register, value pairs from CRT+X to a negative register.
; Clobbers A, X.
crws:   lda CRT,x
        bmi @d
        sta CRTC_IDX
        lda CRT+1,x
        sta CRTC_DAT
        inx
        inx
        bne crws                   ; (always)
@d:     rts
        .assert >crws = >@d, error, "crws: in one page (its pace)"

        .pushseg
        .segment "TABLES"
CRT:
CTZ:    .byte 3, $24, 2, 45, 0, 63                      ; Ez: the top's timing
CT0:    .byte 1, 32, 6, PROWS, 12, >(TOP/8), 13, <(TOP/8), $FF   ; and frame
CTB0:   .byte 0, 79-EBS, 2, 90, $FF                     ; Eb: before the switch
CTB:    .byte 0, 127, 3, $28, 1, 64, 6, 12, 4, CR_TOTAL-PROWS-1, $FF  ; after
CTA:    .byte 0, 87, 4, PROWS-1, 7, CR_VSYNC-PROWS, 13, 0, 12         ; Ea
lfront: .byte >(LAND0/8), 1, 8, 2, 21, 0, 63, $FF       ; (R12: flip's)
        .popseg
        .assert >CRT = >(lfront+7), error, "crws: its table in one page"

; dejit: pads an event's latency out to DJK.  A = the latency (latch less count);
; the slide skips one NOP a cycle of it.  Clobbers A.
dejit:  clc
        adc #<(15-DJK)
        and #15
        sta @b+1
        clc
@b:     bcc @b+2                   ; (operand: NOPs skipped)
        .repeat 15
        nop
        .endrepeat
        rts
        .assert >(@b+2) = >(@b+17), error, "dejit: its slide in one page"

.ifdef MODE2
; pal2, pal5: the ULA's palette for the land (MODE 2) or the top (MODE 5).
; Clobbers A, X.
pal2:   ldx #31
        .byte $2C                  ; (BIT abs: skips pal5's LDX)
pal5:   ldx #15
:       lda PALT,x
        sta $FE21
        dex
        txa
        and #15
        cmp #15
        bne :-
        rts
        .pushseg
        .segment "TABLES"
PALT:   P5PAL                      ; the top's palette
        P2PAL                      ; the land's
PIX5:   .byte $88, $44, $22, $11   ; MODE 5's pixels
        .popseg
.endif
        .pushseg
        .segment "TABLES"
evn:    .byte 0                    ; the next timer event: 0 Ez, 1 Ea, 2 Eb, 3 Ev
        .popseg
