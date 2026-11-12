; lander.s: Lander for the BBC Micro, the program's root: the constants, the
; macros, the main loop and the modules, included in the code's order.  Two
; builds: `base`, for a 32K Model B, and `swr` (-D SWR), for a Model B with
; 64K of sideways RAM or a Master.
;
; A landscape of dithered tiles seen in perspective, a strip of land at a time
; between rows of projected corners, with the ship flying over it.  The 32K
; build's display is a field of two CRTC frames: a MODE 5 panel (FUEL, the
; gauge and the map) above a double-buffered land, 256 x 96 pixels in MODE 1
; or MODE 2.  The sideways RAM build's is one frame, two 256 x 160 screens,
; the panel in each one's top 64 lines.
;
; The modules:
;
;   ram.s       the memory map: every variable and table, by address
;   project.s   the camera's rows of points; the tiles' colours (SWR:
;               projswr.s, and prow7.s in bank 7)
;   mapgen.s    the map, generated as it comes into view (32K only: the SWR
;               build's map is stored whole in bank 4)
;   strips.s    the frame's strips; the rows traced
;   rungs.s     the strip's rungs: where each pixel changes box
;   columns.s   the strip's byte columns; the runs
;   video.s     the display's interrupt, the screens' flip (SWR: videoswr.s,
;               with the banks' paging)
;   game.s      the flight, the dots, the panel (SWR: in bank 5)
;   ship.s      the ship (SWR: shipb.s and shipspan.s, bank 6, assembled
;               apart)
;   boot.s      the start: the machine taken, the tables made; run once, from
;               screen 0
;   tabgen.s    its table makers
;
; loader.s, the disc's !BOOT, is a program of its own (src/loader.cfg).
;
; Memory, low to high: the data (zero page to the stored tables), a free block,
; the code, ending with the generated tables' pages (the 32K build's parity
; tables; the SWR build's store pages), and the screen.  The code is placed to
; end exactly where the generated pages begin; build.sh links it there.
;
; Versions (-D): mode1 (none); MODE2 with CPC (cpc: the CPC's 27 colours as
; MODE 2 dithers) or NULA (nula: the VideoNULA's 16), and NULA with ARC (arc:
; Lander's own colours as dithers of the NULA's).  In MODE 2 the land is drawn
; exactly as in MODE 1, four pixels a byte; only the masks (PM) and the colours
; differ.  SWR: the sideways RAM build, its parts in banks 4 .. 7 (videoswr.s
; has the list).

        .setcpu "6502"
        .include "tables.inc"
.ifdef SWR
        .include "swrtab.inc"
.endif
.ifdef MODE2
        .include "pal.inc"
        .assert .defined(CPC) .xor .defined(NULA), error, "MODE2: CPC or NULA"
.define PM(m) ((((m) >> 3) & 1) * $AA | (((m) >> 1) & 1) * $55)
ULAL    = $F4                      ; the land's ULA control: MODE 2
.else
.define PM(m) (m)
ULAL    = $D8                      ; MODE 1
.endif

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
NPART   = 20                       ; dots
FSRJ    = 8                        ; fsplit walks to transitions this near
R2N     = (YGND+1-YSKY)/2          ; run's store pages (SWR): slots a page,
R2OFF   = 255 - 3*R2N              ; the first's offset
PTN     = 3*((YGND+1-YSKY)/2+1)    ; a parity table's bytes (32K)
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

; GSEG s: the game's segment s, or bank 5's in the sideways RAM build.
.macro GSEG s
.ifdef SWR
        .segment "B5CODE"
.else
        .segment s
.endif
.endmacro

; TAIL s .. ENDTAIL: code in segment s, a store page's head, in the sideways
; RAM build; in the 32K build, where it stands.
.macro TAIL s
.ifdef SWR
        .pushseg
        .segment s
.endif
.endmacro
.macro ENDTAIL
.ifdef SWR
        .popseg
.endif
.endmacro

        .include "ram.s"

; loop: the main loop, entered from boot.s's clr with the stack empty.  Never
; returns.
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

; units: su = sy >> 4, the ship's height in units, 8.8.  X, Y kept; clobbers
; A.  (The game's: in bank 5 in the SWR build; in the 32K build here, ahead of
; video.s, whose place the code after it fixes: TAILPAD.)
        GSEG "CODE"
units:  lda sy+1
        lsr a
        lsr a
        lsr a
        lsr a
        sta su+1
        lda sy+2
        asl a
        asl a
        asl a
        asl a
        ora su+1
        sta su+1
        lda sy
        lsr a
        lsr a
        lsr a
        lsr a
        sta su
        lda sy+1
        asl a
        asl a
        asl a
        asl a
        ora su
        sta su
        rts
        .code

.ifdef SWR
        .include "projswr.s"
.else
        .include "project.s"
        .include "mapgen.s"
.endif
        .include "strips.s"
        .include "rungs.s"
        .include "columns.s"
.ifndef COREPAD                    ; the renderer's page phase, tuned by the
.ifdef SWR                         ; flight's cycles (tools/padscan.sh)
COREPAD = 18
.else
COREPAD = 1
.endif
.endif
        .res COREPAD
.ifndef SWR
; mkad (32K): g0 and Y set so that (g0),y is the panel map's byte for line X
; (0..63), pixel mkt (0..31).  X kept; clobbers A.  (The game's; here, ahead
; of video.s, as units.)
mkad:   txa
        and #$38
        asl a
        asl a
        asl a
        sta g0
        lda #>MAP
        adc #0
        sta g0+1
        lda mkt
        and #$1C
        asl a
        ora g0
        sta g0
        txa
        and #7
        tay
        rts
.endif

.ifdef SWR
        .include "videoswr.s"
        .pushseg
        .segment "B5CODE"
        .include "game.s"
        .popseg
        .pushseg
        .include "prow7.s"
        .popseg
.else
        .include "video.s"
        .include "game.s"
        .include "ship.s"
.ifndef TAILPAD                    ; the display's place against the pages:
TAILPAD = 12                       ; its timed branches within theirs
.endif                             ; (video.s's asserts)
        .res TAILPAD
.endif
        .include "boot.s"
