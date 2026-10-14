#!/bin/sh
# SHIP's build: build/ship/ship.ssd (SHIFT+BREAK: !BOOT sets MODE 1 and runs SHIP, the
# ship demo; it loads LAND's TABLES into sideways RAM bank 4 for DQT, DRT).  ca65, ld65 (cc65), Python 3.
set -e
cd "$(dirname "$0")"
B=build/ship
mkdir -p $B
python3 tools/shipgen.py $B
python3 tools/landgen.py build/land
ca65 -g --cpu 6502 -I src -I $B -I build/land -o $B/ship.o src/ship.s -l $B/ship.lst
ld65 -C src/ship.cfg -o $B/SHIP $B/ship.o -m $B/map.txt -Ln $B/labels.txt --dbgfile $B/ship.dbg
printf 'MODE 1\r*RUN SHIP\r' > $B/BOOT
python3 tools/mkdfs.py build $B/ship.ssd SHIP "!BOOT:$B/BOOT:0000:FFFF" "SHIP:$B/SHIP:1900:1900" "TABLES:build/land/TABLES:3000:3000"
echo "$B/ship.ssd: SHIP $(wc -c < $B/SHIP | tr -d ' ') bytes"
