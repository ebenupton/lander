; ============================================================================
; main.s -- BAND: two Bresenham-interpolated rows and a yellow fill between them,
; on a narrow MODE 1 screen, timed.
;
; The display: MODE 1 cut to 64 bytes a line (256 MODE 1 pixels), so a character
; row is 512 bytes and the 16K screen sits at $4000-$7FFF.  The game's pixel is
; two MODE 1 pixels square: 128 x 128, x across, y up, half a byte wide.
;
; Each frame: two rows of nine points (x = 20, 30 .. 100; the first at y = 80 and
; 68, each later point within 10 of the last, so no segment is steeper than 1,
; and the second row 8 to 16 below the first at every point), interpolated by
; `bres` to a y for every x, the band between them filled a byte column (two x)
; at a time by `fill`, the rows drawn over it in white and the points in red,
; and the two routines' cycle counts written at the top.  Any key: a new pair.
;
; Memory, all built at run time under the screen (the MOS thinks MODE 1 starts
; at $3000; nothing here prints through it):
;   $3000 TAB1  the fill table for byte columns 0-31: per fat row, top first,
;               STA abs,Y to the row's two lines (6 bytes), 128 rows
;   $3300 TAB2  the same for columns 32-63 (every address 256 higher); its
;               first byte doubles as TAB1's stop slot, $3600 as its own
;   $3680 T4    4x mod 256: a byte column's Y from its even x
;   $3700 OL    the low byte of a fat row's place in either table, indexed by
;               y+1 for the first store of a fill and by y for the store below
;   $3800 OH1, $3900 OH2  the high bytes, TAB1's and TAB2's
;   $3A00 OUT0, $3A80 PTS0, $3B00 OUT1, $3B80 PTS1  the rows: y by x, and the
;               points as x0,y0 .. x8,y8
;   $3BFF DUMMY a byte `sweep` may restore before it has planted anything
; ============================================================================
        .setcpu "6502"

OSWRCH  = $FFEE
OSWORD  = $FFF1
OSBYTE  = $FFF4
OSRDCH  = $FFE0
CRTC_IDX = $FE00
CRTC_DAT = $FE01
SVIA_T1L = $FE44                   ; the system VIA's timer: a seed
UVIA_T2L = $FE68                   ; the user VIA's timer 2, counting at 1MHz
UVIA_T2H = $FE69

TAB1    = $3000
TAB2    = $3300
T4      = $3680
OL      = $3700
OH1     = $3800
OH2     = $3900
OUT0    = $3A00
PTS0    = $3A80
OUT1    = $3B00
PTS1    = $3B80
DUMMY   = $3BFF
SCREEN  = $4000

OP_STAY = $99                      ; STA abs,Y
OP_RTS  = $60
OP_INY  = $C8
OP_DEY  = $88

YELLOW2 = $F0                      ; colour 2 in both pixels of a byte
YELLOWL = $C0                      ; and in the left one only
WHITE   = $FF
RED     = $0F

        .zeropage
si:     .res 1                     ; bres: the segment's offset in the points
et:     .res 1                     ; bres: the error, across the store
lb:     .res 1                     ; sweep: the bottom whose stop is planted
ptr:    .res 2                     ; sweep: the planted stop; plot, text: the byte
xe:     .res 1                     ; fill: the end of the whole byte columns
rng:    .res 2
tmp:    .res 2
tnull:  .res 2                     ; timer readings
tread:  .res 2
cyc:    .res 2                     ; a routine's cycles
colour: .res 1                     ; plot
mask:   .res 1
tx:     .res 1                     ; text: the character position
ty:     .res 1
num:    .res 2                     ; putdec
gmin:   .res 1
gmax:   .res 1

        .code
; ---------------------------------------------------------------- start
start:  lda #22                    ; MODE 1
        jsr OSWRCH
        lda #1
        jsr OSWRCH
        ldx #0                     ; then narrow it: 64 bytes a line from $4000
