; ram.s: the memory map of main RAM below the code, every byte by address, for
; both builds (the stored tables, segment TABLES, follow it).  The layout is
; absolute, so its constraints are checked as it assembles.  What both builds
; hold is declared once; zero page's shared part is at the same addresses in
; both.  The MOS's own bytes are left where they fall: $FC (its IRQ entry saves
; A there), the vectors at $0200, the top of the stack; the 32K build keeps an
; RTI at $0D00, the NMI's target, and the sideways RAM build leaves the whole
; of page $0D alone, which a Master's MOS keeps live (its NMI code and extended
; vectors).
;
; tools/memmap.py prints each declaration's trailing comment, and any
; comment-only lines under it, as the variable's use in docs/map-base.md and
; docs/map-swr.md.

; ---------------------------------------------------------------- zero page
        .segment "ZEROPAGE"
        .org $0000
tyy:    .res 1                     ; t_steep: the line (tg_op's INC or DEC);
                                   ; tr_l: the error kept
TY:     .res NX+2                  ; the strip's top row: y (TX: x)
cxt:    .res 1                     ; the camera: its tile, x
cxs:    .res 1                     ; its sixteenth of a tile, x
czt:    .res 1                     ; its tile, z
czs:    .res 1                     ; its sixteenth, z
back:   .res 1                     ; the screen being drawn (0, 1)
scrb:   .res 1                     ; its base page
np:     .res 1                     ; points a row
nr:     .res 1                     ; rows (7 or 8)
vcount: .res 1                     ; fields
ptr:    .res 2                     ; scratch: a pointer
tmp:    .res 2                     ; scratch: a word
tfe:    .res 1                     ; t_flo: the run's end
tfn:    .res 1                     ; t_flo: the last fill's stores skipped
ph_e:   .res 1                     ; phase's end
rl:     .res 1                     ; the row's r, low byte; the 32K build's
                                   ; run: the covered STA's operand, likewise
rh:     .res 1                     ; their high bytes
ns:     .res 1                     ; the strip (0 the farthest)
xl:     .res 1                     ; its left margin
xr:     .res 1                     ; its right margin
xlp:    .res 1                     ; the last strip's left margin
xrp:    .res 1                     ; the last strip's right margin
topa:   .res 2                     ; the strip's top row's lines by pixel (ROWA
                                   ; or ROWB)
bota:   .res 2                     ; its bottom row's (the other)
tdx2:   .res 1                     ; traceb: 2 dx; t_flo: Y kept
terr:   .res 1                     ; traceb: dx, then the error
tj:     .res 1                     ; traceb: the segment; elsewhere a rung, a
                                   ; pixel or a column kept
tyv:    .res 1                     ; traceb: the pending run's line
ra2:    .res 1                     ; 2a (a: dy's size)
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
mn:     .res 1                     ; the top's highest line
mx:     .res 1                     ; the top's lowest line
flr:    .res 1                     ; the near strip's floor when it slopes
flr1:   .res 1                     ; the line the column ends before
ve:     .res 1                     ; the byte drawn on even lines
vo:     .res 1                     ; the byte drawn on odd lines
bpos:   .res 1                     ; a boundary: the pixels left of a rung
p1:     .res 1                     ; mktr's bottom boundary
yy:     .res 1                     ; split2, slow2: a line; fsplit: rsm
kk:     .res 1                     ; split2: a transition; fsplit: fwe
msk:    .res 1                     ; the pixels drawn on a line
zv:     .res 1                     ; zline's byte
zp_:    .res 2                     ; a line's address
dvx:    .res 1                     ; div8's divisor
svE:    .res 1                     ; ve kept round a black run
svO:    .res 1                     ; vo kept round a black run
TRL:    .res 16                    ; mktr's transitions' lines (12; TRB their
                                   ; masks); all 16 the ship's scratch
kb:     .res 1                     ; split2: the second rung's transition
tsp:    .res 2                     ; gone: the drawn screen's column tops
bsp:    .res 2                     ; gone: its column bottoms
bpos2:  .res 1                     ; split2's second boundary
DCUR:   .res 1                     ; the row's depth index
RN16:   .res 1                     ; 16 RN
OVL:    .res 19                    ; the overlay (below)
HGV:    .res 1                     ; the ground's height under the ship
c_v1:   .res 1                     ; $40: BIT c_v1 sets V
MT0:    .res 1                     ; the projection's scratch
MT1:    .res 1                     ; the projection's scratch
BCL:    .res 1                     ; the strip's bottom points below YGND
EYV:    .res 1                     ; the row's drop for CAME
CAME:   .res 1                     ; the camera's raise (0..EMAX)
TX:     .res 16                    ; the strip's top row: x
BX:     .res 16                    ; the strip's bottom row: x
LO:     .res 16                    ; each rung's first pixel
HI:     .res 16                    ; the pixel after each rung's last
su:     .res 2                     ; the game: the height in units, 8.8
dpass:  .res 1                     ; dots: the side of the ship
scrg:   .res 1                     ; the game: the drawn screen's page
.ifdef SWR
syp:    .res 2                     ; prow7: the row's SYT7 row
lp:     .res 2                     ; prow7, hgnd: a LERPQ7 row
kpp:    .res 2                     ; runk: the RTS it planted last
kpg:    .res 1                     ; and its table's page (sethalf's)
.ifdef ARC
cte:    .res 2                     ; setup: CTE + the strip's brightness
cto:    .res 2                     ; setup: CTO + the strip's brightness
.endif
BY:     .res NX+2                  ; the strip's bottom row: y
CE:     .res NX+1                  ; each box's byte on even lines
CO:     .res NX+1                  ; each box's byte on odd lines
ldCLE:  .res 1                     ; 16 o: setup's window row (pcol5's)
.else
RD:     .res 1                     ; prow32: the row's depth index
pp:     .res 2                     ; run's planted RTS
smB:    .res 1                     ; smul: Y's bits, then the low product
smA:    .res 1                     ; smul: A
smB0:   .res 1                     ; smul: Y
HHI:    .res 1                     ; the row's greatest height
MQB:    .res 1                     ; mul4: LQ's bits
HLO:    .res 1                     ; the row's least height
RK:     .res 1                     ; prow32: 16 k
rodd:   .res 1                     ; run: the even pass's end entry
wn:     .res 1                     ; rast: the line's segments
WF:     .res 8                     ; rast: each segment's face
db:     .res 1                     ; rast: DBUF's next byte
bln:    .res 1                     ; rast: the open band's lines
px8:    .res 1                     ; rast: a point pitched, x (px >> 6)
lx1:    .res 1                     ; rast: the pixel after the line's last
tqb:    .res 1                     ; tq8: the sum's high byte
tqa:    .res 2                     ; tq8: V
pxl:    .res 1                     ; rast: px, low byte
lx0:    .res 1                     ; rast: the line's first pixel
yc:     .res 1                     ; rast: the line
NFL:    .res 1                     ; rast: the faces set up
sxl:    .res 1                     ; fline: the span's first pixel
pyh:    .res 1                     ; rast: a point pitched, y, high byte
pyl:    .res 1                     ; rast: its low byte
zrh:    .res 1                     ; rast: a point turned, Zr, high byte
zrl:    .res 1                     ; rast: its low byte
xrh:    .res 1                     ; rast: a point turned, Xr, high byte
pxh:    .res 1                     ; rast: px, high byte
xrl:    .res 1                     ; rast: Xr, low byte
tql:    .res 1                     ; tq8's product, low byte
tqh:    .res 1                     ; tq8's product, high byte
NPAT:   .res 1                     ; rast: the last pattern
edx:    .res 1                     ; fset's dx
bh:     .res 1                     ; rast: the open band's header ($FF none)
YHI:    .res 1                     ; the line after the faces' last
fi:     .res 1                     ; fset: the face
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
g0      = OVL+1                    ; game: pointers and scratch
g1      = OVL+3
gt0     = OVL+5
gt1     = OVL+6
gt2     = OVL+7
gt3     = OVL+8
gt4     = OVL+9
tsg     = OVL+11                   ; the drawn screen's column tops, bottoms
bsg     = OVL+13
.ifdef SWR
HPZ     = OVL+1                    ; proj4: the map rows' addresses, row 7's
                                   ; first (zsh4: one)
