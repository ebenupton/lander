; ramswr.s: the sideways RAM build's memory map, every byte of main RAM below
; the code, by address (the stored tables, segment TABLES, follow it).  The
; MOS's own bytes are left where they fall: $FC (its IRQ entry saves A there),
; the vectors at $0200, the stack's top, and page $0D, which a Master's MOS
; keeps live (its NMI code and extended vectors).

; ---------------------------------------------------------------- zero page
        .segment "ZEROPAGE"
        .org $0000
tyy:    .res 1                     ; t_steep, tr_l: a y (INC/DEC zp, patched)
TY:     .res NX+2                  ; the strip's top row: y (TX: x)
cxt:    .res 1                     ; the camera: tile and sixteenth, x and z
cxs:    .res 1
czt:    .res 1
czs:    .res 1
back:   .res 1                     ; the screen being drawn (0, 1)
scrb:   .res 1                     ; its base page
np:     .res 1                     ; points a row
nr:     .res 1                     ; rows (7 or 8)
vcount: .res 1                     ; fields
ptr:    .res 2                     ; scratch: a pointer, a word
tmp:    .res 2
tfe:    .res 1                     ; t_flo's end and count
tfn:    .res 1
ph_e:   .res 1                     ; phase's end
rl:     .res 1                     ; the row's r; run's covered STA's operand
rh:     .res 1
ns:     .res 1                     ; the strip
xl:     .res 1                     ; its margins, and the last strip's
xr:     .res 1
xlp:    .res 1
xrp:    .res 1
topa:   .res 2                     ; its rows' lines by pixel (ROWA, ROWB)
bota:   .res 2
tdx2:   .res 1                     ; traceb: 2 dx, the error, the segment
terr:   .res 1
tj:     .res 1
tyv:    .res 1                     ; traceb: the pending run's line
ra2:    .res 1                     ; 2a (2|dy|)
rq:     .res 1                     ; D div 2a, then q2 + 1
rrem:   .res 1                     ; the error E; rfast's yt
rq2:    .res 1                     ; D div a
rr2:    .res 1                     ; 2 (D mod a)
alloc:  .res 2                     ; RTBUF's next free byte
rtp:    .res 2                     ; a rung's transitions by pixel
dva:    .res 1                     ; a; the divisor
dvd:    .res 1                     ; D; the dividend
tcnt:   .res 1                     ; traceb: the pending run's first x
tsy:    .res 1                     ; gone: the first column right of the strip
last:   .res 1                     ; $FF: the near strip
lastri: .res 1                     ; the rung fsplit's tables are for
x4:     .res 1                     ; the column's first x
coff:   .res 1                     ; its byte offset, 8 x4/4 mod 256
scrh:   .res 1                     ; its screen half's page
ri:     .res 1                     ; the first rung not wholly left of it
ys:     .res 4                     ; each pixel's top-row line
mn:     .res 1                     ; the top's highest and lowest lines
mx:     .res 1
flr:    .res 1                     ; the near strip's floor when it slopes
flr1:   .res 1                     ; the line the column ends before
ve:     .res 1                     ; the bytes drawn on even and odd lines
vo:     .res 1
bpos:   .res 1                     ; a boundary: the pixels left of a rung
p1:     .res 1                     ; mktr's bottom boundary
yy:     .res 1                     ; split2, slow2: a line; fsplit: rsm
kk:     .res 1                     ; split2: a transition; fsplit: fwe
msk:    .res 1                     ; the pixels drawn on a line
zv:     .res 1                     ; zline's byte
zp_:    .res 2                     ; a line's address
dvx:    .res 1                     ; div8's divisor
svE:    .res 1                     ; ve, vo kept round a black run
svO:    .res 1
TRL:    .res 12                    ; mktr's transitions: line, mask (also
TRB:    .res 12                    ; the ship's scratch, bank 6's)
kb:     .res 1                     ; split2: the second rung's transition
tsp:    .res 2                     ; the screen's column records
bsp:    .res 2
bpos2:  .res 1                     ; split2's second boundary
DCUR:   .res 1                     ; prow7: the row's depth index
RN16:   .res 1                     ; 16 RN
syp:    .res 2                     ; prow7: the row's SYT7 row
lp:     .res 2                     ; prow7, hgnd: a LERPQ7 row
OVL:    .res 19                    ; the overlay (below)
HGV:    .res 1                     ; the ground's height under the ship
c_v1:   .res 1                     ; $40: BIT c_v1 sets V
MT0:    .res 1                     ; the projection's scratch
MT1:    .res 1
BCL:    .res 1                     ; the strip's bottom points below YGND
EYV:    .res 1                     ; the row's drop for CAME
CAME:   .res 1                     ; the camera's raise (0..EMAX)
TX:     .res 16                    ; the strip's rows' x's
BX:     .res 16
LO:     .res 16                    ; each rung's pixels LO .. HI-1
HI:     .res 16
.ifdef ARC
cte:    .res 2                     ; setup: CTE, CTO + the strip's brightness
cto:    .res 2
.endif
        .assert * <= $FC, error, "zero page: $FC on are the MOS's"