:       lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne :-
        lda SVIA_T1L
        ora #1                     ; never zero
        sta rng
        lda #$A5
        sta rng+1
        jsr gentables

frame:  jsr cls
        jsr genrows
        jsr timenull
        jsr timeinterp
        jsr timefill
        lda #WHITE
        sta colour
        jsr drawrows
        lda #RED
        sta colour
        jsr drawpoints
        jsr readout
        jsr OSRDCH
        bcc frame
        lda #126                   ; ESCAPE: acknowledge it, carry on
        jsr OSBYTE
        jmp frame

crtc_regs:
        .byte 1, 64                ; displayed characters
        .byte 2, 90                ; hsync, to centre the 64
        .byte 12, >(SCREEN/8)      ; screen start
        .byte 13, <(SCREEN/8)
        .byte 10, $20              ; cursor off
crtc_end:

; ---------------------------------------------------------------- bres
; Interpolate a row: for each of its 8 segments, Bresenham from (x0,y0) to (x1,y1)
; with |y1-y0| <= x1-x0, storing y at out[x] for x0 <= x < x1; then out[x8] = y8.
; The segment's |dy|, dx, step direction and store base are written into the
; inner loop; X counts -dx up to 0 against a base of out + x1 - 256.  Inner loop:
; 23 cycles an x, 26 when y steps.
.macro BRES pts, out
        .local seg, up, setstp, loop, st, sb, ad, stp, ns
        ldx #0
        ldy pts+1                  ; y0; each segment ends with Y at the next's
seg:    stx si
        lda pts+3,x
        sec
        sbc pts+1,x                ; y1 - y0
        bcs up
        eor #$FF
        adc #1                     ; |dy|
        sta sb+1
        lda #OP_DEY
        bne setstp
up:     sta sb+1
        lda #OP_INY
setstp: sta stp
        lda pts+2,x
        sta st+1                   ; store base = out + x1 - 256
        sec
        sbc pts,x                  ; dx
        sta ad+1
        eor #$FF
        tax
        inx                        ; X = -dx
        lda ad+1
        lsr a                      ; err = dx/2
        sec
loop:   sta et
        tya
st:     sta out-256,x
        lda et
sb:     sbc #0                     ; err -= |dy|
        bcs ns
ad:     adc #0                     ; err += dx, leaving C set
stp:    iny                        ; y += step
ns:     inx
        bne loop
        ldx si
        inx
        inx
        cpx #16
        bne seg
        ldx pts+16
        lda pts+17
        sta out,x                  ; the last point
        rts
.endmacro

bres0:  BRES PTS0, OUT0
bres1:  BRES PTS1, OUT1

; ---------------------------------------------------------------- fill
; Fill the band a byte column (two x) at a time: from the lower of the top row's
; two y down to the higher of the bottom row's, yellow.  Columns 0-31 through
; TAB1, 32-63 through TAB2; a last x that is even (the left half of its byte)
; fills its left pixel only.  Assumes the first x is even.
fill:   lda PTS0+16
        clc
        adc #1
        and #$FE
        sta xe                     ; whole columns end here
        lda #YELLOW2
        sta fv+1
        lda xe
        cmp #64
        bcc :+
        lda #64
:       sta ce+1
        ldx PTS0
        cpx ce+1
        bcs @tab2
        lda #>OH1
        sta h1+2
        sta h2+2
        jsr sweep                  ; columns below 32
@tab2:  lda xe
        sta ce+1
        ldx PTS0
        cpx #64
        bcs :+
        ldx #64
:       cpx ce+1
        bcs @half
        lda #>OH2
        sta h1+2
        sta h2+2
        jsr sweep                  ; columns from 32
@half:  ldx PTS0+16
        txa
        lsr a
        bcs @done
        lda OUT0,x                 ; the last x alone: make it its own pair
        sta OUT0+1,x
        lda OUT1,x
        sta OUT1+1,x
        lda #YELLOWL
        sta fv+1
        inx
        inx
        stx ce+1
        dex
        dex
        lda #>OH1
        cpx #64
        bcc :+
        lda #>OH2
