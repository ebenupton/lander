#!/bin/sh
# LAND's build: build/land/land.ssd (SHIFT+BREAK: !BOOT sets MODE 1, loads LAND and runs LANDS, its start, which
# loads TABLES, TABLES2 and SHIPB into sideways RAM banks 4, 5 and 6).  ca65, ld65 (cc65), Python 3.
set -e
cd "$(dirname "$0")"
B=build/land
mkdir -p $B
python3 tools/landgen.py $B
ca65 -g --cpu 6502 -I src -I $B -o $B/land.o src/land.s -l $B/land.lst
ld65 -C src/land.cfg -o $B/LAND $B/land.o -m $B/map.txt -Ln $B/labels.txt --dbgfile $B/land.dbg
python3 - $B <<'PY'                 # LAND's symbols for bank 6, L_ before each
import sys
want = {'TRL', 'TRB', 'scrb', 'back', 'sidx', 'setTl', 'setTh', 'setBl', 'setBh',
        'cxs', 'cxt', 'czs', 'czt'}
out = []
for ln in open(sys.argv[1] + '/labels.txt'):
    _, a, n = ln.split()
    if n.lstrip('.') in want:
        out.append(f'L_{n.lstrip(".")} = ${int(a, 16):04X}')
open(sys.argv[1] + '/landsyms.inc', 'w').write('\n'.join(sorted(set(out))) + '\n')
PY
python3 tools/shipgen.py $B
ca65 -g --cpu 6502 -I src -I $B -o $B/shipb.o src/shipb.s -l $B/shipb.lst
ld65 -C src/shipb.cfg -o $B/SHIPB $B/shipb.o -m $B/shipb_map.txt -Ln $B/shipb_labels.txt
printf 'MODE 1\r*LOAD LAND\r*RUN LANDS\r' > $B/BOOT
python3 tools/mkdfs.py build $B/land.ssd LAND \
    "!BOOT:$B/BOOT:0000:FFFF" "LAND:$B/LAND:1900:1900" "LANDS:$B/LANDS:7000:7000" "TABLES:$B/TABLES:3000:3000" "TABLES2:$B/TABLES2:3000:3000" "SHIPB:$B/SHIPB:3000:3000"
echo "$B/land.ssd: LAND $(wc -c < $B/LAND | tr -d ' ') bytes, SHIPB $(wc -c < $B/SHIPB | tr -d ' ')"
