; loader.s: the disc's !BOOT, built on its own (src/loader.cfg), which
; SHIFT+BREAK *RUNs at $7000 in whatever mode the machine is in.  It names the
; machine, finds sideways RAM (find_ram) and a VideoNULA (nula), shows in MODE
; 7 the versions the machine can run, and loads the one chosen:
;
;   the 32K build       d.BASE loaded at $2000 and entered at its execution
;                       address.  Offered on a Model B or B+.
;   the sideways RAM    $.BANK7, $.BANK6, d.BANK5 and $.BANK4 each loaded at
;   build               STAGE and copied into its bank, then d.MAIN loaded at
;                       STAGE and entered at its execution address with X, Y
;                       the address of `params`.  Offered when four banks of
;                       sideways RAM are free; the only build for a Master.
;
; d is the version's directory: M (MODE 1), C (MODE 2, the CPC's colours), N
; (MODE 2, the VideoNULA's) or A (MODE 2, Lander's own through the NULA); N
; and A are offered only with a VideoNULA.  The screen stays in MODE 7 while
; the files load: its memory, $7C00 on, and this program are clear of STAGE's
; 16K and of BASE.  The program entered sets the display itself and never
; returns.

        .setcpu "6502"
OSFILE  = $FFDD
OSRDCH  = $FFE0
OSWRCH  = $FFEE
OSWORD  = $FFF1
OSBYTE  = $FFF4
CRTC_IDX = $FE00
CRTC_DAT = $FE01
ULA_CTL = $FE20
NULA_CTL = $FE22                   ; a VideoNULA's control register; on a plain
                                   ; ULA, a copy of ULA_CTL
ROMSEL  = $FE30
UVIA_DDRB = $FE62
WRSEL_WATFORD = $FF30              ; a Watford board's write select: + socket
WRSEL_SOLIDISK = $FE60             ; a Solidisk's: the user VIA's port B
ROMCOPY = $F4                      ; the MOS's copy of ROMSEL
MOS_ROMTAB = $02A1                 ; the MOS's ROM type table, by socket
ROMHDR_TYPE = $8006                ; a ROM header's type byte
ROMHDR_COPY = $8007                ; and its copyright offset
STAGE   = $3000                    ; where a bank's image and MAIN load
BASE    = $2000                    ; where BASE loads
ptr     = $70                      ; scratch: two pointers
dst     = $72
MASTER  = 3                        ; OSBYTE 0's machine: 1 a Model B, 2 a B+,
                                   ; 3 or more a Master

        .code
start:  lda #119                   ; any EXEC or SPOOL file closed
        jsr OSBYTE
        lda #0                     ; the machine
        ldx #1
        jsr OSBYTE
        stx machine
        lda #114                   ; a B+ or Master's shadow screen off from
        ldx #1                     ; the next change of mode
        jsr OSBYTE
        lda ROMCOPY
        sta old_bank
        jsr find_ram               ; C set: fewer than four banks
        ror noram
        jsr nula                   ; C set: a VideoNULA
        ror hasnula
        lda noram                  ; the build: the sideways RAM one if it can
        eor #$80
        sta swr
        bmi menu
        lda machine                ; no RAM: a Master has no build
        cmp #MASTER
        bcc menu
        jsr mode7
        jsr print
        .byte 13, 10, "LANDER needs 64K of sideways RAM on a", 13, 10
        .byte "Master: four 16K banks that hold no ROM.", 13, 10, 0
        rts                        ; (to the MOS)

; menu: the screen, then a key: 1 .. 4 a version (3, 4 with a VideoNULA), B
; the other build (where both run).
menu:   jsr mode7
        jsr print
        .byte 13, 10, 141, 131, "LANDER", 13, 10, 141, 131, "LANDER", 13, 10, 10, 134, 0
        ldx machine
        cpx #6
        bcc :+
        ldx #0
:       lda mname,x
        tax
        jsr prx
        bit noram
        bmi @nr
        jsr print
        .byte 13, 10, 134, "64K sideways RAM: sockets", 0
        ldx #0
:       lda #' '
        jsr OSWRCH
        lda fbank,x
        jsr pdec
        inx
        cpx #4
        bne :-
        ldx board
        beq @nl
        lda bname-1,x
        tax
        jsr prx
        jmp @nl
