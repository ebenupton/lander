; ram.s: the memory map, every byte of RAM below the code, by address (the
; stored tables, segment TABLES, follow it).  The layout is absolute, so its
; constraints are checked as it assembles.  The MOS's own bytes are named
; where they fall: $FC (its IRQ entry saves A there), the vectors at $0200,
; the stack's top 19 bytes, and $0D00 (the NMI's target: an RTI).

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
RD:     .res 1                     ; prow32: the row's depth index
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
rrem:   .res 1                     ; the error E
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
TRB:    .res 12                    ; the ship's walker's scratch)
kb:     .res 1                     ; split2: the second rung's transition
pp:     .res 2                     ; run's planted RTS
tsp:    .res 2                     ; the screen's column records
bsp:    .res 2
bpos2:  .res 1                     ; split2's second boundary
smB:    .res 1                     ; smul
smA:    .res 1
smB0:   .res 1
HHI:    .res 1                     ; the row's greatest and least heights
MQB:    .res 1                     ; mul4
HLO:    .res 1
RK:     .res 1                     ; prow32: 16 k
DCUR:   .res 1                     ; prow32: the row's depth index
RN16:   .res 1                     ; 16 RN
rodd:   .res 1                     ; run: the even pass's end entry
wn:     .res 1                     ; rast: the line's segments, faces, DBUF's
WF:     .res 8                     ; next byte
db:     .res 1
        .res 3
OVL:    .res 19                    ; the overlay (below)
HGV:    .res 1                     ; the ground's height under the ship
c_v1:   .res 1                     ; $40: BIT c_v1 sets V
bln:    .res 1                     ; rast's scratch
px8:    .res 1
lx1:    .res 1
tqb:    .res 3
tqa:    .res 3
pxl:    .res 1
lx0:    .res 1
yc:     .res 1
NFL:    .res 1
sxl:    .res 1
pyh:    .res 1
pyl:    .res 1
zrh:    .res 1
zrl:    .res 1
xrh:    .res 1
pxh:    .res 1
xrl:    .res 1
MT0:    .res 1                     ; the projection's scratch
MT1:    .res 1
BCL:    .res 1                     ; the strip's bottom points below YGND
EYV:    .res 1                     ; the row's drop for CAME
CAME:   .res 1                     ; the camera's raise (0..EMAX)
TX:     .res 16                    ; the strip's rows' x's
BX:     .res 16
LO:     .res 16                    ; each rung's pixels LO .. HI-1
HI:     .res 16
        .assert * = $FC, error, "zero page: $FC on are the MOS's"

RVE     = ve                       ; run's bytes
RVO     = vo
fwe     = kk
rsm     = yy
fwu     = tj

; The overlay: scratch for routines that are never live together.
BE      = OVL+1                    ; fsplit: the rung's bytes by bpos, even
BO      = BE+5                     ; and odd lines
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
g0      = OVL+1                    ; game: pointers and scratch
g1      = OVL+3
gt0     = OVL+5
gt1     = OVL+6
gt2     = OVL+7
gt3     = OVL+8
gt4     = OVL+9
tsg     = OVL+11                   ; the screen's column records
bsg     = OVL+13
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
fdr:    .res 1                     ; the gauge as drawn
dpass:  .res 1                     ; dots: the side of the ship
sctl:   .res 1                     ; the noise channel as written
satt:   .res 1
rnd:    .res 1                     ; rand's state
scrg:   .res 1                     ; the screen's page
pnext:  .res 1                     ; the last dot launched
mky:    .res 1                     ; the marker: line ($FF none), column, and
mkt:    .res 1                     ; the bytes under it
mkb:    .res 2
pvxh:   .res NPART                 ; (a dot array)
        .res $0140 - *
