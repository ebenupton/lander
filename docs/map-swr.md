# The memory map of the sideways RAM build

Written by `tools/memmap.py` from the linked builds; the gate fails if it is not
current. [memory-map.md](memory-map.md) explains the layout. Addresses and sizes
are the MODE 1 version's unless a table says otherwise.

## Main RAM

| from | to | bytes | contents |
|---|---|---|---|
| `$0000` | `$00F7` | 248 | zero page: the variables |
| `$00F8` | `$00FB` | 4 | free |
| `$00FC` | `$00FF` | 4 | the MOS's: `$FC`, where its interrupt entry saves A; `$FD`-`$FF` |
| `$0100` | `$01A0` | 161 | page 1: variables and tables below the stack |
| `$01A1` | `$01FF` | 95 | the stack |
| `$0200` | `$0205` | 6 | the MOS's vectors: `USERV`, `BRKV`, `IRQ1V` (the program's `irq`) |
| `$0206` | `$02FF` | 250 | page 2: variables |
| `$0300` | `$0CFF` | 2560 | the workspace: buffers and tables |
| `$0D00` | `$0DFF` | 256 | the MOS's: page `$0D`, a Master's NMI code and extended vectors |
| `$0E00` | `$10BC` | 701 | the workspace |
| `$10BD` | `$111C` | 96 | the stored tables |
| `$111D` | `$1783` | 1639 | free: the free block |
| `$1784` | `$27FF` | 4220 | the code |
| `$2800` | `$2853` | 84 | store page 0: code |
| `$2854` | `$286E` | 27 | free |
| `$286F` | `$28FF` | 145 | store page 0: the store table (generated code) |
| `$2900` | `$2955` | 86 | store page 1: code |
| `$2956` | `$296E` | 25 | free |
| `$296F` | `$29FF` | 145 | store page 1: the store table (generated code) |
| `$2A00` | `$2A4D` | 78 | store page 2: code |
| `$2A4E` | `$2A6E` | 33 | free |
| `$2A6F` | `$2AFF` | 145 | store page 2: the store table (generated code) |
| `$2B00` | `$2B10` | 17 | store page 3: code |
| `$2B11` | `$2B6E` | 94 | free |
| `$2B6F` | `$2BFF` | 145 | store page 3: the store table (generated code) |
| `$2C00` | `$2C20` | 33 | store page 4: code |
| `$2C21` | `$2C6E` | 78 | free |
| `$2C6F` | `$2CFF` | 145 | store page 4: the store table (generated code) |
| `$2D00` | `$2D44` | 69 | store page 5: code |
| `$2D45` | `$2D6E` | 42 | free |
| `$2D6F` | `$2DFF` | 145 | store page 5: the store table (generated code) |
| `$2E00` | `$2E5B` | 92 | store page 6: code |
| `$2E5C` | `$2E6E` | 19 | free |
| `$2E6F` | `$2EFF` | 145 | store page 6: the store table (generated code) |
| `$2F00` | `$2F56` | 87 | store page 7: code |
| `$2F57` | `$2F6E` | 24 | free |
| `$2F6F` | `$2FFF` | 145 | store page 7: the store table (generated code) |
| `$3000` | `$57FF` | 10240 | screen 0: the panel's 8 rows, the land's 12 |
| `$5800` | `$7FFF` | 10240 | screen 1 |

2220 bytes are free: the 1639 of the free block between the data and the code,
346 more in the table above, and 235 within pages 1 and 2 and the workspace (the tables
below show each).

## By version