CX2     = OVL+0                    ; prow7: 2 cxs, B1T's entry
CAMF    = OVL+1                    ; $80 with the camera raised, else 0
MODE    = OVL+2                    ; the row's kind
LQP     = OVL+3                    ; LERPQ7's row for cxs (the ends)
bp      = OVL+5                    ; B1T's row
CX11    = OVL+7                    ; 11 cxs: PXF7, PXN7's entry
E0      = OVL+8                    ; a lerped row's heights at corners 0, 1,
E1      = OVL+9                    ; NX-2, NX-1
E2      = OVL+10
E3      = OVL+11
HOFF    = OVL+12                   ; HMAX - hg: syp's low byte ORs it
gt5     = OVL+10                   ; game: scratch
        .assert HPZ+16 <= OVL+19 && HOFF < OVL+19, error, "the overlay"
.else
WH      = OVL+1                    ; prow32: the row's heights
Y0      = OVL+12                   ; ytab's sum, xrow's M
Q0      = OVL+15                   ; their steps
LQ      = OVL+18                   ; lerp4's q
MGPH    = OVL+1                    ; mapgen: the six phases
MGA     = OVL+7                    ; the sum
MGB     = OVL+8
MGX     = OVL+9                    ; the corner, its slot
MGZ     = OVL+10
MGS     = OVL+11
MGN     = OVL+12                   ; the line's count and step
MGD     = OVL+13
MGT     = OVL+14                   ; scratch
MGU     = OVL+15
MGW     = OVL+16
MGR     = OVL+17
MWK     = OVL+18                   ; mwin's row, mstep's step
c0      = OVL                      ; the ship's walker: c0+j, x0+j the
x0      = OVL+6                    ; segments' dithers and flips
sptr    = OVL+13                   ; the line's screen byte
dp      = OVL+15                   ; the line's slot in DBUF
lim     = OVL+17                   ; the byte's last boundary
bl      = OVL+18                   ; the pass's lines
st      = TRL                      ; scratch
al      = TRL+1                    ; GSHX & 3
dpb     = TRL+4                    ; pass B's first slot
pm      = TRL+9                    ; $FF: pass A's lines odd
nb      = TRL+12                   ; pass B's lines ($80: none)
ptb     = TRL+14                   ; pass B's first screen byte
.endif

