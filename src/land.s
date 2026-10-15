; ============================================================================
; land.s -- LAND: a Lander-style landscape on a narrow, double-buffered MODE 1
; screen, with game.s's ship flying over it.  The BBC Micro port of
; proto/land.py (the projection) as proto/frame.py draws it (the strips),
; pixel for pixel.
;
; Building (build.sh).  tools/landgen.py writes the three table images TABLES
; (bank 4), TABLES2 (bank 5) and TABLES7 (bank 7) and tables.inc (their
; addresses and the constants: NX, ZBACK, YSKY, YGND...); tools/gamegen.py
; writes gametab.inc (the game's).  ca65 assembles this file (game.s is
; .included near the end) under src/land.cfg: segment CODE is LAND, loaded at
; $1900; BOOT is LANDS, at $7000; the other segments are code for the banks,
; which build.sh splices into the table images at their addresses.  landsyms.inc
; (the symbols shipb.s needs, L_ before each) is cut from labels.txt; then
; tools/shipgen.py and shipb.s make SHIPB (bank 6), and tools/mkdfs.py writes
; lander.ssd: !BOOT, LAND, LANDS, TABLES, TABLES2, SHIPB, TABLES7.
;
; Starting.  !BOOT selects MODE 1 with every colour black and the cursor off,
; *LOADs LAND and *RUNs LANDS.  LANDS (segment BOOT, the end of this file) finds
; four sideways RAM banks (find_ram), patches each PAGE's write select for the
; board (wpatch), loads each image through $3000 into its bank, closes !BOOT
; (the filing system is then idle: its workspace from $0E00 is LAND's), makes
; the glyphs, narrows the screen, clears screen 0, sets the palette and jumps
; to `go`.  go runs init, hooks the vertical sync event, turns the VIAs' other
; interrupts off, runs G_INIT (bank 5: the game's start) and enters the main
; loop: G_STEP (bank 5: the keys, the flight, the camera), B6_KEYS (bank 6:
; the ship's attitude and place), project, strips, G_PRE (the dots beyond the
; ship), B6_SHIP (the ship, unless crashed: GSHV 0), G_POST (the other dots,
; the map, the status), readout (the frame rate), flip.
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
; register 12) and swaps `back`; strips waits for the sync after the flip
; before its first store.  TOPS and BOTS (64 columns a screen) record, for
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
;   $0D00-$0DC1   ENTL, ENTH: each line's entry in its STAB (lines
;                 YSKY..YGND+1: 97 each)
;   $0E00, $1000, $1200, $1400  STAB for t = 0..3 (437 bytes each)
;   $16C2-$1722   LAH: each line's 2 * (y >> 3)
;   $1740-$17A3   EINL,y for y = YSKY-1..YGND+3 (EINL = $1701): run2's table
;                 offsets by line
;   $1800-$18EF   GLY: the readout's 15 characters, 16 bytes each
;   $1900-$2E66   the code (this file's CODE segment)
;   $2F00         DBUF: shipspan.s's (bank 6), so the code must end below it
;   $3000-$57FF   screen 0; $5800-$7FFF screen 1, LANDS at $7000-$73FB until
;                 init clears it
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
;     and odd lines, by map row * 64 + x), pcol5 at $A000, game.s from $A100,
;     GLY5 $BE00 (the game's letters)
;   bank 6, SHIPB (shipb.s): B6_KEYS $8000, B6_SHIP $8003 and the ship's spans
;   bank 7, TABLES7: R7L, R7H, SYT7 $8200, B1T $9800, CLP7, PINL7, PINR7,
;     LERPQ7 $B100, SYL7, SYH7, LQLO, LQHI, prow7 and its helpers ($B480-
;     $BDB1), PXF7 $BEA0, PXN7 $BF50; su_l7's and satrow's pieces in the
;     tables' spare entries ($80B0, $81B0, $AEB0, $AFB0, $B0B0)
; ============================================================================
        .setcpu "6502"
        .include "tables.inc"

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
        jsr .ident(.sprintf("pg%d", n))
.endmacro

                                   ; (YSKY, YGND: the first and last land
                                   ; lines, tables.inc)
MARGIN  = 0                        ; pixels beyond the bottom row's ends before
                                   ; rounding out to a byte boundary (setup)

ROWA    = $0400
ROWB    = $0500
RTBUF   = $0600
PX      = $0700                    ; the rows' points, far to near: 16 a row
PY      = $0800
HTN     = $07E0                    ; zsh4's: the new row's heights, for hsh
HT      = $0880                    ; the rows' raw heights, 16 a row (project)
CLE     = $0900                    ; pcol5's window of box bytes: 16 a row, even
CLO     = $09A0                    ; and odd lines
TX      = $0A40                    ; the strip's top row's points (0 and np+1:
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
EINL    = $1701                    ; run2's table offsets by line (init's;
                                   ; EINL,x and EINL-1,x in one page)
GLY     = $1800                    ; the readout's characters: 16 bytes each
ENTL    = $0D00-YSKY               ; each line's entry in its STAB: low byte,
ENTH    = $0D61-YSKY               ; and the page within the table (lines
                                   ; YSKY..YGND+1)
TOPS    = $0C00                    ; by screen (+64 for screen 1) and column:
BOTS    = $0C80                    ; the land's highest and lowest line last
CURT    = $0B60                    ; time there, and this frame's
CURB    = $0BA0
STAB    = $0E00
LAH     = $16C2-YSKY               ; each line's 2 * (y >> 3) (lines
                                   ; YSKY..YGND+1)
        .assert YGND+2-YSKY <= 97, error, "LAH, ENTL: 97 lines each"
        .assert <EINL + YGND+2 < $100 && LAH + YGND+2 < EINL + YSKY-1, error, "EINL: in its page, past LAH"
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

SWT     = $9400                    ; init's line tables, in bank 4's free
                                   ; space: two a page, by line (YSKY..YGND+1,
                                   ; 97 lines): one at the page's start (its
                                   ; base in the page before: a read crosses,
                                   ; a cycle more), one 97 on
EXLB    = SWT+97-YSKY              ; run's entry for each line (low; the high
                                   ; by table)
LAHSB0  = SWT+$100+97-YSKY         ; each line's address high byte, by t
LAHSB1  = SWT+$200+97-YSKY
LAHSB2  = SWT+$300+97-YSKY
LAHSB3  = SWT+$400+97-YSKY
EXHB0   = SWT+$400-YSKY            ; run's entry, high byte, by t
EXHB1   = SWT+$500-YSKY
EXHB2   = SWT+$500+97-YSKY
EXHB3   = SWT+$600-YSKY
        .assert RSMT = SWT+$600+97-YSKY, error, "RSMT: SWT's last page, past EXHB3 (landgen's)"
ENTB0   = SWT-YSKY                 ; each line's entry page (ENTH + the
                                   ; table's page) by t
ENTB1   = SWT+$100-YSKY
ENTB2   = SWT+$200-YSKY
ENTB3   = SWT+$300-YSKY
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
rA:     .res 1                     ; (unused)
rp:     .res 2                     ; (unused)
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
; go: LAND's first byte, at its load address.  LANDS jumps here with the four
; banks loaded, bank 4 paged in and write selected, the screen narrowed and
; screen 0 cleared.  Never returns.
        .assert * = $1900, error, "go must be first"
go:     jsr init
        sei                        ; vsync counts vertical syncs: event 4
        lda #<vsync
        sta EVNTV
        lda #>vsync
        sta EVNTV+1
        cli
        lda #14
        ldx #4
        jsr OSBYTE
        lda #$7D                   ; the system VIA's interrupts off except
        sta $FE4E                  ; CA1's (vertical sync): no OS keyboard
        lda #$7F                   ; scan, clock or ADC (game.s scans the keys
        sta $FE6E                  ; itself); the user VIA's all off
        lda #0
        sta back
        jsr setback
        lda vcount
        sta vflip
        sta vlast

        lda #<G_INIT               ; bank 5: the game's start
        jsr call5
loop:   lda #<G_STEP               ; the game: keys, flight, the camera
        jsr call5
        lda #<B6_KEYS              ; bank 6: the ship's attitude and place
        jsr call6
        jsr project
        jsr strips                 ; (waits for the flip before its first store)
        lda #<G_PRE                ; the dots beyond the ship in z
        jsr call5
        lda GSHV                   ; the ship, unless crashed (GSHV 0)
        beq :+
        lda #<B6_SHIP
        jsr call6
:       lda #<G_POST               ; the other dots, the map, the status
        jsr call5
        jsr readout
        jsr flip
        jmp loop

; The vertical sync event handler (EVNTV): vcount += 1.  Flags kept.
vsync:  php
        inc vcount
        plp
        rts

; call6: bank 6's routine at $8000 + A (A = <B6_KEYS or <B6_SHIP), then bank 4
; paged back.  Patches the JSR's low byte.  Clobbers what the routine does; A
; is bank 4's socket after.
call6:  sta @j+1
        PAGE 6
@j:     jsr $8000
        PAGE 4
        rts

; call5: bank 5's routine at $A100 + A (A = <G_INIT, <G_STEP, <G_PRE or
; <G_POST: game.s's jump table), then bank 4 paged back.  As call6.
call5:  sta @j+1
        PAGE 5
@j:     jsr G_INIT
        PAGE 4
        rts

; flip: when FMIN vertical syncs have passed since the last flip, show the
; screen just drawn (`back`) and make the other the one to draw.  Records the
; frame's syncs in dvs (the last 8, dvi the next slot) for the readout; vflip,
; vlast = vcount at the flip.  Falls into setback.  Clobbers A, X.
flip:   lda vcount                 ; (FMIN = 4: 12.5 frames a second at most)
        sec
        sbc vlast
        cmp #FMIN
        bcc flip
        lda #12                    ; CRTC R12: the screen start's high byte
        sta CRTC_IDX               ; ($06 or $0B; R13 is 0 for both: LANDS's)
        lda back
        beq :+
        lda #>($5800/8) - >($3000/8)
:       clc
        adc #>($3000/8)
        sta CRTC_DAT
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
        lda back
        eor #1
        sta back
; setback: scrb ($30 or $58) and sethalf's screen bits (sh_b's operand: 2 *
; back) for `back`.  Clobbers A.
setback:
        lda back
        beq :+
        lda #$28