:       sta h1+2
        sta h2+2
        jmp sweep
@done:  rts

; One table's columns, X = 2 * the first column (an even x) up to ce+1.  The fill
; is a JSR into the table at the top row's first store; it returns from an RTS
; planted over the first store below the bottom row, which stays planted while
; the bottom is unchanged and is put back (STA abs,Y) when it moves and at the end.
sweep:  lda #$FF
        sta lb                     ; nothing planted (no bottom is $FF)
        lda #<DUMMY
        sta ptr
        lda #>DUMMY
        sta ptr+1
col:    lda OUT1,x                 ; bottom: the higher of the pair
        cmp OUT1+1,x
        bcs :+
        lda OUT1+1,x
:       cmp lb
        beq same
        sta lb
        ldy #0
        lda #OP_STAY
        sta (ptr),y                ; put the old stop back
        ldy lb
        lda OL,y
        sta ptr
h1:     lda OH1,y                  ; (high byte: the table's, patched)
        sta ptr+1
        ldy #0
        lda #OP_RTS
        sta (ptr),y                ; plant the new one
same:   lda OUT0,x                 ; top: the lower of the pair
        cmp OUT0+1,x
        bcc :+
        lda OUT0+1,x
:       tay
        lda OL+1,y
        sta entry+1
h2:     lda OH1+1,y
        sta entry+2
        ldy T4,x                   ; Y = 8 * column, mod 256
fv:     lda #YELLOW2
entry:  jsr $FFFF
        inx
        inx
ce:     cpx #0
        bcc col
        ldy #0
        lda #OP_STAY
        sta (ptr),y
        rts

; ---------------------------------------------------------------- the tables
gentables:
        ; TAB1 and TAB2: fat row m (from the top) is screen lines 2m and 2m+1,
        ; in character row m/4 at line 2(m mod 4): $4000 + (m/4)*512 + 2(m mod 4)
        lda #<TAB1
        sta ptr
        lda #>TAB1
        sta ptr+1
        ldx #0                     ; m
@row:   txa
        and #3
        asl a
        sta tmp                    ; the line's low byte
        txa
        lsr a
        lsr a
        asl a
        adc #>SCREEN               ; (C clear: m/4*2 is even, no carry in)
        sta tmp+1                  ; its high byte
        ldy #0
        jsr @two                   ; TAB1's six bytes
        inc tmp+1
        inc ptr+1                  ; TAB2's, 768 on
        inc ptr+1
        inc ptr+1
        ldy #0
        jsr @two
        dec ptr+1
        dec ptr+1
        dec ptr+1
        lda ptr
        clc
        adc #6
        sta ptr
        bcc :+
        inc ptr+1
:       inx
        bpl @row
        ; OL, OH1, OH2: a fat row y's place, 6 * (127 - y), indexed by y + 1
        lda #0
        sta tmp
        sta tmp+1
        ldx #128
@off:   lda tmp
        sta OL,x
        lda tmp+1
        clc
        adc #>TAB1
        sta OH1,x
        lda tmp+1
        clc
        adc #>TAB2
        sta OH2,x
        lda tmp
        clc
        adc #6
        sta tmp
        bcc :+
        inc tmp+1
:       dex
        cpx #$FF
        bne @off
        ldx #0                     ; T4
:       txa
        asl a
        asl a
        sta T4,x
        inx
        bpl :-
        rts
@two:   jsr @one                   ; STA lo,Y and STA lo+1,Y, hi
        inc tmp
        jsr @one
        dec tmp
        rts
@one:   lda #OP_STAY
        sta (ptr),y
        iny
        lda tmp
        sta (ptr),y
        iny
        lda tmp+1
        sta (ptr),y
        iny
        rts

; ---------------------------------------------------------------- the rows
rnd:    lda rng+1                  ; 16-bit xorshift (7,9,8); A = a new byte
        lsr a
        lda rng
        ror a
        eor rng+1
        sta rng+1
        ror a
        eor rng
        sta rng
        eor rng+1
        sta rng+1
        rts

rnd21:  jsr rnd                    ; A = -10 .. 10, evenly
        and #31
        cmp #21
        bcs rnd21
        sec
        sbc #10
        rts

genrows:
        ldx #0
        lda #20
:       sta PTS0,x
        sta PTS1,x
        clc
        adc #10
        inx
        inx
        cpx #18
        bne :-
        lda #80
        sta PTS0+1
        lda #68
        sta PTS1+1
        ldx #2
@pt:    jsr rnd21                  ; the top row: within 10, 16 .. 127
        clc
        adc PTS0-1,x
        cmp #16
        bcc @pt
        cmp #128
        bcs @pt
        sta PTS0+1,x
@pb:    jsr rnd21                  ; the bottom: within 10, 8 .. 16 below the top
        clc
        adc PTS1-1,x
        sta tmp
        lda PTS0+1,x
        sec
        sbc tmp
        cmp #8
        bcc @pb
        cmp #17
        bcs @pb
        lda tmp
        sta PTS1+1,x
        inx
        inx
        cpx #18
        bne @pt
        rts

; ---------------------------------------------------------------- timing
; The user VIA's timer 2 counts down at 1MHz from $FFFF; a routine's reading
; less an empty run's, doubled, is its 2MHz cycles (to 2), JSR and RTS included.
.macro TIMED routine, dest
        sei
        lda #$FF
        sta UVIA_T2L
        sta UVIA_T2H
.ifnblank routine
        jsr routine
.endif
:       lda UVIA_T2H
        sta dest+1
        lda UVIA_T2L
        sta dest
        lda UVIA_T2H
        cmp dest+1
        bne :-
        cli
.endmacro

timenull:
        TIMED , tnull
        rts
timeinterp:
        TIMED interp, tread
        jsr elapsed
        lda cyc
        sta icyc
        lda cyc+1
        sta icyc+1
        rts
timefill:
        TIMED fill, tread
        jsr elapsed
        lda cyc
        sta fcyc
        lda cyc+1
        sta fcyc+1
        rts
interp: jsr bres0
        jmp bres1
elapsed:                           ; cyc = 2 * (tnull - tread)
        sec
        lda tnull
        sbc tread
        sta cyc
        lda tnull+1
        sbc tread+1
        asl cyc
        rol a
        sta cyc+1
        rts
icyc:   .word 0
fcyc:   .word 0

; ---------------------------------------------------------------- drawing
cls:    lda #0
        sta ptr
        lda #>SCREEN
        sta ptr+1
        ldx #$40                   ; 16K
        lda #0
        tay
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        dex
        bne :-
        rts

; Plot fat pixel (X, A) in `colour`: lines 2m and 2m+1, m = 127 - y, of byte
; column x/2, its left pixel pair (mask $CC) or right ($33).
plot:   eor #$7F                   ; m
        sta tmp
        and #3
        asl a
        sta tmp+1                  ; the line in the character row
        lda tmp
        lsr a
        lsr a
        asl a
        adc #>SCREEN               ; (C clear)
        sta ptr+1
        txa
        and #$FE
        asl a
        asl a                      ; 8 * column; C: the second page
        bcc :+
        inc ptr+1
:       ora tmp+1
        sta ptr
        txa
        lsr a
        lda #$CC
        bcc :+
        lda #$33
:       sta mask
        ldy #0
        jsr @merge
        iny
@merge: lda colour                 ; ((colour ^ old) & mask) ^ old
        eor (ptr),y
        and mask
        eor (ptr),y
        sta (ptr),y
        rts

drawrows:
        ldx PTS0
:       lda OUT0,x
        stx num                    ; (plot uses X, Y, tmp)
        jsr plot
        ldx num
        lda OUT1,x
        jsr plot
        ldx num
        inx
        cpx PTS0+16
        bcc :-
        beq :-
        rts

drawpoints:
        ldy #0
:       sty num
        ldx PTS0,y
        lda PTS0+1,y
        jsr plot
        ldy num
        ldx PTS1,y
        lda PTS1+1,y
        jsr plot
        ldy num
        iny
        iny
        cpy #18
        bne :-
        rts

; ---------------------------------------------------------------- text
; Characters from the MOS's font (OSWORD 10), white, at character position
; (tx, ty) of the narrow screen: 32 across, each 16 bytes (two MODE 1 bytes a
; line), ty the character row.
putc:   sta oswblk
        lda #10
        ldx #<oswblk
        ldy #>oswblk
        jsr OSWORD
        lda tx
        asl a
        asl a
        asl a
        asl a
        sta ptr                    ; 16 * tx, mod 256
        lda ty
        asl a
        adc #>SCREEN
        sta ptr+1
        lda tx
        cmp #16
        bcc :+
        inc ptr+1
:       ldx #0
@line:  txa
        tay
        lda oswblk+1,x
        and #$F0
        sta tmp
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp
        sta (ptr),y                ; the left four pixels
        lda oswblk+1,x
        and #$0F
        sta tmp
        asl a
        asl a
        asl a
        asl a
        ora tmp
        pha
        txa
        clc
        adc #8
        tay
        pla
        sta (ptr),y                ; the right four
        inx
        cpx #8
        bne @line
        inc tx
        rts
oswblk: .res 9

puts:   stx @ld+1                  ; the string at (X low, Y high), zero-ended
        sty @ld+2
        ldy #0
@ld:    lda $FFFF,y
        beq @end
        sty num
        jsr putc
        ldy num
        iny
        bne @ld
@end:   rts

putdec: ldx #0                     ; num, unsigned, without leading zeros
        stx tmp+1                  ; (non-zero once a digit is out)
@pow:   ldy #'0'
@sub:   lda num
        sec
        sbc pow10lo,x
        pha
        lda num+1
        sbc pow10hi,x
        bcc @dig
        sta num+1
        pla
        sta num
        iny
        bne @sub
@dig:   pla
        tya
        cpx #4
        beq @out                   ; the units always
        cmp #'0'
        bne @out
        lda tmp+1
        beq @next
        lda #'0'
@out:   sta tmp+1
        stx gtmp
        jsr putc
        ldx gtmp
@next:  inx
        cpx #5
        bne @pow
        rts
gtmp:   .byte 0
pow10lo: .byte <10000, <1000, <100, <10, <1
pow10hi: .byte >10000, >1000, >100, >10, >1

readout:
        lda #0
        sta tx
        sta ty
        ldx #<s_interp
        ldy #>s_interp
        jsr puts
        lda icyc
        sta num
        lda icyc+1
        sta num+1
        jsr putdec
        ldx #<s_fill
        ldy #>s_fill
        jsr puts
        lda fcyc
        sta num
        lda fcyc+1
        sta num+1
        jsr putdec
        lda #255                   ; the gap's range over the row
        sta gmin
        lda #0
        sta gmax
        ldx PTS0
:       lda OUT0,x
        sec
        sbc OUT1,x
        cmp gmin
        bcs :+
        sta gmin
:       cmp gmax
        bcc :+
        sta gmax
:       inx
        cpx PTS0+16
        bcc :---
        beq :---
        lda #0
        sta tx
        lda #1
        sta ty
        ldx #<s_gap
        ldy #>s_gap
        jsr puts
        lda gmin
        sta num
        lda #0
        sta num+1
        jsr putdec
        lda #'-'
        jsr putc
        lda gmax
        sta num
        lda #0
        sta num+1
        jsr putdec
        rts

        .rodata
s_interp: .asciiz "Interp "
s_fill:   .asciiz " Fill "
s_gap:    .asciiz "Gap "