; ---------------------------------------------------------------- page 1
        .segment "PAGE1"
        .org $0100
tx:     .res 1                     ; the game: the thrust's x part
tz:     .res 1                     ; the thrust's z part
gkb:    .res 1                     ; the keys
gk:     .res 1                     ; the ship's direction
gp:     .res 1                     ; the ship's pitch
thr:    .res 1                     ; thrusting (spawn zeroes thr .. gvz)
landed: .res 1                     ; landed
ctim:   .res 1                     ; crashed: steps left
sx:     .res 3                     ; the ship's position, 24 bits: x
sz:     .res 3                     ; its z
sy:     .res 3                     ; its y
gvx:    .res 2                     ; the ship's velocity: x
gvy:    .res 2                     ; its y
gvz:    .res 2                     ; its z
fuel:   .res 2                     ; the fuel left
sctl:   .res 1                     ; the noise channel's control as written
satt:   .res 1                     ; its attenuation as written
rnd:    .res 1                     ; rand's state
pnext:  .res 1                     ; the last dot launched
.ifdef SWR
fdr:    .res 2                     ; each screen's gauge as drawn
mkl:    .res 2                     ; each screen's marker: line ($FF none)
mkp:    .res 2                     ; each screen's marker: pixel
mdl:    .res 1                     ; mdot's line
mdp:    .res 1                     ; mdot's pixel
mdc:    .res 1                     ; mdot's colour
.else
fdr:    .res 1                     ; the gauge as drawn
mky:    .res 1                     ; the marker: line ($FF none)
mkt:    .res 1                     ; the marker: pixel
mkb:    .res 2                     ; the two bytes under the marker
pvxh:   .res NPART                 ; the dots: x velocity, high byte
.endif
        .res $0140 - *