@nr:    jsr print
        .byte 13, 10, 134, "No sideways RAM (four free banks)", 0
@nl:    bit hasnula
        bpl :+
        jsr print
        .byte 13, 10, 134, "VideoNULA", 0
:       jsr print
        .byte 13, 10, 10, 131, 0
        bit swr
        bmi :+
        jsr print
        .byte "The 32K build", 0
        jmp @vs
:       jsr print
        .byte "The sideways RAM build", 0
@vs:    jsr print
        .byte 13, 10, 10, " 1  MODE 1: four colours, dithered", 13, 10
        .byte " 2  MODE 2: 27 colours (CPC palette)", 13, 10, 0
        bit hasnula
        bpl :+
        jsr print
        .byte " 3  MODE 2: 16 colours (VideoNULA)", 13, 10
        .byte " 4  MODE 2: Archimedes colours (NULA)", 13, 10, 0
:       jsr both                   ; B: only where both builds run
        bcs @key
        bit swr
        bmi :+
        jsr print
        .byte 13, 10, " B  the sideways RAM build instead", 13, 10, 0
        jmp @key
:       jsr print
        .byte 13, 10, " B  the 32K build instead", 13, 10, 0
@key:   lda #15                    ; the keyboard buffer emptied
        ldx #1
        jsr OSBYTE
@k:     jsr OSRDCH
        bcc :+
        lda #126                   ; (ESCAPE acknowledged)
        jsr OSBYTE
        jmp @k
:       and #$DF                   ; (letters upper case; digits $11 ..)
        cmp #'B'
        bne @dig
        jsr both
        bcs @k
        lda swr
        eor #$80
        sta swr
        jmp menu
@dig:   sec
        sbc #'1' & $DF
        cmp #2
        bcc @go
        cmp #4
        bcs @k
        bit hasnula
        bpl @k
@go:    tax
        lda dirs,x
        sta f_base
        sta f_main
        sta f_bank5
        jsr print
        .byte 13, 10, 131, "Loading", 0
        bit swr
        bmi load_swr
        ; (falls into load_base)

; load_base: BASE at $2000, and into it.
load_base:
        ldx #<f_base
        ldy #>f_base
        lda #>BASE
        jsr load
        jmp (osf+6)

; load_swr: the banks, 7 down to 4, then MAIN, and into it with X, Y = params.
load_swr:
        ldx #3
@b:     stx bi
        lda #0                     ; STAGE's 16K zeroed: the image's tail
        tay
        sta ptr
        lda #>STAGE
        sta ptr+1
        ldx #$40
        tya
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        dex
        bne :-
        ldx bi
        lda fnl,x
        ldy fnh,x
        tax
        lda #>STAGE
        jsr load
        lda #'.'
        jsr OSWRCH
        ldx bi
        lda fbank,x
        tax
        sei
        jsr selwr
        cli
        lda #>STAGE                ; 64 pages into the bank
        sta ptr+1
        lda #$80
        sta dst+1
        ldy #0
        sty ptr
        sty dst
        ldx #$40
:       lda (ptr),y
        sta (dst),y
        iny
        bne :-
        inc ptr+1
        inc dst+1
        dex
        bne :-
        ldx bi
        dex
        bpl @b
        ldx #<f_main
        ldy #>f_main
        lda #>STAGE
        jsr load
        lda old_bank               ; the ROM paged in at the start, again
        sta ROMCOPY
        sta ROMSEL
        ldx #<params
        ldy #>params
        jmp (osf+6)

; load: the file named at Y X loaded at page A; its catalogue entry in osf (its
; execution address osf+6) after.  Clobbers A, X, Y.
load:   stx osf
        sty osf+1
        pha
        lda #5                     ; the entry: load, execution, length
        ldx #<osf
        ldy #>osf
        jsr OSFILE
        lda osf+6                  ; (kept: the load below needs osf+6 zero to
        pha                        ; load at the address given)
        lda osf+7
        pha
        lda #0
        sta osf+2
        sta osf+6
        lda #$FF
        sta osf+4
        sta osf+5
        tsx
        lda $0103,x                ; (the page)
        sta osf+3
        lda #$FF
        ldx #<osf
        ldy #>osf
        jsr OSFILE
        pla
        sta osf+7
        pla
        sta osf+6
        pla
        rts

