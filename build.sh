#!/bin/sh
# bandfill's build: one program, BAND, run at $1900 by !BOOT, on one disc (build/band.ssd).
# ca65 and ld65 (cc65), Python 3 for the tables (tools/gentab.py, from proto/points.py),
# and beebgame's mkdfs.py for the disc image.
#   sh build.sh
set -e
cd "$(dirname "$0")"
mkdir -p build
python3 tools/gentab.py build
ca65 -g --cpu 6502 -I src -I build -o build/main.o src/main.s -l build/main.lst
ld65 -C src/band.cfg -o build/BAND build/main.o -m build/map.txt -Ln build/labels.txt \
    --dbgfile build/band.dbg
printf 'MODE 1\r*RUN BAND\r' > build/BOOT
python3 tools/mkdfs.py build build/band.ssd BAND \
    "!BOOT:build/BOOT:0000:FFFF" "BAND:build/BAND:1900:1900"
echo "build/band.ssd: BAND $(wc -c < build/BAND | tr -d ' ') bytes"