| version | data ends | code starts | free block | stored tables | code | start-up (discarded) |
|---|---|---|---|---|---|---|
| mode1 | `$111C` | `$1784` | 1639 | 96 | 4220 | 1190 |
| cpc | `$111C` | `$1784` | 1639 | 96 | 4220 | 1195 |
| nula | `$111C` | `$1784` | 1639 | 96 | 4220 | 1240 |
| arc | `$12D9` | `$1770` | 1174 | 218 | 4240 | 1256 |

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
| `$00CB` | 2 | `syp` | prow7: the row's SYT7 row |
| `$00CD` | 2 | `lp` | prow7, hgnd: a LERPQ7 row |
| `$00CF` | 2 | `kpp` | runk: the RTS it planted last |
| `$00D1` | 1 | `kpg` | and its table's page (sethalf's) |
| `$00D2` | 13 | `BY` | the strip's bottom row: y |
| `$00DF` | 12 | `CE` | each box's byte on even lines |
| `$00EB` | 12 | `CO` | each box's byte on odd lines |
| `$00F7` | 1 | `ldCLE` | 16 o: setup's window row (pcol5's) |
| `$00F8` | 4 | | free |

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
| `$011D` | 2 | `fdr` | each screen's gauge as drawn |
| `$011F` | 2 | `mkl` | each screen's marker: line ($FF none) |
| `$0121` | 2 | `mkp` | each screen's marker: pixel |
| `$0123` | 1 | `mdl` | mdot's line |
| `$0124` | 1 | `mdp` | mdot's pixel |
| `$0125` | 1 | `mdc` | mdot's colour |
| `$0126` | 26 | | free |
| `$0140` | 97 | `LAHB` | LAH,y: 2 (y >> 3), y YSKY..YGND+1 |

## Page 2

| address | bytes | name | use |
|---|---|---|---|
| `$0206` | 1 | `ZB` | row 0's map row less czt |
| `$0207` | 1 | `RN` | the near row |
| `$0208` | 1 | `FACT` | 1: the far row is lerped |
| `$0209` | 1 | `GSHK` | the ship as drawn: direction |
| `$020A` | 1 | `GSHP` | its pitch |
| `$020B` | 1 | `GSHX` | its centre's x |
| `$020C` | 1 | `GSHY` | its centre's line |
| `$020D` | 1 | `GSHV` | 0: not drawn (crashed) |
| `$020E` | 11 | `HTN` | the row of heights zsh4 fetches |
| `$0219` | 11 | `CX` | the corners' map columns |
| `$0224` | 1 | `SHF` | zsh4's step for prow7's hsh: 1, $FF, 0 |
| `$0225` | 1 | `tdy2` | traceb: twice dy's size |
| `$0226` | 1 | `tx1` | traceb: x1; slow: the pixel's x |
| `$0227` | 1 | `x4p4` | slow: x4 + 4 |
| `$0228` | 1 | `re` | split2: the right box, even lines |
| `$0229` | 1 | `ro` | split2: the right box, odd lines |
| `$022A` | 1 | `le` | split2: the left box, even lines |
| `$022B` | 1 | `lo2` | split2: the left box, odd lines |
| `$022C` | 1 | `me` | split2: middle ^ right, even lines |
| `$022D` | 1 | `mo` | split2: middle ^ right, odd lines |
| `$022E` | 1 | `p0` | mktr's top boundary |
| `$022F` | 1 | `vflip` | the flip's field (less one: shown at once) |
| `$0230` | 1 | `vlast` | the field of the last flip |
| `$0231` | 12 | `TRB` | mktr's transitions: the masks |
| `$023D` | 4 | `BANKMAP` | banks 4..7's sockets |
| `$0241` | 20 | `plife` | the dots: life |
| `$0255` | 20 | `ppx` | the dots: x, 8.8 tiles, low byte |
| `$0269` | 20 | `ppxh` | the dots: x, high byte |
| `$027D` | 20 | `ppz` | the dots: z, 8.8 tiles, low byte |
| `$0291` | 20 | `ppzh` | the dots: z, high byte |
| `$02A5` | 20 | `ppy` | the dots: y, 8.8 units, low byte |
| `$02B9` | 20 | `ppyh` | the dots: y, high byte |
| `$02CD` | 20 | `pvx` | the dots: x velocity, low byte |
| `$02E1` | 20 | `pvxh` | the dots: x velocity, high byte |
| `$02F5` | 11 | | free |

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
| `$07D0` | 48 | | free |
| `$0800` | 128 | `PY` | the rows' points: y |
| `$0880` | 128 | `HT` | the rows' heights, 16 a row (+13 its EYV; the 32K build: +11, +12 its range) |
| `$0900` | 160 | `CLE` | the colour window: even lines |
| `$09A0` | 16 | | free |
| `$09B0` | 16 | `RTPL` | each rung's transitions' base |
| `$09C0` | 32 | | free |
| `$09E0` | 16 | `SPB` | slow: each pixel's box |
| `$09F0` | 16 | `STL` | slow: each pixel's transitions' lines |
| `$0A00` | 160 | `CLO` | the colour window: odd lines |
| `$0AA0` | 16 | `STD` | slow: the box's change at each |
| `$0AB0` | 64 | `CURT` | the third set's tops (see TOPS) |
| `$0AF0` | 16 | | free |
| `$0B00` | 128 | `TOPS` | two sets of column records: tops.  Of the three sets, one is each screen's and one this frame's, in turn (sidx, cidx) |
| `$0B80` | 128 | `BOTS` | the two sets' bottoms |
| `$0C00` | 256 | `RPT` | the rungs' tables (grung): the patterns |

