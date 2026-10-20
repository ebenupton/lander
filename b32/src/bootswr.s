; bootswr.s: the sideways RAM build's loader.  LANDER loads at $7000 and is
; *RUN with the MOS in charge (the chooser has set MODE 1, the palette black).
; It finds four banks of sideways RAM (find_ram, beebgame's), loads the bank
; images B7, B6, B5 and B4 through the screens at $3000 and copies each into
; its bank, loads LAND (the stored parts) at $3000, and then takes the machine:
; the MOS's interrupts off for good (IRQ1V is ours; page $0D, the NMI's, is
; left alone), the data zeroed, the stored parts copied into place, the tables
; and the generated code made, the display set, the game started.  The loader's
; own pages are cleared last, by a stub run from DBUF.

        .segment "BOOT"
OSWRCH  = $FFEE
OSCLI   = $FFF7
ROMCOPY = $F4                      ; the MOS's copy of ROMSEL
MOS_ROMTAB = $02A1                 ; the MOS's ROM type table, by socket
ROMHDR_TYPE = $8006                ; a ROM header's type byte
ROMHDR_COPY = $8007                ; and its copyright offset
UVIA_DDRB = $FE62
BOARD_STD = 0                      ; find_ram's write selects: ROMSEL alone,
BOARD_WATFORD = 1                  ; or a board's
BOARD_SOLIDISK = 2

start:  lda ROMCOPY                ; (the ROM in at entry: find_ram restores it)
        sta old_bank
        jsr find_ram               ; fbank, board; C set: under four banks
        bcc :+
        jmp no_ram
:       ldx #3                     ; the banks, 7 down to 4
@ld:    stx bi
        lda cmdl,x
        tay
        lda #<cmdb
        clc
        adc cmdo,x
        tax
        bcc :+
        iny
:       jsr OSCLI
        ldx bi
        lda fbank,x
        tax
        sei
        jsr selwr
        cli
        lda #$30                   ; 64 pages, $3000 to $8000
        sta ptr+1
        lda #$80
        sta tmp+1
        ldy #0
        sty ptr
        sty tmp
        ldx #$40
:       lda (ptr),y
        sta (tmp),y
        iny
        bne :-
        inc ptr+1
        inc tmp+1
        dex
        bne :-
        ldx bi
        dex
        bpl @ld
        ldx #<cmd_land             ; LAND, at $3000
        ldy #>cmd_land
        jsr OSCLI
        lda #119                   ; any EXEC or SPOOL file closed: no filing
        jsr OSBYTE                 ; system call follows
        sei
        ldx #$FF
        txs
        jsr takeover
        ldx #clre-clr-1            ; clr into DBUF, and on to it
@cs:    lda clr,x
        sta DBUF,x
        dex
        bpl @cs
        lda #$82                   ; the sync's interrupt on
        sta SVIA_IER
        cli
        jmp DBUF
; clr: the loader's pages black, then the main loop.  (Relocatable.)
clr:    lda #0
        sta ptr
        tay
        ldx #>__BOOT_LOAD__
@p:     stx ptr+1
@b:     sta (ptr),y
        iny
        bne @b
        inx
        bpl @p
        jmp loop
clre:
        .assert __BOOT_LOAD__ = $7000, error, "the loader at $7000, in screen 1's land"

; The banks' files: B4 .. B7 (cmdo: each command's offset in cmdb).
cmdb:
.ifdef ARC
cmd4:   .byte "LOAD B4 3000", 13
.else
cmd4:   .byte "LOAD $.B4 3000", 13         ; (shared by the other versions)
.endif
cmd5:   .byte "LOAD B5 3000", 13
cmd6:   .byte "LOAD B6 3000", 13
cmd7:   .byte "LOAD $.B7 3000", 13        ; (shared by the versions)
cmd_land: .byte "LOAD LAND", 13
cmdo:   .byte cmd4-cmdb, cmd5-cmdb, cmd6-cmdb, cmd7-cmdb
cmdl:   .byte >cmdb, >cmdb, >cmdb, >cmdb
        .assert >cmdb = >cmd7, error, "cmdb: the commands in one page"

