# The memory map of the 32K build

Written by `tools/memmap.py` from the linked builds; the gate fails if it is not
current. [memory-map.md](memory-map.md) explains the layout. Addresses and sizes
are the MODE 1 version's unless a table says otherwise.

## Main RAM

| from | to | bytes | contents |
|---|---|---|---|
| `$0000` | `$00F8` | 249 | zero page: the variables |
| `$00F9` | `$00FB` | 3 | free |
| `$00FC` | `$00FF` | 4 | the MOS's: `$FC`, where its interrupt entry saves A; `$FD`-`$FF` |
| `$0100` | `$01E3` | 228 | page 1: variables and tables below the stack |
| `$01E4` | `$01FF` | 28 | the stack |
| `$0200` | `$0205` | 6 | the MOS's vectors: `USERV`, `BRKV`, `IRQ1V` (the program's `irq`) |
| `$0206` | `$02FF` | 250 | page 2: variables |
| `$0300` | `$14FC` | 4605 | the workspace: buffers and tables (`$0D00`: the NMI's `RTI`) |
| `$14FD` | `$1876` | 890 | the stored tables |
| `$1877` | `$1954` | 222 | free: the free block |
| `$1955` | `$1B17` | 451 | the fills (generated code) |
| `$1B18` | `$48FF` | 11752 | the code |
| `$4900` | `$4992` | 147 | parity table 0 (generated code) |
| `$4993` | `$49F5` | 99 | parity page 0: code |
| `$49F6` | `$49FF` | 10 | free |
| `$4A00` | `$4A92` | 147 | parity table 1 (generated code) |
| `$4A93` | `$4AFB` | 105 | parity page 1: code |
| `$4AFC` | `$4AFF` | 4 | free |
| `$4B00` | `$4B92` | 147 | parity table 2 (generated code) |
| `$4B93` | `$4BFF` | 109 | parity page 2: code |
| `$4C00` | `$4C92` | 147 | parity table 3 (generated code) |
| `$4C93` | `$4CF9` | 103 | parity page 3: code |
| `$4CFA` | `$4CFF` | 6 | free |
| `$4D00` | `$4D3F` | 64 | code |
| `$4D40` | `$4DFF` | 192 | the panel's row 0: FUEL and the gauge |
| `$4E00` | `$4FFF` | 512 | the panel's map |
| `$5000` | `$67FF` | 6144 | land buffer 0 |
| `$6800` | `$7FFF` | 6144 | land buffer 1 |

270 bytes are free: the 222 of the free block between the data and the code,
23 more in the table above, and 25 within pages 1 and 2 and the workspace (the tables
below show each).

## By version

| version | data ends | code starts | free block | stored tables | code | start-up (discarded) |
|---|---|---|---|---|---|---|
| mode1 | `$1876` | `$1955` | 222 | 890 | 12203 | 1683 |
| cpc | `$189E` | `$1955` | 182 | 930 | 12203 | 1663 |
| nula | `$1896` | `$1955` | 190 | 922 | 12203 | 1708 |
| arc | `$1932` | `$1A17` | 228 | 1078 | 12009 | 1707 |

## Zero page

| address | bytes | name | use |
|---|---|---|---|
| `$0000` | 1 | `tyy` | t_steep: the line (tg_op's INC or DEC); tr_l: the error kept |
| `$0001` | 13 | `TY` | the strip's top row: y (TX: x) |
| `$000E` | 1 | `cxt` | the camera: its tile, x |
| `$000F` | 1 | `cxs` | its sixteenth of a tile, x |
| `$0010` | 1 | `czt` | its tile, z |
| `$0011` | 1 | `czs` | its sixteenth, z |
| `$0012` | 1 | `back` | the screen being drawn (0, 1) |
| `$0013` | 1 | `scrb` | its base page |
| `$0014` | 1 | `np` | points a row |
| `$0015` | 1 | `nr` | rows (7 or 8) |
| `$0016` | 1 | `vcount` | fields |
| `$0017` | 2 | `ptr` | scratch: a pointer |
| `$0019` | 2 | `tmp` | scratch: a word |
| `$001B` | 1 | `tfe` | t_flo: the run's end |
| `$001C` | 1 | `tfn` | t_flo: the last fill's stores skipped |
| `$001D` | 1 | `ph_e` | phase's end |
| `$001E` | 1 | `rl` | the row's r, low byte; the 32K build's run: the covered STA's operand, likewise |
| `$001F` | 1 | `rh` | their high bytes |
| `$0020` | 1 | `ns` | the strip (0 the farthest) |
| `$0021` | 1 | `xl` | its left margin |
| `$0022` | 1 | `xr` | its right margin |
| `$0023` | 1 | `xlp` | the last strip's left margin |
| `$0024` | 1 | `xrp` | the last strip's right margin |
| `$0025` | 2 | `topa` | the strip's top row's lines by pixel (ROWA or ROWB) |
| `$0027` | 2 | `bota` | its bottom row's (the other) |
| `$0029` | 1 | `tdx2` | traceb: 2 dx; t_flo: Y kept |
| `$002A` | 1 | `terr` | traceb: dx, then the error |
| `$002B` | 1 | `tj` | traceb: the segment; elsewhere a rung, a pixel or a column kept |
| `$002C` | 1 | `tyv` | traceb: the pending run's line |
| `$002D` | 1 | `ra2` | 2a (a: dy's size) |
| `$002E` | 1 | `rq` | D div 2a, then q2 + 1 |
| `$002F` | 1 | `rrem` | the error E; rfast's yt |
| `$0030` | 1 | `rq2` | D div a |
| `$0031` | 1 | `rr2` | 2 (D mod a) |
| `$0032` | 2 | `alloc` | RTBUF's next free byte |
| `$0034` | 2 | `rtp` | a rung's transitions by pixel |
| `$0036` | 1 | `dva` | a; the divisor |
| `$0037` | 1 | `dvd` | D; the dividend |
| `$0038` | 1 | `tcnt` | traceb: the pending run's first x |
| `$0039` | 1 | `tsy` | gone: the first column right of the strip |
| `$003A` | 1 | `last` | $FF: the near strip |
| `$003B` | 1 | `lastri` | the rung fsplit's tables are for |
| `$003C` | 1 | `x4` | the column's first x |
| `$003D` | 1 | `coff` | its byte offset, 8 x4/4 mod 256 |
| `$003E` | 1 | `scrh` | its screen half's page |
| `$003F` | 1 | `ri` | the first rung not wholly left of it |
| `$0040` | 4 | `ys` | each pixel's top-row line |
| `$0044` | 1 | `mn` | the top's highest line |
| `$0045` | 1 | `mx` | the top's lowest line |
| `$0046` | 1 | `flr` | the near strip's floor when it slopes |
| `$0047` | 1 | `flr1` | the line the column ends before |
| `$0048` | 1 | `ve` | the byte drawn on even lines |
| `$0049` | 1 | `vo` | the byte drawn on odd lines |
| `$004A` | 1 | `bpos` | a boundary: the pixels left of a rung |
| `$004B` | 1 | `p1` | mktr's bottom boundary |
| `$004C` | 1 | `yy` | split2, slow2: a line; fsplit: rsm |
| `$004D` | 1 | `kk` | split2: a transition; fsplit: fwe |
| `$004E` | 1 | `msk` | the pixels drawn on a line |
| `$004F` | 1 | `zv` | zline's byte |
| `$0050` | 2 | `zp_` | a line's address |
| `$0052` | 1 | `dvx` | div8's divisor |
| `$0053` | 1 | `svE` | ve kept round a black run |
| `$0054` | 1 | `svO` | vo kept round a black run |
| `$0055` | 16 | `TRL` | mktr's transitions' lines (12; TRB their masks); all 16 the ship's scratch |
| `$0065` | 1 | `kb` | split2: the second rung's transition |
| `$0066` | 2 | `tsp` | gone: the drawn screen's column tops |
| `$0068` | 2 | `bsp` | gone: its column bottoms |
| `$006A` | 1 | `bpos2` | split2's second boundary |
| `$006B` | 1 | `DCUR` | the row's depth index |
| `$006C` | 1 | `RN16` | 16 RN |
| `$006D` | 19 | `OVL` | the overlay (below) |
| `$0080` | 1 | `HGV` | the ground's height under the ship |
| `$0081` | 1 | `c_v1` | $40: BIT c_v1 sets V |
| `$0082` | 1 | `MT0` | the projection's scratch |
| `$0083` | 1 | `MT1` | the projection's scratch |
| `$0084` | 1 | `BCL` | the strip's bottom points below YGND |
| `$0085` | 1 | `EYV` | the row's drop for CAME |
| `$0086` | 1 | `CAME` | the camera's raise (0..EMAX) |
| `$0087` | 16 | `TX` | the strip's top row: x |
| `$0097` | 16 | `BX` | the strip's bottom row: x |
| `$00A7` | 16 | `LO` | each rung's first pixel |
| `$00B7` | 16 | `HI` | the pixel after each rung's last |
| `$00C7` | 2 | `su` | the game: the height in units, 8.8 |
| `$00C9` | 1 | `dpass` | dots: the side of the ship |
| `$00CA` | 1 | `scrg` | the game: the drawn screen's page |
| `$00CB` | 1 | `RD` | prow32: the row's depth index |
| `$00CC` | 2 | `pp` | run's planted RTS |
| `$00CE` | 1 | `smB` | smul: Y's bits, then the low product |
| `$00CF` | 1 | `smA` | smul: A |
| `$00D0` | 1 | `smB0` | smul: Y |
| `$00D1` | 1 | `HHI` | the row's greatest height |
| `$00D2` | 1 | `MQB` | mul4: LQ's bits |
| `$00D3` | 1 | `HLO` | the row's least height |
| `$00D4` | 1 | `RK` | prow32: 16 k |
| `$00D5` | 1 | `rodd` | run: the even pass's end entry |
| `$00D6` | 1 | `wn` | rast: the line's segments |
| `$00D7` | 8 | `WF` | rast: each segment's face |
| `$00DF` | 1 | `db` | rast: DBUF's next byte |
| `$00E0` | 1 | `bln` | rast: the open band's lines |
| `$00E1` | 1 | `px8` | rast: a point pitched, x (px >> 6) |
| `$00E2` | 1 | `lx1` | rast: the pixel after the line's last |
| `$00E3` | 1 | `tqb` | tq8: the sum's high byte |
| `$00E4` | 2 | `tqa` | tq8: V |
| `$00E6` | 1 | `pxl` | rast: px, low byte |
| `$00E7` | 1 | `lx0` | rast: the line's first pixel |
| `$00E8` | 1 | `yc` | rast: the line |
| `$00E9` | 1 | `NFL` | rast: the faces set up |
| `$00EA` | 1 | `sxl` | fline: the span's first pixel |
| `$00EB` | 1 | `pyh` | rast: a point pitched, y, high byte |
| `$00EC` | 1 | `pyl` | rast: its low byte |
| `$00ED` | 1 | `zrh` | rast: a point turned, Zr, high byte |
| `$00EE` | 1 | `zrl` | rast: its low byte |
| `$00EF` | 1 | `xrh` | rast: a point turned, Xr, high byte |
| `$00F0` | 1 | `pxh` | rast: px, high byte |
| `$00F1` | 1 | `xrl` | rast: Xr, low byte |
| `$00F2` | 1 | `tql` | tq8's product, low byte |
| `$00F3` | 1 | `tqh` | tq8's product, high byte |
| `$00F4` | 1 | `NPAT` | rast: the last pattern |
| `$00F5` | 1 | `edx` | fset's dx |
| `$00F6` | 1 | `bh` | rast: the open band's header ($FF none) |
| `$00F7` | 1 | `YHI` | the line after the faces' last |
| `$00F8` | 1 | `fi` | fset: the face |
| `$00F9` | 3 | | free |

## Page 1

| address | bytes | name | use |
|---|---|---|---|
| `$0100` | 1 | `tx` | the game: the thrust's x part |
| `$0101` | 1 | `tz` | the thrust's z part |
| `$0102` | 1 | `gkb` | the keys |
| `$0103` | 1 | `gk` | the ship's direction |
| `$0104` | 1 | `gp` | the ship's pitch |
| `$0105` | 1 | `thr` | thrusting (spawn zeroes thr .. gvz) |
| `$0106` | 1 | `landed` | landed |
| `$0107` | 1 | `ctim` | crashed: steps left |
| `$0108` | 3 | `sx` | the ship's position, 24 bits: x |
| `$010B` | 3 | `sz` | its z |
| `$010E` | 3 | `sy` | its y |
| `$0111` | 2 | `gvx` | the ship's velocity: x |
| `$0113` | 2 | `gvy` | its y |
| `$0115` | 2 | `gvz` | its z |
| `$0117` | 2 | `fuel` | the fuel left |
| `$0119` | 1 | `sctl` | the noise channel's control as written |
| `$011A` | 1 | `satt` | its attenuation as written |
| `$011B` | 1 | `rnd` | rand's state |
| `$011C` | 1 | `pnext` | the last dot launched |
| `$011D` | 1 | `fdr` | the gauge as drawn |
| `$011E` | 1 | `mky` | the marker: line ($FF none) |
| `$011F` | 1 | `mkt` | the marker: pixel |
| `$0120` | 2 | `mkb` | the two bytes under the marker |
| `$0122` | 20 | `pvxh` | the dots: x velocity, high byte |
| `$0136` | 10 | | free |
| `$0140` | 97 | `LAHB` | LAH,y: 2 (y >> 3), y YSKY..YGND+1 |
| `$01A1` | 31 | `TN` | the near row's line by h - hg + 15 |
| `$01C0` | 18 | `ER` | the ship's edges: dx mod dy |
| `$01D2` | 18 | `ED` | the ship's edges: dy |

## Page 2

| address | bytes | name | use |
|---|---|---|---|
| `$0206` | 48 | `LB` | rast: the face at each pixel of a line |
| `$0236` | 6 | `MGQ` | mapgen: the phases' z steps |
| `$023C` | 1 | | free |
| `$023D` | 6 | `MGP` | mapgen: the phases' x steps |
| `$0243` | 7 | `YQT` | mtl: TY's quantiles |
| `$024A` | 7 | `LQT` | mtl: TL's quantiles |
| `$0251` | 4 | `SEAI` | mtl: the sea's colours |
| `$0255` | 17 | `CPX8` | rast: the pitched points kept: px8 |
| `$0266` | 17 | `CPYL` | their py, low byte |
| `$0277` | 17 | `CPYH` | their py, high byte |
| `$0288` | 1 | `cpi` | their pitch ($FF none) |
| `$0289` | 1 | `cmiss` | rast: $FF if the pitch has changed |
| `$028A` | 9 | `FBY` | the faces' corners: b's line |
| `$0293` | 9 | `FCY` | c's line |
| `$029C` | 9 | `FBX` | b's x |
| `$02A5` | 9 | `FCX3` | c's x |
| `$02AE` | 18 | `EX` | the faces' edges: x |
| `$02C0` | 18 | `EE` | the faces' edges: the error |
| `$02D2` | 18 | `EQ` | the faces' edges: dx div dy |
| `$02E4` | 8 | `WB` | a line's boundaries |
| `$02EC` | 1 | `ey` | ecore's slot |
| `$02ED` | 1 | `YLO` | the faces' first line |
| `$02EE` | 12 | `TRB` | mktr's transitions: the masks |
| `$02FA` | 6 | | free |

## The workspace

| address | bytes | name | use |
|---|---|---|---|
| `$0300` | 256 | `DBUF` | the ship's bands |
| `$0400` | 256 | `ROWA` | a row's lines by pixel |
| `$0500` | 256 | `ROWB` | the other row's |
| `$0600` | 256 | `RTBUF` | the rungs' transitions |
| `$0700` | 128 | `PX` | the rows' points, 16 a row: x |
| `$0780` | 20 | `pvz` | the dots: z velocity, low byte |
| `$0794` | 20 | `pvzh` | the dots: z velocity, high byte |
| `$07A8` | 20 | `pvy` | the dots: y velocity, low byte |
| `$07BC` | 20 | `pvyh` | the dots: y velocity, high byte |
| `$07D0` | 1 | `ZB` | row 0's map row less czt |
| `$07D1` | 1 | `RN` | the near row |
| `$07D2` | 1 | `FACT` | 1: the far row is lerped |
| `$07D3` | 1 | `GSHK` | the ship as drawn: direction |
| `$07D4` | 1 | `GSHP` | its pitch |
| `$07D5` | 1 | `GSHX` | its centre's x |
| `$07D6` | 1 | `GSHY` | its centre's line |
| `$07D7` | 1 | `GSHV` | 0: not drawn (crashed) |
| `$07D8` | 11 | `HTN` | the row of heights zsh4 fetches |
| `$07E3` | 16 | `PATON` | rast: each pattern's end in PATF |
| `$07F3` | 1 | `ncame` | the CAME the near row's EYV is for |
| `$07F4` | 1 | `neyv` | the near row's EYV |
| `$07F5` | 1 | `tdy2` | traceb: twice dy's size |
| `$07F6` | 1 | `tx1` | traceb: x1; slow: the pixel's x |
| `$07F7` | 1 | `x4p4` | slow: x4 + 4 |
| `$07F8` | 1 | `re` | split2: the right box, even lines |
| `$07F9` | 1 | `ro` | split2: the right box, odd lines |
| `$07FA` | 1 | `le` | split2: the left box, even lines |
| `$07FB` | 1 | `lo2` | split2: the left box, odd lines |
| `$07FC` | 1 | `me` | split2: middle ^ right, even lines |
| `$07FD` | 1 | `mo` | split2: middle ^ right, odd lines |
| `$07FE` | 1 | `p0` | mktr's top boundary |
| `$07FF` | 1 | `vflip` | the flip's field (less one: shown at once) |
| `$0800` | 128 | `PY` | the rows' points: y |
| `$0880` | 128 | `HT` | the rows' heights, 16 a row (+13 its EYV; the 32K build: +11, +12 its range) |
| `$0900` | 160 | `CLE` | the colour window: even lines |
| `$09A0` | 160 | `CLO` | the colour window: odd lines |
| `$0A40` | 16 | `BY` | the strip's bottom row: y |
| `$0A50` | 16 | `RTPL` | each rung's transitions' base |
| `$0A60` | 16 | `CE` | each box's byte on even lines |
| `$0A70` | 16 | `CO` | each box's byte on odd lines |
| `$0A80` | 16 | `SPB` | slow: each pixel's box |
| `$0A90` | 16 | `STL` | slow: each pixel's transitions' lines |
| `$0AA0` | 16 | `STD` | slow: the box's change at each |
| `$0AB0` | 32 | `B1N` | the near row's corner 1 by cxs |
| `$0AD0` | 16 | `PATN` | rast: each pattern's segments |
| `$0AE0` | 96 | `PATF` | rast: the patterns' faces |
| `$0B40` | 64 | `CURT` | the third set's tops (see TOPS) |
| `$0B80` | 64 | `CURB` | the third set's bottoms |
| `$0BC0` | 16 | `YT` | ytab: the row's line by height |
| `$0BD0` | 48 | `LIM` | the walker's, by boundary: the next byte's first boundary |
| `$0C00` | 128 | `TOPS` | two sets of column records: tops.  Of the three sets, one is each screen's and one this frame's, in turn (sidx, cidx) |
| `$0C80` | 128 | `BOTS` | the two sets' bottoms |
| `$0D00` | 1 | `NMI` | the MOS's NMI target: an RTI |
| `$0D01` | 1 | `vlast` | the field of the last flip |
| `$0D02` | 1 | `ECAME` | the CAME the rows' EYVs are for |
| `$0D03` | 1 | `ECZS` | the czs the rows' EYVs are for |
| `$0D04` | 1 | `EHIT` | $80: the rows' EYVs kept |
| `$0D05` | 11 | `MCB` | the map window's columns' first slots |
| `$0D10` | 48 | `KTN` | the walker's, by boundary: the mask of the pixels before it in its byte |
| `$0D40` | 98 | `OLB` | OL,y: line y's entry in a parity table |
| `$0DA2` | 1 | `dpi` | the pitch DBUF holds |
| `$0DA3` | 1 | `dal` | the al (GSHX & 3) DBUF holds |
| `$0DA4` | 1 | `bxl` | the ship's box: left |
| `$0DA5` | 1 | `bxr` | the ship's box: right |
| `$0DA6` | 1 | `byt` | the ship's box: top |
| `$0DA7` | 1 | `byb` | the ship's box: bottom |
| `$0DA8` | 1 | `OYT` | the box's offsets from the centre: top |
| `$0DA9` | 1 | `OYB` | the box's offsets: bottom |
| `$0DAA` | 1 | `OXL` | the box's offsets: left |
| `$0DAB` | 1 | `OXR` | the box's offsets: right |
| `$0DAC` | 9 | `FCE` | each face's dither: even lines |
| `$0DB5` | 9 | `FCX` | each face's dither: even ^ odd |
| `$0DBE` | 1 | `ca` | rast: the pitch's cosine |
| `$0DBF` | 1 | `sa` | rast: the pitch's sine |
| `$0DC0` | 1 | `cb` | rast: the direction's cosine |
| `$0DC1` | 1 | `sb` | rast: the direction's sine |
| `$0DC2` | 9 | `SXV` | the vertices' offsets: x |
| `$0DCB` | 9 | `SYV` | the vertices' offsets: y |
| `$0DD4` | 1 | `NVIS` | the normals: a bit each, shown |
| `$0DD5` | 1 | `NNEG` | the normals: a bit each, lit |
| `$0DD6` | 8 | `NBR` | the normals: brightness |
| `$0DDE` | 3 | `cx3` | fset: the face's corners' x |
| `$0DE1` | 3 | `cy3` | fset: the face's corners' lines |
| `$0DE4` | 9 | `FID` | each face set up: its number |
| `$0DED` | 9 | `FAY` | each face set up: its first line |
| `$0DF6` | 1 | `PEND` | rast: the open band's segments |
| `$0DF7` | 1 | `PATTOP` | rast: PATF's next byte |
| `$0DF8` | 8 | | free |
| `$0E00` | 256 | `RPT` | the rungs' tables (grung): the patterns |
| `$0F00` | 256 | `RQF` | the rungs' tables: 16 q2 + t(1) |
| `$1000` | 20 | `plife` | the dots: life |
| `$1014` | 20 | `ppx` | the dots: x, 8.8 tiles, low byte |
| `$1028` | 20 | `ppxh` | the dots: x, high byte |
| `$103C` | 20 | `ppz` | the dots: z, 8.8 tiles, low byte |
| `$1050` | 176 | `R7L` | r by depth index, low byte |
| `$1100` | 20 | `ppzh` | the dots: z, high byte |
| `$1114` | 20 | `ppy` | the dots: y, 8.8 units, low byte |
| `$1128` | 20 | `ppyh` | the dots: y, high byte |
| `$113C` | 20 | `pvx` | the dots: x velocity, low byte |
| `$1150` | 176 | `R7H` | r by depth index, high byte |
| `$1200` | 128 | `MC` | the map window's ring |
| `$1280` | 65 | `TENL` | the fills' entries by stores: low byte |
| `$12C1` | 65 | `TEN4H` | TBLK4's entries' pages |
| `$1302` | 48 | `BYN` | the walker's, by boundary: its byte |
| `$1332` | 17 | `PAL` | rast's products, kept for a point's twin: cb px8, low byte |
| `$1343` | 17 | `PAH` | cb px8, high byte |
| `$1354` | 17 | `PBL` | sb px8, low byte |
| `$1365` | 17 | `PBH` | sb px8, high byte |
| `$1376` | 17 | `PCL` | sb Z, low byte |
| `$1387` | 17 | `PCH` | sb Z, high byte |
| `$1398` | 17 | `PDL` | cb Z, low byte |
| `$13A9` | 17 | `PDH` | cb Z, high byte |
| `$13BA` | 7 | `QOA` | div8's rows |
| `$13C1` | 65 | `TEN5H` | TBLK5's entries' pages |
| `$1402` | 32 | `LUT` | mtl's colours |
| `$1422` | 189 | `QRA` | div8's table |
| `$14DF` | 15 | `HTL` | mapgen's height thresholds, low bytes |
| `$14EE` | 15 | `HTH` | mapgen's height thresholds, high bytes |

## The stored tables

Segment `TABLES`: constant tables that the file holds and the start-up copies here.

| address | bytes | name |
|---|---|---|
| `$14FD` | 1 | `WX` |
| `$14FE` | 1 | `WK` |
| `$14FF` | 1 | `WO` |
| `$1500` | 1 | `VLO` |
| `$1501` | 1 | `VHI` |
| `$1502` | 1 | `WE` |
| `$1503` | 1 | `WM` |
| `$1504` | 1 | `pkx` |
| `$1505` | 1 | `pkz` |
| `$1506` | 1 | `SHF` |
| `$1507` | 15 | `DCE` |
| `$1516` | 15 | `DCO` |
| `$1525` | 4 | `SDL` |
| `$1529` | 4 | `SWO` |
| `$152D` | 4 | `SCA` |
| `$1531` | 4 | `SCY` |
| `$1535` | 4 | `STX0` |
| `$1539` | 4 | `STY0` |
| `$153D` | 2 | `MWT` |
| `$153F` | 1 | `MWX` |
| `$1540` | 1 | `MWZ` |
| `$1541` | 1 | `MWO` |
| `$1542` | 1 | `MOK` |
| `$1543` | 64 | `SL` |
| `$1583` | 64 | `RA` |
| `$15C3` | 2 | `sidx` |
| `$15C5` | 1 | `cidx` |
| `$15C6` | 3 | `setTl` |
| `$15C9` | 3 | `setTh` |
| `$15CC` | 3 | `setBl` |
| `$15CF` | 3 | `setBh` |
| `$15D2` | 2 | `tfbl` |
| `$15D4` | 2 | `tfbh` |
| `$15D6` | 9 | `rg_rbe` |
| `$15DF` | 9 | `rg_lbe` |
| `$15E8` | 2 | `zbt0` |
| `$15EA` | 2 | `zbt1` |
| `$15EC` | 2 | `npt0` |
| `$15EE` | 2 | `npt1` |
| `$15F0` | 2 | `npt2` |
| `$15F2` | 4 | `shs` |
| `$15F6` | 16 | `MASKB` |
| `$1606` | 16 | `MASKN` |
| `$1616` | 5 | `LM` |
| `$161B` | 4 | `PIXM` |
| `$161F` | 6 | `CTZ` |
| `$1625` | 9 | `CT0` |
| `$162E` | 5 | `CTB0` |
| `$1633` | 11 | `CTB` |
| `$163E` | 9 | `CTA` |
| `$1647` | 8 | `lfront` |
| `$164F` | 1 | `evn` |
| `$1650` | 18 | `GSHYT` |
| `$1662` | 5 | `BARB` |
| `$1667` | 40 | `EXNL` |
| `$168F` | 40 | `EXNH` |
| `$16B7` | 40 | `EXA` |
| `$16DF` | 13 | `THY` |
| `$16EC` | 63 | `TQ` |
| `$172B` | 17 | `VQX` |
| `$173C` | 17 | `VQY` |
| `$174D` | 17 | `VQZ` |
| `$175E` | 17 | `TWIN` |
| `$176F` | 32 | `SINT` |
| `$178F` | 13 | `PSIN` |
| `$179C` | 13 | `PCOS` |
| `$17A9` | 9 | `FV0` |
| `$17B2` | 9 | `FV1` |
| `$17BB` | 9 | `FV2` |
| `$17C4` | 9 | `FHUE` |
| `$17CD` | 9 | `FGRN` |
| `$17D6` | 48 | `RAMPE` |
| `$1806` | 48 | `RAMPO` |
| `$1836` | 7 | `PNL` |
| `$183D` | 7 | `CNL` |
| `$1844` | 7 | `SGL` |
| `$184B` | 7 | `SGH` |
| `$1852` | 7 | `FLL` |
| `$1859` | 7 | `PNH` |
| `$1860` | 7 | `CNH` |
| `$1867` | 7 | `FLH` |
| `$186E` | 8 | `BIT8` |
| `$1876` | 1 | `dk` |

## The code by source file

| file | main RAM | start-up |
|---|---|---|
| `columns.s` | 2826 |  |
| `ship.s` | 2363 | 39 |
| `game.s` | 2014 | 54 |
| `project.s` | 1910 |  |
| `strips.s` | 1190 |  |
| `mapgen.s` | 935 |  |
| `tabgen.s` |  | 736 |
| `boot.s` |  | 666 |
| `rungs.s` | 545 |  |
| `video.s` | 337 |  |
| `mapgen.inc` |  | 125 |
| `lander.s` | 112 |  |
| `neartab.inc` |  | 63 |
| total | 12232 | 1683 |