RVE     = ve                       ; run's bytes
RVO     = vo
fwe     = kk
rsm     = yy
fwu     = tj

; The overlay: scratch for routines that are never live together.
BE      = OVL+1                    ; fsplit: the rung's bytes by bpos, even
BO      = BE+5                     ; and odd lines
HPZ     = OVL+1                    ; project: the map rows' addresses, row 7's
                                   ; first (zsh4: one)
CX2     = OVL+0                    ; prow7: 2 cxs, B1T's entry
CAMF    = OVL+1                    ; $80 with the camera raised, else 0
MODE    = OVL+2                    ; the row's kind
LQP     = OVL+3                    ; LERPQ7's row for cxs (the edges)
bp      = OVL+5                    ; B1T's row
CX11    = OVL+7                    ; 11 cxs: PXF7, PXN7's entry
E0      = OVL+8                    ; a lerped row's heights at corners 0, 1,
E1      = OVL+9                    ; NX-2, NX-1
E2      = OVL+10
E3      = OVL+11
HOFF    = OVL+12                   ; HMAX - hg: syp's low byte ORs it
g0      = OVL+1                    ; game: pointers and scratch
g1      = OVL+3
gt0     = OVL+5
gt1     = OVL+6
gt2     = OVL+7
gt3     = OVL+8
gt4     = OVL+9
gt5     = OVL+10
tsg     = OVL+11                   ; the screen's column records
bsg     = OVL+13
        .assert HPZ+16 <= OVL+19 && HOFF < OVL+19, error, "the overlay"

; ---------------------------------------------------------------- page 1
        .segment "PAGE1"
        .org $0100
thxs:   .res 1                     ; the game
tx:     .res 1                     ; the thrust, x and z
tz:     .res 1
gkb:    .res 1                     ; the keys
gk:     .res 1                     ; the direction and pitch
gp:     .res 1
thr:    .res 1                     ; thrusting
landed: .res 1
ctim:   .res 1                     ; crashed: steps left
sx:     .res 3                     ; position (24-bit; spawn zeroes thr ..
sz:     .res 3                     ; gvz)
sy:     .res 3
gvx:    .res 2                     ; velocity
gvy:    .res 2
gvz:    .res 2
su:     .res 2                     ; the height in units, 8.8
fuel:   .res 2
dpass:  .res 1                     ; dots: the side of the ship
sctl:   .res 1                     ; the noise channel as written
satt:   .res 1
rnd:    .res 1                     ; rand's state
scrg:   .res 1                     ; the screen's page
pnext:  .res 1                     ; the last dot launched
fdr:    .res 2                     ; each screen's gauge as drawn
mkl:    .res 2                     ; each screen's marker: line ($FF none),
mkp:    .res 2                     ; pixel
mdl:    .res 1                     ; mdot's line, pixel, colour
mdp:    .res 1
mdc:    .res 1
        .res $0140 - *
LAHB:   .res YGND+2-YSKY           ; LAH,y: 2 (y >> 3), y YSKY..YGND+1
; The stack: the main loop's worst case and an IRQ (b32/tools/stackdepth.py
; checks it).
STACK:  .res $0200 - STACK
        .assert STACK <= $0200 - 64, error, "the stack: 64 bytes at least"

; ---------------------------------------------------------------- page 2
        .segment "PAGE2"
        .org $0200
USERV:  .res 2                     ; the MOS's
BRKV:   .res 2
IRQ1V:  .res 2                     ; irq
ZB:     .res 1                     ; row 0's map row less czt
RN:     .res 1                     ; the near row
FACT:   .res 1                     ; the far row lerped
GSHK:   .res 1                     ; the ship as drawn: direction, pitch,
GSHP:   .res 1                     ; centre, and whether
GSHX:   .res 1
GSHY:   .res 1
GSHV:   .res 1
HTN:    .res NX                    ; zsh4's new row of heights
CX:     .res NX                    ; the corners' map columns
SHF:    .res 1                     ; zsh4's step for prow7's hsh: 1, $FF, 0
tdy2:   .res 1                     ; traceb: 2|dy|, x1
tx1:    .res 1
x4p4:   .res 1                     ; slow: x4 + 4
re:     .res 1                     ; split2's boxes' bytes
ro:     .res 1
le:     .res 1
lo2:    .res 1
me:     .res 1
mo:     .res 1
p0:     .res 1                     ; mktr's top boundary
vflip:  .res 1                     ; the flip's field (less one: shown at once)
vlast:  .res 1                     ; the field of the last flip
ldCLE:  .res 1                     ; 16 o: setup's window row (pcol5's)
BANKMAP: .res 4                    ; banks 4..7's sockets
plife:  .res NPART                 ; the dots: life, position (8.8 tiles x, z;
ppx:    .res NPART                 ; 8.8 units y), velocity
ppxh:   .res NPART
ppz:    .res NPART
ppzh:   .res NPART
ppy:    .res NPART
ppyh:   .res NPART
pvx:    .res NPART
pvxh:   .res NPART
        .assert * <= $0300, error, "page 2"