| address | bytes | name | use |
|---|---|---|---|
| `$0E00` | 256 | `RQF` | the rungs' tables: 16 q2 + t(1) |
| `$0F00` | 64 | `CURB` | the third set's bottoms |
| `$0F40` | 99 | `EINLB` | EINL,y: run's slot for line y (y from YSKY-1 to YGND+2) |
| `$0FA3` | 7 | `QOA` | div8's rows |
| `$0FAA` | 86 | | free |
| `$1000` | 189 | `QRA` | div8's table |

## The stored tables

Segment `TABLES`: constant tables that the file holds and the start-up copies here.

| address | bytes | name |
|---|---|---|
| `$10BD` | 2 | `sidx` |
| `$10BF` | 1 | `cidx` |
| `$10C0` | 3 | `setTl` |
| `$10C3` | 3 | `setTh` |
| `$10C6` | 3 | `setBl` |
| `$10C9` | 3 | `setBh` |
| `$10CC` | 2 | `tfbl` |
| `$10CE` | 2 | `tfbh` |
| `$10D0` | 9 | `rg_rbe` |
| `$10D9` | 9 | `rg_lbe` |
| `$10E2` | 2 | `zbt0` |
| `$10E4` | 2 | `zbt1` |
| `$10E6` | 2 | `npt0` |
| `$10E8` | 2 | `npt1` |
| `$10EA` | 2 | `npt2` |
| `$10EC` | 4 | `shs` |
| `$10F0` | 4 | `lahsh` |
| `$10F4` | 16 | `MASKB` |
| `$1104` | 16 | `MASKN` |
| `$1114` | 5 | `LM` |
| `$1119` | 4 | `PIXM` |

## The code by source file

| file | main RAM | bank 4 | bank 5 | bank 7 | start-up |
|---|---|---|---|---|---|
| `columns.s` | 2752 | 236 |  |  |  |
| `game.s` |  |  | 2313 |  |  |
| `prow7.s` |  |  |  | 2169 |  |
| `strips.s` | 1226 | 404 |  |  |  |
| `gametab.inc` |  |  | 1220 |  |  |
| `rungs.s` | 553 | 288 |  |  |  |
| `tabgen.s` |  |  |  |  | 617 |
| `boot.s` |  |  |  |  | 573 |
| `projswr.s` | 18 | 208 | 211 |  |  |
| `videoswr.s` | 170 |  |  |  |  |
| `lander.s` | 47 |  | 41 |  |  |
| `panel.inc` |  |  | 73 |  |  |
| total | 4766 | 1136 | 3858 | 2169 | 1190 |

Bank 6 is assembled apart (`shipb.s`, `shipspan.s`): its bytes are in its bank's table below.

## The banks

### Bank 4