LAHB:   .res YGND+2-YSKY           ; LAH,y: 2 (y >> 3), y YSKY..YGND+1
.ifndef SWR
TN:     .res 31                    ; the near row's line by h - hg + 15
ER:     .res 18                    ; the ship's edges: dx mod dy
ED:     .res 18                    ; the ship's edges: dy
.endif
; The stack: the main loop's worst case, an interrupt (the 32K build's with
; the sync's nested in it) and an NMI (tools/stackdepth.py checks it).
STACK:  .res $0200 - STACK
.ifdef SWR
        .assert STACK <= $0200 - 64, error, "the stack: 64 bytes at least"
.else
        .assert STACK = $0200 - 28, error, "the stack: 28 bytes"
.endif

; ---------------------------------------------------------------- page 2
        .segment "PAGE2"
        .org $0200
USERV:  .res 2                     ; the MOS's
BRKV:   .res 2                     ; the MOS's
IRQ1V:  .res 2                     ; irq
.ifdef SWR
ZB:     .res 1                     ; row 0's map row less czt
RN:     .res 1                     ; the near row
FACT:   .res 1                     ; 1: the far row is lerped
GSHK:   .res 1                     ; the ship as drawn: direction
GSHP:   .res 1                     ; its pitch
GSHX:   .res 1                     ; its centre's x
GSHY:   .res 1                     ; its centre's line
GSHV:   .res 1                     ; 0: not drawn (crashed)
HTN:    .res NX                    ; the row of heights zsh4 fetches
CX:     .res NX                    ; the corners' map columns
SHF:    .res 1                     ; zsh4's step for prow7's hsh: 1, $FF, 0
tdy2:   .res 1                     ; traceb: twice dy's size
tx1:    .res 1                     ; traceb: x1; slow: the pixel's x
x4p4:   .res 1                     ; slow: x4 + 4
re:     .res 1                     ; split2: the right box, even lines
ro:     .res 1                     ; split2: the right box, odd lines
le:     .res 1                     ; split2: the left box, even lines
lo2:    .res 1                     ; split2: the left box, odd lines
me:     .res 1                     ; split2: middle ^ right, even lines
mo:     .res 1                     ; split2: middle ^ right, odd lines
p0:     .res 1                     ; mktr's top boundary
vflip:  .res 1                     ; the flip's field (less one: shown at once)
vlast:  .res 1                     ; the field of the last flip
TRB:    .res 12                    ; mktr's transitions: the masks
BANKMAP: .res 4                    ; banks 4..7's sockets
plife:  .res NPART                 ; the dots: life
ppx:    .res NPART                 ; the dots: x, 8.8 tiles, low byte
ppxh:   .res NPART                 ; the dots: x, high byte
ppz:    .res NPART                 ; the dots: z, 8.8 tiles, low byte
ppzh:   .res NPART                 ; the dots: z, high byte
ppy:    .res NPART                 ; the dots: y, 8.8 units, low byte
ppyh:   .res NPART                 ; the dots: y, high byte
pvx:    .res NPART                 ; the dots: x velocity, low byte
pvxh:   .res NPART                 ; the dots: x velocity, high byte
.else
LB:     .res 48                    ; rast: the face at each pixel of a line
MGQ:    .res 6                     ; mapgen: the phases' z steps
        .res 1
MGP:    .res 6                     ; mapgen: the phases' x steps
YQT:    .res 7                     ; mtl: TY's quantiles
LQT:    .res 7                     ; mtl: TL's quantiles
SEAI:   .res 4                     ; mtl: the sea's colours
CPX8:   .res 17                    ; rast: the pitched points kept: px8
CPYL:   .res 17                    ; their py, low byte
CPYH:   .res 17                    ; their py, high byte
cpi:    .res 1                     ; their pitch ($FF none)
cmiss:  .res 1                     ; rast: $FF if the pitch has changed
FBY:    .res 9                     ; the faces' corners: b's line
FCY:    .res 9                     ; c's line
FBX:    .res 9                     ; b's x
FCX3:   .res 9                     ; c's x
EX:     .res 18                    ; the faces' edges: x
EE:     .res 18                    ; the faces' edges: the error
EQ:     .res 18                    ; the faces' edges: dx div dy
WB:     .res 8                     ; a line's boundaries
ey:     .res 1                     ; ecore's slot
YLO:    .res 1                     ; the faces' first line
TRB:    .res 12                    ; mktr's transitions: the masks
.endif
        .assert * <= $0300, error, "page 2"
        .res $0300 - *

