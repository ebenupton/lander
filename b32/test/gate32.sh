#!/bin/sh
# The 32K build's gate: build, then everything checked against the reference.
#   soak32.py   the land, byte-exact against proto/land.py (plain, moving camera, and
#               jumps of 10 tiles a frame: the map window remade, the rare paths)
#   shiptest32  the ship, every STEP'th orientation against b32/tools/ship32.py
#   stackdepth  the main loop's worst-case stack within b32.cfg's 12 (+ IRQ, NMI)
#   gametest32  the game: profile32.py's flight, every frame's state, against
#               build32/gate_base.txt (made by `gate32.sh base` from a known-good build)
# Prints GATE PASS and the flight's cycles a frame, or GATE FAIL <step>.
#   [VERSION=cpc|nula|arc] b32/test/gate32.sh [base] [SHIPSTEP]
# VERSION builds and tests a MODE 2 build (proto/nula.py; default mode1): the land and
# ship against the reference in its colours, the game's state against the same baseline
# (the game does not depend on the colours).
cd "$(dirname "$0")/../.."
B=build32
fail() { echo "GATE FAIL $1"; exit 1; }
case ${VERSION:-mode1} in cpc) export CPC=1 NULA=0 ARC=0 ;; nula) export NULA=1 CPC=0 ARC=0 ;; arc) export ARC=1 NULA=0 CPC=0 ;; *) export CPC=0 NULA=0 ARC=0 ;; esac
sh b32/build32.sh ${VERSION:-mode1} > $B/gate_build.log 2>&1 || fail build
grep -qi 'error' $B/gate_build.log && fail build
python3 b32/tools/stackdepth.py loop > $B/gate_stack.txt 2>&1 || fail stackdepth
grep -q '^loop: \([0-9]\|1[0-2]\) bytes' $B/gate_stack.txt || fail "stack: the loop needs more than 12 bytes (b32.cfg's 19-byte stack)"
SCRIPT=$(python3 -c "import sys; sys.path.insert(0,'b32/test'); import profile32; print(profile32.SCRIPT)")
python3 b32/test/gametest32.py "$SCRIPT" > $B/gate_flight.txt 2>&1 || fail flight
cut -c19- $B/gate_flight.txt > $B/gate_state.txt
if [ "$1" = base ]; then cp $B/gate_state.txt $B/gate_base.txt; echo "baseline written"; shift; fi
cmp -s $B/gate_state.txt $B/gate_base.txt || fail "flight differs (diff $B/gate_state.txt $B/gate_base.txt)"
python3 b32/test/soak32.py 16 2 2 2>&1 | tee $B/gate_soak1.txt | grep -q ' 0 failed' || fail "soak plain"
python3 b32/test/soak32.py 16 5 3 cam 2>&1 | tee $B/gate_soak2.txt | grep -q ' 0 failed' || fail "soak cam"
python3 b32/test/soak32.py 24 9 160 2>&1 | tee $B/gate_soak3.txt | grep -q ' 0 failed' || fail "soak jumps"
python3 b32/test/shiptest32.py ${1:-5} 2>&1 | tee $B/gate_ship.txt | grep -q ' 0 failed' || fail ship
cut -c11-17 $B/gate_flight.txt | awk '{s += $1; n++} END {printf "GATE PASS %d cycles a frame (flight), ", s/n}'
grep -E '^strips|^project' $B/gate_soak2.txt | awk '{printf "%s %s ", $1, $3}'; echo