; ---------------------------------------------------------------- $0300 on
        .segment "RAM"
        .org $0300
DBUF:   .res 256                   ; the ship's lines (bank 6's spdec)
ROWA:   .res 256                   ; the rows' lines by pixel
ROWB:   .res 256
RTBUF:  .res 256                   ; the rungs' transitions
PX:     .res 128                   ; the rows' points, 16 a row: x
pvz:    .res NPART                 ; (dot arrays)
pvzh:   .res NPART
pvy:    .res NPART
pvyh:   .res NPART
        .res 48
PY:     .res 128                   ; the rows' points: y
HT:     .res 128                   ; the rows' heights
CLE:    .res 160                   ; the colour window: even, odd lines
BY:     .res 16                    ; the strip's bottom row: y
RTPL:   .res 16                    ; each rung's transitions' base
CE:     .res 16                    ; each box's bytes, even and odd lines
CO:     .res 16
SPB:    .res 16                    ; slow: each pixel's box, transitions
STL:    .res 16
CLO:    .res 160
STD:    .res 16
CURT:   .res 64                    ; this frame's column records
        .res 16
TOPS:   .res 128                   ; each screen's column records
BOTS:   .res 128
RPT:    .res 256                   ; the rungs' tables (grung)
        .assert * = $0D00, error, "page $0D: the MOS's"

        .segment "RAM2"
        .org $0E00
RQF:    .res 256
CURB:   .res 64
EINLB:  .res YGND+4-YSKY           ; EINL,y: run's slot for line y (y from
                                   ; YSKY-1 to YGND+2)
QOA:    .res 7                     ; div8's rows
TEN5L:  .res TNB+1                 ; the fills' entries
        .res $1000 - *
TEN4H:  .res TNB+1
TEN5H:  .res TNB+1
TEN4L:  .res TNB+1
        .res $1100 - *
QRA:    .res QRAN                  ; div8's table
.ifdef ARC
        .res $1200 - *             ; (the stored tables' CTE, CTO: setup's
.endif                             ; operands index them within their pages)

EINL    = EINLB-(YSKY-1)
LAH     = LAHB-YSKY

        .assert <PX = 0 && <PY = 0 && <HT = $80 && <CLE = 0, error, "the rows' points and heights"
        .assert <(PX+16+NX-1) + 6*16 < $100, error, "traceb: PX+16+NX-1,y within its page"
        .assert <CLO + 48 < $100, error, "crow: CLO + 48 in its page"
        .assert >CE = >(CO+15), error, "slow2: CE, CO in one page"
        .assert ROWB = ROWA + $100 && <ROWA = 0 && (>ROWA & 1) = 0, error, "the rows: a page each, ROWA's even"
        .assert <DBUF = 0 && <RTBUF = 0, error, "DBUF, RTBUF page-aligned"
        .assert <LAHB = YSKY && >EINL = >(EINL+YGND+2), error, "the line tables: indexed within their pages"
        .assert >TOPS = >(BOTS+127) && >CURT = >(CURT+63) && >CURB = >(CURB+63), error, "the column records"
        .assert <RPT = 0 && <RQF = 0, error, "page-aligned tables"
        .assert >TEN5L = >(TEN5L+TNB) && >TEN4H = >(TEN5H+TNB) && >TEN4L = >(TEN4L+TNB) && >QRA = >(QRA+QRAN-1), error, "TEN4L .. TEN5H, QRA: in their pages"

RUNT    = $2800                    ; run's store pages (made by init): eight,
                                   ; their first R2OFF bytes code (T0 .. T7)

; ---------------------------------------------------------------- the screen
        .segment "SCREEN"
        .org $3000
LAND0:  .res 20*512                ; the two screens, 160 lines of 64 bytes:
LAND1:  .res 20*512                ; the panel, then the land
        .assert * = $8000, error, "the screen"
SCR0    = >LAND0                   ; line y at SCRn*256 + 512 (y >> 3) + (y & 7)
SCR1    = >LAND1

        .reloc