; ---------------------------------------------------------------- $0300 on
        .segment "RAM"
        .org $0300
DBUF:   .res 256                   ; the ship's bands
ROWA:   .res 256                   ; a row's lines by pixel
ROWB:   .res 256                   ; the other row's
RTBUF:  .res 256                   ; the rungs' transitions
PX:     .res 128                   ; the rows' points, 16 a row: x
pvz:    .res NPART                 ; the dots: z velocity, low byte
pvzh:   .res NPART                 ; the dots: z velocity, high byte
pvy:    .res NPART                 ; the dots: y velocity, low byte
pvyh:   .res NPART                 ; the dots: y velocity, high byte
.ifdef SWR
        .res 48
.else
ZB:     .res 1                     ; row 0's map row less czt
RN:     .res 1                     ; the near row
FACT:   .res 1                     ; 1: the far row is lerped
GSHK:   .res 1                     ; the ship as drawn: direction
GSHP:   .res 1                     ; its pitch
GSHX:   .res 1                     ; its centre's x
GSHY:   .res 1                     ; its centre's line
GSHV:   .res 1                     ; 0: not drawn (crashed)
HTN:    .res 11                    ; the row of heights zsh4 fetches
PATON:  .res 16                    ; rast: each pattern's end in PATF
ncame:  .res 1                     ; the CAME the near row's EYV is for
neyv:   .res 1                     ; the near row's EYV
tdy2:   .res 1                     ; traceb: twice dy's size
tx1:    .res 1                     ; traceb: x1; slow: the pixel's x
x4p4:   .res 1                     ; slow: x4 + 4
re:     .res 1                     ; split2: the right box, even lines
ro:     .res 1                     ; split2: the right box, odd lines
le:     .res 1                     ; split2: the left box, even lines
lo2:    .res 1                     ; split2: the left box, odd lines
me:     .res 1                     ; split2: middle ^ right, even lines
mo:     .res 1                     ; split2: middle ^ right, odd lines
p0:     .res 1                     ; mktr's top boundary
vflip:  .res 1                     ; the flip's field (less one: shown at once)
.endif
PY:     .res 128                   ; the rows' points: y
HT:     .res 128                   ; the rows' heights, 16 a row (+13 its EYV;
                                   ; the 32K build: +11, +12 its range)
CLE:    .res 160                   ; the colour window: even lines
.ifdef SWR
        .res 16
RTPL:   .res 16                    ; each rung's transitions' base
        .res 32
SPB:    .res 16                    ; slow: each pixel's box
STL:    .res 16                    ; slow: each pixel's transitions' lines
CLO:    .res 160                   ; the colour window: odd lines
STD:    .res 16                    ; slow: the box's change at each
CURT:   .res 64                    ; the third set's tops (see TOPS)
        .res 16
TOPS:   .res 128                   ; two sets of column records: tops.  Of the
                                   ; three sets, one is each screen's and one
                                   ; this frame's, in turn (sidx, cidx)
BOTS:   .res 128                   ; the two sets' bottoms
RPT:    .res 256                   ; the rungs' tables (grung): the patterns
        .assert * = $0D00, error, "page $0D: the MOS's"

        .segment "RAM2"
        .org $0E00
RQF:    .res 256                   ; the rungs' tables: 16 q2 + t(1)
CURB:   .res 64                    ; the third set's bottoms
EINLB:  .res YGND+4-YSKY           ; EINL,y: run's slot for line y (y from
                                   ; YSKY-1 to YGND+2)
QOA:    .res 7                     ; div8's rows
        .res $1000 - *
