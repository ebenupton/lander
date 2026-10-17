#!/bin/sh
# The 32K build (branch b32): build32/lander32.ssd, Lander for a 32K Model B with no
# sideways RAM.  SHIFT+BREAK: !BOOT (an EXEC file) sets MODE 1 with every colour black
# and the cursor off, then *RUN L32: the loader (b32/src/boot32.s, $7000), which loads
# L32M ($1900-$4FFF: the program, its tables, the map), hands the machine over from the
# MOS and starts.  Needs ca65, ld65, Python 3 with numpy.
#   b32/tools/gen32.py   the renderer's and the game's tables (tables.inc, b32tab.inc,
#                        gametab.inc, MAP32)
#   b32/tools/ship32.py  the ship's model data (ship32.inc)
# The tests (b32/test/: soak32.py, shiptest32.py, gametest32.py) run L32M and L32 in
# py65.
set -e
cd "$(dirname "$0")/.."
B=build32
mkdir -p $B
python3 b32/tools/gen32.py $B
python3 b32/tools/ship32.py $B
ca65 -g --cpu 6502 ${CODEPAD:+-D CODEPAD=$CODEPAD} -I b32/src -I $B --bin-include-dir $B -o $B/land.o b32/src/land.s -l $B/land.lst
ld65 -C b32/src/b32.cfg -o $B/x.bin $B/land.o -m $B/map.txt -Ln $B/labels.txt --dbgfile $B/game.dbg
EXEC=$(awk '$3 == ".start" {print $2}' $B/labels.txt | sed 's/^00//')
printf '*RUN LANDER\r' > $B/BOOT    # (the test disc's convenience: not the program's)
python3 tools/mkdfs.py build $B/lander32.ssd LANDER32 "!BOOT:$B/BOOT:0000:FFFF" \
    "LANDER:$B/LANDER:2000:$EXEC"
echo "LANDER $(wc -c < $B/LANDER | tr -d ' ') bytes ($(( ($(wc -c < $B/LANDER) + 255) / 256 )) sectors), exec \$$EXEC; $B/lander32.ssd"