; takeover: everything but the interrupts' start, from LAND at $3000 and the
; banks loaded (fbank, board: find_ram's).  (The tests call it with LAND at
; $3000 and the banks in place.)  Clobbers A, X, Y.
takeover:
.ifdef MODE2
        lda #$40                   ; a VideoNULA reset (on a plain ULA, a
        sta $FE22                  ; mirror of its registers)
.ifdef NULA
        ldx #0                     ; and its palette
:       lda nulapal,x
        sta $FE23
        inx
        cpx #32
        bne :-
.endif
.endif
        ldx #15                    ; every colour black
@pk:    txa
        asl a
        asl a
        asl a
        asl a
        ora #7
        sta $FE21
        dex
        bpl @pk
        lda #ULAL
        sta ULA_CTL
        lda #$7F                   ; the VIAs' interrupts off
        sta SVIA_IER
        sta UVIA_IER
        lda #<irq
        sta IRQ1V
        lda #>irq
        sta IRQ1V+1
        lda #0                     ; timer 2 counts the clock
        sta UVIA_ACR
        sta UVIA_T2L
        ldx #$FC                   ; the data zeroed: zero page to $FB, page
@z0:    dex                        ; 1 below the stack, page 2 past the
        sta $00,x                  ; vectors, $0300 to $0CFF and $0E00 to the
        bne @z0                    ; data's end
        ldx #<STACK
@z1:    dex
        sta $0100,x
        bne @z1
        ldx #$FA
@z2:    dex
        sta $0206,x
        bne @z2
        tay
        ldx #>$0300
@z3p:   stx ptr+1
        sta ptr
@z3:    sta (ptr),y
        iny
        bne @z3
        inx
        cpx #>$0D00
        bne :+
        inx                        ; (page $0D skipped)
:       cpx #>(__DATA_LAST__+255)
        bne @z3p
        .assert __DATA_LAST__ + 255 < $3000, error, "takeover: the zeroing stops below LAND"
        ldx #3                     ; the banks' sockets
:       lda fbank,x
        sta BANKMAP,x
        dex
        bpl :-
        ldx #0                     ; the stored parts to their places
@cl:    lda copies,x
        sta ptr
        lda copies+1,x
        sta ptr+1
        lda copies+2,x
        sta g0
        lda copies+3,x
        sta g0+1
        lda copies+4,x
        sta tmp
        lda copies+5,x
        sta tmp+1
        txa
        pha
        jsr mcopy
        pla
        clc
        adc #6
        tax
        cpx #copye-copies
        bne @cl
        jsr wpatch
        jsr pg4
        jsr gfill
        jsr gqr
        jsr grung
        jsr init
        lda #0                     ; both screens black, to the loader
        tay
        sta ptr
        ldx #>LAND0
@z4p:   stx ptr+1
@z4:    sta (ptr),y
        iny
        bne @z4
        inx
        cpx #>__BOOT_LOAD__
        bne @z4p
        ldx #0                     ; the CRTC
@cr:    lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne @cr
        lda #1                     ; screen 1 drawn first, screen 0 shown
        sta back
        jsr setback
        jsr ginit
        ldx #15                    ; the palette
@pl:    lda palv,x
        sta $FE21
        dex
        bpl @pl
        rts

; copies: source, destination, length; in the file's order, each destination
; below every later source.
copies: .word __TABLES_LOAD__, __TABLES_RUN__, __TABLES_SIZE__
        .word __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
        .word __T0_LOAD__, __T0_RUN__, __T0_SIZE__
        .word __T1_LOAD__, __T1_RUN__, __T1_SIZE__
        .word __T2_LOAD__, __T2_RUN__, __T2_SIZE__
        .word __T3_LOAD__, __T3_RUN__, __T3_SIZE__
        .word __T4_LOAD__, __T4_RUN__, __T4_SIZE__
        .word __T5_LOAD__, __T5_RUN__, __T5_SIZE__
        .word __T6_LOAD__, __T6_RUN__, __T6_SIZE__
        .word __T7_LOAD__, __T7_RUN__, __T7_SIZE__