LAHB:   .res YGND+2-YSKY           ; LAH,y: 2 (y >> 3), y YSKY..YGND+1
TN:     .res 31                    ; the near row's line by height
ER:     .res 18                    ; the ship's edges
ED:     .res 18
STACK:  .res $0200 - STACK         ; the stack: loop, an IRQ (nesting the sync's)
        .assert STACK = $0200 - 28, error, "the stack: 28 bytes"   ; and an NMI

; ---------------------------------------------------------------- page 2
        .segment "PAGE2"
        .org $0200
USERV:  .res 2                     ; the MOS's
BRKV:   .res 2
IRQ1V:  .res 2                     ; irq
LB:     .res 48                    ; rast: the face at each pixel of a line
MGQ:    .res 6                     ; mapgen: the phases' z steps, x steps
        .res 1
MGP:    .res 6
YQT:    .res 7                     ; mtl's quantiles, the sea's colours
LQT:    .res 7
SEAI:   .res 4
CPX8:   .res 17                    ; rast: the pitched points kept
CPYL:   .res 17
CPYH:   .res 17
cpi:    .res 1                     ; their pitch ($FF none)
cmiss:  .res 1
FBY:    .res 9                     ; the faces' corners
FCY:    .res 9
FBX:    .res 9
FCX3:   .res 9
EX:     .res 18                    ; the faces' edges
EE:     .res 18
EQ:     .res 18
WB:     .res 8                     ; a line's boundaries
ey:     .res 1                     ; ecore's slot, fset's dx
edx:    .res 1
YLO:    .res 1                     ; the faces' lines
YHI:    .res 1
        .res $0300 - *

; ---------------------------------------------------------------- $0300 on
        .segment "RAM"
        .org $0300
DBUF:   .res 256                   ; the ship's bands
ROWA:   .res 256                   ; the rows' lines by pixel
ROWB:   .res 256
RTBUF:  .res 256                   ; the rungs' transitions
PX:     .res 128                   ; the rows' points, 16 a row: x
pvz:    .res NPART                 ; (dot arrays)
pvzh:   .res NPART
pvy:    .res NPART
pvyh:   .res NPART
ZB:     .res 1                     ; row 0's map row less czt
RN:     .res 1                     ; the near row
FACT:   .res 1                     ; the far row lerped
GSHK:   .res 1                     ; the ship as drawn: direction, pitch,
GSHP:   .res 1                     ; centre, and whether
GSHX:   .res 1
GSHY:   .res 1
GSHV:   .res 1
HTN:    .res 11                    ; zsh4's new row of heights
PATON:  .res 16                    ; rast: each pattern's end in PATF
ncame:  .res 1                     ; the near row's EYV and its CAME
neyv:   .res 1
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
PY:     .res 128                   ; the rows' points: y
HT:     .res 128                   ; the rows' heights (+11, +12 range, +13 EYV)
CLE:    .res 160                   ; the colour window: even, odd lines
CLO:    .res 160
BY:     .res 16                    ; the strip's bottom row: y
RTPL:   .res 16                    ; each rung's transitions' base
CE:     .res 16                    ; each box's bytes, even and odd lines
CO:     .res 16
SPB:    .res 16                    ; slow: each pixel's box, transitions
STL:    .res 16
STD:    .res 16
B1N:    .res 32                    ; the near row's corner 1 by cxs
PATN:   .res 16                    ; rast: each pattern's faces
PATF:   .res 96
CURT:   .res 64                    ; this frame's column records
CURB:   .res 64
YT:     .res 16                    ; ytab: the row's line by height
LIM:    .res 48                    ; the walker's: by boundary
TOPS:   .res 128                   ; each screen's column records
BOTS:   .res 128
NMI:    .res 1                     ; the MOS's NMI target: an RTI
vlast:  .res 1                     ; the field of the last flip
ECAME:  .res 1                     ; the CAME, czs the rows' EYVs are for
ECZS:   .res 1
EHIT:   .res 1
MCB:    .res 11                    ; the map window's columns' first slots
KTN:    .res 48                    ; the walker's: by boundary
OLB:    .res YGND+3-YSKY           ; OL,y: line y's entry in a parity table
dpi:    .res 1                     ; rast: the attitude DBUF holds
dal:    .res 1
bxl:    .res 1                     ; the ship's box, and its offsets
bxr:    .res 1
byt:    .res 1
byb:    .res 1
OYT:    .res 1
OYB:    .res 1
OXL:    .res 1
OXR:    .res 1
FCE:    .res 9                     ; each face's dither, even and even ^ odd
FCX:    .res 9
ca:     .res 1                     ; the angles
sa:     .res 1
cb:     .res 1
sb:     .res 1
tql:    .res 1                     ; tq8's product
tqh:    .res 1
SXV:    .res 9                     ; the vertices' offsets
SYV:    .res 9
NVIS:   .res 1                     ; the normals: shown, lit, brightness
NNEG:   .res 1
NBR:    .res 8
EOFS    = 9                        ; the short edges' slots: + EOFS
fi:     .res 1                     ; fset: the face, its corners
cx3:    .res 3
cy3:    .res 3
FID:    .res 9                     ; each face set up: its number, lines
FAY:    .res 9
bh:     .res 1                     ; rast: the open band, the patterns
NPAT:   .res 1
PEND:   .res 1
PATTOP: .res 1
        .res 3
RPT:    .res 256                   ; the rungs' tables (grung)
RQF:    .res 256
plife:  .res NPART                 ; (dot arrays)
ppx:    .res NPART
ppxh:   .res NPART
ppz:    .res NPART
R7L:    .res NDI                   ; r by depth index
ppzh:   .res NPART
ppy:    .res NPART
ppyh:   .res NPART
pvx:    .res NPART
R7H:    .res NDI
MC:     .res 128                   ; the map window's ring
TEN4L:  .res TNB+1                 ; the fills' entries
TEN5L:  .res TNB+1
BYN:    .res 48                    ; the walker's: by boundary
LUT:    .res 32                    ; mtl's colours
TEN4H:  .res TNB+1
TEN5H:  .res TNB+1
PAL:    .res 17                    ; rast's products, for a point's twin
PAH:    .res 17
PBL:    .res 17
PBH:    .res 17
QRA:    .res QRAN                  ; div8's table, and its rows
QOA:    .res 7
HTL:    .res 15                    ; mapgen's height thresholds
HTH:    .res 15
PCL:    .res 17
PCH:    .res 17
PDL:    .res 17
PDH:    .res 17

OL      = OLB-YSKY
LAH     = LAHB-YSKY

        .assert <PX = 0 && <PY = 0 && <HT = $80 && <CLE = 0, error, "the rows' points and heights"
        .assert <(PX+16+NX-1) + 6*16 < $100, error, "traceb: PX+16+NX-1,y within its page"
        .assert <CLO + 48 < $100, error, "crow: CLO + 48 in its page"
        .assert >CE = >(CO+15), error, "slow2: CE, CO in one page"
        .assert ROWB = ROWA + $100 && <ROWA = 0 && (>ROWA & 1) = 0, error, "the rows: a page each, ROWA's even"
        .assert <DBUF = 0 && <RTBUF = 0, error, "DBUF, RTBUF page-aligned"
        .assert <LAHB = YSKY && <OLB = YSKY, error, "the line tables: their lines' offsets in the page"
        .assert >TOPS = >(BOTS+127) && >CURT = >(CURT+63) && >CURB = >(CURB+63), error, "the column records"
        .assert NMI = $0D00, error, "the NMI's RTI at $0D00"
        .assert <RPT = 0 && <RQF = 0 && <MC & $7F = 0 && >R7L = >(R7L+NDI-1) && >R7H = >(R7H+NDI-1), error, "page-aligned tables"
        .assert >TEN4H = >(TEN5H+TNB) && >QRA = >(QRA+QRAN-1), error, "TEN4H, TEN5H, QRA: one page"
        .assert MGP = MGQ+7 && YQT = MGP+6 && LQT = YQT+7 && SEAI = LQT+7 && HTH = HTL+15, error, "the copied tables in order"

; ---------------------------------------------------------------- the screen
        .segment "SCREEN"
        .org $4D40
TOP:    .res 24*8                  ; the panel's row 0: FUEL, the gauge
MAP:    .res 512                   ; the map (row 0's last 8 characters on)
LAND0:  .res 12*512                ; the land buffers
LAND1:  .res 12*512
        .assert <MAP = 0 && LAND0 = $5000 && * = $8000, error, "the screen"
SCR0    = >LAND0 - $10             ; their virtual screens' pages: line y at
SCR1    = >LAND1 - $10             ; SCRn*256 + 512 (y >> 3) + (y & 7)

        .reloc
