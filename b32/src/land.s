; ============================================================================
; land.s -- LAND: a Lander-style landscape on a narrow, double-buffered MODE 1
; (or MODE 2: below) screen, with game.s's ship flying over it.  The BBC Micro
; port of proto/land.py (the projection) as proto/frame.py draws it (the
; strips), pixel for pixel.
;
; Building (build.sh).  tools/landgen.py writes the three table images TABLES
; (bank 4), TABLES2 (bank 5) and TABLES7 (bank 7) and tables.inc (their
; addresses and the constants: NX, ZBACK, YSKY, YGND...); tools/gamegen.py
; writes gametab.inc (the game's).  ca65 assembles this file (game.s is
; .included near the end) under src/land.cfg: segment CODE is LAND, loaded at
; $1900; BOOT is LANDS, at $7000; the other segments are code for the banks,
; which build.sh splices into the table images at their addresses.
; landsyms.inc (the symbols shipb.s needs, L_ before each) is cut from
; labels.txt; then tools/shipgen.py and shipb.s make SHIPB (bank 6).
; tools/mkdfs.py writes lander.ssd: !BOOT (the chooser, typed in), $.TABLES7
; (the same in every version), S.LAND and S.TABLES (the same in the MODE 2
; versions) and each version's LANDS, TABLES2 and SHIPB in its directory (M:
; MODE 1, with its LAND and TABLES; C: CPC; N: NULA; A: arc).
;
; Starting.  The chooser selects the version's mode with every colour black
; and the cursor off, selects its directory and *RUNs LANDS.  LANDS (segment
; BOOT, the end of this file) *LOADs LAND, finds four sideways RAM banks
; (find_ram), patches each bank switch's write select for the board (wpatch),
; loads each image through $3000 into its bank, closes !BOOT (the filing
; system is then idle: its workspace from $0E00 is LAND's), makes
; the glyphs, narrows the screen, clears screen 0, sets the palette and jumps
; to `go`.  go runs init, hooks the vertical sync event, turns the VIAs' other
; interrupts off, sets the user VIA's timer 2 counting (vsync restarts it),
; runs G_INIT (bank 5: the game's start) and enters the main loop: G_STEP
; (bank 5: the keys, the flight, the camera), B6_KEYS (bank 6: the ship's
; attitude and place), project, strips, G_PRE (the dots beyond the ship),
; B6_SHIP (the ship, unless crashed: GSHV 0), G_POST (the other dots, the map,
; the status), readout (the frame rate), flip.
;
; The display.  MODE 1 cut by the CRTC to 64 bytes a line and 20 character
; rows: 256 x 160 pixels, 10K a screen, at $3000 (screen 0) and $5800 (screen
; 1); `back` names the one being drawn, and flip shows it.  The land is drawn
; on lines YSKY (64) to YGND (159); the lines above are the game's.  A line's
; byte for pixel x is at (y >> 3) * 512 + (x >> 2) * 8 + (y & 7): the first 32
; byte columns of a character row lie in its first 256 bytes, the rest in its
; second, so a byte column is addressed by its half (scrh: $30, $31, $58, $59)
; and coff = (8 * column) & 255.
;
; The MODE 2 builds (-D MODE2; proto/nula.py): NULA (build.sh nula, -D NULA),
; the VideoNULA's sixteen colours, flat; CPC (build.sh cpc, -D CPC), the 27
; colours of 1 x 2 dithers of MODE 2's eight, as checkerboards; arc (build.sh
; arc, -D NULA -D ARC), Lander's own colours, the row's brightness added
; (pcol5), as checkerboards of the VideoNULA's sixteen.  Everything
; here works in MODE 1's pixels, 256 across and four a byte; a MODE 2
; byte is two pixels, each showing the even one of the pair it covers, so only
; the masks (PM) and the colour bytes (bank 5's, landgen's) differ, with the
; letters (nfont, gbyte) and the palette (palette).  game.s's dots and map
; follow (.ifdef MODE2).
;
; Projection (project).  The camera is at tile (cxt, czt) plus sixteenths
; (cxs, czs), CAMH height units above the ground under the ship (hgnd) and
; CAME more when the game raises it.  The block drawn is NX = 11 columns (map
; x cxt - 4 .. cxt + 6: CX) by nr = 7 or 8 rows, far to near: row 0 on the far
; clip plane (ZFCLIP = 16 tiles: a corner row when czs = 0, otherwise between
; the corner rows either side by 1 - fz), the corner rows, and the last (RN) on
; the near clip plane (ZCLIP = 10), each row's end points pinned at +-XCLIP.
; Bank 7 holds the tables by depth index di: r (pixels a tile), SYT7 (y by
; height less the ground's), B1T (the second corner's x and the carries that
; give the rest), PINL7/PINR7 (the ends' x); and LERPQ7 (land.lerp, by
; sixteenth q), for the ends' heights, the clip rows' and the ground's.  The raw
; heights HT (8 rows of 16) and the strips' box bytes CLE, CLO are kept while
; the camera stays on the same map rows and columns; a step of one row shifts
; them (zsh4, hsh, pcol5's window) and only the new row is fetched.
;
; Strips (strips).  Top to bottom, strip ns lies between rows ns-1 and ns:
; strip 0 has only its bottom row (row 0) traced; strips 1 .. nr-1 are the
; land's, each widened by a black margin box either side out to a byte
; boundary (xl, xr).  (proto/frame.py's sky and ground strips have no
; counterpart: the column records below black the sky above the land and the
; ground below it.)  A strip's two rows are traced into lines by pixel x
; (ROWA, ROWB: the last strip's bottom row is this one's top; traceb traces
; the bottom).  The rungs are the segments joining the rows' corresponding
; points: for each, its pixels LO..HI-1 and the line at which each of them
; passes from the box on one side to the box on the other (RTBUF, by RTPL).
; Box i lies between rungs i and i+1: CE, CO are its dither bytes on even and
; odd lines (black for the margins).  Then the byte columns xl/4 .. xr/4-1
; (cols): a column no rung crosses holds one box; from its top row's highest
; line (mn) to its lowest (mx) the pixels at or below their top are set a line
; at a time (zone1, pmask), then a run fills to the line before the floor
; (flr1: its bottom row's lowest line, which the strip below draws, or in the
; near strip nearpost blacks); a column one rung crosses is split at bpos,
; the number of its pixels left of the rung, which moves at each of the
; rung's transitions (fsplit, split); two rungs (split2, s2v) or more (slow)
; are rarer still.  The near strip's columns are also blacked below the land
; (nearpost).  With the column records' blacking they cover everything the
; frame two back left on this screen (proto/frame.py's argument), so the
; screen is never cleared.
;
; Runs.  STAB is four tables, one for each screen and half (t = 2 * back +
; half): for each line YSKY..YGND, STA addr,Y with addr the line's address in
; that half (Y = coff picks the column), then LDA vo after an even line and TXA
; after an odd (X holds ve), so a run alternates ve and vo down the column; an
; RTS at YGND+1's entry ends the table.  run fills lines X..Y-1 by entering at
; line X's entry (EXLB, EXHB: an odd line's two bytes early, at the LDA vo)
; with an RTS planted at line Y's (ENTL, ENTB), which the next run puts back
; (pp).  run2 does the same in two passes (even lines, then odd) through
; tools/landgen.py's one-parity tables in bank 4 (pages TPE0-3, TPO0-3: an
; STA a line, the RTS planted over the end line's; EINL maps a line to its
; entry).  init builds STAB and the line tables (ENTL, ENTH, LAH in low RAM;
; LAHSB0-3, ENTB0-3, EXLB, EXHB0-3 in bank 4 at SWT).
;
; Double buffering and the column records.  flip waits until FMIN vertical
; syncs have passed since the last flip, shows the screen just drawn (CRTC
; register 12) and swaps `back`; strips waits, before its first store, until
; the screen it draws is no longer shown.  The CRTC takes R12 at the start of
; its frame (display row 0), 11 rows of 512us (5632us) after the vertical
; sync (R7 = 28 of 39 rows), and displays 20 rows, to 15872us; the user VIA's
; timer 2, restarted by vsync, gives the time since the sync.  A flip before
; row 0 (with a margin) is shown from row 0, so strips need not wait (flip
; makes vflip one less); after a flip during the display, strips waits for its
; end (or the sync); one after it needs no wait.  The timer starts a little
; after the sync (the interrupt's latency), so it reads a little early: late
; for the display's end, and within the margin for row 0.  TOPS and BOTS (64
; columns a screen) record, for
; each screen, the land's highest and lowest line at its latest drawing;
; CURT, CURB are this frame's (record, recordc, nearpost; the sky and the
; ground are not land).  The three sets rotate at the end of strips (sidx,
; cidx): this frame's becomes the screen's, the screen's old one is reused.
; record blacks a column from its old top down to its new one, nearpost from
; the new bottom down to the old, and gone blacks columns the land has left;
; game.s and shipb.s widen the screen's set over the dots and the ship.
;
; Main RAM (addresses from build/map.txt and labels.txt):
;   $0000-$008D   zero page (.zeropage below); $008E-$009F scratch shared
;                 between the frame's parts (HPZ, bank 7's, BE/BO, game.s's,
;                 shipb.s's)
;   $0400, $0500  ROWA, ROWB: a row's line by pixel x (a strip's top, bottom)
;   $0600         RTBUF: the rungs' transition lines
;   $0700, $0800  PX, PY: the rows' points, 16 a row, rows 0..7
;   $07D1-$07DA   ZB, RN, (spare), FACT, BCL, CAME, HGV, EYV, MT0, MT1
;   $07DB-$07DF   the game's ship record for bank 6 (game.s: GSHK..GSHV)
;   $07E0         HTN: zsh4's new row of heights (11)
;   $0880-$08FF   HT: the rows' raw heights, 16 a row, rows 0..7
;   $0900, $09A0  CLE, CLO: pcol5's window of box bytes, 16 a row, 10 rows
;   $0A40-$0ADF   TX, TY, BX, BY, LO, HI, RTPL, (spare), CE, CO: the strip's,
;                 16 each
;   $0B00-$0B2F   SPB, STL, STD: the slow way's
;   $0B30         CX: the columns' map x
;   $0B60, $0BA0  CURT, CURB: this frame's column records (64 each)
;   $0C00, $0C80  TOPS, BOTS: each screen's (64 a screen, screen 1's at +64)
;   $0E00, $1000, $1200, $1400  STAB for t = 0..3 (437 bytes each)
;   $1600-$16C1   ENTL, ENTH: each line's entry in its STAB (lines
;                 YSKY..YGND+1: 97 each)
;   $16C2-$1722   LAH: each line's 2 * (y >> 3)
;   $1740-$17A3   EINL,y for y = YSKY-1..YGND+3 (EINL = $1701): run2's table
;                 offsets by line
;   $1800-$18EF   GLY: the readout's 15 characters, 16 bytes each
;   $1900-$2EC0   the code (this file's CODE segment)
;   $2F00         DBUF: shipspan.s's (bank 6), so the code must end below it
;   $3000-$57FF   screen 0; $5800-$7FFF screen 1, LANDS at $7000-$740A
;                 ($7534 at most: the NULA build's) until init clears it
; Page $0D is never touched: the MOS's NMI routine (live on a Master: its
; 1770 disc controller's) and the extended vectors (a ROM's OSBYTE hook) are
; there, and interrupts are still on while init builds the tables.
; The four sideways banks (logical 4..7: BANKMAP holds each one's socket):
;   bank 4, TABLES (paged in except while another bank is called): MAP $8000
;     (64 x 64 corners: height in bits 0-3), run2's store tables (pages
;     $90-$93 even lines, $B6-$B9 odd, from offset R2OFF), the rungs' fast
;     way's TR0-8, TL0-8, SWT $9400-$9AFF (init's line tables; RSMT, landgen's,
;     in its last page), TBLK4, TBLK5, TENL, TENH4, TENH5 (traceb's fills),
;     FPSL, FPSH (the readout), DQT, DRT, DVH, DVR, DVL (division), MRL, MRH
;     (map row addresses), CLMP1, DIV4; and in its free space the code segments
;     B4R, B4L ($9000,
;     $9100), B4S2 ($9200), B4S ($A081), B4C ($A181), B4V1-3 ($B600-$B800),
;     B4Z ($B900)
;   bank 5, TABLES2: CMAPE $8000, CMAPO $9000 (each tile's dither bytes, even
;     and odd lines, by map row * 64 + x; arc: CMAPE the tile's kind and
;     slope, CTE $90EC and CTO $92EC the bytes), pcol5 at $A000, game.s from
;     $A100, GLY5 $BE00 (the game's letters)
;   bank 6, SHIPB (shipb.s): B6_KEYS $8000, B6_SHIP $8003 and the ship's spans
;   bank 7, TABLES7: R7L, R7H, SYT7 $8200, B1T $9800, CLP7, PINL7, PINR7,
;     LERPQ7 $B100, SYL7, SYH7, LQLO, LQHI, prow7 and its helpers ($B480-
;     $BDA5), PXF7 $BEA0, PXN7 $BF50; su_l7's and satrow's pieces in the
;     tables' spare entries ($80B0, $81B0, $AEB0, $AFB0, $B0B0)
; ============================================================================
        .setcpu "6502"
        .include "tables.inc"
; PM m: MODE 1 pixel mask m as drawn.  The MODE 2 builds (-D MODE2: a byte
; two pixels, each showing the even one of the two of LAND's it covers) make
; it the left pixel's bits ($AA) if m has pixel 0, the right's ($55) if pixel 2
; (proto/nula.py's mask); MODE 1: m itself.
.define PM(m) (m)

OSWRCH  = $FFEE
OSWORD  = $FFF1
OSBYTE  = $FFF4
OSCLI   = $FFF7
EVNTV   = $0220
ROMSEL  = $FE30
ROMCOPY = $F4
CRTC_IDX = $FE00
CRTC_DAT = $FE01
BANK    = 4                        ; bank 4: the tables (TABLES)
FMIN    = 4                        ; vertical syncs a frame, at least (flip)
BANK3   = 6                        ; bank 6: the ship (SHIPB, shipb.s)
B6_KEYS = $8000
B6_SHIP = $8003
G_INIT  = $A100                    ; bank 5's jump table: the game (game.s)
G_STEP  = $A103
G_POST  = $A106
G_PRE   = $A109
BANK7   = 7                        ; bank 7: the projection (TABLES7)
BANK2   = 5                        ; bank 5: the tiles' colours and the game
                                   ; (TABLES2)
; (banks 4..7 are logical: BANKMAP holds the socket of each, find_ram's)
MOS_ROMTAB = $02A1                 ; the MOS's ROM type table, by socket
ROMHDR_TYPE = $8006                ; a ROM header's type byte
ROMHDR_COPY = $8007                ; and its copyright offset
UVIA_DDRB = $FE62                  ; the user VIA's port B direction register
UVIA_T2L = $FE68                   ; its timer 2: the time since the vertical
UVIA_T2H = $FE69                   ; sync, counting down from $FF00 (vsync's)
                                   ; at 1 MHz: high byte $FF - ceil(us/256)
UVIA_ACR = $FE6B                   ; (0: timer 2 counts the clock)
CR_ROWS = 20                       ; the CRTC's character rows displayed (R6),
CR_VSYNC = 28                      ; the row of its vertical sync (R7) and its
CR_TOTAL = 39                      ; rows a frame (R4 + 1, the MODE's), of 512us
T2ROW0  = $FF - EV1US/256 + 3     ; T2H at least: at most 7680us since the
                                   ; sync, before irq's E1 (at EV1US) takes
                                   ; lfront for the land's segment (flip's)
T2DEND  = $FF - (CR_TOTAL-CR_VSYNC+CR_ROWS)*512/256  ; T2H at least: at most
                                   ; 15872us, the display's end (strips')
WRSEL_WATFORD = $FF30              ; a Watford board's write select: a store to
WRSEL_SOLIDISK = $FE60             ; here + the socket; a Solidisk's: port B
BOARD_STD = 0                      ; find_ram's board kinds (writes through
BOARD_WATFORD = 1                  ; ROMSEL alone, or by the board's select)
BOARD_SOLIDISK = 2

; PAGE n: sideways bank n (4..7) paged in for reads and writes, by pgN (its
; BIT wrt is patched by LANDS's wpatch into the board's write select).  On
; return A is the socket; X, Y kept; the flags are the BIT's (wrt is 0: Z set,
; N and V clear) or, on a patched board, the LDA's.
.macro PAGE n
.endmacro
; CLAMP4: A, a signed difference just computed (N its sign), clamped to 0..4.
.macro CLAMP4
        bpl :+
        lda #0
:       cmp #5
        bcc :+
        lda #4
:
.endmacro

                                   ; (YSKY, YGND: the first and last land
                                   ; lines, tables.inc)
MARGIN  = 0                        ; pixels beyond the bottom row's ends before
                                   ; rounding out to a byte boundary (setup)

DBUF    = $0300                    ; the ship's lines (ship32.s), a page
ROWA    = $0400
ROWB    = $0500
RTBUF   = $0600
PX      = $0700                    ; the rows' points, far to near: 16 a row
PY      = $0800
HTN     = $07E0                    ; zsh4's: the new row's heights, for hsh
HT      = $0880                    ; the rows' raw heights, 16 a row (project)
CLE     = $0900                    ; pcol5's window of box bytes: 16 a row, even
CLO     = $09A0                    ; and odd lines
TX      = $0A40                    ; the strip's top row's points (0 and NX+1:
TY      = $0A50                    ; the margins)
BX      = $0A60                    ; and its bottom row's
BY      = $0A70
LO      = $0A80                    ; each rung's pixels: LO..HI-1 (HI = LO:
HI      = $0A90                    ; none)
RTPL    = $0AA0                    ; and its transitions' base: pixel x's line
                                   ; is in RTBUF's page at offset RTPL + x + 1
CE      = $0AC0                    ; each box's byte on even and odd lines
CO      = $0AD0
SPB     = $0B00                    ; the slow way's: each pixel's box at the top
STL     = $0B10                    ; and its transitions (4 a pixel: line, step)
STD     = $0B20
GLY     = $1800                    ; the readout's characters: 16 bytes each
ENTL    = $1600-YSKY               ; each line's entry in its STAB: low byte,
ENTH    = $1661-YSKY               ; and the page within the table (lines
                                   ; YSKY..YGND+1)
TOPS    = $0C00                    ; by screen (+64 for screen 1) and column:
BOTS    = $0C80                    ; the land's highest and lowest line last
CURT    = $0B60                    ; time there, and this frame's
CURB    = $0BA0
STAB    = $0E00
LAH     = $16C2-YSKY               ; each line's 2 * (y >> 3) (lines
                                   ; YSKY..YGND+1)
        .assert ENTL + YSKY >= STAB + 2*$100 + 437 && ENTH + YGND+2 <= LAH + YSKY, error, "ENTL, ENTH: past STAB 1, before LAH"
        .assert YGND+2-YSKY <= 97, error, "LAH, ENTL: 97 lines each"
CX      = $0B30                    ; the columns' map x (project)
BCL     = $07D5                    ; this strip's bottom points past YGND: a
                                   ; count (0: none)
ZB      = $07D1                    ; ZBACK less the first row's j: row k's map
RN      = $07D2                    ; row is czt + ZB - k; the near clip's row
FACT    = $07D4                    ; (ZB - ZCLIP, the last); the far clip's row
                                   ; is between the rows either side (1) or a
                                   ; corner row (0)
CAME    = $07D6                    ; the camera above CAMH (0..EMAX: game.s's)
HGV     = $07D7                    ; the ground under the ship (hgnd's, for
                                   ; game.s)
EYV     = $07D8                    ; prow7's: a row's extra y for CAME (eyrow),
MT0     = $07D9                    ; and eyrow's, satrow's and cliprow7's
MT1     = $07DA                    ; scratch

        .assert YGND+2-YSKY <= 97 && 97+YGND+1-YSKY < $100, error, "SWT: a line table crosses its page"
OP_STAY = $99                      ; STA abs,Y
OP_LDAZ = $A5                      ; LDA zp
OP_TXA  = $8A
OP_RTS  = $60
OP_INX  = $E8
OP_DEX  = $CA

        .zeropage
cxt:    .res 1                     ; the camera: tile and sixteenth, x and z
cxs:    .res 1
czt:    .res 1
czs:    .res 1
back:   .res 1                     ; the screen being drawn: 0 ($3000) or 1
scrb:   .res 1                     ; ($5800), and its high byte
np:     .res 1                     ; points a row: NX (prow7's; game.s reads
                                   ; it: the renderer uses NX)
nr:     .res 1                     ; rows: 7 or 8 (project's)
vcount: .res 1                     ; vertical syncs (vsync's)
vflip:  .res 1                     ; vcount at the last flip
ptr:    .res 2                     ; a pointer (init, putg, LANDS)
tmp:    .res 2                     ; scratch (init, prow7's 16 j, hgnd, slow,
                                   ; slow2, LANDS)
; project
syp:    .res 2                     ; bank 7's: the row's SYT7 line, offset by
lp:     .res 2                     ; HOFF; a LERPQ7 row (the clip rows' q =
                                   ; 16 - czs; hgnd's)
rl:     .res 1                     ; the row's r, low and high (R7BP)
rh:     .res 1
; strips
ns:     .res 1                     ; the strip: 0 (row 0 traced only), 1..nr-1
                                   ; the land's (nr-1 the near strip)
xl:     .res 1                     ; the strip's margins: its columns are
xr:     .res 1                     ; xl/4 .. xr/4 - 1
xlp:    .res 1                     ; the last strip's
xrp:    .res 1
topa:   .res 2                     ; its top row's line by pixel (ROWA or
bota:   .res 2                     ; ROWB), and its bottom's (the other)
; trace
tdx2:   .res 1                     ; traceb's: 2 dx, 2 |dy|, the error, the y
tdy2:   .res 1                     ; walked, the segment's x1; tj: an index or
                                   ; scratch (the segment, the rung, gone's
                                   ; column, slow's pixel, mktr's index,
                                   ; s2v's stretch end; fsplit's fwu)
terr:   .res 1
tyy:    .res 1
tx1:    .res 1
tj:     .res 1
; rungs
tyv:    .res 1                     ; traceb's: the pending run's y
ra2:    .res 1                     ; 2a (traceb: 2 |dy|)
rq:     .res 1                     ; D div 2a and the remainder's running form
rrem:   .res 1
rq2:    .res 1                     ; D div a and 2 (D mod a)
rr2:    .res 1
alloc:  .res 2                     ; the next free byte in RTBUF
rtp:    .res 2                     ; a rung's transitions by position (split,
                                   ; mktr)
dva:    .res 1                     ; the divisor a and dividend D (divs, divt)
dvd:    .res 1
fe:     .res 1                     ; traceb's: a long fill's end
tcnt:   .res 1                     ; traceb's: the pending run's first x
tsy:    .res 1                     ; gone's: xr / 4, the first column right
                                   ; of the near strip
last:   .res 1                     ; $FF: the near strip (cols tests bit 7);
                                   ; else 0
lastri: .res 1                     ; the rung BE, BO, rbl, fst_e are made for
                                   ; ($FF: none)
BE      = $8E                      ; fsplit's rung's bytes by bpos 0..4, even
HPZ     = $8E                      ; and odd lines; project's 8 map row pointers
BO      = BE+5                     ; (both in the shared scratch $8E-$9F)
; columns
x4:     .res 1                     ; the column's first pixel x (a multiple
                                   ; of 4)
x4p4:   .res 1                     ; x4 + 4 (slow's)
coff:   .res 1                     ; (8 * column) & 255: the byte within the
                                   ; half
scrh:   .res 1                     ; the screen's high byte + the half (shs)
ri:     .res 1                     ; the first rung not wholly left of the
                                   ; column
ys:     .res 4                     ; each pixel's top-row line
mn:     .res 1                     ; the top's highest and lowest lines
mx:     .res 1
flr:    .res 1                     ; the near strip's floor (the bottom's lowest
                                   ; line) when not level, else 0 (nearpost's)
flr1:   .res 1                     ; the run's end: the floor (the strip below
                                   ; draws that line), or flr + 1 in the near
                                   ; strip when the floor is not level
ve:     .res 1                     ; the bytes being drawn: even and odd lines
vo:     .res 1
re:     .res 1                     ; split2's right box's bytes
ro:     .res 1
bpos:   .res 1                     ; a split column's boundary: pixels left
                                   ; of it
p0:     .res 1                     ; mktr's: the rung's position at the top,
p1:     .res 1                     ; bottom
yy:     .res 1                     ; split2's: the run's first line, its
kk:     .res 1                     ; transition index (yy: slow2's line too)
fwe     = kk                       ; fsplit's: the walk's end, as a line in
                                   ; the row
rsm     = yy                       ; fsplit's: the row's first line - 1 (RSMT)
fwu     = tj                       ; fsplit's: a transition line beyond the
                                   ; row
FSRJ    = 8                        ; fsplit walks, rather than runs, to a
                                   ; transition less than 8 + FSRJ lines
                                   ; below the row's first line
msk:     .res 1                    ; the pixel mask (pixel p: bits 7-p and 3-p)
zv:     .res 1                     ; zline's byte
zp_:    .res 2                     ; a line's address, for (zp_),y
dvx:    .res 1                     ; div8's divisor
RVE:    .res 1                     ; run2's bytes: even and odd lines
RVO:    .res 1
stabp:  .res 1                     ; STAB's page for t (sethalf's)
TRL:    .res 12                    ; mktr's transitions: line, and bpos after
TRB:    .res 12                    ; as an LM mask (a second rung's from 6;
                                   ; also bank 6's scratch)
kb:     .res 1                     ; split2's: the second rung's transition
                                   ; index (s2v's: rung ri's)
pp:     .res 2                     ; run's planted RTS (dummy: none)
tsp:    .res 2                     ; TOPS, BOTS of the screen being drawn (its
bsp:    .res 2                     ; set)
bpos2:  .res 1                     ; split2's, s2v's: the second boundary
le:     .res 1                     ; split2's, s2v's: the left box's bytes;
lo2:    .res 1                     ; split2's: the middle's EORed with the
me:     .res 1                     ; right's
mo:     .res 1

        .code
; ---------------------------------------------------------------- start
; go: the loader's (boot32.s) last jump, with the machine taken over and the
; tables made.  The land buffers cleared, screen 0 the one drawn (setback), the
; game's start; then each frame the game's step, the projection, the strips,
; the dots beyond the ship, the ship (unless crashed), the nearer dots and the
; map's marker, the readout, flip.  Never returns.
go:     lda #0                     ; the land buffers black (the loader ran
        tay                        ; from them)
        sta ptr
        ldx #>LAND0
        stx ptr+1
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        bpl :-                     ; (to $7FFF)
        sta back                   ; screen 0 first
        jsr setback
        jsr ginit
loop:   jsr gstep
        jsr project
        jsr strips
        jsr gpre
        lda GSHV                   ; the ship, unless crashed
        beq :+
        jsr ship
:       jsr gpost
        jsr readout
        jsr flip
        jmp loop

; ---------------------------------------------------------------- the display
; Two CRTC frames a field (vertical rupture), 39 rows of 8 lines in all, the
; vertical sync at row 28 as a one-frame MODE 1 has it:
;   the panel: rows 0..7, R4 7, the first 5 displayed (R6 5), 16 characters
;     wide (R1 16, at the left), from PANEL: the map and the readout; the
;     other 3 rows black border;
;   the land: rows 8..38, R4 30, 12 displayed (R6 12), 64 wide, from the
;     front land buffer (lfront), its sync at its row 20 (R7 20).
; A frame's start address is taken at its start (VCC 0); R4 is compared at
; each row's end and R6 at each row's start, so each frame's are written while
; it runs, the next's start address too.  Three interrupts (irq):
;   E0, the sync (the system VIA's CA1): vcount, timer 2 restarted (the time
;     since the sync), the panel's R1, R6, start; timer 1 for E1;
;   E1, EV1US later, the panel's row 5 (its display over): R4 7, R7 20, the
;     land's R1, R6 and start (lfront); timer 1 for E2;
;   E2, EV2US on, the land's row 0: R4 30.
EV1US   = 11*512 + 5*512 + 250     ; the sync to E1: the panel's row 5 (it
                                   ; starts 11 rows after the sync)
EV2US   = 3*512 + 300              ; E1 to E2: the land's row 0 (+ 300us)
SVIA_IFR = $FE4D
SVIA_IER = $FE4E
UVIA_T1L = $FE64                   ; the user VIA's timer 1 (low, high: a
UVIA_T1H = $FE65                   ; one-shot, ACR 0)
UVIA_IFR = $FE6D
UVIA_IER = $FE6E
.macro CRW r, v                    ; CRTC register r = A (v blank) or #v
        lda #r
        sta CRTC_IDX
.ifnblank v
        lda #v
.else
        lda lfront
.endif
        sta CRTC_DAT
.endmacro
; irq (IRQ1V: the MOS ROM's entry has stored A in $FC): E0, E1 or E2 above.
irq:    txa
        pha
        lda #$02                   ; the sync (CA1)?
        bit SVIA_IFR
        beq @t
        sta SVIA_IFR               ; (its flag cleared)
        inc vcount
        lda #$FF
        sta UVIA_T2H               ; the time since the sync
        CRW 1, 16                  ; the panel: 16 wide, 5 rows, PANEL
        CRW 6, 5
        CRW 12, >(PANEL/8)
        CRW 13, <(PANEL/8)
        lda #<EV1US
        sta UVIA_T1L
        lda #>EV1US
        sta UVIA_T1H               ; (timer 1 off for E1; its flag cleared)
        lda #0
        sta evn
        beq @x                     ; (always)
@t:     lda UVIA_IFR               ; timer 1 (E1, E2)?
        and #$40
        beq @x
        lda UVIA_T1L               ; (its flag cleared)
        lda evn
        bne @e2
        CRW 4, 7                   ; E1: the panel's end; the land's frame
        CRW 7, 20
        CRW 1, 64
        CRW 6, 12
        CRW 12
        CRW 13, 0
        lda #<EV2US
        sta UVIA_T1L
        lda #>EV2US
        sta UVIA_T1H
        inc evn
        bne @x                     ; (always)
@e2:    CRW 4, 30                  ; E2: the land's 31 rows
@x:     pla
        tax
        lda $FC
        rti
evn:    .byte 0                    ; irq's: the next timer event (0 E1, 1 E2)
lfront: .byte >(LAND0/8)           ; the land shown (flip's)
        .assert <(LAND0/8) = 0 && <(LAND1/8) = 0, error, "the land buffers' R13 is 0"

; flip: when FMIN vertical syncs have passed since the last flip, show the
; screen just drawn (`back`) and make the other the one to draw.  Records the
; frame's syncs in dvs (the last 8, dvi the next slot) for the readout; vflip,
; vlast = vcount at the flip, then vflip one less if the CRTC has yet to reach
; display row 0 (timer 2: the new screen is shown from there, so strips need
; not wait).  Falls into setback.  Clobbers A, X.
flip:   lda vcount                 ; (FMIN = 4: 12.5 frames a second at most)
        sec
        sbc vlast
        cmp #FMIN
        bcc flip
        lda back                   ; the land shown from the next panel event
        beq :+                     ; on (irq's: R12; R13 is 0 for both)
        lda #>(LAND1/8) - >(LAND0/8)
:       clc
        adc #>(LAND0/8)
        sta lfront
        lda vcount
        sta vflip
        sec
        sbc vlast                  ; the frame's syncs: dvs[dvi], then dvi =
                                   ; (dvi + 1) & 7
        ldx dvi
        sta dvs,x
        inx
        txa
        and #7
        sta dvi
        lda vflip
        sta vlast
        lda UVIA_T2H               ; before row 0: shown from row 0, so the
        cmp #T2ROW0                ; screen to draw is no longer
        bcc :+
        dec vflip
:       lda back
        eor #1
        sta back
; setback: scrb ($30 or $58) and sethalf's screen bits (sh_b's operand: 2 *
; back) for `back`.  Clobbers A.
setback:
        lda back
        beq :+
        lda #SCR1-SCR0
:       clc
        adc #SCR0
        sta scrb
        lda back
        asl a
        sta sh_b+1                 ; (sethalf's ORA #: t = 2 * back + half)
; The two STABs (one a half) store to the screen `back`: when they hold the
; other's addresses (stabs), each line's STA operand's high byte moves by the
; screens' difference, in both.  Clobbers A, X, Y, ptr.
        lda back
        cmp stabs
        beq @x
        sta stabs
        ldy #SCR1-SCR0             ; (the move: up to screen 1, down to 0)
        cmp #0
        bne :+
        ldy #<(SCR0-SCR1)
:       sty sdl
        ldx #YSKY
@l:     lda ENTL,x                 ; line X's STA in STAB 0: its operand's
        sta ptr                    ; high byte 2 on
        lda ENTH,x
        ora #>STAB
        sta ptr+1
        ldy #2
        lda (ptr),y
        clc
        adc sdl
        sta (ptr),y
        inc ptr+1                  ; and in STAB 1, two pages on
        inc ptr+1
        lda (ptr),y
        clc
        adc sdl
        sta (ptr),y
        inx
        cpx #YGND+1
        bne @l
@x:     rts
stabs:  .byte 0                    ; the screen the STABs store to (init's: 0)
rk:     .res 2                     ; (init's: k, the divisor, the dividend and
rd:     .res 2                     ; quotient, the remainder)
rn:     .res 3
rr:     .res 2
sdl:    .byte 0

        .include "boot32.s"
; ---------------------------------------------------------------- init
        .segment "BOOT"            ; (the loader's: run once, then overwritten)
; init: both screens black ($3000-$7FFF: LANDS with them); the four STABs and
; the line tables (ENTL, ENTH; LAH; in bank 4: LAHSB0-3,
; ENTB0-3, EXLB, EXHB0-3); TOPS, BOTS to nothing drawn; traceb's fill blocks'
; JMPs; EINL; pp to dummy; the camera at tile (40, 30), sixteenths 0; dvs.  No
; OS calls: the tests (test/landsoak.py, test/gametest.py) run it under py65.
; Needs bank 4 paged in and writable.  Clobbers A, X, Y, ptr, tmp.
init:   jsr shtab                  ; the ship's walker's tables
        lda #<DI0                  ; R7L, R7H: (2^21 + k) div 2k, k = DI0 + di
        sta rk                     ; (rk, rk+1: k)
        lda #>DI0
        sta rk+1
        ldx #0
@r7:    lda rk                     ; the divisor 2k
        asl a
        sta rd
        lda rk+1
        rol a
        sta rd+1
        lda rk                     ; the dividend 2^21 + k, 24-bit (rn)
        sta rn
        lda rk+1
        sta rn+1
        lda #$20
        sta rn+2
        lda #0                     ; the remainder (rr, rr+1), the quotient
        sta rr                     ; shifted into rn
        sta rr+1
        ldy #24
@rd:    asl rn
        rol rn+1
        rol rn+2
        rol rr
        rol rr+1
        lda rr
        sec
        sbc rd
        pha
        lda rr+1
        sbc rd+1
        bcc :+
        sta rr+1
        pla
        sta rr
        inc rn
        bne :++                    ; (always: bit 0 was 0)
:       pla
:       dey
        bne @rd
        lda rn
        sta R7L,x
        lda rn+1
        sta R7H,x
        inc rk
        bne :+
        inc rk+1
:       inx
        cpx #NDI
        bne @r7
        ; STAB t = 2 * screen + half, at page >STAB + 2t: for each line x of
        ; YSKY..YGND+1, STA addr,Y (RTS at YGND+1), then LDA vo (even x) or
        ; TXA (odd); ENTL, ENTH hold each line's entry
        lda #0
        sta tmp                    ; t
@tab:   lda tmp
        asl a
        adc #>STAB
        sta ptr+1
        lda #0
        sta ptr
        ldx #YSKY
@line:  lda ptr
        sta ENTL,x
        lda ptr+1
        and #1                     ; (each STAB starts at an even page: 0 or 1)
        sta ENTH,x
        ldy #0
        lda #OP_STAY
        cpx #YGND+1
        bne :+
        lda #OP_RTS
:       sta (ptr),y
        txa
        and #7                     ; the line's address: low byte y & 7,
        iny
        sta (ptr),y
        txa
        lsr a
        lsr a
        and #$FE                   ; high byte 2 * (y >> 3) + the half + the
        sta tmp+1                  ; screen's $30 or $58
        lda tmp
        and #1
        ora tmp+1
        sta tmp+1
        lda tmp
        and #2
        beq :+
        lda #SCR1-SCR0
:       clc
        adc #SCR0
        adc tmp+1
        iny
        sta (ptr),y
        iny
        txa                        ; an even line: LDA vo (2 bytes); odd: TXA
        lsr a
        lda #OP_TXA
        bcs :+
        lda #OP_LDAZ
        sta (ptr),y
        iny
        lda #vo
:       sta (ptr),y
        tya
        sec                        ; ptr += Y + 1
        adc ptr
        sta ptr
        bcc :+
        inc ptr+1
:       inx
        cpx #YGND+2
        bne @line
        inc tmp
        lda tmp
        cmp #2
        bne @tab
        ldx #0                     ; the line tables, for lines YSKY..YGND+1
@ent:   cpx #YSKY                  ; (X runs 0..255; the rest skipped)
        bcc :+
        cpx #YGND+2
        bcs :+
        txa
        lsr a
        lsr a
        and #$FE                   ; 2 * (y >> 3)
        sta LAH,x
:       inx
        beq :+
        jmp @ent
:
        ldx #127                   ; TOPS $FF, BOTS 0: nothing drawn, both
                                   ; screens
:       lda #$FF
        sta TOPS,x
        lda #0
        sta BOTS,x
        dex
        bpl :-
        lda #<dummy                ; no RTS planted yet: run's first put-back
        sta pp                     ; lands on dummy
        lda #>dummy
        sta pp+1
        lda #40                    ; the camera (proto's start: tile 40, 30)
        sta cxt
        lda #30
        sta czt
        lda #0
        sta cxs
        sta czs
        ldx #7                     ; the readout's sync counts
:       lda #0
        sta dvs,x
        dex
        bpl :-
        rts

        .code
; ---------------------------------------------------------------- project
; project: the block of corners (proto/land.py: project) as rows of points.
; Sets ZB, FACT, RN and nr from czs.  If the map columns (cxt) or rows (czt +
; ZB) differ from last frame's (pkx, pkz): refetches CX and every row's raw
; height into HT (bank 4's MAP via HPZ), or for a step of one row has zsh4
; fetch the new row alone (HTN, SHF: prow7's hsh shifts HT).  Then, changed
; or not, bank 5's pcol5 remakes the strips' box bytes (CLE, CLO) as needed
; (the arc build's change with czt, which can change on the same rows: czt +
; 1 as czs goes from 15 to 0), and bank 7's prow7 makes the rows' points (PX,
; PY: x from B1T and r, y from SYT7 by height less the ground's, hgnd, plus
; eyrow's EYV for CAME), the clip planes' rows interpolated by 1 - fz, and np
; = NX.
; In: cxt, cxs, czt, czs, CAME.  Out: ZB, RN, FACT, nr, np, CX, HT, HTN,
; SHF (0 after), PX, PY, HGV, EYV, pkx, pkz, CLE, CLO, ldCLE; bank 4 paged.
; Clobbers A, X, Y, tmp, rl, rh, syp, lp, MT0, MT1, $8E-$9E.  Called by the
; main loop.
project:
        lda #ZFCLIP                ; ZB: the first row is the far clip's: a
        ldx #0                     ; corner row (ZB = ZFCLIP, FACT 0) at czs 0,
        ldy czs                    ; else between rows ZFCLIP and ZFCLIP+1 (ZB
        beq :+                     ; = ZFCLIP+1, FACT 1)
        lda #ZFCLIP+1
        inx
:       sta ZB
        stx FACT
        sec                        ; RN = ZB - ZCLIP: the near clip's row, the
        sbc #ZCLIP                 ; last; nr = RN + 1
        sta RN
        tay
        iny
        sty nr
        lda cxt                    ; the same columns and map rows as last frame
        cmp pkx                    ; (pkx, pkz): HT stands, pcol5 and prow7 only
        bne @cx
        lda czt
        clc
        adc ZB
        cmp pkz
        bne @zs
        jmp @p5
@zs:    jsr zsh4                   ; (bank 4) a step of one map row: the new
        bcc @hl                    ; row's heights into HTN, SHF set for prow7's
        jmp @p5                    ; hsh to shift HT, C set; C clear: all anew
@cx:    sta pkx                    ; CX: map x cxt - 5 + XSKIP + i, i = 0..NX-1,
        sec                        ; mod 64 (proto's xs)
        sbc #5-XSKIP
        ldx #0
:       and #MAPN-1
        sta CX,x
        clc
        adc #1
        inx
        cpx #NX
        bne :-
        .assert ZBACK-ZSKIP-ZCLIP+1 = 8 && ZFCLIP-ZCLIP+1 = 7, error, "nr 7 or 8"
@hl:    lda czt                    ; (bank 4) all 8 rows' heights: pkz = czt +
        clc                        ; ZB; HPZ + 2j = map row czt + ZB - j's
        adc ZB                     ; address (MRL, MRH), row 7's first; then
        sta pkz                    ; HT + 16j + i = its corner CX[i]'s height
        sbc #6                     ; (C clear: - 7)
        ldx #14
@hp:    and #MAPN-1                ; HPZ + 2j = MAP32 + 32 z: page + (z >> 3),
        tay                        ; low byte (z & 7) << 5
        lsr a
        lsr a
        lsr a
        ora #>MAP32
        sta HPZ+1,x
        tya
        asl a
        asl a
        asl a
        asl a
        asl a
        sta HPZ,x
        iny
        tya
        dex
        dex
        bpl @hp
        ldx #NX-1
@hc:    ldy CX,x
        lda (HPZ+14),y             ; row 7
        and #15
        sta HT+$70,x
        .repeat 7, i               ; rows 6..0
        lda (HPZ+12-2*i),y
        and #15
        sta HT+$60-16*i,x
        .endrepeat
        dex
        bpl @hc
@p5:    jsr pcol5                  ; the land strips' box bytes
        jmp prow32                 ; the rows' points (proj32.s)

; ---------------------------------------------------------------- strips
; strips: the frame's strips, top to bottom.  Strip ns (0 .. nr-1) lies
; between rows ns-1 and ns: strip 0 only has its bottom row (row 0) traced;
; strips 1 .. nr-1 are the land's, and the last of them (ns = nr-1, the near
; strip) also paints the ground below the near row from its columns
; (nearpost).  A strip's points: 0 its left margin, 1 .. NX the rows', NX+1
; its right margin.
; Each column's highest and lowest land line is kept in three sets of 64
; bytes (setTl .. setBh: TOPS, BOTS; TOPS+64, BOTS+64; CURT, CURB): one a
; screen (sidx: the land as last drawn there, two frames back) and one this
; frame's (cidx).  The operand of every site that reads the screen's set or
; writes this frame's is patched here, and the sets are rotated at the end.
; In: back, nr, PX, PY (project's), CLE, CLO, ldCLE (pcol5's), vcount,
; vflip, timer 2.  Out: the screen drawn; the sets; sidx, cidx; xlp, xrp,
; topa, bota.
; Clobbers A, X, Y and the strips', trace's, rungs' and columns' zero page.
; Called by loop.
strips: ldx back                   ; the screen's set (sidx): tsp, bsp (gone's)
        ldy sidx,x                 ; and the TOPS reads (pT5, pT5c: record,
        lda setTl,y                ; recordc; pT6, pT6b: gone) and BOTS reads
        sta tsp                    ; (pB5, pB6, pB8: nearpost)
        sta pT5+1
        sta pT5c+1
        sta pT6+1
        sta pT6b+1
        lda setTh,y
        sta tsp+1
        sta pT5+2
        sta pT5c+2
        sta pT6+2
        sta pT6b+2
        lda setBl,y
        sta bsp
        sta pB5+1
        sta pB6+1
        sta pB8+1
        lda setBh,y
        sta bsp+1
        sta pB5+2
        sta pB6+2
        sta pB8+2
        ldy cidx                   ; this frame's set (cidx): the CURT stores
        lda setTl,y                ; (pT3, pT3c: record, recordc, each column
        sta pT3+1                  ; by the first strip it is in; pT4, pT4b:
        sta pT3c+1                 ; gone) and the CURB stores (pB4: nearpost,
        sta pT4+1                  ; in the near strip, whose columns include
        sta pT4b+1                 ; every strip's; pB7, pB7b: gone)
        lda setTh,y
        sta pT3+2
        sta pT3c+2
        sta pT4+2
        sta pT4b+2
        lda setBl,y
        sta pB4+1
        sta pB7+1
        sta pB7b+1
        lda setBh,y
        sta pB4+2
        sta pB7+2
        sta pB7b+2
        lda #>ROWA                 ; the top row's line by pixel at (topa), the
        sta topa+1                 ; bottom row's at (bota): ROWA and ROWB,
        lda #>ROWB                 ; swapped after each strip
        sta bota+1
        lda #0
        sta topa
        sta bota
        sta ns
@strip: jsr setup                  ; the points, boxes and margins, the bottom
        jsr bclip                  ; row traced; then held at YGND+1 where it
        lda ns                     ; is past the screen
        beq @swap                  ; (strip 0: traced only)
        jsr rungs
        lda ns                     ; strip 1, before the frame's first store:
        cmp #1                     ; wait until the screen drawn is no longer
        bne @draw                  ; shown: a sync since the flip (vflip one
@wait:  lda vcount                 ; less: none needed), or the display over
        cmp vflip                  ; (timer 2)
        bne @draw
        lda UVIA_T2H
        cmp #T2DEND
        bcs @wait
@draw:  jsr cols
@swap:  lda topa+1                 ; the bottom row is the next strip's top
        ldx bota+1
        sta bota+1
        stx topa+1
        lda xl
        sta xlp
        lda xr
        sta xrp
        inc ns
        lda ns
        cmp nr
        bcc @strip
        jsr gone                   ; the columns the land has left: black
        ldx back                   ; rotate: this frame's set becomes the
        ldy cidx                   ; screen's, the screen's old set the next
        lda sidx,x                 ; frame's
        sta cidx
        tya
        sta sidx,x
        rts
sidx:   .byte 0, 1                 ; each screen's set (sets 0 and 1: init's
cidx:   .byte 2                    ; $FF, 0, nothing drawn), and this frame's
setTl:  .byte <TOPS, <(TOPS+64), <CURT
setTh:  .byte >TOPS, >(TOPS+64), >CURT
setBl:  .byte <BOTS, <(BOTS+64), <CURB
setBh:  .byte >BOTS, >(BOTS+64), >CURB

; setup: the strip's points, boxes and margins, and its bottom row's line.
; Points 1 .. NX: strip 0 takes row 0 as its bottom row only (it is only
; traced: its TX, TY, CE and CO are never read); a land strip (ns 1 .. nr-1)
; takes rows ns-1 (TX, TY) and ns (BX, BY) and its boxes 1 .. NX-1 from
; pcol5's window (su_l7, in bank 7); BCL counts the bottom points past YGND.
; Points 0 and NX+1 are the margins: x at the byte boundary at or left of the
; bottom row's first point (xl) and at or right of its last (xr), y the end
; points'; boxes 0 and NX black.  Then the bottom row is traced into (bota)
; (traceb, whose RTS is this routine's).  In: ns, nr, PX, PY, CLE, CLO, ldCLE,
; bota.  Out: BX, BY (0 .. NX+1), and for a land strip TX, TY (0 .. NX+1) and
; CE, CO (0 .. NX); xl, xr, BCL, last ($FF for the near strip, ns = nr-1),
; (bota).  Clobbers A, X, Y and traceb's (bank 7 paged for su_l7 and bank 4
; back: pw7s, pw4s are wpatch's).  Called by strips.
setup:  lda #0
        sta BCL
        tax
        ldy ns
        iny
        cpy nr
        bne :+
        dex
:       stx last                   ; the near strip: $FF (cols' kind 1)
        ; a land strip: rows ns-1 and ns; box b's bytes at CLE, CLO + 16 (ns
        ; - 1) + ldCLE + b - 1 (su_l7, unrolled in bank 7)
        lda ns
        beq su_r                   ; (A = 0: strip 0, row 0 its bottom row)
        asl a                      ; 16 (ns - 1): the top row's offset in PX,
        asl a                      ; PY (C clear: ns < 16)
        asl a
        asl a
        adc #$F0
        sta tmp
        tay
        ldx #0                     ; points 1 .. NX: rows ns-1 (TX, TY) and ns
su_l:   lda PX,y                   ; (BX, BY), BCL counting the bottom ones
        sta TX+1,x                 ; past YGND
        lda PY,y
        sta TY+1,x
        lda PX+16,y
        sta BX+1,x
        lda PY+16,y
        sta BY+1,x
        cmp #YGND+1
        bcc :+
        inc BCL
:       iny
        inx
        cpx #NX
        bne su_l
        lda tmp                    ; boxes 1 .. NX-1: CLE, CLO + 16 (ns - 1) +
        clc                        ; ldCLE + b - 1
        adc ldCLE
        tay
        ldx #0
:       lda CLE,y
        sta CE+1,x
        lda CLO,y
        sta CO+1,x
        iny
        inx
        cpx #NX-1
        bne :-
        jmp su_m
ldCLE:  .byte 0                    ; pcol5's: 16 * its window offset, added to
                                   ; su_l7's CLE, CLO index (data, in the code)
su_qc:    inc BCL                  ; a bottom point past YGND
        bcs su_qb                  ; (always: C from the cmp)
        ; strip 0: row 0 as its bottom row (it is traced only: its TX, TY,
        ; CE and CO are never read: 1 .. NX and 1 .. NX-1 are left as they
        ; are; su_m still sets the margins')
su_r:     tay                      ; Y: the row's offset in PX, PY
        ldx #1
su_q:     lda PX,y                 ; points 1 .. NX: the row's
        sta BX,x
        lda PY,y
        sta BY,x
        cmp #YGND+1
        bcs su_qc
su_qb:    iny
        inx
        cpx #NX+1
        bcc su_q
        bcs su_m                   ; (always)
su_m4:
su_m:
        ; the margins: the byte boundaries MARGIN or more beyond the bottom
        ; row's ends (MARGIN 0: nothing is assembled for it)
        lda BX+1
        .if MARGIN
        sec
        sbc #MARGIN
        .endif
        and #$FC
        sta xl
        sta TX
        sta BX
        ldx #NX
        lda BX,x
        clc
        adc #MARGIN+3              ; (no carry: the row within XL .. XR)
        and #$FC
        sta xr
        sta TX+1,x
        sta BX+1,x
        lda TY,x                   ; the margin points level with the end
        sta TY+1,x                 ; points
        lda BY,x
        sta BY+1,x
        lda TY+1
        sta TY
        lda BY+1
        sta BY
        ; boxes 0 and NX (the margins') black; 1 .. NX-1 the strip's
        lda #0
        sta CE
        sta CO
        sta CE,x
        sta CO,x
su_bot:   jmp traceb               ; the bottom row's line (its RTS returns to
                                   ; strips)

; traceb: the bottom row (BX, BY 0 .. NX+1) into (bota), one line a pixel,
; segment by segment as points.py's bresenham_ys (trace: a segment's first
; pixel overwrites the one before's last).  Preconditions: x non-decreasing
; along the row; a segment of no width (dx = 0) leaves its second point's y.
; The row is widened to the next strip's margins (this row is its top row,
; and its margin points are level with the end points): from min(xl, the
; next strip's xl) to max(xr, the next's xr).
; A level run of pixels is "pending" from tcnt at line tyv until something
; ends it; the fills (TBLK4, TBLK5: STA ROWx-k,X for k = TNB .. 1 then JMP
; t_back, entered n stores before the end at TENL, TENH4 or TENH5 + n) store
; it over tcnt .. X-1 in one go, a run of more than TNB pixels by a loop
; (t_flo).  A shallow segment (|dy| < dx) is drawn as its runs: y steps at x0
; + ceil(dx (2k - 1) / 2|dy|), k = 1 .. |dy|, so after the first run each is
; q2 or q2 + 1 long (q2, r2 = dx div |dy|, 2 (dx mod |dy|), from DQT and
; DRT: |dy| < 32 and dx < 64), the longer when E += r2 carries (E = 255 - e,
; e how far the next step is short of a pixel, in 2|dy|ths).  Otherwise (dx
; >= 64 or |dy| >= 32, still shallow) t_old steps a pixel at a time with the
; error in Y biased by 256 - 2dx, a carry marking a step (needs 2dx <= 256);
; a steep segment (|dy| >= dx > 0; rare: the rows are meant to be shallow)
; takes t_steep's general loop.
; In: BX, BY, ns, nr, PX (row ns+1), bota, xl.  Out: (bota) over
; the widened row.  Clobbers A, X, Y, tyv, tj, terr, dva, ra2, rq, rq2,
; rrem, fe, tcnt, tx1, tyy, tdx2, tdy2; patches jvb, tf_h, t1_h, tx_h, tv_h0,
; t_end, t_inc, t_dq, t_dr, t_rr, tf_j, t1_j, tx_j, jv0, t_bq, tr_k and
; tr_inc.  Entered by setup's JMP; its RTS (t_fr's) returns to strips.
traceb: lda bota+1                 ; the row's page: jvb's store, and the
        sta jvb+2                  ; fills' entry tables for it (TEN4L, TEN4H
        and #1                     ; for ROWA, TEN5L, TEN5H for ROWB) into the
        tay                        ; four sites' operands
        lda tenl,y
        sta tv_l+1
        sta tx_l+1
        lda tenl+2,y
        sta tv_l+2
        sta tx_l+2
        lda tenl+4,y
        sta tf_l+1
        sta t1_l+1
        lda tenl+6,y
        sta tf_l+2
        sta t1_l+2
        lda tenh,y
        sta tv_h0+1
        sta tx_h+1
        lda tenh+2,y
        sta tv_h0+2
        sta tx_h+2
        lda tenh+4,y
        sta tf_h+1
        sta t1_h+1
        lda tenh+6,y
        sta tf_h+2
        sta t1_h+2
        ldx #NX+1                  ; the end: xr + 1 (t_end's operand), or the
        ldy BX,x                   ; next strip's xr + 1 if further right
        iny
        sty t_end+1
        lda BX                     ; the start: xl, or the next strip's xl if
        sta tcnt                   ; further left
        ldy ns
        iny
        cpy nr
        bcs @t0                    ; (the near strip: no row below)
        tya
        asl a                      ; 16 (ns + 1): row ns+1 in PX
        asl a
        asl a
        asl a
        tay
        lda PX,y                   ; its xl: its first point's byte boundary
        and #$FC                   ; (setup's, MARGIN 0)
        cmp tcnt
        bcs :+
        sta tcnt
:       tya
        clc
        adc #NX
        tay
        lda PX-1,y                 ; its last point (index NX - 1), and its xr
        adc #3                     ; (C clear)
        and #$FC
        cmp t_end+1
        bcc @t0
        adc #0                     ; (C set: + 1)
        sta t_end+1
@t0:    lda BCL                    ; every point past YGND: the row one run
        cmp #NX                    ; at YGND+1 (as traced and clamped; bclip
        beq t_all                  ; then leaves it)
        lda BY                     ; the pending run: from tcnt at point 0's y
        sta tyv
        ldx #0
        beq t_seg
t_all:  lda #YGND+1
        sta tyv
        bne t_end                  ; (always)
t_end:  ldx #0                     ; (operand: the end + 1) the row's end: the
        jmp t_fl                   ; pending run to it, then t_fr's RTS returns
                                   ; to strips
t_stj:  jmp t_steep                ; (trampolines within reach of t_seg's
t_o:    jsr t_fl0                  ; branches) t_o: the pending run to x0, then
        jmp t_old                  ; a pixel at a time
t_dx0:  jsr t_fl0                  ; dx = 0, y differs: the pending run ends at
                                   ; x0
        ldx tj
        lda BX,x                   ; the new run: from x0 at y1
        sta tcnt
        lda BY+1,x
        sta tyv
t_next: ldx tj
t_nx:   inx                        ; (X = tj on every way here)
        cpx #NX+1
        bcs t_end
t_seg:  lda BY+1,x                 ; segment X: (BX, BY) to (BX+1, BY+1); tyv
        cmp tyv                    ; = BY,x on every way here
        beq t_nx                   ; (level: the pending run goes on)
        stx tj
        lda BX+1,x
        sec
        sbc BX,x
        beq t_dx0
        sta terr                   ; dx
        lda BY+1,x
        sbc tyv                    ; dy (C set: dx > 0)
        ldy #$E6                   ; the step: INC zp (falling, dy > 0) or DEC
        bcs :+                     ; zp (rising), t_inc's opcode
        eor #$FF                   ; |dy|
        adc #1                     ; (C clear: + 1)
        ldy #$C6
:       cmp terr
        bcs t_stj                  ; |dy| >= dx: steep
        sty t_inc
        sta dva                    ; |dy|: the steps
        tay
        cmp #1
        beq t_one                  ; (|dy| 1: one step, at x0 + ceil(dx / 2))
        asl a
        bcs t_o                    ; (|dy| >= 128: 2|dy| past a byte)
        sta ra2                    ; 2|dy|
        sty dvx                    ; q2, r2 = dx div |dy|, 2 (dx mod |dy|)
        lda terr
        sta dvd
        jsr div8
        asl a
        sta t_rr+1                 ; r2: t_rr's operand
        lda dvd                    ; q2 (past TNB: beyond the fills, a pixel
        cmp #TNB+1                 ; at a time)
        bcc :+
        jmp t_o
:       sta rq2                    ; q = q2 >> 1 = dx div 2|dy| (C: q2 odd)
        lsr a
        sta rq
        lda t_rr+1                 ; rem = dx mod 2|dy| = r2 / 2, + |dy| if q2
        bcc :+                     ; is odd (C set: (r2 + 2|dy| + 1) / 2)
        adc ra2
:       lsr a                      ; rem (C clear if rem = 0)
        beq :+                     ; E = 255 - e: rem - 2|dy| - 1, or $FF for
        sec                        ; rem 0 (e = 0)
        sbc ra2                    ; (C clear after: rem < 2|dy|)
:       sbc #0                     ; (C after: rem > 0)
        sta rrem
        lda rq                     ; the first step at x0 + q + (rem > 0): the
        adc #0                     ; pending run extends to it
        adc BX,x                   ; (C clear: q + 1 does not carry)
        tax
        ldy rq2                    ; jv0: the fill q2 stores before its end,
tv_l:   lda TEN4L,y                ; for the runs after the first
        sta jv0+1
tv_h0:  lda TEN4H,y                ; (operand: the row's table)
        sta jv0+2
        txa                        ; the pending run's length - 1 (C clear: X
        sbc tcnt                   ; > tcnt)
        tay
        cpy #TNB
        bcs t_fl1                  ; (more than TNB: the loop)
tf_l:   lda TEN4L+1,y              ; tf_j: the fill, length Y + 1
        sta tf_j+1
tf_h:   lda TEN4H+1,y              ; (operand: the row's table)
        sta tf_j+2
        clc                        ; (t_back's ADC)
        ldy dva                    ; Y: the steps left, this one included
        lda tyv
tf_j:   jmp t_back                 ; (operand: the fill, which jumps to t_back)
t_fl1:  ldy dva                    ; the first run longer than TNB: the loop,
        jmp t_flo                  ; then t_back
t_one:  lda terr                   ; |dy| 1: the pending run to x0 + ceil(dx /
        lsr a                      ; 2) (C: dx odd)
        adc BX,x
        tax
        sbc tcnt                   ; length - 1 (C clear: X > tcnt)
        tay
        cpy #TNB
        bcs t_fl1                  ; (more than TNB: the loop)
t1_l:   lda TEN4L+1,y              ; t1_j: the fill, length Y + 1
        sta t1_j+1
t1_h:   lda TEN4H+1,y              ; (operand: the row's table)
        sta t1_j+2
        ldy #1                     ; one step: t_back steps y and ends at
        lda tyv                    ; t_last
t1_j:   jmp t_back                 ; (operand: the fill)
t_fr:   lda #<(t_last-t_bq-2)      ; t_fl's end: t_bq back to BEQ t_last; the
        sta t_bq+1                 ; RTS is t_fl's (from t_end, traceb's)
        rts
t_last: stx tcnt                   ; the last step made: the run from X at y1
        jmp t_next                 ; is pending
t_fl0:  lda tyv                    ; the pending run to x0 (not included), tyv
        pha                        ; kept (t_fl steps it); X = tj after, tx1 =
        ldx tj                     ; x1 (t_old's, t_steep's)
        lda BX,x
        tax
        jsr t_fl
        pla
        sta tyv
        ldx tj
        lda BX+1,x
        sta tx1
        rts
t_fl:   lda #<(t_fr-t_bq-2)        ; the pending run to X (not included) as a
        sta t_bq+1                 ; subroutine: t_bq patched to BEQ t_fr and Y
        txa                        ; = 1, so t_back's DEY ends at t_fr, whose
        sec                        ; RTS returns here (tyv stepped once)
        sbc tcnt                   ; the length
        tay
        cpy #TNB+1
        bcs t_flf                  ; (more than TNB: the loop)
tx_l:   lda TEN4L,y                ; tx_j: the fill, length Y
        sta tx_j+1
tx_h:   lda TEN4H,y                ; (operand: the row's table)
        sta tx_j+2
        ldy #1
        lda tyv
tx_j:   jmp t_back                 ; (operand: the fill)
t_flf:  ldy #1                     ; (Y: t_back's count)
t_flo:  stx fe                     ; a run longer than TNB: tyv over tcnt ..
        sty tdx2                   ; X-1 by this loop (Y, the count, kept in
        ldy tcnt                   ; tdx2), then t_back as from a fill
        lda tyv
:       sta (bota),y
        iny
        cpy fe
        bne :-
        ldy tdx2
        jmp t_fx
t_fx:   ldx fe
        clc                        ; (t_back's ADC)
t_back:                            ; the fills' JMP target (init plants it): X
t_inc:  inc tyv                    ; the run's end, Y the steps left, C clear.
        dey                        ; y steps (INC or DEC: t_seg's opcode)
t_bq:   beq t_last                 ; (or BEQ t_fr: t_fl's patch)
        lda rrem                   ; the next run: q2 long, or q2 + 1 if E + r2
t_rr:   adc #0                     ; carries (operand: r2); E then 255 - e again
        bcs :+
        sta rrem
        txa
        adc rq2                    ; (C clear after: X < 256)
        tax
        lda tyv
jv0:    jmp t_back                 ; (operand: the fill, q2 stores)
        .assert <(jv0+1) <> $FF, error, "JMP (jv0+1): the vector must not end a page (6502 indirect JMP)"
:       sbc ra2                    ; E + r2 - 2|dy| (C set in, clear after: A <
        sta rrem                   ; r2 < 2|dy|)
        lda tyv                    ; q2 + 1: the run's first pixel stored here,
jvb:    sta ROWB,x                 ; (operand: the row's page) then the fill's
        txa                        ; q2
        sec
        adc rq2
        tax
        lda tyv
        jmp (jv0+1)                ; (jv0's target)
t_old:  lda t_inc                  ; dx >= 64 or |dy| >= 32, shallow: a pixel
        sta tr_inc                 ; at a time (tr_l), the step as t_inc's
        lda terr
        asl a
        sta tdx2                   ; 2dx
        ldy BX,x
        lda tyv
        sta (bota),y               ; pixel x0 at y0
        lda dva
        asl a
        sta tdy2                   ; 2|dy|
        lda #0                     ; tr_k's operand: 255 - 2dx, so that after a
        sec                        ; carry (Y + 2|dy| >= 256) its ADC with C
        sbc tdx2                   ; set takes 2dx off and rebiases
        sec
        sbc #1
        sta tr_k+1
        lda terr                   ; Y: the error dx, biased by 256 - 2dx
        clc
        adc tr_k+1
        adc #1
        tay
        lda BX,x
        tax
        clc
        jsr tr_l                   ; pixels x0+1 .. x1
t_ox:   ldx tj                     ; the pending run: from x1 at y1
        lda BY+1,x
        sta tyv
        lda tx1
        sta tcnt
        jmp t_next
t_steep: sty tr_inc                ; |dy| >= dx > 0 (rare): bresenham_ys as
        asl a                      ; written, y stepping while err >= 2dx; the
        sta tdy2                   ; step as tg_inc (tr_inc's opcode); 2|dy|
        jsr t_fl0                  ; (the pending run to x0; X = tj)
        lda terr
        asl a
        sta tdx2                   ; 2dx
        ldy BX,x
        lda tyv
        sta (bota),y               ; pixel x0 at y0
        sta tyy
        lda BX,x
        tax
t_gl:    inx                       ; pixel X: err += 2|dy|, then y steps while
        lda terr                   ; err >= 2dx
        clc
        adc tdy2
:       cmp tdx2
        bcc :+
        sbc tdx2                   ; (C set)
        pha
        jsr tg_inc
        pla
        jmp :-
:       sta terr
        txa
        tay
        lda tyy
        sta (bota),y
        cpx tx1
        bne t_gl
        beq t_ox
tg_inc: lda tr_inc                 ; tyy + 1 (tr_inc INC zp) or - 1 (DEC)
        cmp #$E6
        bne :+
        inc tyy
        rts
:       dec tyy
        rts


; divs: rungs' division.  In: dva = a, ra2 = 2a (a <= 127), dvd = D.  Out: rq,
; rrem = D div 2a, D mod 2a (div8); rq2, rr2 = D div a, 2 (D mod a) (dv2, from
; them).  Clobbers A, Y, dvx, dvd.  Called by rg_rsl, rg_lsl.
divs:   lda ra2
        sta dvx
        jsr div8
        sta rrem
        lda dvd
        sta rq
        lda rrem
; dv2: rq2, rr2 from rq, rem (A): 2D = 2q (2a) + 2 rem, so q2, r2 = 2q, 2 rem,
; or 2q + 1, 2 rem - 2a if rem >= a.
dv2:    asl a
        sta rr2
        lda rq
        asl a
        sta rq2
        lda rrem
        cmp dva
        bcc :+
        inc rq2
        lda rr2
        sbc ra2                    ; (C set: rem >= a)
        sta rr2
:       rts
; div8: dvd = dvd div dvx, A = dvd mod dvx (8-bit, dvx not 0), by shifts and
; subtractions.  X kept; clobbers Y.
div8:   lda #0
        ldy #8
@l:     asl dvd
        rol a
        bcs @s                     ; (the remainder past 255: dvx > 127)
        cmp dvx
        bcc :+
@s:     sbc dvx
        inc dvd
:       dey
        bne @l
        rts

; tr_l: t_old's pixels X+1 .. tx1, one y each, the error in Y biased so that
; a carry out of Y + 2|dy| is a step (tr_s: Y rebiased by tr_k, y stepped by
; tr_inc).  In: X = x0, Y = the biased error, C clear, tyv = y0, tx1 = x1,
; tdy2 = 2|dy|, tr_k and tr_inc patched.  Out: tyv = y1.  Clobbers A, X, Y,
; tyy.  Called by t_old.
tr_l:   inx
        tya
        adc tdy2                   ; (C clear in: the clc, or the cpx below)
        tay
        bcs tr_s
tr_y:   sty tyy                    ; pixel X at tyv
        txa
        tay
        lda tyv
        sta (bota),y
        ldy tyy
        cpx tx1
        bne tr_l
        rts
tr_s:   tya                        ; a step: 2dx off (ADC 255 - 2dx, C set),
tr_k:   adc #0                     ; y +- 1
        tay
tr_inc: inc tyv                    ; (INC or DEC: t_old's, t_steep's opcode)
        jmp tr_y

; ---------------------------------------------------------------- rungs
; rungs: each rung's pixels and transitions, for the columns.  Rung i (point
; i of the top row (xt, yt) to point i of the bottom row (xb, yb); D = yb -
; yt, a = |xb - xt|) crosses pixels LO .. HI-1 (xt .. xb-1 leaning right, xb
; .. xt-1 left; LO = HI = x upright: none); its j'th pixel from xt (xt + j -
; 1 leaning right, xt - j left; j = 1 .. a) changes box at line yt + ceil(D
; (2j - 1) / 2a) (ragged.transitions: Bresenham stepping in y).  The lines
; are kept in RTBUF's page: rung i's a + 1 bytes from alloc, pixel x's at
; alloc + x - LO = RTP + x + 1 (RTPL,i: the low byte of alloc - LO - 1; the
; high byte is RTBUF's), then $FF, the sentinel that ends a walk up the
; pixels (leaning right) and, as the byte before the next rung's, one down
; them (leaning left; RTBUF+4 serves the first rung).  The margins (rungs 0
; and NX+1): LO = HI = xl, xr, no bytes.  All the rungs' bytes must fit the
; page (alloc is stepped as a byte); a reader of RTP + x + 1 for a rung in a
; column goes no lower than alloc - 3, so from RTBUF+5 the low byte never
; wraps below.  A rung with a <= RFA and D < 16 is filled from tables
; (rfastr, rfastl: bank 4); else q, rem = D div 2a, mod and q2, r2 = D div a,
; 2 (D mod a) (RDIV: DQT, DRT for a < 32, D < 64; divs otherwise), the first
; line yt + q + (rem > 0), each next q2 on, or q2 + 1 when E += r2 carries (E
; = 255 - e, e how far the next step is short of a line, in 2a'ths).
; In: TX, TY, BX, BY (0 .. NX+1), xl, xr.  Out: LO, HI (0 .. NX+1),
; RTPL (1 .. NX), RTBUF, alloc, rtp+1 = RTBUF's page.  Clobbers A, X, Y, tj,
; dva, dvd, ra2, rq, rq2, rrem, rr2.  Called by strips (strips 1 .. nr-1).
; RSET: from A = e and C = (rem > 0) (RDIV's, or rg_rsl's from divs): E =
; 255 - e into rrem, 255 - 2a into dvd (a carry's ADC takes 2a off E), A =
; the first pixel's line yt + q + (rem > 0), rq = q2 + 1 (the longer step;
; rq2 the shorter).  C clear after when D is yb - yt unwrapped (the line is
; at most yb).
.macro RSET
        eor #$FF
        sta rrem
        lda ra2
        eor #$FF
        sta dvd
        lda TY,x                   ; (C: rem > 0)
        adc rq
        ldy rq2
        iny
        sty rq
.endmacro
rungs:  lda xl                     ; the margins: upright, no pixels
        sta LO
        sta HI
        ldx #NX+1
        lda xr
        sta LO,x
        sta HI,x
        lda #$FF                   ; the sentinel before the first rung's bytes
        sta RTBUF+4                ; (a walk down a left-leaning rung's pixels
        lda #<(RTBUF+5)            ; ends on it); the bytes from RTBUF+5
        sta alloc
        lda #>RTBUF
        sta alloc+1
        sta rtp+1                  ; (rtp's page: split's, mktr's)
        ldx #1
rg_r:     stx tj                   ; rung X
        lda BX,x
        cmp TX,x
        bne :+
        sta LO,x                   ; upright: no pixels, a sentinel only (a
        sta HI,x                   ; walk from it reads the $FF at once)
        eor #$FF                   ; RTPL = alloc - LO - 1
        clc
        adc alloc
        sta RTPL,x
        ldy #0                     ; a = 0
        sty dva
        jmp rg_nr
rg_rsl:   jsr divs                 ; leaning right, a >= 32 or D >= 64: divs,
        lda rrem                   ; then A = e (2a - rem, or 0), C = (rem >
        beq rg_rz                  ; 0), as RDIV leaves them
        lda ra2
        sec
        sbc rrem
rg_rz:    cmp #1
        jmp rg_rst
:       bcc rg_lft                 ; xb < xt: leaning left
        sta HI,x                   ; leaning right: pixels xt .. xb-1
        sbc TX,x                   ; a = xb - xt (C set: xb > xt)
        sta dva
        lda TX,x
        sta LO,x
        eor #$FF                   ; RTPL = alloc - LO - 1
        clc
        adc alloc
        sta RTPL,x
        jsr rg_d                   ; ra2 = 2a, dvd = D
        jmp rg_rsl
rg_lft:   sta LO,x
        eor #$FF                   ; leaning left: pixels xb .. xt-1; RTPL =
        adc alloc                  ; alloc - LO - 1 (C clear: the bcc)
        sta RTPL,x
        sec
        lda TX,x
        sta HI,x
        sbc BX,x                   ; a = xt - xb
        sta dva
        jsr rg_d
        jmp rg_lsl
; rg_d: ra2 = 2a (dva), dvd = D = yb - yt.  X kept.
rg_d:   lda dva
        asl a
        sta ra2
        lda BY,x
        sec
        sbc TY,x
        sta dvd
        rts
rg_rst:   RSET                     ; (A: the first line; C clear)
        ldy #0                     ; leaning right: pixel xt's at Y = 0 (x -
        sta (alloc),y              ; LO), then up to Y = a - 1
        iny
        cpy dva
        beq rg_nr
rg_rs:    tax                      ; X: the line.  E += r2 (C clear: the cpy):
        lda rrem                   ; no carry, the next line q2 on
        adc rr2
        bcs :+
        sta rrem
        txa
        adc rq2
        sta (alloc),y
        iny
        cpy dva
        bne rg_rs
        beq rg_nr
:       adc dvd                    ; a carry: E + r2 - 2a (C set in, clear
        sta rrem                   ; after), the next line q2 + 1 on
        txa
        adc rq
        sta (alloc),y
        iny
        cpy dva
        bne rg_rs
rg_nr:    lda #$FF                 ; the sentinel at Y = a; alloc += a + 1 (the
        sta (alloc),y              ; low byte: within RTBUF's page)
        tya
        sec
        adc alloc
        sta alloc
rg_nx:    ldx tj                   ; the next rung, to NX
        inx
        cpx #NX+1
        bcs :+
        jmp rg_r
:       rts
rg_ld:    ldy dva                  ; (Y = a: the sentinel's)
        jmp rg_nr
rg_lsl:   jsr divs                 ; leaning left, a >= 32 or D >= 64 (so also
        lda rrem                   ; yb < yt, D wrapped): divs, then A = e, C =
        beq :+                     ; (rem > 0), as rg_rsl
        lda ra2
        sec
        sbc rrem
:       cmp #1
        RSET
        ldy dva                    ; as rg_lst, but C cleared each pixel: a
        dey                        ; line sum passing 255 (D wrapped) must not
        sta (alloc),y              ; carry into E
        beq rg_ld
rg_lw:    tax
        clc
        lda rrem
        adc rr2
        bcs :+
        sta rrem
        txa
        adc rq2
        dey
        sta (alloc),y
        bne rg_lw
        beq rg_ld
:       adc dvd
        sta rrem
        txa
        adc rq
        dey
        sta (alloc),y
        bne rg_lw
        beq rg_ld

; The column filler's patched jumps and chains rely on pairs of labels sharing
; a page (the .asserts below: record/o_nr, the run2 pages, the fsplit walker
; ...).  LAYPAD puts the code from here on at the page phase that satisfies
; them all (the smallest value that links); change it when code before this
; point grows or shrinks.
LAYPAD  = 0
        .res LAYPAD

; ---------------------------------------------------------------- columns
; cols: draw a land strip's byte columns, xl/4 .. xr/4-1, left to right.  A
; column runs from its top row's highest line (mn) down to the line before its
; floor (its bottom row's lowest line, whose pixels are the strip below's; flr1,
; the run's end, is the floor, or the floor + 1 in the near strip when the floor
; is not level there, flr then the floor: nearpost blacks the floor line's
; ground), and is drawn as one of:
;   - one box (no rung in it: c_lo's test fails, at c_lo or in c_rix): the
;     top zone when the top is not level (zone1: lines mn .. mx-1, the pixels
;     at or below their top-row line), then run2 from mx (c_r1);
;   - one rung in it (c_sp): fsplit (top level) or split (not), or c_ld's one
;     box when the rung's two boxes have the same bytes;
;   - two rungs (c_dbl): s2v (bank 4; top level) or split2; three: slow.
; A column the land has not covered yet this frame (phase: left of xlp or from
; xrp on; strip 1: every column) is recorded first (record, recordc: CURT, and
; black from the land's highest line last time on this screen, TOPS, down to
; mx-1); in the near strip every column ends at nearpost (black below, CURB).
; In: ns, last, xl, xr, xlp, xrp; topa, bota (the rows' lines by pixel);
; TX, BX, LO, HI, RTPL, CE, CO (setup's, rungs'); sh_b's operand (setback's).
; Out: the strip drawn; CURT, CURB where recorded; lastri; the operands below
; patched; flr 0.  Clobbers A, X, Y and the column variables (x4, coff, scrh,
; ri, mn, mx, flr1, ys, msk, ve, vo, zp_, bpos, ...).  Called by strips (@draw)
; for ns = 1 .. nr-1.  Bank 4 is paged throughout (the tables, s2v, slow).
cols:   lda #$FF                   ; fsplit's tables are no rung's yet
        sta lastri
        lda topa+1                 ; the top row's page into every ROWA,y
        sta pt0+2
        sta pt1+2
        sta pt2+2
        sta pt3+2
        sta zt1+2
        sta zt2+2
        sta zt3+2
        sta ot0+2
        sta ot3+2
        sta oz1+2
        sta oz2+2
        sta oz3a+2
        sta oz3b+2
        sta oz1b+2
        sta oz2b+2
        lda bota+1                 ; the bottom row's into every ROWB,y
        sta ob0+2
        sta ob3+2
        sta obz+2
        sta pb0+2
        sta pb1+2
        sta pb2+2
        sta pb3+2
        sta zb1+2                  ; (zb1, zb2, zb3: a CMP, then its LDA 5 on)
        sta zb1+7
        sta zb2+2
        sta zb2+7
        sta zb3+2
        sta zb3+7
        ldx #0                     ; the strip's kind, X: 0 a strip above the
        bit last                   ; near one; 1 the near strip (last $FF)
        bpl @kind
        inx
@kind:   cpx #$FF                   ; operand: the kind patched last ($FF: none
        beq @kd                   ; yet); patched only when it changes
        stx @kind+1
        lda zbt0,x                 ; ob_st, zb_st (a floor not level; 2 bytes):
        sta ob_st                  ; 0 STA flr1 (the run ends at the floor); 1
        sta zb_st                  ; BNE ob_n, zb_n (flr + 1: nearpost draws
        lda zbt1,x                 ; the floor), 3 on from each
        sta ob_st+1
        sta zb_st+1
        lda npt0,x                 ; c_np (3 bytes; the column done): 0 LDA x4
        sta c_np                   ; / CLC, on into c_nd1; 1 JMP nearpost
        lda npt1,x
        sta c_np+1
        lda npt2,x
        sta c_np+2
        lda #0                     ; flr: 0 until a near-strip floor is not
        sta flr                    ; level (o_zb, c_zb; nearpost puts it back)
@kd:
        lda xlp                    ; phase's bounds: record below xlp (strip 1:
        ldx ns                     ; below xr, so everywhere), not from there to
        dex                        ; xrp, record from xrp on
        bne :+
        lda xr
:       sta ph_lo+1
        lda xrp
        sta ph_hi+1
        ldx #0                     ; rung 0 (the left margin's, upright at xl):
        stx ri                     ; c_lo, c_hi its; the first column's c_rix
        jsr rpatch                 ; moves on from it
        lda xl
        sta x4
        jsr phase                  ; (A kept)
        asl a                      ; coff = 8 * column mod 256; C: x4 >= 128,
        sta coff                   ; the right half
        lda #0
        rol a
        jsr sethalf
        ldy x4
        jmp c_coly

; phase: the columns from x4 (A, kept) up to the next of xlp, xrp and xr form
; a phase: ph_e is its end and c_xe's operand the end, or 128 when the phase
; would cross from the left half into the right (the half switches at 128,
; c_lim's and c_nh's), and the record choice is patched for it: c_rec JMP
; recordc or c_srx, o_rec and ob_rj JMP record or o_nr (low bytes only: record
; and o_nr share a page).  In: A = x4; ph_lo and ph_hi's operands (cols').
; Clobbers X, Y.  Called by cols, c_lim and c_nh.
phase:
ph_lo:  cmp #0                     ; operand: xlp (strip 1: xr), cols'
        bcs ph_h
        ldx ph_lo+1                ; x4 < xlp: recorded, to xlp
        bcc ph_rec
ph_h:
ph_hi:  cmp #0                     ; operand: xrp, cols'
        bcs ph_x
        ldx ph_hi+1                ; xlp <= x4 < xrp: not recorded, to xrp (at
        cpx xr                     ; most xr)
        bcc ph_n
        ldx xr
ph_n:   ldy #<o_nr
        sty o_rec+1
        sty ob_rj+1
        ldy #>o_nr
        sty o_rec+2
        sty ob_rj+2
        ldy #<c_srx
        sty c_rec+1
        ldy #>c_srx
        sty c_rec+2
        jmp ph_en
ph_x:   ldx xr                     ; x4 >= xrp: recorded, to xr
ph_rec: cpx xr                     ; (at most xr)
        bcc ph_r
        ldx xr
ph_r:   ldy #<record
        sty o_rec+1
        sty ob_rj+1
        ldy #>record
        sty o_rec+2
        sty ob_rj+2
        ldy #<recordc
        sty c_rec+1
        ldy #>recordc
        sty c_rec+2
ph_en:  stx ph_e                   ; the end (X); c_xe's operand at most 128
        cpx #129                   ; when x4 is in the left half
        bcc :+
        cmp #128
        bcs :+
        ldx #128
:       stx c_xe+1
        rts
ph_e:   .byte 0                    ; the phase's end (data, in the code)
; c_nh: x4 is 128, an end from the left half (c_lim's): the right half starts
; (sethalf, A = 1), then the phase goes on to its own end (ph_e), or, when
; that is 128, the next phase (phase).  Out to c_xt with A = x4.
c_nh:   lda #1
        jsr sethalf
        ldx ph_e
        cpx #129
        lda #128                   ; (x4 again)
        bcc :+
        stx c_xe+1
        jmp c_xt
:       jsr phase
        jmp c_xt

; c_dbl: from c_split, rung ri+1 starts in the column too (A = x4 | 3 >= its
; LO).  Two rungs: s2v (bank 4) when the top is level (V clear, c_coly's), else
; split2.  Three or more (rung ri+2's LO <= x4 + 3 as well): slow, which reads
; mn and ys (made mx here when the top is level).  Back to c_next.
c_dbl:  bvs :+                     ; a level top: mn and each pixel's top
        tay                        ; are mx (A, C kept)
        lda mx
        sta mn
        sta ys
        sta ys+1
        sta ys+2
        sta ys+3
        tya
:       cmp LO+2,x                 ; rung ri+2 in the column too: slow
        bcs c_d3
        jsr split2
        jmp c_next
c_d3:   jsr slow
        jmp c_next

; record: a one-box column the land covers for the first time this frame
; (o_rec's and ob_rj's target in a recording phase; recordc is c_rec's).
; CURT[x4/4] = the column's highest line (mn when the top is not level, V set;
; else mx).  Then, if the land's highest line last time on this screen (TOPS)
; is above mx, black from it down to mx-1 (rc_t): the lines above mx are not
; covered by the strip above here, and the strip's own top zone (mn .. mx-1)
; is drawn over them after.  In: Y = x4, V, mn, mx, ri.  Out: on to o_nr (one
; box), or, after the black, to c_rd's tests, which find the column one box
; again; Y = x4 and V kept.  pT3, pT5: strips' operands (CURT, TOPS by set).
record: tya                        ; the column, x4 / 4
        lsr a
        lsr a
        tax
        lda mx
        bvc :+                     ; V set: the top not level, its highest mn
        lda mn
:
pT3:    sta CURT,x                 ; (strips: this frame's set)
pT5:    lda TOPS,x                 ; (strips: this screen's set)
        cmp mx
        bcs o_nr                   ; nothing above to black: one box
        bcc rc_t

; c_ri: from c_rd with A = Y = x4, X = ri: rung ri is wholly left of the column
; (HI <= x4), so ri moves on to the first rung with HI > x4 (rpv: its RVE, RVO,
; c_lo, c_hi), then c_rr's test.  Not reached: c_coly's c_rix has advanced ri
; past every rung with HI <= x4 before record or recordc runs, and nothing
; brings it back; c_rd's test is for form.
c_ri:   inx
        cmp HI,x
        bcs c_ri
        stx ri
        jsr rpv
        tya
        jmp c_rr
c_v1:   .byte $40                  ; BIT c_v1: V set (bit 6), N clear

; c_ld: rung ri's two boxes have the same bytes (fs_s1's and split's finding),
; so the column is one box: RVE, RVO = box ri-1's; its run (c_r1) if the top is
; level, else the top zone first (zone1, back to c_r1x).  In: X = ri, V.
c_ld:   lda CE-1,x
        sta RVE
        lda CO-1,x
        sta RVO
        bvc c_r1
c_z1:    jmp zone1                 ; (c_on's too)

; c_srx: c_rec's target in a phase without recording, and recordc's way on:
; to c_split.  In: Y = x4, ri.
c_srx:  ldx ri
        tya
        ora #3
; c_split: rung ri is in the column (from c_sp by way of c_rec, or c_rr).
; A = x4 | 3, X = ri, V set if the top is not level.  Rung ri+1 in it too (its
; LO <= x4 + 3): c_dbl.  Else split (V set), or fsplit: straight to fs_c when
; its tables are already rung ri's (lastri), else fs_ns builds them.
c_split: cmp LO+1,x
        bcs c_dbl
        bvs :+
fsplit: cpx lastri                 ; (equal: C set, fs_c's)
        beq :++
        jmp fs_ns
:       jmp split
:       jmp fs_c

; rc_t: record's and recordc's black above: lines TOPS (A, < mx) .. mx-1, one
; line here (rc_h) or a run; then c_rd.  V is kept throughout (run's STAB code
; is STA, LDA, TXA, RTS).
rc_t:   tax
        inx
        cpx mx
        bne rc_r
        dex                        ; one line, TOPS = mx - 1
rc_h:   php                        ; the line's page: LAH + scrh (V kept:
        lda LAH,x                  ; the ADC would clear it)
        clc
        adc scrh
        plp
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
        ldy x4
        jmp c_rd
rc_r:   dex                        ; lines TOPS .. mx-1, black (V kept: run's
        ldy mx                     ; entry arithmetic would clear it)
        lda #0
        sta ve
        sta vo
        php
        jsr run
        plp
        ldy x4
; c_rd: c_coly's rung tests again, from Y = x4 (V kept): rung ri wholly left
; (c_ri), in the column (c_split), or right of it (one box: o_nr).
c_rd:
        ldx ri
        tya
        cmp HI,x
        bcs c_ri                   ; HI <= x4
c_rr:   ora #3
        cmp LO,x
        bcs c_split                ; LO <= x4 + 3
; o_nr (c_one, c_on): the column is one box, ri-1: the top zone if the top is
; not level (V set: zone1, back to c_r1x with X = mx), then lines mx .. flr1-1
; by run2 with RVE, RVO = box ri-1's bytes (set by c_rix when it finds the
; column one box, by c_ri, and by c_ld; fr and fe_r set them only in a column
; rung ri is in, and a one-box column after one of those is reached through
; c_rix).  Then c_next.
o_nr:
c_one:
c_on:   bvs c_z1
c_r1:    ldx mx
c_r1x:  cpx flr1                   ; (zone1 returns here, X = mx)
        bcs c_next                 ; (no lines)
        ldy flr1
; run2: lines X .. Y-1 (X < Y) of the column: RVE on even lines, RVO on odd,
; through tools/landgen.py's store tables.  For t = 2 back + half, page TPEt
; holds STA line,Y for each even line (3 bytes a line from offset R2OFF, line
; YGND+1's slot at $FF) and page TPOt the odd lines' (line YGND+2's at $FF);
; EINL,y (init's) is the slot of the first even line at or after
; y, EINL-1,y that of the first odd line at or after y.  The even pass is a JSR
; to line X's slot (je), back by an RTS planted over line Y's (pr0 its address:
; the page sethalf's, the offset EINL,y); the odd pass likewise (jo, pr1).  The
; last end's RTSes are put back as STAs first unless Y is the last Y (pY's
; operand); the entries stay while X is the last X (pX's).  The slot at $FF
; is kept like any other: planted when a run ends at YGND+1, put back after.
; In: X, Y, coff; the pages (sethalf's).  Clobbers A, X, Y.  Falls through
; into c_next, so fr, which JSRs here, and s2v, whose fsplit may end through
; here, make c_np an RTS meanwhile.
run2:
        lda RVE                    ; (STAB's run, ve on even lines, vo on odd)
        sta ve
        lda RVO
        sta vo
        jsr run
; c_next: the column is done.  c_np (3 bytes, cols' by kind): LDA x4 / CLC, on
; into c_nd1 for the next column; in the near strip JMP nearpost, which comes
; back to c_nd or c_xe (np_n).  fr (while it JSRs run2) and s2v (while it JSRs
; fsplit) make it an RTS.
c_next:
c_np:   jmp nearpost
c_nd1:  adc #4                     ; (C clear) x4 + 4: the next column
        sta x4
c_xe:   cmp #0                     ; operand: the phase's end, at most 128
                                   ; from the left half (phase's, c_nh's)
        beq c_lim
c_xt:   tay
        asl a                      ; coff = 8 * column mod 256
        sta coff
; c_coly: the column at Y = x4 (coff set).  V is clear here: c_nd1's and np_n's
; ADC can set it only for x4 = 128, which comes through c_lim, c_nh and
; sethalf's CLV.  ri is the first rung not wholly left of the column (its HI > x4,
; c_rix's); rung ri is in the column if its LO <= x4 + 3, i.e. LO & $FC <= x4.
c_coly:
c_lo:   cpy #0                     ; operand: rung ri's LO & $FC (rpatch's)
        bcs c_hi
; One box: no rung ends in the column (rungs before ri at or left of x4, ri on
; right of x4 + 3), so each row is monotonic across it: level if its two end
; pixels are, and otherwise highest and lowest at its ends.
ot0:    lda ROWA,y                 ; the top row's pixels 0 and 3 (page: cols')
ot3:    cmp ROWA+3,y
        bne o_zt
        sta mx                     ; level: mx (mn is mx, V clear)
o_ft:
ob0:    lda ROWB,y                 ; the bottom row's (page: cols')
ob3:    cmp ROWB+3,y
        bne o_zb
        sta flr1                   ; a level floor, A: the run ends at it (as
                                   ; c_lv; flr stays 0: level, nearpost's)
o_rec:  jmp record                 ; (phase's: record or o_nr)
c_lim:  cmp xr                     ; the phase's end: the strip's too?
        beq c_end
        cmp #128                   ; 128 from the left half: the right half
        beq c_nhj                  ; starts
        jsr phase                  ; (A = x4 kept)
        jmp c_xt
c_end:  rts
c_nhj:  jmp c_nh
; o_zt: a one-box column whose top is not level.  C from ot3: p0 > p3, oz_dn
; (mn = p3).  Else mn = p0, mx = p3 and msk the pixels at line mn: pixel 0,
; and 1, 2 while they equal it (the row monotonic).  V set (zone1's and
; record's).  On to the floor.
o_zt:   bcs oz_dt
        sta mn
oz3a:   ldx ROWA+3,y
        stx mx
oz1:    ldx ROWA+1,y
        lda #PM($88)               ; pixel 0
        cpx mn
        bne oz_mu
oz2:    ldx ROWA+2,y
        lda #PM($CC)               ; pixels 0, 1
        cpx mn
        bne oz_mu
        lda #PM($EE)               ; pixels 0, 1, 2
oz_mu:  sta msk
        bit c_v1                   ; V set: the top not level
        bvs o_ft                   ; (always)
oz_dt:  jmp oz_dn
; o_zb: a one-box column whose floor is not level: the lower of p0 (C from ob3:
; p0 > p3) and p3 is flr1 (ob_st: STA flr1, cols' kind 0), or in the near strip
; (BNE ob_n, always taken: TAX's Z, a line not being 0) flr, with flr1 = flr +
; 1, at most YGND+1 (bclip held the row at YGND+1: flr is then YGND); flr not 0
; tells nearpost the floor is not level.
o_zb:   bcs :+
obz:    lda ROWB+3,y
:       tax
ob_st:  sta flr1                   ; (STA flr1 or BNE ob_n: cols', by kind)
ob_rj:  jmp record                 ; (phase's: record or o_nr)
ob_n:   stx flr                    ; the near strip: flr1 = flr + 1, at most
        inx                        ; YGND+1
        cpx #YGND+2
        bcc :+
        dex                        ; flr1 YGND+1, flr YGND
        dec flr
:       stx flr1
        jmp ob_rj
c_hi:   cpy #0                     ; operand: rung ri's HI (rpatch's)
        bcc c_sp                   ; in the column
; c_rix: cols' next rung.  Rung ri is wholly left of the column (x4 >= HI):
; ri advances to the first rung with HI > x4 (rung NX+1, the right margin,
; stops it: HI = xr) and c_lo and c_hi are patched for it (as rpatch); then
; c_lo's test again: rung ri in the column (LO & $FC <= x4), c_sp; else one
; box, the box to its left (ri - 1) becoming run2's bytes (RVE, RVO: a one-box
; column follows a column rung ri is in only through here, and c_ld sets them
; itself), ot0.  In: Y = x4, ri.  Out: ri, X = ri, Y = x4.
c_rix:  ldx ri
        tya
:       inx
        cmp HI,x
        bcs :-
        stx ri
        lda HI,x                   ; c_hi's operand its HI, c_lo's its LO &
        sta c_hi+1                 ; $FC (rpatch, inline)
        lda LO,x
        and #$FC
        sta c_lo+1
        cpy c_lo+1
        bcs c_sp
        lda CE-1,x                 ; one box: box ri - 1's bytes, run2's
        sta RVE
        lda CO-1,x
        sta RVO
        jmp ot0
; c_sp: rung ri is in the column.  The top: level (mx; V clear) or each pixel's
; line into ys with mn, mx and V set (c_zt); the floor: level (c_lv) or its
; lowest (c_zb); then c_rec.
c_sp:
pt0:    lda ROWA,y                 ; (pages: cols')
pt1:    cmp ROWA+1,y
        bne c_zt
pt2:    cmp ROWA+2,y
        bne c_zt2
pt3:    cmp ROWA+3,y
        bne c_zt3
        sta mx
c_ft:
pb0:    lda ROWB,y                 ; (pages: cols')
pb1:    cmp ROWB+1,y
        bne zb1c                   ; (into c_zb after this CMP, C from it)
pb2:    cmp ROWB+2,y
        bne zb2c
pb3:    cmp ROWB+3,y
        bne zb3c
c_lv:   sta flr1                   ; a level floor, A: the run ends at it (the
                                   ; strip below draws line flr1, or nearpost:
                                   ; flr stays 0, level)
c_rec:  jmp recordc                ; (phase's: recordc or c_srx)
; c_zt: the top not level, the first pixel differing from pixel 0 being 1 (A =
; pixel 0's line; c_zt2, c_zt3: pixel 2, 3): ys each pixel's line, mn, mx; V
; set by BIT c_v1, and nothing touches it before c_on's and c_split's tests.
c_zt:    sta ys
        sta mn
        sta mx
        bit c_v1
.macro ZTP n                        ; pixel n's line into ys+n, mn, mx
        lda ROWA+n,y
        sta ys+n
        cmp mn
        bcs :+
        sta mn
        bcc :++
:       cmp mx
        bcc :+
        sta mx
:
.endmacro
zt1:    ZTP 1
zt2:    ZTP 2
zt3:    lda ROWA+3,y               ; (ZTP 3, ending at c_ft)
        sta ys+3
        cmp mn
        bcs :+
        sta mn
        bcc c_ft
:       cmp mx
        bcc c_ft
        sta mx
        jmp c_ft
c_zt2:  sta ys                     ; pixels 0, 1 alike: on at zt2
        sta ys+1
        sta mn
        sta mx
        bit c_v1
        jmp zt2
c_zt3:  sta ys                     ; pixels 0, 1, 2 alike: on at zt3
        sta ys+1
        sta ys+2
        sta mn
        sta mx
        bit c_v1
        jmp zt3

; c_zb: the floor not level: the lowest of the bottom row's four pixels (A the
; first's; entered at zb1c, zb2c or zb3c with C from c_ft's CMP) is flr1 (zb_st:
; STA flr1, cols' kind 0), or in the near strip (BNE zb_n, always taken: TAX's
; Z) flr, with flr1 = flr + 1, at most YGND+1 (bclip's row at YGND+1: flr then
; YGND); flr not 0 tells nearpost the floor is not level.
c_zb:
zb1:    cmp ROWB+1,y               ; (pages: cols', the CMPs' and the LDAs')
zb1c:   bcs :+
        lda ROWB+1,y
:
zb2:    cmp ROWB+2,y
zb2c:   bcs :+
        lda ROWB+2,y
:
zb3:    cmp ROWB+3,y
zb3c:   bcs :+
        lda ROWB+3,y
:       tax
zb_st:  sta flr1                   ; (STA flr1 or BNE zb_n: cols', by kind)
        jmp c_rec
zb_n:   stx flr                    ; the near strip: flr1 = flr + 1, at most
        inx                        ; YGND+1
        cpx #YGND+2
        bcc :+
        dex                        ; flr1 YGND+1, flr YGND
        dec flr
:       stx flr1
        jmp c_rec
; nearpost: the near strip's column after its drawing (c_np's JMP, kind 1):
; black below the near row.  The column is drawn to flr1 - 1: the line before
; the floor when the bottom row is level across the column (c_lv: flr1 the
; floor, flr 0), else the floor itself (c_zb: flr the floor, flr1 = flr + 1).
; Level: line flr1 black.  Not level: from the row's highest pixel down to flr -
; 1, each pixel at or below its own bottom-row line black (read-modify-write,
; np_l); then line flr whole, or masked too when flr is YGND (bclip may have
; held pixels at YGND+1); then flr back to 0 (np_x).  Then CURB = the floor
; (YGND if the row is off the screen) and black from the floor + 1 down to the
; land's lowest line last time on this screen (BOTS): one line here, or a run.
; In: flr, flr1, x4, coff, bota, scrh; pB4, pB5, pB6, pB8 strips' operands
; (CURB, BOTS by set).  Out: CURB; flr 0; on to the next column (c_nd, np_n).
; Clobbers A, X, Y, ys, zp_, ve, vo.
np_b:     pha                      ; CURB = the floor (A), or YGND if it is
        lda x4                     ; YGND+1 (Y: the column)
        lsr a
        lsr a
        tay
        pla
        cmp #YGND+1
        bcc pB4
        lda #YGND
        bcs pB4                    ; (always)
nearpost:
        lda flr
        bne np_z                   ; not level
        lda flr1                   ; level: flr1 the floor
        cmp #YGND+1
        bcs np_b                   ; held at YGND+1: nothing to draw
        tax                        ; line flr1 black
        and #7
        sta zp_
np_h:   lda LAH,x                  ; the line's page: LAH + scrh
        clc
        adc scrh
        sta zp_+1
        ldy coff
        lda #0
        sta (zp_),y
        lda x4                     ; (Y: the column)
        lsr a
        lsr a
        tay
        txa                        ; (flr1, on the screen)
pB4:    sta CURB,y                 ; (strips: this frame's set)
pB5:    cmp BOTS,y                 ; (strips: this screen's set)
        bcs np_n                   ; BOTS at or above the floor: nothing below
        adc #1                     ; (C clear) the floor + 1
        tax
pB6:    cmp BOTS,y
        bne np_r
        lda LAH,x                  ; one line, BOTS = the floor + 1: black
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
        jmp c_nd
np_r:
pB8:    lda BOTS,y                 ; lines the floor + 1 .. BOTS black
        tay
        iny
        lda #0
        sta ve
        sta vo
        jsr run
        jmp c_nd
np_n:   lda x4                     ; the next column: x4 + 4 (C set)
        adc #3
        sta x4
        jmp c_xe                   ; (V: see c_coly)
np_z:     ldy x4                     ; not level: each pixel's bottom-row line
        lda (bota),y
        sta ys
        iny
        lda (bota),y
        sta ys+1
        iny
        lda (bota),y
        sta ys+2
        iny
        lda (bota),y
        sta ys+3
        cmp ys+2                   ; the highest of them, X
        bcc :+
        lda ys+2
:       cmp ys+1
        bcc :+
        lda ys+1
:       cmp ys
        bcc :+
        lda ys
:       tax                        ; (at most flr: equal only when bclip held
        cpx flr                    ; the lower pixels, flr being YGND)
        bcs np_e
np_l:
np_h2:    lda LAH,x                  ; the line's page: LAH + scrh
        clc
        adc scrh
        sta zp_+1                  ; black (page: sethalf's)
        txa
        and #7
        sta zp_
        lda #0                     ; bit i: X >= ys+i (as pmask); MASKN keeps
        cpx ys+3                   ; the others
        rol a
        cpx ys+2
        rol a
        cpx ys+1
        rol a
        cpx ys
        rol a
        tay
        lda MASKN,y
        ldy coff
        and (zp_),y
        sta (zp_),y
        inx
        cpx flr
        bcc np_l
        bne np_x                   ; (X = YGND+1 after np_e's masked line: done)
np_e:   cpx #YGND                  ; X = flr: every pixel at or below its bottom
        beq np_l                   ; unless bclip held some at YGND+1 (flr
np_h3:  lda LAH,x                  ; the line's page: LAH + scrh
        clc
        adc scrh
        sta zp_+1                  ; (page: sethalf's)
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
np_x:   lda flr                    ; the floor, A; flr 0 again (level until
        ldx #0                     ; o_zb or c_zb says otherwise)
        stx flr
        jmp np_b

; rpatch: c_coly's operands for rung X: c_hi's its HI, c_lo's its LO & $FC
; (LO <= x4 + 3 iff LO & $FC <= x4, x4 being a multiple of 4).  rpv: RVE, RVO =
; box X-1's bytes (c_one's) first.  X kept; clobbers A.  rpatch: cols (X = 0);
; rpv: c_ri (c_rix does rpatch's work inline, and rpv's on its one-box exit).
rpv:    lda CE-1,x
        sta RVE
        lda CO-1,x
        sta RVO
rpatch: lda HI,x
        sta c_hi+1
        lda LO,x
        and #$FC
        sta c_lo+1
        rts

; sethalf: the column's half of the screen, A = 0 (left) or 1 (right).  t = 2 *
; back + A selects the STAB and the line tables for the screen and half: scrh
; (the screen's page + the half), run's ENTBt (r_eh1) and EXHBt (r_eh2), run2's
; store pages (TPEt: pr0, pp0, je; TPOt: pr1, pp1, jo; tools/landgen.py's) and
; the LAHSBt page in every LDA LAHSB0,x (fs_h, z1_h, np_h, np_h2, np_h3, rc_h,
; sl_h).  run2's planted RTSes are put back in the pages being left (sh_1,
; sh_2: their pages are the last call's; at first TPE0, TPO0 at offset $FF)
; and pY's operand made t, below YSKY, so the next run2 plants afresh.  In: A;
; sh_b's operand (setback's 2 * back).  Out: V clear (c_coly's), Y = t.
; Clobbers A, X.  Called by cols, c_nh and gn_d.
sethalf:
sh_b:   ora #0                     ; operand: 2 * back (setback's)
        tay                        ; Y = t
        lda shs,y
        sta scrh
        clv
        tya                        ; stabp = STAB's page for the half: >STAB
        and #1                     ; + 2 half (the STABs store to `back`)
        asl a
        adc #>STAB                 ; (C clear)
        sta stabp
        rts
zbt0:   .byte $85, $D0             ; ob_st, zb_st by kind (cols): STA flr1,
zbt1:   .byte flr1, 3              ; BNE +3 (ob_n, zb_n: past the JMP after)
        .assert ob_n = ob_st+5 && zb_n = zb_st+5, error, "ob_n, zb_n: 3 bytes past ob_st, zb_st's branch (zbt1)"
npt0:   .byte $A5, $4C             ; c_np by kind (cols): LDA x4 / CLC, JMP
npt1:   .byte x4, <nearpost        ; nearpost
npt2:   .byte $18, >nearpost
shs:    .byte SCR0, SCR0+1, SCR1, SCR1+1 ; scrh by t: the screen's page + the half
; MASKB,n: the pixels whose bit is set in n (pixel i, 0 leftmost, is $88 >> i);
; MASKN,n the rest (nearpost's)
MASKB:  .byte PM($00), PM($88), PM($44), PM($CC), PM($22), PM($AA), PM($66), PM($EE)
        .byte PM($11), PM($99), PM($55), PM($DD), PM($33), PM($BB), PM($77), PM($FF)
MASKN:  .byte PM($FF), PM($77), PM($BB), PM($33), PM($DD), PM($55), PM($99), PM($11)
        .byte PM($EE), PM($66), PM($AA), PM($22), PM($CC), PM($44), PM($88), PM($00)

; fsplit: a column rung ri splits, its top level: lines mx .. flr1-1 with the
; boxes split at bpos, the number of the column's pixels left of the rung at
; the line (0..4), which moves one at each of the rung's transitions in the
; column.  The rung's tables, made at its first column (fs_ns, fs_new; lastri
; says whose they are): BE, BO + bpos its byte for even and odd lines (pixels
; 0 .. bpos-1 box ri-1's, the rest box ri's); rbl and fl_e, fl_o's operands
; from RTPL (rungs': pixel x's transition line is at RTBUF-page offset RTPL +
; x + 1), so that LDA RTBUF,x at X = bpos reads the next transition: pixel
; x4 + bpos's leaning right (bpos + 1 from that line), pixel x4 + bpos - 1's
; leaning left (bpos - 1); fst_e, fst_o INX or DEX and fen_e, fen_o's operands
; 4 or 0 (the boundary leaving the column) by the lean.  The rung's sentinel
; ($FF, rungs') ends the transitions too.
; The walker stores a character row's lines one at a time: Y the line in the
; row (also the byte's offset: zp_ = coff, zp_+1 the row's page), X = bpos, rsm
; the row's first line - 1 (RSMT, landgen's), fwe the next transition's line
; in the row (fw_e, fw_o by parity; fwx_e, fwx_o on to the row's end and the
; next row, fw_c).  A transition 8 + FSRJ lines or more below the row's start
; is reached by run2 instead (fr), as is a floor past the row (fe_r); a floor
; within it is walked by the copy at ff_e, ff_o.
; In: X = ri, C set, x4, coff, mx, flr1, TX; the tables; fs_h's page
; (sethalf's).  Entered at fs_c (c_split with the tables rung ri's; fs_new's
; end; s2v's JSR, c_np an RTS then) or fs_w (split, after its zone, X = bpos).
; Ends at c_np (ff_d), or through run2 into c_next.  Clobbers A, X, Y, bpos,
; fwe, fwu, rsm, zp_, RVE, RVO.
fs_c:   lda #0                     ; operand (rbl): RTPL, - 1 leaning left
rbl     = *-1                      ; (fs_ln's)
        adc x4                     ; (C set) + x4 + 1: fl_e, fl_o's operands
        sta fl_e+1
        sta fl_o+1
        lda TX,x                   ; bpos at the top: TX - x4 clamped to 0..4
        sec
        sbc x4
        CLAMP4
        tax
fs_w:   lda coff                   ; the walker's row: (zp_),y, Y its line
        sta zp_
        ldy mx
fs_h:   lda LAH,y                  ; the line's page: LAH + scrh
        clc
        adc scrh
        sta zp_+1
        tya                        ; the row's first line - 1
        and #$F8
        sec
        sbc #1
        sta rsm
        tya
        and #7
        tay
        lsr a                      ; C: an odd line
        bcc fl_e
        bcs fl_o
fwx_e:  lda BE,x                   ; a transition past the row (fwe >= 8): on
        sta (zp_),y                ; to the row's end
        iny
fwx_o:  lda BO,x
        sta (zp_),y
        iny
        cpy #8
        bne fwx_e
fw_c:   lda zp_+1                  ; the next row: two pages on (C set: CPY)
        adc #1
        sta zp_+1
        lda rsm                    ; (C clear) + 8
        adc #8
        sta rsm
        ldy #0
        lda fwe                    ; (C clear) - 8
        sbc #7
        sta fwe
        beq fn_e                   ; the transition at the row's first line
fw_e:   lda BE,x                   ; lines Y .. fwe-1 of the row at bpos X
        sta (zp_),y
        iny
        cpy fwe
        beq fn_o
fw_o:   lda BO,x
        sta (zp_),y
        iny
        cpy fwe
        bne fw_e
fn_e:                              ; at a transition, Y even: bpos moves
fst_e:  inx                        ; (INX or DEX: fs_ln's, the lean)
fen_e:  cpx #4                     ; (4 or 0: the boundary out of the column)
        beq fe_x
fl_e:   lda RTBUF,x                ; the next transition's line t (operand:
        cmp flr1                   ; fs_c's)
        bcs fe_x                   ; at or past the floor, or the sentinel
        sbc rsm                    ; (C clear) t in the row
        sta fwe
        cpy fwe
        bcs fn_e                   ; at or above this line: bpos moves again
        cmp #8
        bcc fw_e                   ; in the row: walked
        cmp #8+FSRJ
        bcc fwx_e                  ; a little past it: walked across
        bcs fr                     ; else a run
fn_o:                              ; Y odd
fst_o:  inx
fen_o:  cpx #4
        beq fe_x
fl_o:   lda RTBUF,x
        cmp flr1
        bcs fe_x
        sbc rsm
        sta fwe
        cpy fwe
        bcs fn_o
        cmp #8
        bcc fw_o
        cmp #8+FSRJ
        bcc fwx_o
fr:     stx bpos                   ; a run from this line to t
        adc rsm                    ; (C set) fwe + rsm + 1 = t
        sta fwu
        lda BE,x
        sta RVE
        lda BO,x
        sta RVO
        tya
        sec
        adc rsm                    ; this line: Y + rsm + 1
        tax
        ldy fwu
        lda c_np                   ; run2 ends at c_np: an RTS there meanwhile
        pha
        lda #OP_RTS
        sta c_np
        jsr run2
        pla
        sta c_np
        ldy fwu
        lda LAH,y                  ; the walker again from t: its row's page
        clc                        ; (LAH + scrh), rsm, Y
        adc scrh
        sta zp_+1
        tya
        and #$F8
        sec
        sbc #1
        sta rsm
        tya
        and #7
        tay
        ldx bpos
        lsr a
        bcc fn_e
        bcs fn_o
fe_x:   lda flr1                   ; no more transitions: to the floor at bpos X
        clc
        sbc rsm                    ; flr1 in the row (Y < 8 here)
        cmp #9
        bcs fe_r                   ; past the row: a run
        sta fwe
        cpy fwe
        bcs ff_d                   ; nothing left
        tya
        lsr a                      ; C: an odd line
        bcs ff_o
ff_e:   lda BE,x                   ; lines Y .. fwe-1 (the walker's copy)
        sta (zp_),y
        iny
        cpy fwe
        beq ff_d
ff_o:   lda BO,x
        sta (zp_),y
        iny
        cpy fwe
        bne ff_e
        jmp c_np
fe_r:   lda BE,x                   ; lines Y + rsm + 1 .. flr1-1 by run2
        sta RVE
        lda BO,x
        sta RVO
        tya
        adc rsm                    ; (C set: fe_x's CMP)
        tax
        ldy flr1
        jmp run2                   ; (on into c_next)
ff_d:   jmp c_np

; fs_new, fs_ns: rung X's tables for fsplit, lastri = X.  fs_ns (fsplit's, a
; rung new to it): when boxes X-1 and X have the same bytes the column is one
; box, c_ld (V clear: its run).  fs_new (split's, s2v's) skips that test.  BE +
; bpos: box X's even byte with pixels 0 .. bpos-1 from box X-1's (fs_dif; fs_e0
; when the two are alike), BO + bpos the odd likewise (fs_co, fs_oe); then the
; lean (fs_ln): rbl, and fst_e, fst_o and fen_e, fen_o's operands, patched
; only when the lean changes.  Ends at fs_nj, JMP fs_c (sp_r while split has
; it), with C set.
fs_new: lda CE-1,x
        sta BE+4                   ; (bpos 4: box X-1's)
        eor CE,x
        bne fs_dif
        beq fs_e0
fs_s1:  lda CO-1,x                 ; the even bytes alike: the odd too?
        cmp CO,x
        bne fs_e0
        jmp c_ld                   ; one box
fs_e0:  stx lastri                 ; BE .. BE+3 = BE+4
        lda BE+4
        sta BE
        sta BE+1
        sta BE+2
        sta BE+3
        jmp fs_co
fs_oe:  lda BO                     ; BO+1 .. BO+3 = BO
        sta BO+1
        sta BO+2
        sta BO+3
        jmp fs_ln
fs_ns:  lda CE-1,x
        sta BE+4
        eor CE,x
        beq fs_s1
fs_dif: stx lastri                 ; Y: the two even bytes' difference
        tay
        eor BE+4                   ; BE = box X's (bpos 0)
        sta BE
        tya
        and #PM($88)               ; pixel 0 from box X-1
        eor BE
        sta BE+1
        tya
        and #PM($CC)               ; pixels 0, 1
        eor BE
        sta BE+2
        tya
        and #PM($EE)               ; pixels 0, 1, 2
        eor BE
        sta BE+3
fs_co:  lda CO-1,x                 ; the odd bytes likewise
        sta BO+4
        lda CO,x
        sta BO
        eor BO+4
        beq fs_oe
        tay
        and #PM($88)
        eor BO
        sta BO+1
        tya
        and #PM($CC)
        eor BO
        sta BO+2
        tya
        and #PM($EE)
        eor BO
        sta BO+3
fs_ln:  lda BX,x
        cmp TX,x
        bcs fs_nr
        lda RTPL,x                 ; leaning left: rbl = RTPL - 1 (C clear), so
        sbc #0                     ; fl_e reads pixel x4 + bpos - 1's line;
        sta rbl                    ; bpos counts down (DEX), out at 0
        lda #OP_DEX
        cmp fst_e
        beq fs_nj                  ; (already so; C set)
        sta fst_e
        sta fst_o
        lda #0
        sta fen_e+1
        sta fen_o+1
        sec
        bcs fs_nj
fs_nr:  lda RTPL,x                 ; leaning right, or upright: rbl = RTPL, so
        sta rbl                    ; fl_e reads pixel x4 + bpos's line; bpos
        lda #OP_INX                ; counts up (INX), out at 4
        cmp fst_e
        beq fs_nj                  ; (already so; C set)
        sta fst_e
        sta fst_o
        lda #4
        sta fen_e+1
        sta fen_o+1
        sec
fs_nj:  jmp fs_c                   ; (operand: sp_r while split runs fs_new)
        .res 1                     ; (a spare byte: the layout is fixed)

; zone1: a one-box column's top zone: lines mn .. min(mx, flr1)-1, in each the
; pixels at or below their top-row line (msk: line mn's from o_zt or split's
; pmask, then pmask by ys, loaded from the top row) set to RVE on even lines,
; RVO on odd, read-modify-write.  In: mn < mx (V set), msk, RVE, RVO, flr1, x4,
; coff, topa; z1_h's page (sethalf's).  Out: X = mx, to c_r1x (the run below),
; or to c_np when the floor is reached (the run would be empty).  Entered from
; c_z1 (c_on, c_ld).  Clobbers A, X, Y, ys, msk, zp_.
zone1:  ldx mn
        cpx flr1
        bcs z1_n
z1_h:   lda LAH,x                  ; the line's page: LAH + scrh
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        lsr a                      ; C: an odd line
        ldy coff
        lda (zp_),y
        bcs z1_o
        eor RVE                    ; msk's pixels from RVE, the rest kept
        and msk
        eor (zp_),y
        sta (zp_),y
        inx
        cpx mx
        bcc z1_m
        jmp c_r1x                  ; X = mx
z1_o:   eor RVO
        and msk
        eor (zp_),y
        sta (zp_),y
        inx
        cpx mx
        bcc z1_m
        jmp c_r1x                  ; X = mx
z1_m:   ldy x4                     ; more lines: each pixel's top for pmask
        lda (topa),y               ; (loaded again every line)
        sta ys
        iny
        lda (topa),y
        sta ys+1
        iny
        lda (topa),y
        sta ys+2
        iny
        lda (topa),y
        sta ys+3
z1_l:   cpx flr1
        bcs z1_n
        jsr pmask
        jmp z1_h
z1_n:   jmp c_np

; c_nd: nearpost's way to the next column (c_nd1).
c_nd:   lda x4
        clc
        jmp c_nd1
; oz_dn: o_zt's other case, p0 > p3: mx = p0, mn = p3, msk pixel 3 and those
; leftward equal to it (the row monotonic).  V set; on to the floor.
oz_dn:    sta mx
oz3b:   ldx ROWA+3,y               ; (pages: cols')
        stx mn
oz2b:   ldx ROWA+2,y
        lda #PM($11)               ; pixel 3
        cpx mn
        bne oz_m
oz1b:   ldx ROWA+1,y
        lda #PM($33)               ; pixels 2, 3
        cpx mn
        bne oz_m
        lda #PM($77)               ; pixels 1, 2, 3
oz_m:     sta msk
        bit c_v1                   ; V set: the top not level
        jmp o_ft

; pmask: msk = line X's pixels at or below their top-row line (ys): bit i of
; the MASKB index is X >= ys+i.  X kept; clobbers A, Y.  Called by zone1,
; split and split2; inline in sp_ln and np_l.
pmask:  lda #0
        cpx ys+3
        rol a
        cpx ys+2
        rol a
        cpx ys+1
        rol a
        cpx ys
        rol a
        tay
        lda MASKB,y
        sta msk
        rts

; zline: line X of the column: A's byte into msk's pixels, the rest kept
; (read-modify-write; the line's page LAH,x + scrh).  X kept; clobbers A, Y,
; zv.  Called by split2 (its zone) and slow2.
zline:  sta zv
        lda LAH,x
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda (zp_),y
        eor zv
        and msk
        eor (zp_),y
        sta (zp_),y
        rts

; split: a column rung ri splits, its top not level: the zone (lines mn ..
; min(mx, flr1)-1, in each the pixels at or below their top-row line, ys) with
; the boxes split at bpos as it stands at the line (rung ri's transitions at
; (rtp),y, read as fsplit does), then fsplit's walker from mx (fs_w).  Rung
; ri's tables are fsplit's already (lastri: sp_c) or fs_new makes them (back
; to sp_r), unless its two boxes have the same bytes: then the column is one
; box, zone1 by way of c_ld (V set; msk for line mn first).  In: ri, lastri,
; mn, mx, flr1, ys, x4, coff, TX.  Entered from c_split (JMP); ends as
; fsplit.  Clobbers A, X, Y, bpos, rtp, msk, zp_, zv and fs_nj's operand (sp_r
; while fs_new runs, then fs_c again).
split:  ldx ri
        cpx lastri
        beq sp_c
        lda CE-1,x                 ; the boxes alike: one box
        cmp CE,x
        bne :+
        lda CO-1,x
        cmp CO,x
        bne :+
        ldx mn                     ; (line mn's msk, zone1's first)
        jsr pmask
        ldx ri
        jmp c_ld
:
        lda #<sp_r                 ; fs_new, back to sp_r
        sta fs_nj+1
        lda #>sp_r
        sta fs_nj+2
        jmp fs_new
sp_r:   lda #<fs_c                 ; (C set) fs_nj's own operand again
        sta fs_nj+1
        lda #>fs_c
        sta fs_nj+2
sp_c:   lda rbl                    ; (C set) as fs_c: rtp = RTPL + x4 + 1 (one
        adc x4                     ; less leaning left), fl_e, fl_o's operands
        sta rtp                    ; too (rtp+1: RTBUF's page, rungs')
        sta fl_e+1
        sta fl_o+1
        lda TX,x                   ; Y = bpos at the top: TX - x4, clamped 0..4
        sec
        sbc x4
        CLAMP4
        tay
        ldx mn                     ; the zone's line, X
        lda fst_e                  ; the lean: fs_ln's INX or DEX
        cmp #OP_INX
        bne sp_lz
sp_rz:  cpx mx                     ; leaning right, or upright: to mx or flr1
        bcs sp_zd
        cpx flr1
        bcs sp_zd
sp_rc:  cpy #4                     ; bpos up past each transition at or above
        beq sp_rb                  ; line X (pixel x4 + Y's: (rtp),y)
        txa
        cmp (rtp),y
        bcc sp_rb
        iny
        bne sp_rc
sp_rb:  jsr sp_ln
        inx
        bne sp_rz
sp_lz:  cpx mx                     ; leaning left
        bcs sp_zd
        cpx flr1
        bcs sp_zd
sp_lc:  cpy #0                     ; bpos down past each (pixel x4 + Y - 1's)
        beq sp_lb
        txa
        cmp (rtp),y
        bcc sp_lb
        dey
        bpl sp_lc
sp_lb:  jsr sp_ln
        inx
        bne sp_lz
sp_zd:  tya                        ; X = bpos: the walker from mx (sp_zg:
        tax                        ; unless the zone took bpos out of the
        jmp sp_zg                  ; column)
; sp_ln: line X of the zone at bpos Y: BE or BO + Y (by the line's parity) into
; the pixels at or below their top (pmask inline, from ys).  X and Y kept;
; clobbers A, bpos, msk, zp_, zv.
sp_ln:  sty bpos
        lda #0                     ; (pmask)
        cpx ys+3
        rol a
        cpx ys+2
        rol a
        cpx ys+1
        rol a
        cpx ys
        rol a
        tay
        lda MASKB,y
        sta msk
sl_h:   lda LAH,x                  ; the line's page: LAH + scrh
        clc
        adc scrh
        sta zp_+1
        txa
        and #7
        sta zp_
        lsr a                      ; C: an odd line
        ldy bpos
        lda BE,y
        bcc :+
        lda BO,y
:       sta zv
        ldy coff
        lda (zp_),y
        eor zv
        and msk
        eor (zp_),y
        sta (zp_),y
        ldy bpos
        rts

; mktr: rung X's transitions in the column into TRL (the line) and TRB (the LM
; mask of the pixels left of the rung from that line on), from index A, ended
; by a TRL of $FF; returns A = the mask at the top, LM of p0 = TX - x4 clamped
; to 0..4 (p1 the bottom's, BX).  Leaning right: pixels p0 .. p1-1, mask p + 1
; after pixel p's line; left: pixels p0-1 down to p1, mask p after pixel p's.
; rtp = RTPL + x4 + 1: (rtp),y is pixel x4 + y's transition (rungs').
; Clobbers X, Y, tj, p0, p1, rtp.  Called by split2 and s2v.
mktr:   sta tj
        lda RTPL,x
        sec
        adc x4
        sta rtp                    ; (rtp+1: RTBUF's page, rungs')
        lda BX,x                   ; p1: BX - x4 clamped to 0..4
        sec
        sbc x4
        CLAMP4
        sta p1
        lda TX,x                   ; p0
        sec
        sbc x4
        CLAMP4
        sta p0
        ldx tj
        cmp p1
        beq @end                   ; none in the column
        bcs @lt
        tay
@rt:    lda (rtp),y                ; leaning right: pixel Y's line, then Y + 1
        sta TRL,x                  ; pixels left
        lda LM+1,y
        sta TRB,x
        inx
        iny
        cpy p1
        bne @rt
        beq @end
@lt:    tay                        ; leaning left: pixel Y-1's line, then Y-1
:       dey                        ; left
        lda LM,y
        sta TRB,x
        lda (rtp),y
        sta TRL,x
        inx
        cpy p1
        bne :-
@end:   lda #$FF
        sta TRL,x
        ldy p0
        lda LM,y
        rts

; split2: a column two rungs split (ri, ri+1), its top not level (s2v, bank 4,
; is the level case): boxes L, M, R = ri-1, ri, ri+1, the boundaries at bpos
; and bpos2 (LM masks: the pixels left of each rung), each moving at its rung's
; transitions (TRL, TRB from 0 and from 6, mktr's; kk, kb index the next of
; each).  The zone (lines mn .. min(mx, flr1)-1) a line at a time in the pixels
; at or below their top (catch2, pmask, bytes2, zline); then runs from mx, each
; to the nearer next transition or the floor.  In: ri, mn, mx, flr1, ys, x4,
; coff.  Called by c_dbl (JSR).  Clobbers A, X, Y, le, lo2, re, ro, me, mo,
; bpos, bpos2, kk, kb, yy, ve, vo, msk, zv, zp_, TRL, TRB, tj, p0, p1, rtp.
split2: ldx ri
        lda CE-1,x                 ; L's bytes
        sta le
        lda CO-1,x
        sta lo2
        lda CE+1,x                 ; R's, and M's as M xor R (bytes2's)
        sta re
        eor CE,x
        sta me
        lda CO+1,x
        sta ro
        eor CO,x
        sta mo
        lda #0                     ; rung ri's transitions at TRL, TRB + 0 on
        jsr mktr
        sta bpos
        ldx ri
        inx
        lda #6                     ; rung ri+1's at + 6 on
        jsr mktr
        sta bpos2
        lda #0
        sta kk
        lda #6
        sta kb
        ldx mn                     ; the zone
@z:     cpx mx
        bcs @zd
        cpx flr1
        bcs @zd
        jsr catch2
        jsr pmask
        jsr bytes2
        txa
        lsr a                      ; C: an odd line
        lda ve
        bcc :+
        lda vo
:       jsr zline
        inx
        bne @z
@zd:    ldx mx                     ; the runs, from mx
        cpx flr1
        bcs @rd
        stx yy
@tr:    ldy kk                     ; bpos, bpos2 by the transitions at or above
        txa                        ; line X (catch2's, inline)
        cmp TRL,y
        bcc @k2
:       lda TRB,y
        sta bpos
        iny
        txa
        cmp TRL,y
        bcs :-
        sty kk
@k2:    ldy kb                     ; (A = X)
        cmp TRL,y
        bcc @rl3
:       lda TRB,y
        sta bpos2
        iny
        txa
        cmp TRL,y
        bcs :-
        sty kb
@rl3:   lda TRL,y                  ; the run's end: the nearer next transition
        ldy kk                     ; ($FF: none), at most the floor
        cmp TRL,y
        bcc :+
        lda TRL,y
:       cmp flr1
        bcc :+
        lda flr1
:       tay
        lda me                     ; the bytes (bytes2's, inline): M in bpos2's
        and bpos2                  ; pixels, else R; then L in bpos's
        eor re
        sta ve
        eor le
        and bpos
        eor ve
        sta ve
        lda mo
        and bpos2
        eor ro
        sta vo
        eor lo2
        and bpos
        eor vo
        sta vo
        ldx yy                     ; lines yy .. Y-1
        sty yy
        jsr run
        ldx yy
        cpx flr1
        bcc @tr
@rd:    rts

; catch2: bpos, bpos2 by the transitions at or above line X (TRL, TRB from kk
; and kb, which move on past them).  X kept; clobbers A, Y.
catch2: ldy kk
:       txa
        cmp TRL,y
        bcc :+
        lda TRB,y
        sta bpos
        iny
        bne :-
:       sty kk
        ldy kb
:       txa
        cmp TRL,y
        bcc :+
        lda TRB,y
        sta bpos2
        iny
        bne :-
:       sty kb
        rts

; bytes2: ve, vo = split2's bytes for a line: M in bpos2's pixels, else R (me,
; mo hold M xor R); then L in bpos's.  X, Y kept; clobbers A.
bytes2: lda me
        and bpos2
        eor re
        sta ve
        lda mo
        and bpos2
        eor ro
        sta vo
        lda le
        eor ve
        and bpos
        eor ve
        sta ve
        lda lo2
        eor vo
        and bpos
        eor vo
        sta vo
        rts

                                   ; LM,n: the n leftmost pixels
LM:     .byte PM($00), PM($88), PM($CC), PM($EE), PM($FF)

; run: lines X .. Y-1 (X < Y) of the column, ve on even lines and vo on odd,
; through the STAB for the screen and half (init's: for each line STA line,Y,
; then LDA vo after an even line and TXA after an odd).  A JMP to line X's
; entry (EXLB, EXHBt; an odd line's entry is the LDA vo before its STA, so A
; need only be ve) with A = X = ve and Y = coff; back by an RTS planted over
; line Y's STA opcode (ENTL, ENTBt), whose address pp keeps so the next run can
; put the STA back (init points pp at dummy first).  In: X, Y, ve, vo, coff;
; r_eh1, r_eh2's operands (sethalf's).  Clobbers A, X, Y.  Called by rc_r,
; np_r, split2 and gn_d.
run:    txa                        ; line X's entry: ENTL, ENTH + stabp, less
        lsr a                      ; 2 for an odd line (C)
        lda ENTL,x
        bcc :+
        sbc #2                     ; (C set: - 2)
        sta r_j+1
        lda ENTH,x
        sbc #0
        jmp :++
:       sta r_j+1
        lda ENTH,x
:       ora stabp
        sta r_j+2
        ldx #0
        lda #OP_STAY               ; the last RTS back
        sta (pp,x)
        lda ENTL,y                 ; line Y's entry: the RTS
        sta pp
        lda ENTH,y                 ; (+ stabp)
        ora stabp
        sta pp+1
        lda #OP_RTS
        sta (pp,x)
        ldx ve                     ; A = X = ve (the odd lines' TXA)
        txa
        ldy coff
r_j:    jmp $FFFF                  ; (the planted RTS returns to run's caller)
dummy:  .byte 0                    ; pp's first target: the first run's put-back

; recordc: record's twin for a column a rung splits (c_rec's target in a
; recording phase): CURT, then the black above (rc_t, whose c_rd re-tests the
; rungs) when TOPS is above mx, else on to c_srx.  In: Y = x4, V, mn, mx.
; pT3c, pT5c: strips' operands (CURT, TOPS by set).
recordc: tya
        lsr a
        lsr a
        tax
        lda mx
        bvc :+                     ; V set: the top not level, its highest mn
        lda mn
:
pT3c:   sta CURT,x                 ; (strips: this frame's set)
pT5c:   lda TOPS,x                 ; (strips: this screen's set)
        cmp mx
        bcc :+
        jmp c_srx
:       jmp rc_t

; gone: the columns the land has left since the last frame on this screen: those
; outside the near strip's xl .. xr-1 (every strip's columns lie within the
; near strip's) that had land last time (TOPS not $FF) are blacked from TOPS
; to BOTS (gn_d), and all of them are marked empty this frame (CURT $FF, CURB
; 0).  In: xl, xr (the near strip's), tsp, bsp and the GONE1 sites' operands
; (strips': TOPS, CURT, CURB by set).  Clobbers A, X, Y, tsy, tj, coff, scrh,
; ve, vo and sethalf's patches.  Called by strips after its last strip.
.macro GONE1 lt, lc, lb            ; column X; lt, lc, lb: the patched sites
        .local nd
lt      = *
        lda TOPS,x
        cmp #$FF
        beq nd
        jsr gn_d
nd:     lda #$FF
lc      = *
        sta CURT,x
        lda #0
lb      = *
        sta CURB,x
.endmacro
gone:   lda xr                     ; columns 63 down to xr / 4
        lsr a
        lsr a
        sta tsy
        ldx #63
        cpx tsy
        bcc gn_l
gn_c:   GONE1 pT6, pT4, pB7
        dex
        cpx tsy
        bcs gn_c
gn_l:   lda xl                     ; and xl / 4 - 1 down to 0
        lsr a
        lsr a
        tax
        dex
        bmi gn_x
gn_c2:  GONE1 pT6b, pT4b, pB7b
        dex
        bpl gn_c2
gn_x:   rts
; gn_d: column X black from TOPS to BOTS (a run).  X kept.
gn_d:   stx tj
        txa
        asl a                      ; coff = 8 * column mod 256
        asl a
        asl a
        sta coff
        txa
        lsr a                      ; the half: column / 32
        lsr a
        lsr a
        lsr a
        lsr a
        jsr sethalf
        ldy tj                     ; (sethalf leaves Y = t)
        lda (bsp),y                ; X = TOPS, Y = BOTS + 1
        pha
        lda (tsp),y
        tax
        pla
        tay
        iny
        lda #0
        sta ve
        sta vo
        jsr run
        ldx tj
        rts

; The vertical sync event handler (EVNTV): vcount += 1, and the user VIA's
; timer 2 restarted (the time since the sync, for flip and strips).  A and
; the flags kept.
vsync:  php
        pha
        lda #$FF
        sta UVIA_T2H
        pla
        inc vcount
        plp
        rts

; bclip: the bottom row's line held on the screen.  If setup saw a bottom
; point past YGND (BCL) but not all NX (traceb drew the row at YGND+1 then),
; every entry of (bota) greater than YGND+1 (below the screen) is set to
; YGND+1, so each column's floor is at most YGND+1 (o_zb, c_zb) and the lines
; drawn stay on the screen.  A pixel is past YGND+1 only within a segment one
; of whose points is past, so the clamp runs from the point before the first
; past one to the point after the last (the page's end when that is a row
; end: the row is widened level with its ends); the page's other entries are
; at most YGND+1 already (every row is).
; In: BCL, BX, BY, bota.  Clobbers A, X, Y.  Called by strips.
bclip:  lda BCL
        beq bc_x
        cmp #NX
        beq bc_x                   ; (all past: the row at YGND+1, traceb's)
        ldx #0                     ; the first past point, from the left: Y the
        ldy #0                     ; clamp's start, x of the point before it
:       inx                        ; (0 for point 1: the widening left of it)
        lda BY,x
        cmp #YGND+1
        bcs :+
        ldy BX,x
        bcc :-                     ; (always)
:       ldx #NX+1                  ; the last, from the right: its end bc_e,
        lda #0                     ; x of the point after it (0: the page's
:       sta bc_e+1                 ; end, for point NX)
        dex
        lda BY,x
        cmp #YGND+1
        bcs :+
        lda BX,x
        bcc :-                     ; (always)
:       lda #YGND+1
:       cmp (bota),y
        bcs :+                     ; (at most YGND+1 already: kept)
        sta (bota),y
:       iny
bc_e:   cpy #0                     ; (operand: the end, exclusive; 0 the page's)
        bne :--
bc_x:   rts

; sp_zg: split's way into the walker (fs_w) from mx at bpos X, unless the
; zone has already moved bpos to the column's edge (fen_e's operand: 4
; leaning right, 0 left).  The walker would then read the transition of a
; pixel outside the column and step bpos past the edge, so instead lines mx
; .. flr1-1 take the rung's bytes at bpos X, BE and BO + X (the rung has
; crossed the column: box ri-1's leaning right, ri's leaning left), by run2
; (on into c_next), or nothing when the zone reached the floor.  In: X =
; bpos, mx, flr1, coff, the rung's tables.  Called by split (JMP).
sp_zg:  cpx fen_e+1
        beq :+
        jmp fs_w
:       lda mx
        cmp flr1
        bcc :+
        jmp c_np                   ; (nothing below the zone)
:       lda BE,x
        sta RVE
        lda BO,x
        sta RVO
        ldy flr1
        ldx mx
        jmp run2

; ---------------------------------------------------------------- readout
; readout: the frame rate at the top left of the screen being drawn, character
; row 2 (the game's area), eight characters "TU.t FPS": flip records each
; frame's vertical syncs in dvs (the last eight frames); their sum s gives
; (4000 + s / 2) / s, the rate in tenths (eight frames at 50
; syncs a second), printed as tens (blank when 0), units, '.', tenths, ' ',
; "FPS".  The
; sum is held at 255 if it would pass it.  With fpson 0 (game.s's F key) eight
; blanks are drawn instead.  In: fpson, dvs, scrb.  Clobbers A, X, Y, fps10,
; tcol, ptr.  Caller: loop (after G_POST, before flip; so dvs is the eight
; frames before this one).
G_DOT   = 10                       ; GLY's characters: gchars's index (LANDS's
                                   ; glyphs makes them)
G_SP    = 11
G_F     = 12

readout:
        lda fpson
        bne @on
        sta tcol                   ; off: eight blanks from column 0
:       lda #G_SP
        jsr putg
        lda tcol
        cmp #8
        bne :-
        rts
@on:    ldx #7                     ; s = the sum of dvs, 255 at most
        lda #0
        clc
:       adc dvs,x
        bcc :+
        lda #$FF
        bne :++
:       dex
        bpl :--
:       sta MT0                    ; fps10 = (4000 + s / 2) / s (0 for s 0)
        lsr a
        clc
        adc #<4000
        sta fps10
        lda #>4000
        adc #0
        sta fps10+1
        lda MT0
        beq @f0
        lda #0                     ; the 16 by 8 division: quotient into fps10,
        ldy #16                    ; the remainder in A
@fd:    asl fps10
        rol fps10+1
        rol a
        bcs @fs                    ; (past 255: s > 127)
        cmp MT0
        bcc @fn
@fs:    sbc MT0
        inc fps10
@fn:    dey
        bne @fd
        beq @fz                    ; (always)
@f0:    sta fps10
        sta fps10+1
@fz:
        lda #0
        sta tcol
        ldy #0                     ; fps10's hundreds (tens of frames a second)
:       lda fps10
        sec
        sbc #100
        tax
        lda fps10+1
        sbc #0
        bcc :+
        sta fps10+1
        stx fps10
        iny
        bne :-
:       tya
        bne :+
        lda #G_SP                  ; (a leading zero blank)
:       jsr putg
        ldy #0                     ; the tens (units of frames a second)
:       lda fps10
        sec
        sbc #10
        bcc :+
        sta fps10
        iny
        bne :-
:       tya
        jsr putg
        lda #G_DOT
        jsr putg
        lda fps10                  ; the rest: tenths
        jsr putg
        lda #G_SP
        jsr putg
        lda #G_F                   ; "FPS"
        jsr putg
        lda #G_F+1
        jsr putg
        lda #G_F+2
                                   ; (falls into putg)
; putg: character A (GLY's index) at column tcol (8 pixels: two bytes wide) of
; character row 2 of the screen being drawn (scrb), tcol then one on.  The 16
; bytes at GLY + 16 A go to the screen's row 2 + 16 tcol: a character cell's 8
; lines, then the next cell's.  In: A, tcol, scrb.  Clobbers A, X, Y, ptr.
; Callers: readout.
putg:   asl a
        asl a
        asl a
        asl a
        tax                        ; X = 16 A (GLY is page-aligned)
        lda tcol
        asl a
        asl a
        asl a
        asl a
        sta ptr                    ; ptr = the panel's row 4 + 16 tcol (128
        lda #>(PANEL+4*128)        ; bytes a row)
        sta ptr+1
        ldy #0
:       lda GLY,x
        sta (ptr),y
        inx
        iny
        cpy #16
        bne :-
        inc tcol
        rts

pkx:    .byte $FF                  ; project's: the cxt and czt + ZB the heights
pkz:    .byte $FF                  ; (HT) and boxes (CLE, CLO) are for ($FF:
                                   ; none yet)
SHF:    .byte 0                    ; zsh4's: HT to shift a row on (1) or back
                                   ; ($FF) with HTN; 0 none
        .segment "HIB"
fps10:  .res 2                     ; readout's: the rate in tenths
        .code
fpson:  .byte 1                    ; the readout on (game.s's F toggles it)
        .segment "HIB"
dvs:    .res 8                     ; flip's: the last eight frames' vertical
                                   ; syncs (init zeroes them)
dvi:    .res 1                     ; the next entry
vlast:  .res 1                     ; vcount at the last flip
tcol:   .res 1                     ; putg's column (readout's); glyphs' counter
        .code

        .include "b32tab.inc"     ; DCE, DCO


; traceb's fills (TBLK4, TBLK5: ROWA's, ROWB's): STA ROWx-k,X for k = TNB .. 1
; then JMP t_back; TENxL, TENxH + n: the entry for n stores, TBLKx + 3 (TNB -
; n); tenl, tenh: the tables' addresses by the row (traceb patches its sites:
; the entries for n and for n + 1).
        .segment "FILLS"
TBLK4:  .repeat TNB, i
        sta ROWA-TNB+i,x
        .endrepeat
        jmp t_back
TBLK5:  .repeat TNB, i
        sta ROWB-TNB+i,x
        .endrepeat
        jmp t_back
TEN4L:  .repeat TNB+1, n
        .byte <(TBLK4 + 3*(TNB-n))
        .endrepeat
TEN4H:  .repeat TNB+1, n
        .byte >(TBLK4 + 3*(TNB-n))
        .endrepeat
TEN5L:  .repeat TNB+1, n
        .byte <(TBLK5 + 3*(TNB-n))
        .endrepeat
TEN5H:  .repeat TNB+1, n
        .byte >(TBLK5 + 3*(TNB-n))
        .endrepeat
tenl:   .byte <TEN4L, <TEN5L, >TEN4L, >TEN5L, <(TEN4L+1), <(TEN5L+1), >(TEN4L+1), >(TEN5L+1)
tenh:   .byte <TEN4H, <TEN5H, >TEN4H, >TEN5H, <(TEN4H+1), <(TEN5H+1), >(TEN4H+1), >(TEN5H+1)
        .assert ROWB = ROWA + $100 && <ROWA = 0, error, "fills: the row's page's bit 0 picks the tables"

        .code
        .include "proj32.s"
        .segment "GAME"
        .include "game.s"
        .segment "SHIP"
        .include "ship32.s"
; MAP32 + 32 z + x: corner (x, z)'s height (bits 0-3) and tile (x, z)'s colour
; index (bits 4-7: DCE, DCO), b32/tools/gen32.py's.
        .segment "MAPD"
MAP32:  .incbin "MAP32"
; R7L, R7H + di: r, the row's pixels a tile at depth index di (d = 16 (DI0 +
; di)): land.recip(d) = (2^21 + k) div 2k, k = DI0 + di; init's.
        .segment "MID"
R7L:    .res NDI
R7H:    .res NDI

; ---------------------------------------------------------------- the slow way
; Bank 4's free space again (zsh4 at $B900 and slow2 at $9200, the first R2OFF
; bytes of run2's store pages TPO3 and TPE2; slow at $A081, after TENH4's 129
; entries): a map step's heights, and the column no faster routine takes.
        .code
; zsh4 (bank 4): the map rows one step on or back since last frame.  In: A =
; czt + ZB (row 0's map row), pkz (last frame's).  If the difference is +1
; (SHF 1: each row's heights become the row before's) or -1 (SHF $FF: the row
; after's), the one new row's heights are read from the map into HTN: map row
; czt + ZB for +1 (the new row 0), czt + ZB - 7 for -1 (the new row 7), masked
; to the height (bits 0-3) at each column CX; prow7's hsh then shifts HT and
; takes HTN in.  Out: C set, SHF, HTN, pkz = czt + ZB.  Otherwise C clear
; (pkz still updated; project reloads every row).  Uses HPZ (zero page, 2
; bytes) as the map row's pointer.  Clobbers A, X, Y.  Caller: project.
zsh4:   tay
        sec
        sbc pkz                    ; A = new - old
        sty pkz
        cmp #1
        beq @ld                    ; (+1: SHF = A = 1, Y = czt + ZB)
        cmp #$FF
        bne @no
        tya                        ; (-1: row 7's map row, czt + ZB - 7)
        sbc #7                     ; (C set: the CMP matched)
        tay
        lda #$FF
@ld:    sta SHF
        tya
        and #MAPN-1                ; HPZ = MAP32 + 32 z
        tay
        lsr a
        lsr a
        lsr a
        ora #>MAP32
        sta HPZ+1
        tya
        asl a
        asl a
        asl a
        asl a
        asl a
        sta HPZ
        ldx #NX-1
:       ldy CX,x
        lda (HPZ),y
        and #15
        sta HTN,x
        dex
        bpl :-
        sec
        rts
@no:    clc
        rts

        .code
; slow (bank 4): a column three or more rungs reach (c_d3's), drawn a line at a
; time from its top.  First each pixel p (x = x4 + p) is classed: SPB+p, its
; box at its top line, is ri - 1 plus one for every rung whose top-row point is
; at or left of x; STL+4p.. its transitions in rung order (four slots, $FF
; after the last), each the line (from RTBUF, the rung's by RTPL) where a rung
; crosses the pixel, with STD the box's change below it (+1 for a rung leaning
; left: below the crossing the pixel is right of the rung, in the next box; -1
; leaning right).  The rungs considered are ri on, while LO < x4p4.  Then
; slow2.  In: ri, x4, x4p4, LO, HI, TX, BX, RTPL, RTBUF; and slow2's.  Out:
; SPB, STL, STD (slow2's).  Clobbers A, X, Y, tj, tx1, tmp.  Caller: c_d3
; (JSR; slow2's RTS returns).
slow:   lda x4                     ; x4p4 = x4 + 4: the column's end
        clc
        adc #4
        sta x4p4
        ldx #0
@p:     stx tj                     ; pixel p
        txa
        clc
        adc x4
        sta tx1                    ; its x
        ldy ri
        dey
        tya
        sta SPB,x                  ; box ri - 1 to start
        txa
        asl a
        asl a
        tay                        ; Y = 4p: its transition slots, all $FF
        lda #$FF
        sta STL,y
        sta STL+1,y
        sta STL+2,y
        sta STL+3,y
        ldx ri
@r:     lda LO,x                   ; rung X, while its LO < x4p4
        cmp x4p4
        bcs @pd
        lda tx1
        cmp TX,x
        bcc :+
        stx tmp                    ; its top at or left of x: its top box one on
        ldx tj
        inc SPB,x
        ldx tmp
:       lda tx1                    ; LO <= x < HI: it crosses the pixel
        cmp LO,x
        bcc @rn
        cmp HI,x
        bcs @rn
        lda RTPL,x                 ; RTBUF + RTP + x + 1: the pixel's transition
        sec                        ; line (RTP = alloc - LO - 1; RTBUF's page)
        adc tx1
        sty tmp
        tay
        lda RTBUF,y
        ldy tmp
        sta STL,y
        lda BX,x                   ; STD: +1 leaning left (BX < TX), else -1
        cmp TX,x
        lda #1
        bcc :+
        lda #$FF
:       sta STD,y
        iny
@rn:    inx
        bne @r
@pd:    ldx tj
        inx
        cpx #4
        bne @p
        jmp slow2
        .code
; slow2 (bank 4): lines mn .. flr1-1, each pixel at or below its top line (ys)
; in its box's byte for the line's parity (CE or CO: @cl's operand, patched),
; the box its top box shifted by the transitions at or above the line; the line
; written through zline (read-modify-write in msk's pixels).  In: mn, flr1,
; ys, SPB, STL, STD, CE, CO, PIXM; zline's (scrh, coff, LAH).  Clobbers A, X,
; Y, yy, msk, zv, tj, tmp.
slow2:  ldx mn
@l:     stx yy
        txa
        lsr a
        lda #<CE                   ; (CE, CO in one page)
        bcc :+
        lda #<CO
:       sta @cl+1
        lda #0
        sta msk
        sta zv
        ldy #3
@lp:    lda yy                     ; pixel Y
        cmp ys,y
        bcc @skip                  ; above its top: not drawn
        lda PIXM,y
        ora msk
        sta msk
        sty tj
        lda SPB,y                  ; its box: the top's, +- each transition at
                                   ; or above the line
        sta tmp
        tya
        asl a
        asl a
        tax
@s:     lda STL,x
        cmp #$FF
        beq @sd
        lda yy
        cmp STL,x
        bcc @sn
        lda tmp
        clc
        adc STD,x
        sta tmp
@sn:    inx
        bne @s
@sd:    ldx tmp
@cl:    lda CE,x                   ; (CE or CO: the line's parity)
        ldy tj
        and PIXM,y
        ora zv
        sta zv
@skip:  dey
        bpl @lp
        ldx yy
        lda zv
        jsr zline
        inx
        cpx flr1
        bcc @l
        rts
                                   ; pixel p's bits as drawn (PM)
PIXM:   .byte PM($88), PM($44), PM($22), PM($11)

; ---------------------------------------------------------------- bank 5
        .code
; pcol5 (bank 5, $A000, after CMAPO; bank 5 must be paged in): the land strips'
; boxes' bytes.  Entry i of a window row (box i+1 of the strip whose near row
; is map row z: su_l7) is tile (CX+i, z): its even-line byte from CMAPE, its
; odd-line byte from CMAPO (both at z*64 + x in bank 5).  The bytes are kept
; in a window of ten rows at CLE, CLO + 16 m
; (m 0..9): window row m holds map row WK - m for the columns CX made at cxt =
; WX.  While the camera's tile column stays at WX the window is reused: the
; rows the strips need are o..o+6, o = WK - (czt + ZB) + 1 (strip ns's near
; row, map row czt + ZB - ns, is window row o + ns - 1), so with o in 0..3 the
; rows not yet made (outside VLO..VHI) are made and VLO, VHI widened.  When
; the column changes, or o leaves 0..3, the window is remade: WK = czt + ZB,
; rows 1..7 (o 1).  The arc build's bytes are by the row as well: CMAPE holds
; the tile's 16 kind + slope, and its bytes are CTE's and CTO's at that plus
; j, its row's brightness (the near row's corner row, czt + ZBACK - z, 3..13:
; land.colour), so the window is remade when czt changes too (WZ).  Out: ldCLE
; = 16 o (setup's su_l7 adds it to its row index); WX, WK, WO, VLO, VHI, WE
; (WZ).  In: cxt, czt, ZB, CX.  Clobbers A, X, Y, WM.  Caller: project (PAGE
; 5 around it).
pcol5:  lda cxt
        cmp WX
        beq :+
        jmp @f                     ; (new columns: all anew)
:
        lda WK                     ; o = WK - czt - ZB + 1
        clc
        sbc czt                    ; (C clear: WK - czt - 1)
        sec
        sbc ZB
        clc
        adc #2
        cmp #4
        bcc :+
        lda cxt                    ; (o outside 0..3: all anew, A to WX at @f)
        jmp @f
:
        sta WO
        tax                        ; rows o .. VLO-1
:       cpx VLO
        bcs :+
        txa
        jsr crow
        inx
        bne :-
:       lda WO                     ; and rows VHI+1 .. o+6 (WE = o + 7)
        adc #6                     ; (C set from the CPX: + 7)
        sta WE
        ldx VHI
:       inx
        cpx WE
        bcs :+
        txa
        jsr crow
        jmp :-
:       lda WO                     ; VLO = min(VLO, o), VHI = max(VHI, o + 6)
        cmp VLO
        bcs :+
        sta VLO
:       ldx WE
        dex
        cpx VHI
        bcc @pt
        stx VHI
@pt:    lda WO                     ; ldCLE = 16 o
        asl a
        asl a
        asl a
        asl a
        sta ldCLE
        rts
@f:     sta WX                     ; (A = cxt) WK = czt + ZB; rows 1..7; o 1
        lda czt
        clc
        adc ZB
        sta WK
        lda #1
        sta WO
        sta VLO
        lda #7
        sta VHI
        ldx #1
:       txa
        jsr crow
        inx
        cpx #8
        bne :-
        jmp @pt
        .assert <MAP32 = 0 && (>MAP32 & 3) = 0, error, "MAP32: 1K, aligned (its pages ORed)"
        .assert <CLE = 0 && <CLO + 48 < $100, error, "crow: CLE page-aligned (@se's operand is 16 m); CLO + 48 in its page"
; crow: window row A (m, 0..9): map row (WK - m) & 63, entries 0..NX-2 by CX,
; into CLE + 16 m and CLO + 16 m (self-modifying: @le/@lo's operands the map
; row's 64-byte rows of CMAPE and CMAPO, @se/@so's the window row; arc:
; @le's CMAPE's, @ce/@co's CTE and CTO's by the row's j).  In: A, WK, CX
; (czt).  Out: WM = m.  X kept; clobbers A, Y.  Caller: pcol5.
crow:   sta WM
        asl a
        asl a
        asl a
        asl a
        sta @se+1                  ; CLE + 16 m (CLE's low byte 0)
        clc
        adc #<CLO                  ; CLO + 16 m (with the carry into its page)
        sta @so+1
        lda #>CLO
        adc #0
        sta @so+2
        lda WK
        sec
        sbc WM                     ; (no borrow: WK >= ZFCLIP > m)
        and #MAPN-1                ; z = (WK - m) mod MAPN
        tay
        lsr a
        lsr a
        lsr a
        ora #>MAP32                ; MAP32 + 32 z: page + (z >> 3),
        sta @le+2
        tya
        asl a
        asl a
        asl a
        asl a
        asl a                      ; low byte (z & 7) << 5
        sta @le+1
        txa
        pha
        ldx #NX-2
@c:     ldy CX,x
@le:    lda MAP32,y                ; the tile's colour index: its corner's high
        lsr a                      ; nibble
        lsr a
        lsr a
        lsr a
        tay
        lda DCE,y
@se:    sta CLE,x
        lda DCO,y
@so:    sta CLO,x
        dex
        bpl @c
        pla
        tax
        rts
WX:     .byte $FF                  ; the window's cxt ($FF: none made yet)
WK:     .byte 0                    ; the map row at window row 0
WO:     .byte 0                    ; o: strip 1's near row's window row (strip
                                   ; ns's is o + ns - 1)
VLO:    .byte 0                    ; the rows made: VLO..VHI
VHI:    .byte 0
WE:     .byte 0                    ; o + 7
WM:     .byte 0                    ; crow's m