copye:
        .assert __TABLES_RUN__ + __TABLES_SIZE__ <= __TABLES_LOAD__ && __CODE_RUN__ <= __CODE_LOAD__, error, "copies: below their sources"

crtc_regs:                         ; MODE 1 or 2's frame: 64 bytes by 20 rows
        .byte 0, 127
        .byte 1, 64
        .byte 2, 90
        .byte 3, $28
        .byte 4, CR_TOTAL-1
        .byte 5, 0
        .byte 6, CR_ROWS
        .byte 7, CR_VSYNC
        .byte 8, 0
        .byte 9, 7
        .byte 10, $20              ; no cursor
        .byte 12, >(LAND0/8)
        .byte 13, <(LAND0/8)
crtc_end:

.ifdef MODE2
palv:   P2PAL                      ; MODE 2: the land's colours
.ifdef NULA
nulapal: NULAPAL                   ; the VideoNULA's 16 colours
.endif
.else
palv:   .repeat 16, e              ; MODE 1: black, cyan, magenta, yellow
        .byte e << 4 | ((($3560 >> (4 * (((e >> 3) & 1) * 2 + ((e >> 1) & 1)))) & 7) ^ 7)
        .endrepeat
.endif

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

; selwr: socket X paged in for reads (ROMSEL, and ROMCOPY in step) and selected
; for writes the way `board` says.  wrx: the write select alone.  In: X the
; socket; board.  Out: X, Y kept; A clobbered (0, or 1 on a Solidisk).  Callers:
; ldbank, find_ram.
selwr:  stx ROMCOPY
        stx ROMSEL
wrx:    lda board
        lsr a                      ; board 0: A 0, C 0; 1 (Watford): A 0, C 1; 2
                                   ; (Solidisk): A 1, C 0
        bcc @sol
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
; Interrupts are off throughout the probing.  Clobbers A, X, Y, tmp, want,
; best, bestb, SOCKCLASS, SAVED, and the user VIA's port B direction (left at
; $0F on a Solidisk).  Caller: start.
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
@image: stx tmp                    ; an image: 0, "(C)" at the copyright offset
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
        ldx tmp
@cls:   sta SOCKCLASS,x
@snext: dex
        bpl @sock
        ldx #NSOCK-1               ; sign each RAM socket: its copyright-offset
@sig:   lda SOCKCLASS,x            ; byte saved (SAVED), SIG_TAG | its number
                                   ; written there
        bmi @signx
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
        sta SOCKCLASS,x            ; another number's signature: this one is its
                                   ; alias (bit 7 set: dropped)
@chknx: dex
        bpl @chk
        inx                        ; restore, lowest number first: an alias
@res:   ldy SOCKCLASS,x            ; (signed before the real number, so holding
                                   ; the original) restores after the RAM's real
                                   ; number
        iny
        beq @resnx                 ; (CLASS_NONE: not RAM)
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
                                   ; images.  Y, fbank's index, starts at 0,
                                   ; CLASS_FREE's value, which is want's first
        sty want
@cl:    ldx #0
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
                                   ; as set; X $FF after
        sta want
        ldx #NSOCK-1
@cnt:   jsr @selflip
        bne @cntnx
        inc want
@cntnx: dex
        bpl @cnt
        lda want
        rts