| from | to | bytes | name | contents |
|---|---|---|---|---|
| `$8000` | `$8FFF` | 4096 | `B4MAP` | the map: a height for each of 64 x 64 corners |
| `$9000` | `$97FF` | 2048 | `DQT` | the quotients d / a, a row of 64 for each divisor a 0 .. 31 |
| `$9800` | `$9FFF` | 2048 | `DRT` | the remainders, 2 (d mod a), in the same order |
| `$A000` | `$A0FF` | 256 | `CLMP1` | a difference of lines plus one, clamped to 0 .. 4 |
| `$A100` | `$A1FF` | 256 | `DIV4` | x / 4: a pixel's byte column |
| `$A200` | `$A23F` | 64 | `MRL` | the map's row z: its address's low byte |
| `$A240` | `$A2A0` | 97 | `LAHS0` | a line's page in one half of one screen, by line |
| `$A2A1` | `$A2F0` | 80 | `TR4` | a rung to the right, by its shape: each pixel's box |
| `$A2F1` | `$A2FF` | 15 | | free |
| `$A300` | `$A33F` | 64 | `MRH` | the map's row z: its page |
| `$A340` | `$A3A0` | 97 | `LAHS1` | a line's page in one half of one screen, by line |
| `$A3A1` | `$A3F0` | 80 | `TL4` | a rung to the left |
| `$A3F1` | `$A3FF` | 15 | | free |
| `$A400` | `$A43F` | 64 | `TR5` | a rung to the right, by its shape: each pixel's box |
| `$A440` | `$A4A0` | 97 | `LAHS2` | a line's page in one half of one screen, by line |
| `$A4A1` | `$A4E0` | 64 | `TL5` | a rung to the left |
| `$A4E1` | `$A4F0` | 16 | `TR8` | a rung to the right, by its shape: each pixel's box |
| `$A4F1` | `$A4FF` | 15 | | free |
| `$A500` | `$A52F` | 48 | `TR6` | a rung to the right, by its shape: each pixel's box |
| `$A530` | `$A53F` | 16 | `TL8` | a rung to the left |
| `$A540` | `$A5A0` | 97 | `LAHS3` | a line's page in one half of one screen, by line |
| `$A5A1` | `$A5D0` | 48 | `TL6` | a rung to the left |
| `$A5D1` | `$A5F0` | 32 | `DVH` | DQT's row for a divisor: its page |
| `$A5F1` | `$A5FF` | 15 | | free |
| `$A600` | `$A680` | 129 | `TEN4H` | the fills' entries by stores, row 4: page (made at start-up) |
| `$A681` | `$A6F0` | 112 | `TR2` | a rung to the right, by its shape: each pixel's box |
| `$A6F1` | `$A6FF` | 15 | | free |
| `$A700` | `$A780` | 129 | `TEN5H` | the fills' entries by stores, row 5: page (made at start-up) |
| `$A781` | `$A801` | 129 | `TENL` | the fills' entries by stores: low byte, both rows' (made at start-up) |
| `$A802` | `$A984` | 387 | `TBLK4` | the fill for row 4: a chain of STA abs,X (made at start-up) |
| `$A985` | `$A9F4` | 112 | `TL2` | a rung to the left |
| `$A9F5` | `$AA01` | 13 | | free |
| `$AA02` | `$AB84` | 387 | `TBLK5` | the fill for row 5 (made at start-up) |
| `$AB85` | `$ABE6` | 98 | `RSMT` | a line's character row less one line, by line |
| `$ABE7` | `$ABFF` | 25 | | free |
| `$AC00` | `$AC8F` | 144 | `TR0` | a rung to the right, by its shape: each pixel's box |
| `$AC90` | `$ACEF` | 96 | `TR3` | a rung to the right, by its shape: each pixel's box |
| `$ACF0` | `$ACFF` | 16 | | free |
| `$AD00` | `$AD8F` | 144 | `TL0` | a rung to the left |
| `$AD90` | `$ADEF` | 96 | `TL3` | a rung to the left |
| `$ADF0` | `$ADFF` | 16 | | free |
| `$AE00` | `$AE7F` | 128 | `TR1` | a rung to the right, by its shape: each pixel's box |
| `$AE80` | `$AEFF` | 128 | `TL1` | a rung to the left |
| `$AF00` | `$AF1F` | 32 | `DVL` | DQT's row for a divisor: its low byte |
| `$AF20` | `$AF3F` | 32 | `TR7` | a rung to the right, by its shape: each pixel's box |
| `$AF40` | `$AF5F` | 32 | `TL7` | a rung to the left |
| `$AF60` | `$AFFF` | 160 | | free |
| `$B000` | `$B3B1` | 946 | `B4CODE` | code |
| `$B3B2` | `$B3FF` | 78 | | free |
| `$B400` | `$B4BD` | 190 | `B4BODY` | code |
| `$B4BE` | `$B7FF` | 834 | | free |
| `$B800` | `$B922` | 291 | `BLK0` | a black run's store table for one half of one screen: a STA for each line |
| `$B923` | `$B93F` | 29 | | free |
| `$B940` | `$B9A1` | 98 | `KENL` | a line's slot in a black run's store table: low byte |
| `$B9A2` | `$B9FF` | 94 | | free |
| `$BA00` | `$BB22` | 291 | `BLK1` | a black run's store table for one half of one screen: a STA for each line |
| `$BB23` | `$BB3F` | 29 | | free |
| `$BB40` | `$BBA1` | 98 | `KENH` | a line's slot in a black run's store table: page offset |
| `$BBA2` | `$BBFF` | 94 | | free |
| `$BC00` | `$BD22` | 291 | `BLK2` | a black run's store table for one half of one screen: a STA for each line |
| `$BD23` | `$BDFF` | 221 | | free |
| `$BE00` | `$BF22` | 291 | `BLK3` | a black run's store table for one half of one screen: a STA for each line |
| `$BF23` | `$BFFF` | 221 | | free |

