#!/bin/sh
# LAND's build: build/lander.ssd, a DFS disc holding four versions: MODE 1 (directory
# M), MODE 2 with the CPC palette (C), MODE 2 with the VideoNULA's (N) and MODE 2 in
# Lander's own colours through the VideoNULA (A, arc); see proto/nula.py.  SHIFT+BREAK
# runs !BOOT, an EXEC file that types in and runs the chooser (src/menu.bas): it tests
# for a VideoNULA, offers the versions (the NULA ones only when found), sets the chosen
# mode with the palette black and the cursor off, selects the version's directory and
# *RUNs LANDS, LAND's start, which loads LAND, then TABLES, TABLES2, SHIPB and
# $.TABLES7 (the same in every version) into sideways RAM banks 4, 5, 6 and 7.  The
# MODE 2 versions' LAND and TABLES are the same, S.LAND and S.TABLES.  Needs ca65 and
# ld65 (cc65) and Python 3 with numpy and scipy.
#
#   sh build.sh              the disc: each version built in turn (MODE 1 last, so it is
#                            what build/ holds after), its files kept in build/disc/
#   sh build.sh VERSION      one version (mode1, cpc, nula or arc) into build/, no disc:
#                            for the tests, which need CPC=1, NULA=1 or ARC=1 in the
#                            environment to match (build/variant says which was built)
#   DP11_MOUSE=1 sh build.sh with the mouse (src/game.s; off without)
#
# Steps for a version (everything into build/):
#   1. tools/landgen.py: the renderer's tables, TABLES (bank 4), TABLES2 (bank 5) and
#      TABLES7 (bank 7), tables.inc (their addresses and the constants) for land.s
#      and, for MODE 2, mode2.inc (its colour bytes, NULA palette and letters).
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
# then for the disc, !BOOT, and tools/mkdfs.py.
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
MOUSE=
[ "${DP11_MOUSE:-0}" != 0 ] && MOUSE="-D DP11_MOUSE"

one() {                                                                         # the version $1 into build/
case $1 in
    arc) export ARC=1 NULA=0 CPC=0; CA="-D MODE2 -D NULA -D ARC" ;;
    nula) export ARC=0 NULA=1 CPC=0; CA="-D MODE2 -D NULA" ;;
    cpc) export ARC=0 NULA=0 CPC=1; CA="-D MODE2 -D CPC" ;;
    mode1) export ARC=0 NULA=0 CPC=0; CA= ;;
    *) echo "build.sh: no version $1 (mode1, cpc, nula, arc)" >&2; exit 1 ;;
esac
echo $1 > $B/variant
python3 tools/landgen.py $B                                                     # TABLES, TABLES2, TABLES7, tables.inc
python3 tools/gamegen.py $B                                                     # gametab.inc
ca65 -g --cpu 6502 $CA $MOUSE -I src -I $B -o $B/land.o src/land.s -l $B/land.lst   # LAND, LANDS, the bank segments
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
echo "$1: LAND $(wc -c < $B/LAND | tr -d ' ') bytes, LANDS $(wc -c < $B/LANDS | tr -d ' '), SHIPB $(wc -c < $B/SHIPB | tr -d ' ')"
}

[ $# -le 1 ] || { echo "build.sh: one VERSION at most" >&2; exit 1; }
if [ -n "$1" ]; then
    rm -rf $B/disc $B/lander.ssd $B/BOOT                                        # (no disc from one version)
    one "$1"
    exit 0
fi
rm -rf $B/disc
for v in cpc:C nula:N arc:A mode1:M; do
    one ${v%:*}
    mkdir -p $B/disc/${v#*:}
    cp $B/LAND $B/LANDS $B/TABLES $B/TABLES2 $B/SHIPB $B/TABLES7 $B/disc/${v#*:}/
done
same() { cmp -s $B/disc/$2/$1 $B/disc/$3/$1 || { echo "build.sh: $1 differs in $2 and $3" >&2; exit 1; }; }
for d in C N A; do same TABLES7 $d M; done                                     # $.TABLES7
for d in N A; do same LAND $d C; same TABLES $d C; done                         # S.LAND, S.TABLES
{ printf 'VDU21\rNEW\r'; tr '\n' '\r' < src/menu.bas; printf 'RUN\r'; } > $B/BOOT      # the chooser typed in, unseen
F="M.LAND:$B/disc/M/LAND:1900:1900 M.TABLES:$B/disc/M/TABLES:3000:3000"
F="$F S.LAND:$B/disc/C/LAND:1900:1900 S.TABLES:$B/disc/C/TABLES:3000:3000"
for d in M C N A; do
    F="$F $d.LANDS:$B/disc/$d/LANDS:7000:7000 $d.TABLES2:$B/disc/$d/TABLES2:3000:3000"
    F="$F $d.SHIPB:$B/disc/$d/SHIPB:3000:3000"
done
python3 tools/mkdfs.py build $B/lander.ssd LANDER \
    "!BOOT:$B/BOOT:0000:FFFF" "TABLES7:$B/disc/M/TABLES7:3000:3000" $F
echo "$B/lander.ssd: MODE 1 (M), CPC (C), NULA (N) and arc (A) versions, MODE 2's LAND and TABLES shared (S)"