:       clc
        adc #$30
        sta scrb
        lda back
        asl a
        sta sh_b+1                 ; (sethalf's ORA #: t = 2 * back + half)
        rts

; ---------------------------------------------------------------- init
; init: both screens black ($3000-$7FFF: LANDS with them); the four STABs and
; the line tables (ENTL, ENTH; LAH; in bank 4: LAHSB0-3,
; ENTB0-3, EXLB, EXHB0-3); TOPS, BOTS to nothing drawn; traceb's fill blocks'
; JMPs; EINL; pp to dummy; the camera at tile (40, 30), sixteenths 0; dvs.  No
; OS calls: the tests (test/landsoak.py, test/gametest.py) run it under py65.
; Needs bank 4 paged in and writable.  Clobbers A, X, Y, ptr, tmp.
init:   lda #0
        tay
        sta ptr
        ldx #$30
        stx ptr+1
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        bpl :-                     ; (to $7FFF)
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
        lda #$28
:       clc
        adc #$30
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
        cmp #4
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
        clc                        ; LAHSBt = LAH + $30, $31, $58, $59 (shs)
        adc #$30
        sta LAHSB0,x
        sec
        adc #0                     ; (C set: + 1)
        sta LAHSB1,x
        adc #$28
        sta LAHSB3,x
        sec
        sbc #1
        sta LAHSB2,x
        lda ENTH,x
        ora #>STAB                 ; ENTBt = ENTH + >STAB + 2t
        sta ENTB0,x
        clc
        adc #2
        sta ENTB1,x
        adc #2
        sta ENTB2,x
        adc #2
        sta ENTB3,x
        txa                        ; run's entries (EXLB, EXHBt): an odd line's
        and #1                     ; is 2 bytes before its STA, at the even
        asl a                      ; line's LDA vo, so run enters with A = ve
        sta tmp+1                  ; whatever the first line's parity
        lda ENTL,x
        sec
        sbc tmp+1
        sta EXLB,x
        lda ENTH,x
        sbc #0
        ora #>STAB
        sta EXHB0,x
        clc
        adc #2
        sta EXHB1,x
        adc #2
        sta EXHB2,x
        adc #2
        sta EXHB3,x
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
        lda #<t_back               ; the JMP ending each of traceb's fill blocks
        sta TBLK4+3*TNB+1          ; (landgen's $4C at TBLK4/5 + 3 TNB): t_back
        sta TBLK5+3*TNB+1
        lda #>t_back
        sta TBLK4+3*TNB+2
        sta TBLK5+3*TNB+2
        ldx #YSKY-1                ; EINL: lines 2k-1 and 2k share R2OFF + 3
        lda #R2OFF                 ; (k - YSKY/2): run2's slots; the last
        clc                        ; pair (YGND+2, +3) wraps past 255 and is
:       sta EINL,x                 ; never read
        sta EINL+1,x
        adc #3
        inx
        inx
        cpx #YGND+3
        bcc :-
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

; ---------------------------------------------------------------- project
; project: the block of corners (proto/land.py: project) as rows of points.
; Sets ZB, FACT, RN and nr from czs.  If the map columns (cxt) or rows (czt +
; ZB) differ from last frame's (pkx, pkz): refetches CX and every row's raw
; height into HT (bank 4's MAP via HPZ), or for a step of one row has zsh4
; fetch the new row alone (HTN, SHF: prow7's hsh shifts HT), then bank 5's
; pcol5 remakes the strips' box bytes (CLE, CLO) as needed.  Then, changed or
; not, bank 7's prow7 makes the rows' points (PX, PY: x from B1T and r, y from
; SYT7 by height less the ground's, hgnd, plus eyrow's EYV for CAME), the clip
; planes' rows interpolated by 1 - fz, and np = NX.
; In: cxt, cxs, czt, czs, CAME.  Out: ZB, RN, FACT, nr, np, CX, HT, HTN,
; SHF (0 after), PX, PY, HGV, EYV, pkx, pkz, CLE, CLO, ldCLE; bank 4 paged.
; Clobbers A, X, Y, tmp, rl, rh, syp, lp, MT0, MT1, $8E-$9E.  Called by the
; main loop.
        .assert <PY = 0, error, "PY page-aligned"
.macro PYSE i                       ; (bank 7) corner i's y: SYT7 (syp) by the
        ldy PY+i,x                  ; height in PY + EYV, the camera raised
        lda (syp),y                 ; (C clear on entry; the sum stays within a
        adc EYV                     ; byte, or satrow is used instead)
        sta PY+i,x
.endmacro
.macro PYH i                        ; (bank 7) corner i's y: SYT7 by HT's height
        ldy HT+i,x
        lda (syp),y
        sta PY+i,x
.endmacro
.macro PYHE i                       ; (bank 7) PYH + EYV (C clear on entry)
        ldy HT+i,x
        lda (syp),y
        adc EYV
        sta PY+i,x
.endmacro
; (bank 7) The ends' heights, not y's: between corners 0 and 1, and NX-2 and
; NX-1, of row S by fx (LQP: LERPQ7's row q = cxs), into PY,x and PY+NX-1,x for
; PYSE.  (b | 16) - a - 1 with C clear = b - a + LQOFF, the row's index; the
; table holds lerp - 1 and C is set after, so the ADC gives a + lerp.
.macro EDGESP S
        lda S+1,x
        ora #16
        clc
        sbc S,x
        tay
        lda (LQP),y
        adc S,x
        sta PY,x
        lda S+NX-1,x
        ora #16
        clc
        sbc S+NX-2,x
        tay
        lda (LQP),y
        adc S+NX-2,x
        sta PY+NX-1,x
.endmacro
; (bank 7) The ends' y's: their heights from row S as EDGESP's, then SYT7
; (syp), into PY,x and PY+NX-1,x.  L0, L1: labels for LERPQ7,y loads whose
; operands prow7 patches to the row; blank: (LQP),y.  NC non-blank: C is known
; clear and the first CLC is left out.
.macro EDGEY S, L0, L1, NC
        lda S+1,x
        ora #16
.ifblank NC
        clc
.endif
        sbc S,x
        tay
.ifblank L0
        lda (LQP),y
.else
L0:     lda LERPQ7,y
.endif
        adc S,x
        tay
        lda (syp),y
        sta PY,x
        lda S+NX-1,x
        ora #16
        clc
        sbc S+NX-2,x
        tay
.ifblank L1
        lda (LQP),y
.else
L1:     lda LERPQ7,y
.endif
        adc S+NX-2,x
        tay
        lda (syp),y
        sta PY+NX-1,x
.endmacro
; (bank 7) A clip plane's row, corner CI: its height between rows SA and SB by
; 1 - fz ((lp): LERPQ7's row q = 16 - czs, the EDGESP trick), indexed by X if
; IX.  Corners 0 and NX-1: the height to E0, E3 only; 1 and NX-2: to E1, E2
; and, like the rest, through SYT7 (syp) into PY.
.macro LERPY SA, SB, CI, IX
.if IX
        lda SB+CI,x
        ora #16
        clc
        sbc SA+CI,x
        tay
        lda (lp),y
        adc SA+CI,x
.else
        lda SB+CI
        ora #16
        clc
        sbc SA+CI
        tay
        lda (lp),y
        adc SA+CI
.endif
.if CI = 0
        sta E0
.elseif CI = NX-1
        sta E3
.else
.if CI = 1
        sta E1
.elseif CI = NX-2
        sta E2
.endif
        tay
        lda (syp),y
.if IX
        sta PY+CI,x
.else
        sta PY+CI
.endif
.endif
.endmacro
.macro R7BP NOL                     ; (bank 7) the row's r: rl, rh = R7L, R7H[Y]
.ifblank NOL                        ; (Y = di); NOL non-blank: rh alone
        lda R7L,y
        sta rl
.endif
        lda R7H,y
        sta rh
.endmacro

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
        cmp pkx                    ; (pkx, pkz): HT, CLE, CLO stand, prow7 only
        bne @cx
        lda czt
        clc
        adc ZB
        cmp pkz
        bne @zs
        jmp @p7
@zs:    jsr zsh4                   ; (bank 4) a step of one map row: the new
        bcc @hl                    ; row's heights into HTN, SHF set for prow7's
        jmp @p5                    ; hsh to shift HT, C set; C clear: all anew
@cx:    sta pkx                    ; CX: map x cxt - 5 + XSKIP + i, i = 0..NX-1,
        sec                        ; mod 64 (proto's xs)
        sbc #5-XSKIP
        ldx #0
:       and #63
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
@hp:    and #63
        tay
        lda MRL,y
        sta HPZ,x
        lda MRH,y
        sta HPZ+1,x
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
@p5:    PAGE 5                     ; (bank 5) the land strips' box bytes
        jsr pcol5
@p7:    PAGE 7                     ; (bank 7) the rows' points
        jsr prow7
        PAGE 4
        rts

; ---------------------------------------------------------------- strips
; strips: the frame's strips, top to bottom.  Strip ns (0 .. nr-1) lies
; between rows ns-1 and ns: strip 0 only has its bottom row (row 0) traced;
; strips 1 .. nr-1 are the land's, and the last of them (ns = nr-1, the near
; strip) also paints the ground below the near row from its columns
; (nearpost).  A strip's points: 0 its left margin, 1 .. np the rows', np+1
; its right margin.
; Each column's highest and lowest land line is kept in three sets of 64
; bytes (setTl .. setBh: TOPS, BOTS; TOPS+64, BOTS+64; CURT, CURB): one a
; screen (sidx: the land as last drawn there, two frames back) and one this
; frame's (cidx).  The operand of every site that reads the screen's set or
; writes this frame's is patched here, and the sets are rotated at the end.
; In: back, np, nr, PX, PY (project's), CLE, CLO, ldCLE (pcol5's), vcount,
; vflip.  Out: the screen drawn; the sets; sidx, cidx; xlp, xrp, topa, bota.
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
        cmp #1                     ; wait for the vertical sync after the
        bne @draw                  ; flip, when the screen drawn is no longer
@wait:  lda vcount                 ; the one shown
        cmp vflip
        beq @wait
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

; bclip: the bottom row's line held on the screen.  If setup saw a bottom
; point past YGND (BCL), every entry of (bota) greater than YGND+1 (below the
; screen) is set to YGND+1, so each column's floor is at most YGND+1 (o_zb,
; c_zb) and the lines drawn stay on the screen.  The whole page is
; clamped, not only xl .. xr-1.
; In: BCL, bota.  Clobbers A, Y.  Called by strips.
bclip:  lda BCL
        bne :+
        rts
:       ldy #0
        lda #YGND+1
:       cmp (bota),y
        bcs :+                     ; (at most YGND+1 already: kept)
        sta (bota),y
:       iny
        bne :--
        rts

; setup: the strip's points, boxes and margins, and its bottom row's line.
; Points 1 .. np: strip 0 takes row 0 as its bottom row only (it is only
; traced: its TX, TY, CE and CO are never read); a land strip (ns 1 .. nr-1) takes rows ns-1 (TX, TY)
; and ns (BX, BY) and its boxes 1 .. np-1 from pcol5's window (su_l7, in
; bank 7); BCL counts the bottom points past YGND.  Points 0 and np+1 are the
; margins: x at the byte boundary at or left of the bottom row's first point
; (xl) and at or right of its last (xr), y the end points'; boxes 0 and np
; black.  Then the bottom row is traced into (bota) (traceb, whose RTS is
; this routine's).  In: ns, nr, PX, PY, CLE, CLO, ldCLE, bota.  Out:
; TX, TY, BX, BY, CE, CO (0 .. np+1), xl, xr, BCL, last ($FF for the near
; strip, ns = nr-1), (bota).  Clobbers A, X, Y and traceb's
; (bank 7 paged for su_l7 and bank 4 back: pw7s, pw4s are wpatch's).  Called
; by strips.
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
        beq su_r                   ; (A = 0: strip 0, row 0 as both rows)
        asl a                      ; 16 (ns - 1): the top row's offset in PX,
        asl a                      ; PY (C clear: ns < 16)
        asl a
        asl a
        adc #$F0
        tay
        lda BANKMAP+3              ; bank 7 paged in (as pg7)
        sta ROMCOPY
        sta ROMSEL
pw7s:   bit wrt
        jmp su_l7                  ; (ends at su_m4)
ldCLE:  .byte 0                    ; pcol5's: 16 * its window offset, added to
                                   ; su_l7's CLE, CLO index (data, in the code)
su_qc:    inc BCL                  ; a bottom point past YGND
        bcs su_qb                  ; (always: C from the cmp)
        ; strip 0: row 0 as its bottom row (it is traced only: its TX, TY,
        ; CE and CO are never read, so they are left as they are)
su_r:     tay                      ; Y: the row's offset in PX, PY
        ldx #1
su_q:     lda PX,y                 ; points 1 .. np: the row's
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
su_m4:  lda BANKMAP                ; su_l7's end: bank 4 back (as pg4)
        sta ROMCOPY
        sta ROMSEL
pw4s:   bit wrt
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
        ; boxes 0 and np (the margins') black; 1 .. np-1 the strip's
        lda #0
        sta CE
        sta CO
        sta CE,x
        sta CO,x
su_bot:   jmp traceb               ; the bottom row's line (its RTS returns to
                                   ; strips)

; traceb: the bottom row (BX, BY 0 .. np+1) into (bota), one line a pixel,
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
        sta jvb+2                  ; fills' entry table for it (TENH4 for
        clc                        ; ROWA, TENH5 for ROWB: TENH4 - 4 + page)
        adc #>TENH4-4
        sta tf_h+2
        sta t1_h+2
        sta tx_h+2
        sta tv_h0+2
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
@t0:    lda BY                     ; the pending run: from tcnt at point 0's y
        sta tyv
        ldx #0
        beq t_seg
        .res 34                    ; (padding: keeps the code after it in place)
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
        sta ra2                    ; 2|dy|
        ora terr                   ; |dy| >= 32 or dx >= 64: beyond DQT, DRT
        cmp #64
        bcs t_o
        lda DVH,y                  ; the rows for |dy|: DQT's page (t_dq's
        sta t_dq+2                 ; operand; C clear: 8 on is DRT's, t_dr's),
        adc #>(DRT-DQT)            ; DVL the low byte, | dx the index
        sta t_dr+2
        lda DVL,y
        ora terr
        tay
t_dq:   lda DQT,y                  ; q2 = dx div |dy|; q = q2 >> 1 = dx div
        sta rq2                    ; 2|dy| (C: q2 odd)
        lsr a
        sta rq
t_dr:   lda DRT,y                  ; r2 = 2 (dx mod |dy|): t_rr's operand; rem
        sta t_rr+1                 ; = dx mod 2|dy| = r2 / 2, + |dy| if q2 is
        bcc :+                     ; odd (C set: (r2 + 2|dy| + 1) / 2)
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
        lda TENL,y                 ; for the runs after the first
        sta jv0+1
tv_h0:  lda TENH4,y                ; (operand: the row's table)
        sta jv0+2
        txa                        ; the pending run's length - 1 (C clear: X
        sbc tcnt                   ; > tcnt)
        tay
        bmi t_fl1                  ; (more than TNB: the loop)
        lda TENL+1,y               ; tf_j: the fill, length Y + 1
        sta tf_j+1
tf_h:   lda TENH4+1,y              ; (operand: the row's table)
        sta tf_j+2
        clc                        ; (t_back's ADC)
        ldy dva                    ; Y: the steps left, this one included
        lda tyv
tf_j:   jmp t_back                 ; (operand: the fill, which jumps to t_back)
        .res 1                     ; (padding: keeps the code after it in place)
t_fl1:  ldy dva                    ; the first run longer than TNB: the loop,
        jmp t_flo                  ; then t_back
t_one:  lda terr                   ; |dy| 1: the pending run to x0 + ceil(dx /
        lsr a                      ; 2) (C: dx odd)
        adc BX,x
        tax
        sbc tcnt                   ; length - 1 (C clear: X > tcnt)
        tay
        bmi t_fl1                  ; (more than TNB: the loop)
        lda TENL+1,y               ; t1_j: the fill, length Y + 1
        sta t1_j+1
t1_h:   lda TENH4+1,y              ; (operand: the row's table)
        sta t1_j+2
        ldy #1                     ; one step: t_back steps y and ends at
        lda tyv                    ; t_last
t1_j:   jmp t_back                 ; (operand: the fill)
        .res 1                     ; (padding: keeps the code after it in place)
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
        lda TENL,y                 ; tx_j: the fill, length Y
        sta tx_j+1
tx_h:   lda TENH4,y                ; (operand: the row's table)
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
        .res 10                    ; (padding: keeps the code after it in place)
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


; divs, divt: the division rungs falls back on when RDIV's tables cannot
; serve (a >= 32 or D >= 64).  In: dva = a, ra2 = 2a, dvd = D.  Out: rq, rrem
; = D div 2a, D mod 2a; rq2, rr2 = D div a, 2 (D mod a).  divt looks them up
; (DQT, DRT + 64 a + D: a < 32, D < 64; DVH, DVR their rows' pages, DVL the
; row's low byte); divs takes that way when a < 32 and D < 64 (which its
; callers have ruled out, so in practice never), else divides by repeated
; subtraction (a <= 64: 2a and 2 rem in a byte) and dv2 derives rq2, rr2.
; Clobbers A, Y; divt patches its own operands (@q, @r).  Called by rg_rsl,
; rg_lsl.
divs:   lda dva
        cmp #32
        bcs @sub
        lda dvd
        cmp #64
        bcc divt
@sub:   lda dvd                    ; Y, A = D div 2a, D mod 2a
        ldy #0
:       cmp ra2
        bcc :+
        sbc ra2
        iny
        bne :-
:       sty rq
        sta rrem
        jmp dv2
divt:   ldy dva
        lda DVH,y                  ; the rows for a: DQT's page, DRT's page,
        sta @q+2                   ; the low byte | D
        lda DVR,y
        sta @r+2
        lda DVL,y
        ora dvd
        tay
@q:     lda DQT,y                  ; q2 = D div a; q = q2 >> 1 (C: q2 odd)
        sta rq2
        lsr a
        sta rq
@r:     lda DRT,y                  ; r2 = 2 (D mod a); rem = r2 / 2, + a if q2
        sta rr2                    ; is odd (C set: (r2 + 2a + 1) / 2)
        bcc :+
        adc ra2
:       lsr a
        sta rrem
        rts
dv2:    asl a                      ; from q, rem: 2D = 2q (2a) + 2 rem, so q2,
        sta rr2                    ; r2 = 2q, 2 rem, or 2q + 1, 2 rem - 2a if
        lda rq                     ; rem >= a
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
; and np+1): LO = HI = xl, xr, no bytes.  All the rungs' bytes must fit the
; page (alloc is stepped as a byte); a reader of RTP + x + 1 for a rung in a
; column goes no lower than alloc - 3, so from RTBUF+5 the low byte never
; wraps below.  A rung with a <= RFA and D < 16 is filled from tables
; (rfastr, rfastl: bank 4); else q, rem = D div 2a, mod and q2, r2 = D div a,
; 2 (D mod a) (RDIV: DQT, DRT for a < 32, D < 64; divs otherwise), the first
; line yt + q + (rem > 0), each next q2 on, or q2 + 1 when E += r2 carries (E
; = 255 - e, e how far the next step is short of a line, in 2a'ths).
; In: TX, TY, BX, BY (0 .. np+1), xl, xr.  Out: LO, HI (0 .. np+1),
; RTPL (1 .. np), RTBUF, alloc, rtp+1 = RTBUF's page.  Clobbers A, X, Y, tj,
; dva, dvd, ra2, rq, rq2, rrem, rr2.  Called by strips (strips 1 .. nr-1).
; RDIV slow: D = BY,x - TY,x into dvd; to `slow` if a >= 32 or D >= 64, else
; q2, q, r2 by DQT, DRT (the two LDAs' operands patched for a's rows),
; leaving A = e (2a - rem, or 0 when rem = 0), C = (rem > 0), rq, rq2, rr2.
; In: X the rung, dva = a, ra2 = 2a.
.macro RDIV slow
        lda BY,x                   ; D
        sec
        sbc TY,x
        sta dvd
        ldy dva
        cpy #32
        bcs slow
        cmp #64
        bcs slow
        lda DVH,y                  ; the rows for a: DQT's page (C clear: 8 on
        sta :+ + 2                 ; is DRT's), DVL the low byte, | D
        adc #>(DRT-DQT)
        sta :++ + 2
        lda DVL,y
        ora dvd
        tay
:       lda DQT,y                  ; q2 = D div a; q = q2 >> 1 (C: q2 odd)
        sta rq2
        lsr a
        sta rq
:       lda DRT,y                  ; r2 = 2 (D mod a); rem = r2 / 2, + a if q2
        sta rr2                    ; is odd (C set: (r2 + 2a + 1) / 2)
        bcc :+
        adc ra2
:       lsr a                      ; rem (C clear if rem = 0)
        beq :+                     ; e = 2a - rem (C set after), or 0
        eor #$FF
        sec
        adc ra2
:
.endmacro
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
        tay                        ; (Y = a: rfastr's)
        lda TX,x
        sta LO,x
        eor #$FF                   ; RTPL = alloc - LO - 1
        clc
        adc alloc
        sta RTPL,x
        jmp rfastr                 ; bank 4: by its tables if a <= RFA and D <
rg_lft:   sta LO,x                 ; 16, else back to rg_rdr with ra2 = 2a
        eor #$FF                   ; leaning left: pixels xb .. xt-1; RTPL =
        adc alloc                  ; alloc - LO - 1 (C clear: the bcc)
        sta RTPL,x
        sec
        lda TX,x
        sta HI,x
        sbc BX,x                   ; a = xt - xb
        sta dva
        tay                        ; (Y = a: rfastl's)
        jmp rfastl                 ; bank 4: by its tables if a <= RFA and D <
rg_rdr:   RDIV rg_rsl              ; 16, else back to rg_rdl with ra2 = 2a
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
        .res 3                     ; (padding: keeps the code after it in place)
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
rg_nx:    ldx tj                   ; the next rung, to np
        inx
        cpx #NX+1
        bcs :+
        jmp rg_r
:       rts
rg_lslj:  jmp rg_lsl               ; (rg_rdl's slow way, a trampoline)
        .res 3                     ; (padding: keeps the code after it in place)
rg_rdl:   RDIV rg_lslj
rg_lst:   RSET                     ; (A: the first line; C clear)
        ldy dva                    ; leaning left: pixel xt-1's at Y = a - 1,
        dey                        ; then down to Y = 0
        sta (alloc),y
        beq rg_ld
rg_ls:    tax                      ; as rg_rs (C clear: from the last line's
        lda rrem                   ; add, the lines within a byte)
        adc rr2
        bcs :+
        sta rrem
        txa
        adc rq2
        dey
        sta (alloc),y
        bne rg_ls
        beq rg_ld
:       adc dvd
        sta rrem
        txa
        adc rq
        dey
        sta (alloc),y
        bne rg_ls
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
LAYPAD  = 102
        .res LAYPAD

; ---------------------------------------------------------------- columns
; cols: draw a land strip's byte columns, xl/4 .. xr/4-1, left to right.  A
; column runs from its top row's highest line (mn) down to the line before its
; floor (its bottom row's lowest line, whose pixels are the strip below's; flr1,
; the run's end, is the floor, or the floor + 1 in the near strip when the floor
; is not level there, flr then the floor: nearpost blacks line flr's ground),
; and is drawn as one of:
;   - one box (no rung in it: c_lo fails): the top zone when the top is not
;     level (zone1: lines mn .. mx-1, the pixels at or below their top-row
;     line), then run2 from mx (c_r1);
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
; patched.  Clobbers A, X, Y and the column variables (x4, coff, scrh, ri, mn,
; mx, flr, flr1, ys, msk, ve, vo, zp_, bpos, ...).  Called by strips (@draw)
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
        bpl @lvk
        inx
@lvk:   cpx #$FF                   ; operand: the kind patched last ($FF: none
        beq @lvd                   ; yet); patched only when it changes
        stx @lvk+1
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
@lvd:
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
; c_lim's), and the record choice is patched for it: c_rec JMP recordc or
; c_srx, o_rec and ob_rj JMP record or o_nr (low bytes only: record and o_nr
; share a page).  In: A = x4; ph_lo and ph_hi's operands (cols').  Clobbers
; X, Y.  Called by cols and c_lim.
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
ph_n:   ldy #<o_nr                 ; (>o_nr = >record: asserted below)
        sty o_rec+1
        sty ob_rj+1
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
        .assert >record = >o_nr, error, "record, o_nr: one page (phase patches the low byte only)"
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
c_dbl:  cmp LO+2,x
        bcs c_d3
        bvs :+
        jmp s2v                    ; (ends at c_np)
:       jsr split2
        jmp c_next
c_d3:   bvs :+
        lda mx                     ; a level top: mn and each pixel's top are mx
        sta mn
        sta ys
        sta ys+1
        sta ys+2
        sta ys+3
:       jsr slow
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
record: ldx DIV4,y                 ; the column, x4 / 4 (DIV4: landgen's)
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
c_z1:    jmp zone1                  ; (c_on's too)

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
rc_h:   lda LAHSB0,x               ; (page: sethalf's, the screen and half)
        sta zp_+1
        txa
        and #7
        sta zp_
        ldy coff
        lda #0
        sta (zp_),y
        ldy x4
        jmp c_rd
rc_r:   dex                        ; lines TOPS .. mx-1, black
        ldy mx
        lda #0
        sta ve
        sta vo
        jsr run
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
        bcs c_split                 ; LO <= x4 + 3
; o_nr (c_one, c_on): the column is one box, ri-1: the top zone if the top is
; not level (V set: zone1, back to c_r1x with X = mx), then lines mx .. flr1-1
; by run2 with RVE, RVO = box ri-1's bytes (set whenever ri moves, c_rix and
; c_ri, and by c_ld; fr and fe_r set them too, but only in a column rung ri is
; in, and ri moves on before the next one-box column).  Then c_next.
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
pX:     cpx #$FF                   ; operand: the last X (je, jo already its)
        beq pY
        stx pX+1
        lda EINL,x                 ; the first even line at or after X
        sta je+1
        lda EINL-1,x                ; the first odd
        sta jo+1
pY:     cpy #$FF                   ; operand: the last Y (its RTSes in place);
        beq pY_k                   ; sethalf makes it t, below YSKY
        sty pY+1
        lda #OP_STAY               ; the last RTSes back.  After sethalf the
pr0:    sta $FFFF                  ; page is this half's and the offset the last
pr1:    sta $FFFF                  ; run's: still a slot's opcode, so harmless
        lda #OP_RTS
        ldx EINL,y
        stx pr0+1
pp0:    sta $FF00,x                ; (page: TPEt, sethalf's)
        ldx EINL-1,y
        stx pr1+1
pp1:    sta $FF00,x                ; (TPOt)
pY_k:   lda #0                     ; operand: RVE, the even lines' byte
RVE     = pY_k+1
        ldy coff
je:     jsr $FFFF                  ; the even lines (TPEt, EINL,x)
rvo:    lda #0                     ; operand: RVO, the odd lines' byte
RVO     = rvo+1
jo:     jsr $FFFF                  ; the odd lines (TPOt, EINL-1,x)
; c_next: the column is done.  c_np (3 bytes, cols' by kind): LDA x4 / CLC, on
; into c_nd1 for the next column; in the near strip JMP nearpost, which comes
; back to c_nd or c_xe (np_n).  fr (while it JSRs run2) and s2v (while it JSRs
; fsplit) make it an RTS.
c_next:
c_np:   jmp nearpost
c_nd1:  adc #4                     ; (C clear) x4 + 4: the next column
        sta x4
c_xe:   cmp #0                     ; operand: the phase's end (phase's)
        beq c_lim
c_xt:   tay
        asl a                      ; coff = 8 * column mod 256
        sta coff
; c_coly: the column at Y = x4 (coff set).  V is clear here: c_nd1's and np_n's
; ADC can set it only for x4 = 128, which comes through c_lim and sethalf's
; CLV.  ri is the first rung not wholly left of the column (its HI > x4,
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
o_lv:   sta flr1                   ; a level floor, A: the run ends at it (as
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
        lda #$88                   ; pixel 0
        cpx mn
        bne oz_mu
oz2:    ldx ROWA+2,y
        lda #$CC                   ; pixels 0, 1
        cpx mn
        bne oz_mu
        lda #$EE                   ; pixels 0, 1, 2
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
; ri advances to the first rung with HI > x4 (rung np+1, the right margin,
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
np_b:     ldx x4                     ; CURB = the floor (A), or YGND if it is
        ldy DIV4,x                 ; YGND+1
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
np_h:   lda LAHSB0,x               ; (page: sethalf's)
        sta zp_+1
        ldy coff
        lda #0
        sta (zp_),y
        txa                        ; (flr1, on the screen)
        ldx x4
        ldy DIV4,x
pB4:    sta CURB,y                 ; (strips: this frame's set)
pB5:    cmp BOTS,y                 ; (strips: this screen's set)
        bcs np_n                   ; BOTS at or above the floor: nothing below
        adc #1                     ; (C clear) the floor + 1
        tax
pB6:    cmp BOTS,y
        bne np_r
        lda LAH,x                  ; one line, BOTS = flr + 1: black here
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
pB8:    lda BOTS,y                 ; lines flr + 1 .. BOTS black
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
np_h2:    lda LAHSB0,x             ; line X: the pixels at or below their bottom
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
np_h3:  lda LAHSB0,x               ; YGND): masked then, else the byte black
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
; rpv: c_ri (c_rix does the same inline).
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
; Clobbers A, X.  Called by cols, c_lim and gn_d.
sethalf:
sh_b:   ora #0                     ; operand: 2 * back (setback's)
        tay                        ; Y = t
        lda shs,y
        sta scrh
        clv
        lda enthh,y               ; ENTBt's page (one low byte for all four)
        sta r_eh1+2
        lda exhl,y                 ; EXHBt
        sta r_eh2+1
        lda exhh,y
        sta r_eh2+2
        lda #OP_STAY               ; run2's RTSes back in the last pages
        ldx pr0+1
sh_1:   sta TPE0*256,x             ; (page: the last call's tpe)
        ldx pr1+1
sh_2:   sta TPO0*256,x             ; (the last call's tpo)
        sty pY+1                   ; (t: no end line matches)
        lda tpe,y                  ; the even lines' page
        sta pr0+2
        sta pp0+2
        sta je+2
        sta sh_1+2
        lda tpo,y                  ; the odd lines'
        sta pr1+2
        sta pp1+2
        sta jo+2
        sta sh_2+2
        lda lahsh,y               ; LAHSBt's page (one low byte for all four)
        sta fs_h+2
        sta z1_h+2
        sta np_h+2
        sta np_h2+2
        sta np_h3+2
        sta rc_h+2
        sta sl_h+2
        rts
zbt0:   .byte $85, $D0             ; ob_st, zb_st by kind (cols): STA flr1,
zbt1:   .byte flr1, 3              ; BNE +3 (ob_n, zb_n: past the JMP after)
        .assert ob_n = ob_st+5 && zb_n = zb_st+5, error, "ob_n, zb_n: 3 bytes past ob_st, zb_st's branch (zbt1)"
npt0:   .byte $A5, $4C             ; c_np by kind (cols): LDA x4 / CLC, JMP
npt1:   .byte x4, <nearpost        ; nearpost
npt2:   .byte $18, >nearpost
shs:    .byte $30, $31, $58, $59   ; scrh by t: the screen's page + the half
tpe:    .byte TPE0, TPE1, TPE2, TPE3 ; run2's store pages by t (landgen's)
tpo:    .byte TPO0, TPO1, TPO2, TPO3
exhl:   .byte <(EXHB0), <(EXHB1), <(EXHB2), <(EXHB3) ; run's EXHBt (init's)
exhh:   .byte >(EXHB0), >(EXHB1), >(EXHB2), >(EXHB3)
        .assert <(LAHSB0) = <(LAHSB1) && <(LAHSB0) = <(LAHSB2) && <(LAHSB0) = <(LAHSB3), error, "LAHSB0-3: one low byte (sethalf patches pages only)"
lahsh:  .byte >(LAHSB0), >(LAHSB1), >(LAHSB2), >(LAHSB3) ; LAHSBt's page
        .assert <(ENTB0) = <(ENTB1) && <(ENTB0) = <(ENTB2) && <(ENTB0) = <(ENTB3), error, "ENTB0-3: one low byte (sethalf patches pages only)"
enthh:  .byte >(ENTB0), >(ENTB1), >(ENTB2), >(ENTB3) ; run's ENTBt page
; MASKB,n: the pixels whose bit is set in n (pixel i, 0 leftmost, is $88 >> i);
; MASKN,n the rest (nearpost's)
MASKB:  .byte $00, $88, $44, $CC, $22, $AA, $66, $EE
        .byte $11, $99, $55, $DD, $33, $BB, $77, $FF
MASKN:  .byte $FF, $77, $BB, $33, $DD, $55, $99, $11
        .byte $EE, $66, $AA, $22, $CC, $44, $88, $00

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
        clc
        lda TX,x                   ; bpos at the top: TX - x4 clamped to 0..4
        sbc x4                     ; (CLMP1,d = d + 1 clamped, landgen's)
        tay
        ldx CLMP1,y
fs_w:   lda coff                   ; the walker's row: (zp_),y, Y its line
        sta zp_
        ldy mx
fs_h:   lda LAHSB0,y               ; (page: sethalf's)
        sta zp_+1
        lda RSMT,y                 ; the row's first line - 1
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
        lda RSMT,y
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
        and #$88                   ; pixel 0 from box X-1
        eor BE
        sta BE+1
        tya
        and #$CC                   ; pixels 0, 1
        eor BE
        sta BE+2
        tya
        and #$EE                   ; pixels 0, 1, 2
        eor BE
        sta BE+3
fs_co:  lda CO-1,x                 ; the odd bytes likewise
        sta BO+4
        lda CO,x
        sta BO
        eor BO+4
        beq fs_oe
        tay
        and #$88
        eor BO
        sta BO+1
        tya
        and #$CC
        eor BO
        sta BO+2
        tya
        and #$EE
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
z1_h:   lda LAHSB0,x               ; line X (page: sethalf's)
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
        lda #$11                   ; pixel 3
        cpx mn
        bne oz_m
oz1b:   ldx ROWA+1,y
        lda #$33                   ; pixels 2, 3
        cpx mn
        bne oz_m
        lda #$77                   ; pixels 1, 2, 3
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
        clc
        lda TX,x                   ; Y = bpos at the top: TX - x4, clamped 0..4
        sbc x4
        tax
        ldy CLMP1,x
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
sp_zd:  tya                        ; X = bpos: the walker from mx
        tax
        jmp fs_w
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
sl_h:   lda LAHSB0,x               ; (page: sethalf's)
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
        clc
        lda BX,x                   ; p1 (CLMP1,d = d + 1 clamped to 0..4)
        sbc x4
        tay
        lda CLMP1,y
        sta p1
        clc
        lda TX,x                   ; p0
        sbc x4
        tay
        lda CLMP1,y
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

LM:     .byte $00, $88, $CC, $EE, $FF ; LM,n: the n leftmost pixels

; run: lines X .. Y-1 (X < Y) of the column, ve on even lines and vo on odd,
; through the STAB for the screen and half (init's: for each line STA line,Y,
; then LDA vo after an even line and TXA after an odd).  A JMP to line X's
; entry (EXLB, EXHBt; an odd line's entry is the LDA vo before its STA, so A
; need only be ve) with A = X = ve and Y = coff; back by an RTS planted over
; line Y's STA opcode (ENTL, ENTBt), whose address pp keeps so the next run can
; put the STA back (init points pp at dummy first).  In: X, Y, ve, vo, coff;
; r_eh1, r_eh2's operands (sethalf's).  Clobbers A, X, Y.  Called by rc_r,
; np_r, split2 and gn_d.
run:    lda EXLB,x                 ; line X's entry
        sta r_j+1
r_eh2:  lda EXHB0,x                 ; (operand: EXHBt, sethalf's)
        sta r_j+2
        ldx #0
        lda #OP_STAY               ; the last RTS back
        sta (pp,x)
        lda ENTL,y                 ; line Y's entry: the RTS
        sta pp
r_eh1:  lda ENTB0,y                ; (page: ENTBt, sethalf's)
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
recordc: ldx DIV4,y
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

; ---------------------------------------------------------------- readout
; readout: the frame rate at the top left of the screen being drawn, character
; row 2 (the game's area), eight characters "TU.t FPS": flip records each
; frame's vertical syncs in dvs (the last eight frames); their sum s gives
; FPSL/FPSH + s = 4000 / s rounded, the rate in tenths (eight frames at 50
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
:       tax
        lda FPSL,x                 ; fps10 = 4000 / s
        sta fps10
        lda FPSH,x
        sta fps10+1
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
        sta ptr                    ; ptr = scrb * 256 + $400 + 16 tcol (row 2:
                                   ; 512 bytes a row)
        lda scrb
        clc
        adc #4
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
fps10:  .res 2                     ; readout's: the rate in tenths
fpson:  .byte 1                    ; the readout on (game.s's F toggles it)
BANKMAP: .byte 4, 5, 6, 7          ; the socket of each bank 4..7 (find_ram's;
                                   ; these are the defaults)
wrt:    .byte 0                    ; (pg4..pg7's BIT operand on a plain machine)
; pg4..pg7 (PAGE 4..7): bank 4+k's socket (BANKMAP) paged in for reads, ROMCOPY
; kept in step, and selected for writes: pwN is BIT wrt, three bytes that
; wpatch makes STA WRSEL_WATFORD + the socket or STA WRSEL_SOLIDISK when
; find_ram found such a board (setup's inline pagings pw7s, pw4s likewise).
; Out: A = the socket; X, Y kept; the flags the
; BIT's (wrt is 0: Z set, N and V clear) or, on a patched board, the LDA's (N
; and Z as the socket).
.repeat 4, k
        .ident(.sprintf("pg%d", k+4)):
        lda BANKMAP+k
        sta ROMCOPY
        sta ROMSEL
        .ident(.sprintf("pw%d", k+4)):
        bit wrt
        rts
.endrepeat
dvs:    .res 8                     ; flip's: the last eight frames' vertical
                                   ; syncs (init zeroes them)
dvi:    .res 1                     ; the next entry
vlast:  .res 1                     ; vcount at the last flip
tcol:   .res 1                     ; putg's column (readout's); glyphs' counter

        .assert * <= $2F00, error, "code over bank 6's DBUF ($2F00, shipspan.s's; the screen is from $3000)"

; ---------------------------------------------------------------- s2v
; s2v (bank 4, its free space at $B600, $B700, $B800: three pieces of up to
; $6F bytes, the first R2OFF bytes of run2's store pages TPO0-2, before their
; first entry): a column two rungs split, ri and ri+1, whose top is level
; (c_dbl's V clear).  Boxes L, M, R are ri-1, ri, ri+1.  First fsplit draws
; the whole column from mx to the floor as rung ri+1 splits it (M left of it,
; R right: fs_c, or fs_new first when ri+1 is not the rung its tables are
; for); c_np is made an RTS meanwhile so fsplit's exits (ff_d and the rest
; jump to c_np) return here.  Then L is written over the pixels left of rung
; ri, line by line from mx: rung ri's transitions in the column come from mktr
; (TRL the lines, TRB the mask of pixels left of it below each, ended by $FF;
; bpos2 the mask at the top), and each stretch between transitions is filled
; read-modify-write with L's bytes (le even lines, lo2 odd) in the mask.  In:
; X = ri, mx, flr1, lastri, CE, CO, scrh, coff, LAH, and fsplit's and mktr's.
; Out: through c_np (JMP: cols' next column).  Clobbers A, X, Y, le, lo2,
; bpos2, kb, tj, zp_, and fsplit's and mktr's.  Caller: c_dbl (JMP).
        .segment "B4V1"
s2v:    lda CE-1,x                 ; L's bytes
        sta le
        lda CO-1,x
        sta lo2
        lda #0                     ; rung ri's transitions into TRL, TRB from 0;
                                   ; A = its mask at the top
        jsr mktr
        sta bpos2
        lda #0
        sta kb                     ; (TRL's index)
        lda c_np                   ; c_np an RTS while fsplit runs: its JMP c_np
                                   ; returns to s2ov
        pha
        lda #OP_RTS
        sta c_np
        ldx ri
        inx
        cpx lastri                 ; rung ri+1: fsplit's tables already its
                                   ; (fs_c), or made (fs_new)
        bne :+
        jsr fs_c
        jmp s2ov
:       jsr fs_new
s2ov:   pla                        ; c_np's opcode back
        sta c_np
        lda #0
        sta zp_                    ; ((zp_),y addresses the line: zp_+1 its
                                   ; page, Y its offset)
        ldx mx                     ; from the top, if above the floor
        cpx flr1
        bcs s2_d
        ldy kb
        jmp s2_c
s2_d:   jmp c_np
        .segment "B4V2"
s2_c:   txa                        ; (X: the line) the mask below the
                                   ; transitions at or above it
        cmp TRL,y
        bcc s2_e
:       lda TRB,y
        sta bpos2
        iny
        txa
        cmp TRL,y
        bcs :-
s2_e:   sty kb
        lda TRL,y                  ; it ends at the next transition or the floor
        cmp flr1
        bcc :+
        lda flr1
:       sta tj
        lda bpos2
        beq s2_n                   ; (none left of the rung: nothing to write)
        jmp s2_l
s2_n:   ldx tj                     ; on from the stretch's end
        cpx flr1
        bcs s2_x
        ldy kb
        jmp s2_c
s2_x:   jmp c_np
        .segment "B4V3"
s2_l:   lda LAH,x                  ; lines X..tj-1: L into the mask's pixels
        clc
        adc scrh                   ; the line's page: LAH (2 * (y >> 3)) + the
                                   ; screen's and half's
        sta zp_+1
        txa
        and #7
        ora coff                   ; Y: the line in its row | 8 * column
        tay
        txa
        lsr a
        bcs s2_o
s2_v:   lda (zp_),y                ; an even line
        eor le
        and bpos2
        eor (zp_),y
        sta (zp_),y
        iny
        inx
        cpx tj
        beq s2_m
s2_o:   lda (zp_),y                ; an odd line (a row's last line is odd: the
                                   ; row test follows)
        eor lo2
        and bpos2
        eor (zp_),y
        sta (zp_),y
        iny
        inx
        cpx tj
        beq s2_m
        txa
        and #7
        bne s2_v
        inc zp_+1                  ; the next character row: two pages on, Y
                                   ; back to the column
        inc zp_+1
        ldy coff
        jmp s2_v
s2_m:   jmp s2_n

; ---------------------------------------------------------------- LANDS
; LANDS: the start-up, a separate file *RUN at $7000 by !BOOT (which has set
; MODE 1, the palette all black and the cursor off, and *LOADed LAND at $1900).
; It runs one time: the sideways banks are found (find_ram) and pg4..pg7's
; write selects patched for the board (wpatch); the four bank files are
; *LOADed at $3000 in turn and copied up (ldbank: TABLES7 to bank 7, SHIPB to
; 6, TABLES2 to 5, TABLES to 4, which is left paged in); the EXEC file is
; closed; the readout's and the game's glyphs are made (glyphs, glyphs5); the
; CRTC narrows the screen to 64 bytes by 20 rows; the shown screen is cleared
; and the palette set; then LAND's `go`.  LANDS sits at $7000..$73FB, inside
; screen 1 ($5800..$7FFF), which init clears: nothing returns here.
        .segment "BOOT"
start:  lda ROMCOPY                ; the ROM in at entry: find_ram restores it
        sta old_bank
        jsr find_ram               ; BANKMAP, board; C set: under four banks
        bcc :+
        jmp no_ram
:       jsr wpatch
        ldx #<cmd_load7            ; the banks, 7 down to 4 (4 is left paged in)
        ldy #>cmd_load7
        lda #BANK7
        jsr ldbank
        ldx #<cmd_load3
        ldy #>cmd_load3
        lda #BANK3
        jsr ldbank
        ldx #<cmd_load2
        ldy #>cmd_load2
        lda #BANK2
        jsr ldbank
        ldx #<cmd_load
        ldy #>cmd_load
        lda #BANK
        jsr ldbank
        lda #119                   ; OSBYTE 119: close the EXEC file (!BOOT).
        jsr OSBYTE                 ; No filing system call follows, so its
                                   ; workspace from $0E00 (and the MOS's pages
                                   ; $0400..$0DFF) is LAND's
        jsr glyphs                 ; GLY (the readout's)
        PAGE 5                     ; GLY5 (the game's labels: in bank 5)
        jsr glyphs5
        PAGE 4
        ldx #0                     ; the CRTC: 64 bytes by 20 rows, centred
:       lda crtc_regs,x
        sta CRTC_IDX
        lda crtc_regs+1,x
        sta CRTC_DAT
        inx
        inx
        cpx #crtc_end-crtc_regs
        bne :-
        lda #$30                   ; screen 0 ($3000..$57FF, the one shown)
        sta ptr+1                  ; cleared (the loads went through it, unseen
        ldy #0                     ; with the palette black), then the palette
        sty ptr
        tya
:       sta (ptr),y
        iny
        bne :-
        inc ptr+1
        ldx ptr+1
        cpx #$58
        bne :-
        ldx #0
:       lda vdu_init,x
        jsr OSWRCH
        inx
        cpx #vdu_end-vdu_init
        bne :-
        jmp go

cmd_load: .byte "LOAD TABLES 3000", 13
cmd_load3: .byte "LOAD SHIPB 3000", 13
cmd_load7: .byte "LOAD TABLES7 3000", 13
cmd_load2: .byte "LOAD TABLES2 3000", 13

; ldbank: the *LOAD command at Y:X (OSCLI: a file to $3000, 16K at most: LANDS
; itself is at $7000), then $3000..$6FFF copied to $8000..$BFFF of bank A
; (4..7), whose socket (BANKMAP) is paged in and write selected (selwr, with
; interrupts off) and left so.  Clobbers A, X, Y, ptr, tmp.  Caller: start.
ldbank: pha
        jsr OSCLI
        pla
        tax
        lda BANKMAP-4,x
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
        rts

vdu_init:                          ; VDU 19,l,p,0,0,0: logical 1 cyan (6), 2
                                   ; magenta (5), 3 yellow (3)
        .byte 19, 1, 6, 0, 0, 0
        .byte 19, 2, 5, 0, 0, 0
        .byte 19, 3, 3, 0, 0, 0
vdu_end:

crtc_regs:                         ; (register, value) pairs
        .byte 1, 64                ; R1: 64 characters displayed
        .byte 2, 90                ; R2: horizontal sync, centring the 64
        .byte 6, 20                ; R6: 20 rows displayed
        .byte 7, 28                ; R7: vertical sync position, centring the 20
        .byte 12, >($3000/8)       ; R12, R13: the start, $3000 (screen 0)
        .byte 13, <($3000/8)
        .byte 10, $20              ; R10: cursor off
crtc_end:

; glyphs: the readout's characters, GLY: for each of gchars (16 bytes a
; character, at GLY + 16 * its index), its definition read by OSWORD 10 (8 rows
; of 8 pixels at oswblk+1..8) and turned into MODE 1 bytes in colour 3 (both
; colour bits of each pixel set): the left 4 pixels of each row to bytes 0..7,
; the right 4 to bytes 8..15.  Clobbers A, X, Y, tcol (the character count),
; tmp, oswblk.  Caller: start.
glyphs: ldx #0
@c:     stx tcol
        lda gchars,x
        sta oswblk
        lda #10                    ; OSWORD 10: read the character's definition
        ldx #<oswblk
        ldy #>oswblk
        jsr OSWORD
        lda tcol
        asl a
        asl a
        asl a
        asl a
        tax                        ; X = 16 * the index
        ldy #0
@l:     lda oswblk+1,y             ; row Y: the high nibble (the left 4 pixels)
        and #$F0                   ; in both halves of the byte: colour 3 where
                                   ; the pixel is set
        sta tmp
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp
        sta GLY,x
        lda oswblk+1,y             ; the low nibble (the right 4) likewise, 8 on
        and #$0F
        sta tmp
        asl a
        asl a
        asl a
        asl a
        ora tmp
        sta GLY+8,x
        inx
        iny
        cpy #8
        bne @l
        ldx tcol
        inx
        cpx #gchars_end-gchars
        bne @c
        rts
gchars: .byte "0123456789. FPS"    ; (G_DOT 10, G_SP 11, G_F 12: readout's)
gchars_end:
; glyphs5: the same for the game's letters, lchars, into GLY5 ($BE00 in bank 5:
; paged in and write selected by the caller).  Caller: start.
glyphs5:
        ldx #0
@c:     stx tcol
        lda lchars,x
        sta oswblk
        lda #10
        ldx #<oswblk
        ldy #>oswblk
        jsr OSWORD
        lda tcol
        asl a
        asl a
        asl a
        asl a
        tax
        ldy #0
@l:     lda oswblk+1,y
        and #$F0
        sta tmp
        lsr a
        lsr a
        lsr a
        lsr a
        ora tmp
        sta GLY5,x
        lda oswblk+1,y
        and #$0F
        sta tmp
        asl a
        asl a
        asl a
        asl a
        ora tmp
        sta GLY5+8,x
        inx
        iny
        cpy #8
        bne @l
        ldx tcol
        inx
        cpx #lchars_end-lchars
        bne @c
        rts
lchars: .byte "FUELANDCRSH"        ; (game.s's labels index these)
lchars_end:
oswblk: .res 9                     ; OSWORD 10's block: the character, 8 rows

; -------------------------------------------------------------- rungs' fast way
; rfastr, rfastl (bank 4, its free space at $A181, after TENH5's 129 entries;
; the bodies FR0, FL0 at $9000, $9100, the first R2OFF bytes of run2's store
; pages TPE0, TPE1): rung X's transition lines by table when it spans a <= RFA
; pixels and D = yb - yt < 16 lines.
; tools/landgen.py's TRk (leaning right) and TLk (left), indexed by 16 (RFA -
; a) + D, hold pixel k's transition as an offset from yt (k < a, counted from
; the rung's LO: pixel xt + k leaning right, xb + k left); each is stored at
; RTBUF + alloc + k (rungs' RTP + x + 1 for pixel x) and the rung's sentinel
; $FF after them, alloc advanced by a + 1 (as rungs' rg_nr), then the next
; rung (rg_r) or return (rungs' end).  The unrolled body FR0 / FL0
; stores pixels RFA-1 down to 0; it is entered at pixel a-1 (DUFR, DUFL: the
; entry's low byte, into @j's operand; the bodies are page-aligned so the high
; byte is fixed).  Other rungs (a > RFA, or D >= 16, which includes a wrapped
; D with yb < yt) go back to rungs' division (rg_rdr, rg_rdl) with ra2 = 2a.
; In: X the rung, Y = dva = a, TY, BY, alloc (in RTBUF's
; page), tj = X.  Clobbers A, X, Y, rrem (= yt).  Callers: rungs (JMP
; from rg_r's leaning-right and leaning-left cases).
        .segment "B4C"
rfastr: cpy #RFA+1                 ; a > RFA: the division
        bcs @sl
        lda TY,x
        sta rrem                   ; yt
        eor #$FF                   ; D = yb - yt (yb + ~yt + 1: C as an SBC's)
        sec
        adc BY,x
        cmp #16
        bcs @sl                    ; (C clear after: RFBODY's ADCs rely on it)
        ora B16-1,y                ; X = 16 (RFA - a) + D (D < 16: OR adds)
        tax
        lda DUFR-1,y               ; the entry for a
        sta @j+1
        ldy alloc                  ; (Y: RTBUF's offset)
@j:     jmp FR0                    ; (operand's low byte patched)
@sl:    lda dva
        asl a
        sta ra2
        jmp rg_rdr
rfastl: cpy #RFA+1                 ; (as rfastr, leaning left)
        bcs @sl
        lda TY,x
        sta rrem
        eor #$FF
        sec
        adc BY,x
        cmp #16
        bcs @sl
        ora B16-1,y
        tax
        lda DUFL-1,y
        sta @j+1
        ldy alloc
@j:     jmp FL0
@sl:    lda dva
        asl a
        sta ra2
        jmp rg_rdl
B16:    .repeat RFA, i             ; B16[a-1] = 16 (RFA - a)
        .byte 16 * (RFA - 1 - i)
        .endrepeat
DUFR:   .repeat RFA, i             ; DUFR[a-1], DUFL[a-1]: the body's entry for
                                   ; a (8 bytes a pixel)
        .byte <(FR0 + 8 * (RFA - 1 - i))
        .endrepeat
DUFL:   .repeat RFA, i
        .byte <(FL0 + 8 * (RFA - 1 - i))
        .endrepeat
.macro RFBODY T                    ; pixels RFA-1 .. 0: yt + T<k>[X] to RTBUF +
        .repeat RFA, i             ; alloc + k (Y = alloc's low byte; X the
                                   ; table index)
        lda .ident(.sprintf("%s%d", T, RFA - 1 - i)),x
        adc rrem                   ; (C stays clear: yt + offset <= yb < 256)
        sta RTBUF + RFA - 1 - i,y
        .endrepeat
        tya                        ; alloc += a + 1; $FF at the old alloc + a
        sec
        adc dva
        sta alloc
        tay
        lda #$FF
        sta RTBUF-1,y
        ldx tj                     ; the next rung, or done (rungs' rg_nx)
        inx
        cpx #NX+1
        bcs :+
        jmp rg_r
:       rts
.endmacro
        .segment "B4R"
FR0:    RFBODY "TR"
        .segment "B4L"
FL0:    RFBODY "TL"

; ---------------------------------------------------------------- bank 7
        .segment "B7CODE"
        .assert LQOFF = 15, error, "LERPQ7 is indexed by (b | 16) - a - 1: LQOFF 15"
; prow7 (bank 7, $B480; bank 7 must be paged in): the rows' screen points,
; land.project.  For rows j = 0..RN (nr of them) corner i's x and y go to PX,
; PY + 16 j + i from the raw heights HT + 16 j + i.  A row's depth index is di
; = 16 ZB - czs - DI0 - 16 j (DCUR, 16 less each row); the clip rows have fixed
; ones: row 0 on the far clip plane (ZFCLIP*16 - DI0, when FACT, or when ZB =
; ZFCLIP and czs = 0 puts a corner row on it) and row RN, the near clip plane's
; (ZCLIP*16 - DI0).  A y is SYT7's for the row (syp = SYT7 + 32 di, HOFF ORed
; into the low byte) indexed by the raw height: its entry is for h - hg + HMAX.
; The edges (corners 0 and NX-1, the x clip planes) have their heights lerped
; by fx between corners 0 and 1, NX-2 and NX-1 (LERPQ7's row cxs: @lq2, @lq3's
; operands, or LQP); the near clip row's heights, and the far's when FACT,
; are lerped by 1 - fz between the corner rows either side (LERPQ7's row 16 -
; czs at lp; LERPY) with the edges' at E0..E3 for @ape.  The x's: corner 1's
; from B1T (bp = B1T + 32 di; entry 2 cxs + 1), each further corner the last
; plus rh and a bit of B1T's carry mask (entry 2 cxs: rl), the edges' PINL7,
; PINR7 by di; a clip row's come straight from PXF7 or PXN7 + 11 cxs (CX11).
; With the camera raised (CAME not 0) each row's y's are EYV more (eyrow;
; PYSE, PYHE, or satrow when EYV >= EYS could carry a y past 254; cliprow7 for
; a lerped row), held at 254.  Last (@fin) the near row's y's are made at
; least the row before's + 1 and row 0's, when FACT, at most row 1's - 1.
; MODE: bit 0 the row's heights lerped (LERPY), bit 6 a clip row (x's from
; PXF7/PXN7), bit 7 the camera raised (CAMF: $80 or 0).  In: HT (and SHF: hsh
; first), cxs, czs, ZB, RN, FACT, CAME.  Out: PX, PY rows 0..RN; np = NX;
; HGV, HOFF (hgnd); EYV (the last row's).  Clobbers A, X, Y, rl, rh, syp, lp,
; tmp, MT0, MT1, zero page CX2..HOFF, and its own operands @lq2, @lq3, @nj.
; Caller: project (PAGE 7 around it).
CX2     = $8E                      ; 2 cxs: B1T's entry
CAMF    = $8F                      ; $80 when the camera is raised (CAME not 0),
                                   ; else 0: MODE's bit 7
RN16    = $90                      ; 16 RN: the near clip row's 16 j
DCUR    = $92                      ; the current row's di (a corner row's)
MODE    = $93                      ; the current row's kind (above)
LQP     = $94                      ; LERPQ7 + 32 cxs: the edges' lerp row
bp      = $96                      ; B1T + 32 di
CX11    = $98                      ; 11 cxs: PXF7, PXN7's entry
E0      = $99                      ; a lerped row's heights at corners 0, 1,
                                   ; NX-2, NX-1
E1      = $9A
E2      = $9B
E3      = $9C
HOFF    = $9E                      ; HMAX - hg (hgnd's): syp's low byte ORs it
prow7:  lda SHF                    ; (zsh4 stepped the map: shift HT first)
        beq :+
        jsr hsh
:       ldy cxs                    ; LERPQ7's row for fx (the edges): @lq2,
                                   ; @lq3's operands and LQP
        lda LQHI,y
        sta @lq2+2
        sta @lq3+2
        sta LQP+1
        lda LQLO,y
        sta @lq2+1
        sta @lq3+1
        sta LQP
        tya
        asl a
        sta CX2                    ; 2 cxs
        asl a
        asl a
        adc CX2                    ; (C clear: 8 cxs + 2 cxs, no carry)
        adc cxs
        sta CX11                   ; 11 cxs
        jsr hgnd                   ; HGV, HOFF
        lda #0                     ; CAMF, and @nj's target: @r7 when the camera
        ldy #<@r7                  ; is at CAMH (every row after row 0 then has
        ldx CAME                   ; MODE 0: no test), @rm otherwise
        beq :+
        lda #$80
        ldy #<@rm
:       sta CAMF
        sty @nj+1
        lda RN                     ; RN16 = 16 RN
        asl a
        asl a
        asl a
        asl a
        sta RN16
        lda czs                    ; lp = LERPQ7's row 16 - czs (1 - fz: the
        beq :+                     ; clip rows' heights; unused at czs 0, when
                                   ; no row is lerped)
        lda #16
        sec
        sbc czs
        tay
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
:       lda #NX                    ; (np: NX, game.s's; the strips use NX)
        sta np
        lda #0                     ; row 0: tmp = 16 j = 0
        sta tmp
        lda ZB                     ; DCUR = 16 ZB - DI0 - czs, computed as 16
        sec                        ; (ZB - 9) - (DI0 - 144) - czs so that
                                   ; nothing passes a byte (16 ZB can)
        sbc #9
        asl a
        asl a
        asl a
        asl a
        sbc #DI0-9*16-1            ; (C clear: subtracts DI0 - 144)
        .assert DI0 > 9*16 && ZFCLIP >= 9 && ZBACK-ZSKIP >= 9, error, "DCUR: 16 (ZB - 9), DI0 - 144 must be bytes"
        sec
        sbc czs
        sta DCUR
        tay
        lda FACT                   ; MODE for row 0: bit 0 = FACT (its heights
        beq :+                     ; lerped; its di the far plane's), bit 6 if
                                   ; its di is the far plane's either way
        ldy #ZFCLIP*16-DI0
:       cpy #ZFCLIP*16-DI0
        bne :+
        ora #$40
:       ora CAMF
        sta MODE
        eor #$40                   ; MODE $40 or $41 (a clip row, the camera at
        cmp #2                     ; CAMH) is handled here; every other kind
                                   ; goes through @row (C set there)
        bcs @row
        lsr a                      ; (C = FACT)
        lda #<(SYT7+32*(ZFCLIP*16-DI0))
        ora HOFF                   ; syp = the far plane's SYT7 row + HOFF
        sta syp
        lda #>(SYT7+32*(ZFCLIP*16-DI0))
        sta syp+1
        ldx #0
        bcs :+
        jmp @hp0                   ; (a corner row on the plane: HT's heights)
:       jmp @apf                   ; (lerped to row 1's)
@altj:  jmp @cam                   ; (MODE not 0 here has bit 7 set: the camera
                                   ; raised)
; A row: Y = its di, X = tmp = 16 j, MODE; C set on entry.
@row:   lda SYL7,y                 ; syp = SYT7 + 32 di | HOFF (32 di's low 5
        sta bp                     ; bits are 0, HOFF <= HMAX); bp = B1T + 32 di
                                   ; (the low bytes alike)
        ora HOFF
        sta syp
        lda SYH7,y
        sta syp+1
        adc #>B1T - >SYT7 - 1      ; (C set: + the pages between; C clear after)
        sta bp+1
        ldx tmp
@rm:    lda MODE                   ; (MODE 0: a plain row, the camera at CAMH)
        bne @altj
@r7:    R7BP 1                     ; rh = r's high byte (rl is not needed: B1T
                                   ; holds the carries)
        .assert >@rm = >@r7, error, "@nj's operand is patched by its low byte: @rm, @r7 must share a page"
        EDGEY HT, @lq2, @lq3, 1    ; the edges' y's (heights lerped by fx), then
                                   ; corners 1..NX-2's
        .repeat NX-2, i
        PYH i+1
        .endrepeat
@pyd:   ldy CX2                    ; the x's: rl = B1T's carry mask for cxs,
        lda (bp),y                 ; corner 1's x from its next byte; corner
        sta rl                     ; k+2's x = corner k+1's + rh + bit k of the
        iny                        ; mask (the carry out of B's low byte); no
        lda (bp),y                 ; carry out of the high byte for corners
                                   ; 1..NX-2 (landgen asserts it): C clear after
        sta PX+1,x
        .repeat NX-3, k
        lsr rl
        adc rh
        sta PX+2+k,x
        .endrepeat
        ldy DCUR                   ; the edges' x's: the clip planes' at this di
        lda PINL7,y
        sta PX,x
        lda PINR7,y
        sta PX+NX-1,x              ; (within XL..XR: CLP7 is 0 from di NCLP, and
                                   ; these rows' di >= 16)
        .assert (ZCLIP+1)*16 - DI0 - 15 >= NCLP, error, "a corner row could overhang XL, XR"
@nx:    txa                        ; the next row: X = tmp + 16 (C clear from
        adc #16                    ; the x's); the near clip row (16 RN) is the
                                   ; last and is not a corner row
        cmp RN16
        beq @lst
        tax
        lda DCUR                   ; (C clear: tmp + 16 < RN16) di - 16
        sbc #15
        sta DCUR
        tay
        lda syp+1                  ; (C set) SYT7's and B1T's rows 512 bytes
                                   ; back: the pages
        sbc #2                     ; alone change
        sta syp+1
        adc #>B1T - >SYT7 - 1      ; (C set)
        sta bp+1
@nj:    jmp @rm                    ; (operand patched: @r7 when CAMF is 0)
@nxf:   txa                        ; row 1 after the far clip row (X = 0, C set
        adc #15                    ; from @pxc's CPX): tmp = 16; DCUR, Y = row
                                   ; 1's di; syp, bp from @row's tables
        sta tmp
        lda DCUR
        sbc #15                    ; (C clear: - 16)
        sta DCUR
        tay
        jmp @row
@lst:   sta tmp                    ; the near clip row: tmp = 16 RN
        bit CAMF
        bmi @lsc
        tax                        ; (camera at CAMH) X = 16 RN; syp = the near
        lda #<(SYT7+32*(ZCLIP*16-DI0)) ; plane's SYT7 row + HOFF
        ora HOFF
        sta syp
        lda #>(SYT7+32*(ZCLIP*16-DI0))
        sta syp+1
        lda czs
        bne :+
        jmp @hp0                   ; (czs 0: corner row RN is on the plane;
                                   ; heights from HT)
:       jmp @apz                   ; (lerped from row RN-1's)
@lsc:   ldy #ZCLIP*16-DI0          ; (the camera raised) MODE $C0, or $C1 when
        lda czs                    ; lerped; @row, then @alt's @cam
        beq :+
        lda #1
:       ora #$40
        ora CAMF
        sta MODE
        jmp @row
@fin:   ldx RN16                   ; the near clip row's y's at least the row
        .repeat NX, i              ; before's + 1 (y's are 254 at most, so + 1
                                   ; stays in a byte)
        lda PY-16+i,x
        cmp PY+i,x
        bcc :+
        adc #0                     ; (C set: + 1)
        sta PY+i,x
:
        .endrepeat
        lda FACT                   ; the far clip row's y's, when lerped, at
                                   ; most row 1's - 1
        bne :+
        rts
:
        .repeat NX, i              ; (row 1's y 0 left alone: 0 - 1 would wrap)
        lda PY+i
        cmp PY+16+i
        bcc :+
        ldx PY+16+i
        beq :+
        dex
        stx PY+i
:
        .endrepeat
        rts
@hp0:                              ; a clip row's y's from HT (the camera at
                                   ; CAMH): X = 0 or 16 RN, syp set
        EDGEY HT
        .repeat NX-2, i
        PYH i+1
        .endrepeat
        jmp @pxc
@ap:    txa                        ; a lerped clip row with the camera raised
                                   ; (EYV set): row 0 or RN
        beq @apf
        jmp @apz
; The far clip row (row 0; syp its SYT7 row): heights lerped from row 0's (HT)
; towards row 1's (HT+16) by 1 - fz (lp: LERPQ7's row 16 - czs; czs not 0),
; corners 1..NX-2 straight to y's in PY, the edges' heights to E0..E3.
@apf:   .repeat NX, i
        LERPY HT, HT+16, i, 0
        .endrepeat
        jmp @ape
; The near clip row (X = 16 RN; syp its SYT7 row): heights lerped from row
; RN-1's (HT-16,x) towards row RN's (HT,x) by 1 - fz, likewise.
@apz:   .repeat NX, i
        LERPY HT-16, HT, i, 1
        .endrepeat
@ape:   lda E1                     ; the edges: heights by fx (LQP), then y's
        ora #16                    ; (LERPQ7 at (b | 16) - a - 1, + a, C set)
        clc
        sbc E0
        tay
        lda (LQP),y
        adc E0
        tay
        lda (syp),y
        sta PY,x
        lda E3
        ora #16
        clc
        sbc E2
        tay
        lda (LQP),y
        adc E2
        tay
        lda (syp),y
        sta PY+NX-1,x
        bit MODE                   ; (the camera raised: EYV added, held at 254)
        bmi :+
        jmp @pxc
:       jsr cliprow7
        jmp @pxc
@cam:   R7BP                       ; the camera raised: rl, rh = r, then EYV
        jsr eyrow                  ; (X kept)
        lda MODE
        lsr a
        bcc :+
        jmp @ap                    ; (bit 0: a lerped clip row)
:
        EDGESP HT                  ; the edges' heights by fx into PY, x; then
        lda EYV                    ; the y's, EYV more: satrow when a sum could
                                   ; pass 254, else PYSE (edges) and PYHE
        cmp #EYS
        bcc :+
        jsr satrow
        jmp @cx
:       clc                        ; (C clear for the ADC EYVs: EDGESP sets it)
        .repeat NX, i
        .if i = 0 || i = NX-1
        PYSE i
        .else
        PYHE i
        .endif
        .endrepeat
@cx:    bit MODE                   ; bit 6: a clip row, x's PXF7/PXN7; else B1T
        bvs @pxc
        jmp @pyd
; The clip rows' x's, by cxs alone: PXF7 + 11 cxs for row 0 (on the far plane,
; di ZFCLIP*16 - DI0), PXN7 + 11 cxs for row RN (the near plane's, di ZCLIP*16
; - DI0); both within XL..XR (landgen asserts it).  MODE back to CAMF.
        .assert NX = 11, error, "PXF7, PXN7 are 11 x's a cxs"
@pxc:   lda CAMF
        sta MODE
        ldy CX11
        cpx #0
        bne @pxn
        .repeat NX, i
        lda PXF7+i,y
        sta PX+i
        .endrepeat
        jmp @nxf
@pxn:   .repeat NX, i              ; (the near clip row: the last)
        lda PXN7+i,y
        sta PX+i,x
        .endrepeat
        jmp @fin


; eyrow (bank 7): EYV = (CAME (r >> 5) + 64) >> 7, land.project's ey: how much
; lower the row's y's are with the camera CAME above CAMH.  In: rl, rh = r (the
; row's pixels a tile, 8.8; under 8192, so r >> 5 is a byte), CAME.  Out: EYV,
; X kept; C clear (the trailing CLC: nothing relies on it, @cam's LSR follows).
; Clobbers A, Y, MT0, MT1.  Caller: prow7 (@cam).
eyrow:  lda rh
        sta MT1
        lda rl
        .repeat 5
        lsr MT1
        ror a
        .endrepeat
        sta MT0                    ; r >> 5
        lda CAME
        sta MT1
        lda #0
        ldy #8
        lsr MT1                    ; CAME * MT0, 8 by 8: the multiplier's bits
@m:     bcc :+                     ; out of MT1's bottom, the product shifted in
                                   ; at the top
        clc
        adc MT0
:       ror a
        ror MT1
        dey
        bne @m
        tay                        ; (A high, MT1 low) + 64, >> 7
        lda MT1
        clc
        adc #64
        sta MT1
        tya
        adc #0
        asl MT1
        rol a
        sta EYV
        rts

; hsh (bank 7): the heights HT shifted a row after zsh4's map step.  SHF 1:
; row j becomes row j-1's (rows 7 down to 1), row 0 takes HTN; SHF $FF: row j
; becomes row j+1's (0 up to 6), row 7 takes HTN.  Out: SHF = 0.  Clobbers A,
; X.  Caller: prow7.
hsh:    ldx #NX-1
        lda SHF
        bmi @b
@o:     .repeat 7, k
        lda HT+16*(6-k),x
        sta HT+16*(7-k),x
        .endrepeat
        lda HTN,x
        sta HT,x
        dex
        bpl @o
        bmi @d
@b:     .repeat 7, k
        lda HT+16*(k+1),x
        sta HT+16*k,x
        .endrepeat
        lda HTN,x
        sta HT+$70,x
        dex
        bpl @b
@d:     lda #0
        sta SHF
        rts

; hgnd (bank 7): the ground under the ship, land.ground: ZSHIP tiles ahead of
; the camera at its x, i.e. x = cx + 128 in 8.8 tiles, between the four map
; corners surrounding it, across then down (each by LERPQ7: land.lerp).  The
; ship's row is row ZB - ZSHIP (its map row czt + ZSHIP); its column is corner
; 4 (map x cxt) or, at cxs >= 8, corner 5; across by q = (cxs + 8) & 15
; sixteenths on that row and the row before (16 bytes back in HT: one map row
; farther), then down by q = czs.  In: ZB, cxs, czs, HT, LQLO/LQHI.  Out: HGV
; = hg (the game reads it), HOFF = HMAX - hg (the offset into a SYT7 row for a
; raw height: prow7 ORs it into syp).  Clobbers A, X, Y, lp, tmp.  Caller:
; prow7.
hgnd:   lda ZB                     ; X = 16 (ZB - ZSHIP) + 4 + (cxs >= 8)
        sec
        sbc #ZSHIP
        asl a
        asl a
        asl a
        asl a
        adc #4                     ; (C clear: ZB - ZSHIP < 16)
        ldy cxs
        cpy #8
        adc #0
        tax
        lda cxs                    ; across: LERPQ7's row q = (cxs + 8) & 15
        eor #8
        tay
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
        lda HT+1,x                 ; the ship's row: (b | 16) - a - 1 = b - a +
        ora #16                    ; LQOFF, the table's index; its entry is
        clc                        ; lerp(0, b - a) - 1, added to a with C set
        sbc HT,x
        tay
        lda (lp),y
        adc HT,x
        sta tmp+1                  ; hx0
        lda HT-15,x                ; the row before (one map row farther)
        ora #16
        clc
        sbc HT-16,x
        tay
        lda (lp),y
        adc HT-16,x                ; hx1
        ora #16
        clc
        sbc tmp+1                  ; hx1 - hx0 + LQOFF
        sta tmp
        ldy czs                    ; down: q = czs
        lda LQLO,y
        sta lp
        lda LQHI,y
        sta lp+1
        ldy tmp
        lda (lp),y
        adc tmp+1                  ; hg = lerp(hx0, hx1, czs/16)
        sta HGV
        eor #$FF                   ; HOFF = HMAX - hg
        sec
        adc #HMAX
        sta HOFF
        rts
; su_l7 (bank 7): setup's land strip, unrolled for np = NX.  In: Y = 16 (ns-1).
; Rows ns-1 and ns (PX, PY + Y and + Y + 16) become the strip's top and bottom
; points TX, TY, BX, BY + 1..NX, BCL counted up for each bottom point at or past
; YGND+1 (bclip's); then Y += ldCLE (pcol5's 16 o: the window row of row ns)
; and CLE, CLO + Y + 0..NX-2 become the boxes CE, CO + 1..NX-1 (CE, CO + NX,
; the right margin's, setup zeroes).  Clobbers A, Y.  Entered by setup's JMP
; with bank 7 paged; ends with a JMP to su_m4 (bank 4 back, then setup's
; su_m).  The code is in five pieces: the end of B7CODE, then the
; spare 80 bytes after R7L, R7H, PINL7 and PINR7 (each table is NDI = 176
; bytes of its page).
        .assert NX = 11 && NDI = 176, error, "su_l7: unrolled for NX 11; the spares start at offset NDI of their pages"
.macro SUPX i                      ; corner i of rows ns-1 and ns into point i+1
        lda PX+i,y
        sta TX+1+i
        lda PY+i,y
        sta TY+1+i
        lda PX+16+i,y
        sta BX+1+i
        lda PY+16+i,y
        sta BY+1+i
        cmp #YGND+1
        bcc :+
        inc BCL
:
.endmacro
.macro SUCL i                      ; box i's bytes into CE, CO + i+1
        lda CLE+i,y
        sta CE+1+i
        lda CLO+i,y
        sta CO+1+i
.endmacro
        .segment "B7CODE"
su_l7:
.repeat 8, i
        SUPX i
.endrep
        jmp su_l7a
        .segment "B7A"
su_l7a: SUPX 8
        SUPX 9
        jmp su_l7b
        .segment "B7B"
su_l7b: SUPX 10
        tya
        clc
        adc ldCLE
        tay
.repeat 3, i
        SUCL i
.endrep
        jmp su_l7c
        .segment "B7C"
su_l7c:
.repeat 6, i
        SUCL i+3
.endrep
        jmp su_l7d
        .segment "B7D"
su_l7d: SUCL 9
        jmp su_m4

; satrow (bank 7, CLP7's spare): prow7's row X (16 j) with the camera so far
; raised (EYV >= EYS) that a y plus EYV could pass 254: each corner's y from
; SYT7 (syp) plus EYV, held at 254 (land.project's min(254, sy)).  The edges'
; heights are read from PY (EDGESP's), corners 1..NX-2's from HT.  In: X, syp,
; EYV.  Out: PY + X.., X kept.  Clobbers A, Y, MT0, MT1.  Caller: prow7 (@cam).
        .segment "B7E"
satrow: stx MT1
        ldy PY,x
        jsr sat1
        lda #NX-2
        sta MT0
:       inx
        ldy HT,x
        jsr sat1
        dec MT0
        bne :-
        inx
        ldy PY,x
        jsr sat1
        ldx MT1
        rts
sat1:   lda (syp),y                ; PY,x = min(254, SYT7[Y] + EYV)
sat2:   clc                        ; PY,x = min(254, A + EYV)
        adc EYV
        bcs :+
        cmp #255
        bcc :++
:       lda #254
:       sta PY,x
        rts
; cliprow7 (bank 7): a clip row's y's (PY + X.., X = 16 j), computed without
; EYV, each EYV more and held at 254.  Out: X = tmp (the row's 16 j).  Clobbers
; A, MT0.  Caller: prow7 (@ape, the camera raised).
cliprow7:
        lda #NX
        sta MT0
:       lda PY,x
        jsr sat2
        inx
        dec MT0
        bne :-
        ldx tmp
        rts
; ---------------------------------------------------------------- the slow way
; Bank 4's free space again (zsh4 at $B900 and slow2 at $9200, the first R2OFF
; bytes of run2's store pages TPO3 and TPE2; slow at $A081, after TENH4's 129
; entries): a map step's heights, and the column no faster routine takes.
        .segment "B4Z"
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
        and #63
        tay
        lda MRL,y                  ; HPZ = MAP + 64 z
        sta HPZ
        lda MRH,y
        sta HPZ+1
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

        .segment "B4S"
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
        .segment "B4S2"
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
PIXM:   .byte $88, $44, $22, $11   ; pixel p's two bits in a MODE 1 byte

; ---------------------------------------------------------------- bank 5
        .segment "B5CODE"
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
; rows 1..7 (o 1).  Out: ldCLE = 16 o (setup's su_l7 adds it to its row
; index); WX, WK, WO, VLO, VHI, WE.  In: cxt, czt, ZB, CX.  Clobbers A, X, Y,
; WM.  Caller: project (PAGE 5 around it).
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
        .assert <CLE = 0 && <CLO + 48 < $100, error, "crow: CLE page-aligned (@se's operand is 16 m); CLO + 48 in its page"
; crow: window row A (m, 0..9): map row (WK - m) & 63, entries 0..NX-2 by CX,
; into CLE + 16 m and CLO + 16 m (self-modifying: @le/@lo's operands the map
; row's 64-byte rows of CMAPE and CMAPO, @se/@so's the window row).  In: A, WK,
; CX.  Out: WM = m.  X kept; clobbers A, Y.  Caller: pcol5.
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
        sbc WM
        and #63                    ; z = (WK - m) & 63
        tay
        lsr a
        lsr a
        ora #>CMAPE                ; CMAPE + 64 z: page $80 + (z >> 2),
        sta @le+2
        ora #>$1000                ; CMAPO's a page $10 on
        sta @lo+2
        tya
        lsr a
        ror a
        ror a
        and #$C0                   ; low byte (z & 3) << 6
        sta @le+1
        sta @lo+1
        txa
        pha
        ldx #NX-2
@c:     ldy CX,x
@le:    lda CMAPE,y
@se:    sta CLE,x
@lo:    lda CMAPO,y
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
        .assert * <= $A100, error, "pcol5: bank 5 from $A100 is the game's (game.s)"

        .include "game.s"

; ---------------------------------------------------------------- LANDS's RAM
; The sideways RAM finder and the write-select support, run by start, one time
; (in LANDS, $7000).  find_ram, selwr and wrx are beebgame's loader.s's
; (github.com/ebenupton/beebgame), except that a socket whose ROM the MOS is
; running is classed and never taken.  Three ways of making a socket writable
; are known: a plain machine's (a write to ROMSEL selects it for writes too), a
; Watford board's (a store to WRSEL_WATFORD + the socket) and a Solidisk's
; (the socket in the user VIA's port B, bits 0-3).
        .segment "BOOT"
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

; find_ram: the four banks' sockets.  Out: C clear and BANKMAP+0..3 the sockets
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
                                   ; images.  Y, BANKMAP's index, starts at 0,
                                   ; CLASS_FREE's value, which is want's first
        sty want
@cl:    ldx #0
@pick:  lda SOCKCLASS,x
        cmp want
        bne @pnext
        txa
        sta BANKMAP,y
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

; wpatch: pg4..pg7's and setup's write selects made the board's.  Each pwN
; (and pw7s, pw4s) is BIT wrt (3 bytes); on a Watford board it becomes STA
; WRSEL_WATFORD + the bank's socket,
; on a Solidisk STA WRSEL_SOLIDISK (pgN has the socket in A by then); on a
; plain machine nothing changes.  In: board, BANKMAP.  Clobbers A, X, Y, ptr.
; Caller: start, after find_ram.
wpatch: lda board
        beq @r
        ldx #5
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
; *RUN).  !BOOT left the palette black and the cursor off, so the message
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
        .byte "LAND needs 64K of sideways RAM:", 13, 10
        .byte "four 16K banks, any sockets, writable", 13, 10
        .byte "(through &FE30, or a Watford or", 13, 10
        .byte "Solidisk board).", 13, 10, 0

old_bank: .byte 0                  ; the ROM paged in when LANDS ran (ROMCOPY):
                                   ; find_ram restores it
board:  .byte 0                    ; find_ram's: BOARD_STD, _WATFORD, _SOLIDISK
want:   .byte 0                    ; find_ram's class sought; @count's count
best:   .byte 0                    ; the most sockets a way found, and which way
bestb:  .byte 0
SOCKCLASS: .res NSOCK              ; each socket's CLASS_*, or an alias tag
SAVED:  .res NSOCK                 ; RAM sockets' copyright bytes while signed
; the BIT wrt in each pgN and in setup (pw7s, pw4s), for wpatch: low bytes,
; high bytes, and each one's bank (BANKMAP's index)
wrsl:   .byte <pw4, <pw5, <pw6, <pw7, <pw7s, <pw4s
wrsh:   .byte >pw4, >pw5, >pw6, >pw7, >pw7s, >pw4s
wrsb:   .byte 0, 1, 2, 3, 3, 0