QRA:    .res QRAN                  ; div8's table
.ifdef ARC
        .res $1200 - *             ; (the stored tables' CTE, CTO: setup's
.endif                             ; operands index them within their pages)
.else
CLO:    .res 160                   ; the colour window: odd lines
BY:     .res 16                    ; the strip's bottom row: y
RTPL:   .res 16                    ; each rung's transitions' base
CE:     .res 16                    ; each box's byte on even lines
CO:     .res 16                    ; each box's byte on odd lines
SPB:    .res 16                    ; slow: each pixel's box
STL:    .res 16                    ; slow: each pixel's transitions' lines
STD:    .res 16                    ; slow: the box's change at each
B1N:    .res 32                    ; the near row's corner 1 by cxs
PATN:   .res 16                    ; rast: each pattern's segments
PATF:   .res 96                    ; rast: the patterns' faces
CURT:   .res 64                    ; the third set's tops (see TOPS)
CURB:   .res 64                    ; the third set's bottoms
YT:     .res 16                    ; ytab: the row's line by height
LIM:    .res 48                    ; the walker's, by boundary: the next
                                   ; byte's first boundary
TOPS:   .res 128                   ; two sets of column records: tops.  Of the
                                   ; three sets, one is each screen's and one
                                   ; this frame's, in turn (sidx, cidx)
BOTS:   .res 128                   ; the two sets' bottoms
NMI:    .res 1                     ; the MOS's NMI target: an RTI
vlast:  .res 1                     ; the field of the last flip
ECAME:  .res 1                     ; the CAME the rows' EYVs are for
ECZS:   .res 1                     ; the czs the rows' EYVs are for
EHIT:   .res 1                     ; $80: the rows' EYVs kept
MCB:    .res 11                    ; the map window's columns' first slots
KTN:    .res 48                    ; the walker's, by boundary: the mask of
                                   ; the pixels before it in its byte
OLB:    .res YGND+3-YSKY           ; OL,y: line y's entry in a parity table
dpi:    .res 1                     ; the pitch DBUF holds
dal:    .res 1                     ; the al (GSHX & 3) DBUF holds
bxl:    .res 1                     ; the ship's box: left
bxr:    .res 1                     ; the ship's box: right
byt:    .res 1                     ; the ship's box: top
byb:    .res 1                     ; the ship's box: bottom
OYT:    .res 1                     ; the box's offsets from the centre: top
OYB:    .res 1                     ; the box's offsets: bottom
OXL:    .res 1                     ; the box's offsets: left
OXR:    .res 1                     ; the box's offsets: right
FCE:    .res 9                     ; each face's dither: even lines
FCX:    .res 9                     ; each face's dither: even ^ odd
ca:     .res 1                     ; rast: the pitch's cosine
sa:     .res 1                     ; rast: the pitch's sine
cb:     .res 1                     ; rast: the direction's cosine
sb:     .res 1                     ; rast: the direction's sine
SXV:    .res 9                     ; the vertices' offsets: x
SYV:    .res 9                     ; the vertices' offsets: y
NVIS:   .res 1                     ; the normals: a bit each, shown
NNEG:   .res 1                     ; the normals: a bit each, lit
NBR:    .res 8                     ; the normals: brightness
EOFS    = 9                        ; the short edges' slots: + EOFS
cx3:    .res 3                     ; fset: the face's corners' x
cy3:    .res 3                     ; fset: the face's corners' lines
FID:    .res 9                     ; each face set up: its number
FAY:    .res 9                     ; each face set up: its first line
PEND:   .res 1                     ; rast: the open band's segments
PATTOP: .res 1                     ; rast: PATF's next byte
        .res 8
RPT:    .res 256                   ; the rungs' tables (grung): the patterns
RQF:    .res 256                   ; the rungs' tables: 16 q2 + t(1)
plife:  .res NPART                 ; the dots: life
ppx:    .res NPART                 ; the dots: x, 8.8 tiles, low byte
ppxh:   .res NPART                 ; the dots: x, high byte
ppz:    .res NPART                 ; the dots: z, 8.8 tiles, low byte
R7L:    .res NDI                   ; r by depth index, low byte
ppzh:   .res NPART                 ; the dots: z, high byte
ppy:    .res NPART                 ; the dots: y, 8.8 units, low byte
ppyh:   .res NPART                 ; the dots: y, high byte
pvx:    .res NPART                 ; the dots: x velocity, low byte
R7H:    .res NDI                   ; r by depth index, high byte
MC:     .res 128                   ; the map window's ring
TENL:   .res TNB+1                 ; the fills' entries by stores: low byte
TEN4H:  .res TNB+1                 ; TBLK4's entries' pages
BYN:    .res 48                    ; the walker's, by boundary: its byte
PAL:    .res 17                    ; rast's products, kept for a point's twin:
                                   ; cb px8, low byte