; both: C clear if the machine runs both builds: RAM found, and not a Master.
; Clobbers A.
both:   lda noram
        asl a
        bcs :+
        lda machine
        cmp #MASTER
:       rts

; mode7: MODE 7, the cursor off.  Clobbers A, X.
mode7:  ldx #0
:       lda @v,x
        jsr OSWRCH
        inx
        cpx #12
        bne :-
        rts
@v:     .byte 22, 7, 23, 1, 0, 0, 0, 0, 0, 0, 0, 0

; print: the text after the JSR, to a zero, through OSWRCH; returns after the
; zero.  Clobbers A, X, ptr.
print:  pla
        sta ptr
        pla
        sta ptr+1
@c:     inc ptr
        bne :+
        inc ptr+1
:       ldx #0
        lda (ptr,x)
        beq @x
        jsr OSWRCH
        jmp @c
@x:     lda ptr+1
        pha
        lda ptr
        pha
        rts

; prx: the text at names+X, to a zero.  Clobbers A, X.
prx:    lda names,x
        beq :+
        jsr OSWRCH
        inx
        bne prx
:       rts

; pdec: A (0 .. 15) in decimal.  Clobbers A.
pdec:   cmp #10
        bcc :+
        pha
        lda #'1'
        jsr OSWRCH
        pla
        sbc #10
:       ora #'0'
        jmp OSWRCH

; nula: C set if a VideoNULA is fitted.  The ULA's clock is set to 2 MHz with
; MODE 7's registers, so that the fields come twice as often, and ten are
; timed; then $44 is written to NULA_CTL and ten more timed.  A plain ULA takes
; that as its own control register, the 1 MHz clock again, and the fields take
; twice as long; a NULA takes it as a reset of its own registers and the
; fields keep their length.  The flash is off meanwhile, so the MOS writes
; nothing to the ULA, and the display is off (R8).  The caller sets the mode
; again.  Clobbers A, X, Y, ptr, t1.
nula:   jsr mode7
        lda #9
        jsr @fl0
        lda #10
        jsr @fl0
        lda #8
        sta CRTC_IDX
        lda #$30
        sta CRTC_DAT
        lda #$10
        sta ULA_CTL
        jsr @time
        sta t1
        lda #$44
        sta NULA_CTL
        jsr @time
        sta ptr                    ; a NULA: 3 t2 < 4 t1
        asl a
        adc ptr
        sta ptr
        lda t1
        asl a
        asl a
        cmp ptr                    ; C clear: 4 t1 < 3 t2, a plain ULA
        php
        lda #9                     ; the flash at its default again
        ldx #25
        jsr @fl
        lda #10
        ldx #25
        jsr @fl
        plp
        beq :+                     ; (4 t1 = 3 t2: taken as a plain ULA)
        rts
:       clc
        rts
@fl0:   ldx #0
@fl:    ldy #0
        jmp OSBYTE
@time:  lda #19                    ; A = the centiseconds ten fields take
        jsr OSBYTE
        jsr @clk
        sta ptr+1
        ldx #10
:       txa
        pha
        lda #19
        jsr OSBYTE
        pla
        tax
        dex
        bne :-
        jsr @clk
        sec
        sbc ptr+1
        rts
@clk:   lda #1                     ; A = the clock's low byte
        ldx #<clock
        ldy #>clock
        jsr OSWORD
        lda clock
        rts

NSOCK   = 16
SIG_TAG = $C0                      ; the signature written at a socket's
                                   ; copyright offset: SIG_TAG | its number
CLASS_FREE = 0                     ; RAM holding no ROM image
CLASS_IMAGE = 1                    ; RAM holding an image (0, "(C)" at its
                                   ; copyright offset) the MOS is not running
CLASS_ROM = 2                      ; RAM holding a ROM the MOS runs (MOS_ROMTAB
                                   ; not 0): never taken
