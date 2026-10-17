#!/bin/sh
# The 32K build, development stage: build32/LAND (main RAM from $1900), build32/TABLES
# and TABLES7 (the banks' images, for py65 at $8000 and $C000), build32/CMAP.
set -e
cd "$(dirname "$0")/.."
B=build32
mkdir -p $B
python3 b32/tools/gen32.py $B
ca65 -g --cpu 6502 -I b32/src -I $B --bin-include-dir $B -o $B/land.o b32/src/land.s -l $B/land.lst
ld65 -C b32/src/b32dev.cfg -o $B/LAND $B/land.o -m $B/map.txt -Ln $B/labels.txt
echo "LAND $(wc -c < $B/LAND | tr -d ' ') bytes"