1905 bytes free.

### Bank 5

| from | to | bytes | name | contents |
|---|---|---|---|---|
| `$8000` | `$8FFF` | 4096 | `CMAPE` | each tile's colour byte on even lines |
| `$9000` | `$9FFF` | 4096 | `CMAPO` | each tile's colour byte on odd lines |
| `$A000` | `$AF11` | 3858 | `B5CODE` | code |
| `$AF12` | `$BFFF` | 4334 | | free |

4334 bytes free.

### Bank 6

| from | to | bytes | name | contents |
|---|---|---|---|---|
| `$8000` | `$869E` | 1695 | `CODE` | code (keys, ship, the span walker) and its tables |
| `$869F` | `$B3AE` | 11536 | `SPANS` | the ship: every orientation's spans, compressed |
| `$B3AF` | `$B3FF` | 81 | | free |
| `$B400` | `$B57B` | 380 | `TAIL` | code: the spans' decoder |
| `$B57C` | `$B5FF` | 132 | | free |
| `$B600` | `$BF8E` | 2447 | `DTAB` | the decoder's nibble tables and the walker's pixel tables |
| `$BF8F` | `$BFFF` | 113 | | free |

326 bytes free.

### Bank 7

| from | to | bytes | name | contents |
|---|---|---|---|---|
| `$8000` | `$80AF` | 176 | `R7L` | a row's scale r by its depth: low byte |
| `$80B0` | `$80FF` | 80 | | free |
| `$8100` | `$81AF` | 176 | `R7H` | a row's scale r by its depth: high byte |
| `$81B0` | `$81FF` | 80 | | free |
| `$8200` | `$97FF` | 5632 | `SYT7` | a corner's screen line by depth and height, 32 heights a depth |
| `$9800` | `$ADFF` | 5632 | `B1T` | a row's x by depth and the camera's sixteenth: corner 1's x and the corners' carries |
| `$AE00` | `$AEFF` | 256 | | free |
| `$AF00` | `$AFAF` | 176 | `PINL7` | the left clip plane's x by depth |
| `$AFB0` | `$AFFF` | 80 | | free |
| `$B000` | `$B0AF` | 176 | `PINR7` | the right clip plane's x by depth |
| `$B0B0` | `$B0FF` | 80 | | free |
| `$B100` | `$B2FF` | 512 | `LERPQ7` | interpolation: lerp(0, d, q / 16) - 1, 32 differences d for each q |
| `$B300` | `$B3AF` | 176 | `SYL7` | SYT7's row for a depth: low byte |
| `$B3B0` | `$B45F` | 176 | `SYH7` | SYT7's row for a depth: page |
| `$B460` | `$B46F` | 16 | `LQLO` | LERPQ7's row for q: low byte |
| `$B470` | `$B47F` | 16 | `LQHI` | LERPQ7's row for q: page |
| `$B480` | `$BCF8` | 2169 | `B7CODE` | code |
| `$BCF9` | `$BE9F` | 423 | | free |
| `$BEA0` | `$BF4F` | 176 | `PXF7` | the far clip row's x by the camera's sixteenth |
| `$BF50` | `$BFFF` | 176 | `PXN7` | the near clip row's x by the camera's sixteenth |

999 bytes free.
