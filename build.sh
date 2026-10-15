#!/bin/sh
# LAND's build: build/lander.ssd, a DFS disc.  SHIFT+BREAK runs !BOOT (MODE 1, the
# palette black and the cursor off, *LOAD LAND, *RUN LANDS); LANDS, LAND's start, loads
# TABLES, TABLES2, SHIPB and TABLES7 into sideways RAM banks 4, 5, 6 and 7.
# Needs ca65 and ld65 (cc65) and Python 3 with numpy.
#
# Steps (everything into build/):
#   1. tools/landgen.py: the renderer's tables, TABLES (bank 4), TABLES2 (bank 5) and
#      TABLES7 (bank 7), and tables.inc (their addresses and the constants) for land.s.
#   2. tools/gamegen.py: gametab.inc, the game's tables (game.s, .included by land.s).
#   3. ca65/ld65 on src/land.s (src/land.cfg): LAND (the code, at $1900), LANDS (the
#      start, at $7000), and a file per bank code segment (B4*, B5*, B7*).
#   4. tools/mergebank.py: each bank code segment into the table image of its bank, at
#      the address land.cfg gave it less $8000 (from map.txt), where the tables leave
#      room (below).
#   5. landsyms.inc: the LAND labels shipb.s uses (back, scrb, TRL in zero page; sidx and
#      the setTl..setBh tables), as L_name, from ld65's labels.txt.
#   6. tools/shipgen.py: shipspan.inc, the ship's pre-rasterised spans; then ca65/ld65
#      on src/shipb.s (src/shipb.cfg): SHIPB (bank 6).
#   7. !BOOT, then tools/mkdfs.py: the disc.
#
# The bank code segments and their room (src/land.cfg places them; tools/landgen.py's
# docstring has every table):
#   TABLES, bank 4:  B4R $9000, B4L $9100, B4S2 $9200, B4V1 $B600, B4V2 $B700,
#                    B4V3 $B800, B4Z $B900 -- the first R2OFF ($6F) bytes of run2's
#                    store-table pages, before their first entry;
#                    B4S $A081, B4C $A181 -- after TENH4, TENH5 (129 bytes each).
#   TABLES2, bank 5: B5CODE $A000 (pcol5), B5GAME $A100 (game.s) -- after CMAPO
#                    ($9000-$9FFF).  The image holds nothing else; land.cfg ends
#                    B5GAME's room at $BE00, GLY5, where LANDS writes the game's
#                    letters at start.
#   TABLES7, bank 7: B7A $80B0, B7B $81B0, B7E $AEB0, B7C $AFB0, B7D $B0B0 -- the
#                    spare of R7L, R7H, CLP7, PINL7, PINR7 (NDI = 176 = $B0 entries
#                    of 256); B7CODE $B480 -- between LQHI (ends $B47F) and PXF7 ($BEA0).
set -e
cd "$(dirname "$0")"
B=build
mkdir -p $B
python3 tools/landgen.py $B                                                     # TABLES, TABLES2, TABLES7, tables.inc
python3 tools/gamegen.py $B                                                     # gametab.inc
ca65 -g --cpu 6502 -I src -I $B -o $B/land.o src/land.s -l $B/land.lst          # LAND, LANDS, the bank segments
ld65 -C src/land.cfg -o $B/LAND $B/land.o -m $B/map.txt -Ln $B/labels.txt --dbgfile $B/land.dbg
python3 tools/mergebank.py $B $B/map.txt \
    TABLES:B4R,B4L,B4S2,B4S,B4C,B4V1,B4V2,B4V3,B4Z \
    TABLES2:B5CODE,B5GAME \
    TABLES7:B7A,B7B,B7E,B7C,B7D,B7CODE
python3 - $B <<'PY'                                                             # landsyms.inc: LAND's labels for shipb.s, L_ before each
import sys
want = {'TRL', 'scrb', 'back', 'sidx', 'setTl', 'setTh', 'setBl', 'setBh'}
out = set()
for ln in open(sys.argv[1] + '/labels.txt'):
    _, a, n = ln.split()
    if n.lstrip('.') in want:
        out.add(f'L_{n.lstrip(".")} = ${int(a, 16):04X}')
open(sys.argv[1] + '/landsyms.inc', 'w').write('\n'.join(sorted(out)) + '\n')
PY
python3 tools/shipgen.py $B                                                     # shipspan.inc
ca65 -g --cpu 6502 -I src -I $B -o $B/shipb.o src/shipb.s -l $B/shipb.lst       # SHIPB
ld65 -C src/shipb.cfg -o $B/SHIPB $B/shipb.o -m $B/shipb_map.txt -Ln $B/shipb_labels.txt
printf 'MODE1:VDU23,1,0;0;0;0;19,1,0;0;19,2,0;0;19,3,0;0;\r*LOAD LAND\r*RUN LANDS\r' > $B/BOOT   # (the loads unseen)
python3 tools/mkdfs.py build $B/lander.ssd LAND \
    "!BOOT:$B/BOOT:0000:FFFF" "LAND:$B/LAND:1900:1900" "LANDS:$B/LANDS:7000:7000" \
    "TABLES:$B/TABLES:3000:3000" "TABLES2:$B/TABLES2:3000:3000" "SHIPB:$B/SHIPB:3000:3000" "TABLES7:$B/TABLES7:3000:3000"
echo "$B/lander.ssd: LAND $(wc -c < $B/LAND | tr -d ' ') bytes, SHIPB $(wc -c < $B/SHIPB | tr -d ' ')"
