#!/bin/sh
# LAND's build: build/land/land.ssd (SHIFT+BREAK: !BOOT sets MODE 1 and runs LAND, which
# loads TABLES into sideways RAM bank 4).  ca65, ld65 (cc65), Python 3.
set -e
cd "$(dirname "$0")"
B=build/land
mkdir -p $B
python3 tools/landgen.py $B
ca65 -g --cpu 6502 -I src -I $B -o $B/land.o src/land.s -l $B/land.lst
ld65 -C src/land.cfg -o $B/LAND $B/land.o -m $B/map.txt -Ln $B/labels.txt --dbgfile $B/land.dbg
printf 'MODE 1\r*RUN LAND\r' > $B/BOOT
python3 tools/mkdfs.py build $B/land.ssd LAND \
    "!BOOT:$B/BOOT:0000:FFFF" "LAND:$B/LAND:1900:1900" "TABLES:$B/TABLES:3000:3000"
echo "$B/land.ssd: LAND $(wc -c < $B/LAND | tr -d ' ') bytes"