CLASS_NONE = $FF                   ; not RAM; any value with bit 7 set is also
                                   ; an alias (SIG_TAG | the lower socket)
BOARD_STD = 0                      ; the write selects: ROMSEL alone, or a
BOARD_WATFORD = 1                  ; board's
BOARD_SOLIDISK = 2

; selwr: socket X paged in for reads (ROMSEL, and ROMCOPY in step) and selected
; for writes the way `board` says.  In: X the socket; board.  Out: X, Y kept;
; A clobbered.
selwr:  stx ROMCOPY
        stx ROMSEL
        lda board
        lsr a                      ; board 0: A 0, C 0; 1 (Watford): A 0, C 1;
        bcc @sol                   ; 2 (Solidisk): A 1, C 0
        sta WRSEL_WATFORD,x        ; Watford: the address selects, not the value
@sol:   beq @done
        stx WRSEL_SOLIDISK         ; Solidisk: the socket into port B
@done:  rts

; find_ram: the four banks' sockets.  Out: C clear and fbank+0..3 the sockets
; (the lowest free ones first, then the lowest holding images; the four in
; ascending order of class, then number) and `board` the write select that
; works; or C set: there are fewer than four.  A socket is RAM if bit 0 of
; its ROM type byte takes a flip (it is put back); each way of write
; selecting is tried in turn and the one finding most sockets kept, a plain
; machine winning a tie, then Watford.  A RAM that answers to two socket
; numbers is told by signing every RAM socket's copyright-offset byte with its
; tagged number and reading them back: the higher number is dropped.  All
; signatures are restored, as is the ROM paged in at entry (old_bank).
; Interrupts are off throughout the probing.  Clobbers A, X, Y, ptr, want,
; best, bestb, SOCKCLASS, SAVED, and the user VIA's port B direction (left at
; $0F on a Solidisk).
find_ram:
        sei
        lda #BOARD_STD
        sta board
        sta bestb
        jsr @count
        sta best
        inc board                  ; BOARD_WATFORD
        jsr @count
        cmp best
        bcc @solid
        beq @solid                 ; (a tie: plain)
        sta best
        inc bestb
@solid: lda #$0F                   ; port B bits 0-3 out: the Solidisk select
        sta UVIA_DDRB
        inc board                  ; BOARD_SOLIDISK
        jsr @count
        cmp best
        beq @nsol                  ; (a tie: the winner so far)
        bcs @class                 ; (Solidisk wins: board stays 2, port B out)
@nsol:  lda bestb
        sta board
        inx                        ; (@count left X $FF: 0) port B inputs again
        stx UVIA_DDRB
@class: ldx #NSOCK-1               ; each socket's class
@sock:  lda #CLASS_NONE
        sta SOCKCLASS,x
        jsr @selflip
        bne @snext                 ; (not RAM)
        lda MOS_ROMTAB,x           ; a ROM the MOS runs?
        beq @image
        lda #CLASS_ROM
        bne @cls