@selflip:                          ; Z set if socket X takes a write: its ROM
                                   ; type byte's bit 0 flipped, read, put back
        jsr selwr
        lda ROMHDR_TYPE
        tay
        eor #1
        sta ROMHDR_TYPE
        cmp ROMHDR_TYPE
        sty ROMHDR_TYPE            ; (flags kept: the CMP's)
@found: clc
        rts

; wpatch: pg4..pg7's write selects made the board's.  Each pwN is BIT wrt (3
; bytes); on a Watford board it becomes STA WRSEL_WATFORD + the bank's socket,
; on a Solidisk STA WRSEL_SOLIDISK (pgN has the socket in A by then); on a
; plain machine nothing changes.  In: board, BANKMAP.  Clobbers A, X, Y, ptr.
wpatch: lda board
        beq @r
        ldx #3
@l:     lda wrsl,x                 ; ptr = the BIT (wrsl, wrsh)
        sta ptr
        lda wrsh,x
        sta ptr+1
        ldy #0
        lda #$8D                   ; STA abs
        sta (ptr),y
        lda board
        cmp #BOARD_SOLIDISK
        beq @s
        ldy wrsb,x                 ; Watford: $FF30 | the bank's socket (< 16)
        lda BANKMAP,y
        ora #<WRSEL_WATFORD
        ldy #1
        sta (ptr),y
        iny
        lda #>WRSEL_WATFORD
        bne @h
@s:     ldy #1                     ; Solidisk: $FE60
        lda #<WRSEL_SOLIDISK
        sta (ptr),y
        iny
        lda #>WRSEL_SOLIDISK
@h:     sta (ptr),y
        dex
        bpl @l
@r:     rts

; no_ram: fewer than four banks: the message, then back to the MOS (RTS to the
; *RUN).  The chooser left the palette black and the cursor off, so the message
; starts with VDU 20 (the default palette) and VDU 23,1,1;0;0;0; (cursor on),
; followed by one byte over, a VDU 0, which does nothing.
no_ram: ldx #0
:       lda msg_ram,x
        beq :+
        jsr OSWRCH
        inx
        bne :-
:       rts
msg_ram: .byte 20, 23, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0
        .byte "LANDER needs 64K of sideways RAM:", 13, 10
        .byte "four 16K banks, any sockets, writable", 13, 10
        .byte "(through &FE30, or a Watford or", 13, 10
        .byte "Solidisk board).", 13, 10, 0


old_bank: .byte 0                  ; the ROM paged in at the start
bi:     .byte 0                    ; start's bank
fbank:  .byte 4, 5, 6, 7           ; find_ram's sockets for banks 4..7
board:  .byte 0                    ; find_ram's: BOARD_STD, _WATFORD, _SOLIDISK
want:   .byte 0                    ; find_ram's class sought; @count's count
best:   .byte 0                    ; the most sockets a way found, and which way
bestb:  .byte 0
SOCKCLASS: .res NSOCK              ; each socket's CLASS_*, or an alias tag
SAVED:  .res NSOCK                 ; RAM sockets' copyright bytes while signed
wrsl:   .byte <pw4, <pw5, <pw6, <pw7   ; the BIT wrt in each pgN, for wpatch;
wrsh:   .byte >pw4, >pw5, >pw6, >pw7   ; each one's bank (BANKMAP's index)
wrsb:   .byte 0, 1, 2, 3
        .import __DATA_LAST__, __BOOT_LOAD__
        .import __TABLES_LOAD__, __TABLES_RUN__, __TABLES_SIZE__, __CODE_LOAD__, __CODE_RUN__, __CODE_SIZE__
        .import __T0_LOAD__, __T0_RUN__, __T0_SIZE__, __T1_LOAD__, __T1_RUN__, __T1_SIZE__
        .import __T2_LOAD__, __T2_RUN__, __T2_SIZE__, __T3_LOAD__, __T3_RUN__, __T3_SIZE__
        .import __T4_LOAD__, __T4_RUN__, __T4_SIZE__, __T5_LOAD__, __T5_RUN__, __T5_SIZE__
        .import __T6_LOAD__, __T6_RUN__, __T6_SIZE__, __T7_LOAD__, __T7_RUN__, __T7_SIZE__
        .include "tabgen.s"