PAH:    .res 17                    ; cb px8, high byte
PBL:    .res 17                    ; sb px8, low byte
PBH:    .res 17                    ; sb px8, high byte
PCL:    .res 17                    ; sb Z, low byte
PCH:    .res 17                    ; sb Z, high byte
PDL:    .res 17                    ; cb Z, low byte
PDH:    .res 17                    ; cb Z, high byte
QOA:    .res 7                     ; div8's rows
TEN5H:  .res TNB+1                 ; TBLK5's entries' pages
LUT:    .res 32                    ; mtl's colours
QRA:    .res QRAN                  ; div8's table
HTL:    .res 15                    ; mapgen's height thresholds, low bytes
HTH:    .res 15                    ; mapgen's height thresholds, high bytes
.endif

LAH     = LAHB-YSKY
.ifdef SWR
EINL    = EINLB-(YSKY-1)
RUNT    = $2800                    ; run's store pages (made by init): eight,
                                   ; their first R2OFF bytes code (T0 .. T7)
.else
OL      = OLB-YSKY
.endif

        .assert <PX = 0 && <PY = 0 && <HT = $80 && <CLE = 0, error, "the rows' points and heights"
        .assert <(PX+16+NX-1) + 6*16 < $100, error, "traceb: PX+16+NX-1,y within its page"
        .assert <CLO + 48 < $100, error, "crow: CLO + 48 in its page"
        .assert >CE = >(CO+15), error, "slow2: CE, CO in one page"
        .assert ROWB = ROWA + $100 && <ROWA = 0 && (>ROWA & 1) = 0, error, "the rows: a page each, ROWA's even"
        .assert <DBUF = 0 && <RTBUF = 0, error, "DBUF, RTBUF page-aligned"
        .assert >TOPS = >(BOTS+127) && >CURT = >(CURT+63) && >CURB = >(CURB+63), error, "the column records"
        .assert <RPT = 0 && <RQF = 0, error, "page-aligned tables"
        .assert >QRA = >(QRA+QRAN-1), error, "QRA: in its page"
.ifdef SWR
        .assert <LAHB = YSKY && >EINL = >(EINL+YGND+2), error, "the line tables: indexed within their pages"
.else
        .assert <LAHB = YSKY && <OLB = YSKY, error, "the line tables: their lines' offsets in the page"
        .assert NMI = $0D00, error, "the NMI's RTI at $0D00"
        .assert <MC & $7F = 0 && >R7L = >(R7L+NDI-1) && >R7H = >(R7H+NDI-1), error, "page-aligned tables"
        .assert MGP = MGQ+7 && YQT = MGP+6 && LQT = YQT+7 && SEAI = LQT+7 && HTH = HTL+15, error, "the copied tables in order"
.endif

; ---------------------------------------------------------------- the screen
        .segment "SCREEN"
.ifdef SWR
        .org $3000
LAND0:  .res 20*512                ; the two screens, 160 lines of 64 bytes:
LAND1:  .res 20*512                ; the panel, then the land
        .assert * = $8000, error, "the screen"
PANEL   = 8*512                    ; the panel's bytes at a screen's start
SCR0    = >LAND0                   ; line y at SCRn*256 + 512 (y >> 3) + (y & 7)
SCR1    = >LAND1
.else
        .org $4D40
TOP:    .res 24*8                  ; the panel's row 0: FUEL, the gauge
MAP:    .res 512                   ; the map (row 0's last 8 characters on)
LAND0:  .res 12*512                ; the land buffers
LAND1:  .res 12*512
        .assert <MAP = 0 && LAND0 = $5000 && * = $8000, error, "the screen"
PANEL   = 0                        ; the panel's bytes in a land buffer: none
SCR0    = >LAND0 - $10             ; their virtual screens' pages: line y at
SCR1    = >LAND1 - $10             ; SCRn*256 + 512 (y >> 3) + (y & 7)
.endif

        .reloc
