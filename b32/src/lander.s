; lander.s: Lander for a 32K BBC Micro Model B.
;
; A landscape of dithered tiles seen in perspective, a strip of land at a time
; between rows of projected corners, with the ship flying over it.  The
; display is a field of two CRTC frames: a MODE 5 panel (FUEL, the gauge and
; the map) above a double-buffered land, 256 x 96 pixels in MODE 1 or MODE 2.
;
; The modules, in the code's order:
;
;   ram.s       the memory map: every variable and table, by address
;   project.s   the camera's rows of points; the tiles' colours
;   mapgen.s    the map, generated as it comes into view
;   strips.s    the frame's strips; the rows traced
;   rungs.s     the strip's rungs: where each pixel changes box
;   columns.s   the strip's byte columns; the runs
;   video.s     the display's interrupt, the screens' flip
;   game.s      the flight, the dots, the panel
;   ship.s      the ship
;   boot.s      the loader, run once from the land buffers
;
; Memory, low to high: the data (zero page to the stored tables), a free block,
; the code (ending with the parity tables' pages), the screen (the panel, then
; the land buffers at $5000 and $6800).  The code is placed to end exactly at
; the screen; the build links it there.
;
; Builds (-D): MODE 1 (none); MODE2 with CPC (the CPC's 27 colours as MODE 2
; dithers) or NULA (the VideoNULA's 16), and NULA with ARC (Lander's own
; colours as dithers of the NULA's).  In MODE 2 the land is drawn exactly as in
; MODE 1, four pixels a byte; only the masks (PM) and the colours differ.

        .setcpu "6502"
        .include "tables.inc"
.ifdef MODE2
        .include "pal.inc"
        .assert .defined(CPC) .xor .defined(NULA), error, "MODE2: CPC or NULA"
.define PM(m) ((((m) >> 3) & 1) * $AA | (((m) >> 1) & 1) * $55)
ULAL    = $F4                      ; the land's ULA control: MODE 2
.else
.define PM(m) (m)
ULAL    = $D8                      ; MODE 1
.endif

OSBYTE  = $FFF4
CRTC_IDX = $FE00
CRTC_DAT = $FE01
ULA_CTL = $FE20
SVIA_IFR = $FE4D
SVIA_IER = $FE4E
UVIA_T1L = $FE64
UVIA_T1H = $FE65
UVIA_T1LL = $FE66
UVIA_T1LH = $FE67
UVIA_T2L = $FE68
UVIA_T2H = $FE69
UVIA_ACR = $FE6B
UVIA_IFR = $FE6D
UVIA_IER = $FE6E

FMIN    = 4                        ; fields a frame at least
NPART   = 20                       ; the dots
FSRJ    = 8                        ; fsplit walks to transitions this near
PTN     = 3*((YGND+1-YSKY)/2+1)    ; a parity table's bytes
PTEND   = PTN-3                    ; its end slot (line YGND+1)
OP_STAY = $99                      ; STA abs,Y
OP_RTS  = $60
OP_INX  = $E8
OP_DEX  = $CA
        .assert YGND+2-YSKY = 97 && (YSKY & 1) = 0 && ((YGND+1) & 1) = 0, error, "the land's lines: 97, even"

; CLAMP4: A, a difference just made (N its sign), clamped to 0..4.
.macro CLAMP4
        bpl :+
        lda #0
:       cmp #5
        bcc :+
        lda #4
:
.endmacro

        .include "ram.s"

; loop: the main loop, from the loader with the stack empty.  Never returns.
        .code
loop:   jsr gstep
        jsr project
        jsr strips
        jsr gpre
        lda GSHV                   ; the ship, unless crashed
        beq :+
        jsr ship
:       jsr gpost
        jsr flip
        jmp loop

        .include "project.s"
        .include "mapgen.s"
        .include "strips.s"
        .include "rungs.s"
        .include "columns.s"
.ifndef COREPAD                    ; the renderer's page phase, tuned by the
COREPAD = 4                        ; flight's cycles (b32/tools/padscan.sh)
.endif
        .res COREPAD
        .include "video.s"
        .include "game.s"
        .include "ship.s"
        .include "boot.s"