@cstr:  .byte 0, "(C)"             ; (the image test's string: data, never run)
@image: stx ptr                    ; an image: 0, "(C)" at the copyright offset
        ldy ROMHDR_COPY
        ldx #<-4                   ; X $FC..$FF: @cstr+4-256,x is @cstr+0..3
@cchk:  lda $8000,y
        cmp @cstr+4-256,x
        bne @free
        iny
        inx
        bne @cchk
        lda #CLASS_IMAGE
        .byte $2C                  ; (BIT abs: skips the LDA below)
@free:  lda #CLASS_FREE
        ldx ptr
@cls:   sta SOCKCLASS,x
@snext: dex
        bpl @sock
        ldx #NSOCK-1               ; sign each RAM socket: its copyright-offset
@sig:   lda SOCKCLASS,x            ; byte saved (SAVED), SIG_TAG | its number
        bmi @signx                 ; written there
        jsr selwr
        lda ROMHDR_COPY
        sta SAVED,x
        txa
        ora #SIG_TAG
        sta ROMHDR_COPY
@signx: dex
        bpl @sig
        ldx #NSOCK-1               ; read back (the lowest number wrote last)
@chk:   lda SOCKCLASS,x
        bmi @chknx
        stx ROMCOPY
        stx ROMSEL
        txa
        ora #SIG_TAG
        cmp ROMHDR_COPY
        beq @chknx
        sta SOCKCLASS,x            ; another number's signature: this one is
@chknx: dex                        ; its alias (bit 7 set: dropped)
        bpl @chk
        inx                        ; restore, lowest number first: an alias
@res:   ldy SOCKCLASS,x            ; (signed before the real number, so holding
        iny                        ; the original) restores after the RAM's
        beq @resnx                 ; real number.  (CLASS_NONE: not RAM)
        jsr selwr
        lda SAVED,x
        sta ROMHDR_COPY
@resnx: inx
        cpx #NSOCK
        bne @res
        lda old_bank
        sta ROMCOPY
        sta ROMSEL
        cli
        ldy #CLASS_FREE            ; pick: the free sockets in order, then the
        sty want                   ; images.  (Y, fbank's index, starts at 0,
@cl:    ldx #0                     ; CLASS_FREE's value)
@pick:  lda SOCKCLASS,x
        cmp want
        bne @pnext
        txa
        sta fbank,y
        iny
        cpy #4
        beq @found
@pnext: inx
        cpx #NSOCK
        bne @pick
        inc want
        lda want
        cmp #CLASS_ROM
        bne @cl
        sec                        ; fewer than four
        rts
@count: lda #0                     ; A = the sockets taking a write with `board`
        sta want                   ; as set; X $FF after
        ldx #NSOCK-1
@cnt:   jsr @selflip
        bne @cntnx
        inc want
@cntnx: dex
        bpl @cnt
        lda want
        rts
@selflip:                          ; Z set if socket X takes a write: its ROM
        jsr selwr                  ; type byte's bit 0 flipped, read, put back
        lda ROMHDR_TYPE
        tay
        eor #1
        sta ROMHDR_TYPE
        cmp ROMHDR_TYPE
        sty ROMHDR_TYPE            ; (flags kept: the CMP's)
@found: clc
        rts

        .rodata
dirs:   .byte "MCNA"               ; the versions' directories
f_base: .byte "M.BASE", 13         ; the files (their directories set by menu)
f_main: .byte "M.MAIN", 13
f_bank4: .byte "$.BANK4", 13
f_bank5: .byte "M.BANK5", 13
f_bank6: .byte "$.BANK6", 13
f_bank7: .byte "$.BANK7", 13
fnl:    .byte <f_bank4, <f_bank5, <f_bank6, <f_bank7 ; by bank less 4
fnh:    .byte >f_bank4, >f_bank5, >f_bank6, >f_bank7
names:
n_b:    .byte "BBC Model B", 0
n_bp:   .byte "BBC Model B+", 0
n_m:    .byte "BBC Master 128", 0
n_met:  .byte "BBC Master ET", 0
n_mc:   .byte "BBC Master Compact", 0
n_wat:  .byte " (Watford)", 0
n_sol:  .byte " (Solidisk)", 0
mname:  .byte n_b-names, n_b-names, n_bp-names, n_m-names, n_met-names, n_mc-names
bname:  .byte n_wat-names, n_sol-names

        .data
osf:    .res 18                    ; OSFILE's block
clock:  .res 5                     ; OSWORD 1's
machine: .byte 0                   ; OSBYTE 0's
noram:  .byte 0                    ; bit 7: fewer than four banks
hasnula: .byte 0                   ; bit 7: a VideoNULA
swr:    .byte 0                    ; bit 7: the sideways RAM build chosen
t1:     .byte 0                    ; nula's first time
old_bank: .byte 0                  ; the ROM paged in at the start
bi:     .byte 0                    ; load_swr's bank less 4
params:                            ; MAIN's: banks 4 .. 7's sockets, then the
fbank:  .byte 4, 5, 6, 7           ; write select (BOARD_*)
board:  .byte 0
want:   .byte 0                    ; find_ram's class sought; @count's count
best:   .byte 0                    ; the most sockets a way found, and which
bestb:  .byte 0
SOCKCLASS: .res NSOCK              ; each socket's CLASS_*, or an alias tag
SAVED:  .res NSOCK                 ; RAM sockets' copyright bytes while signed
