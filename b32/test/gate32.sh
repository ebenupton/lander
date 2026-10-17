#!/bin/sh
# The 32K build's gate: build, then everything checked against the reference.
#   soak32.py   the land, byte-exact against proto/land.py (plain and moving camera)
#   shiptest32  the ship, every STEP'th orientation against b32/tools/ship32.py
#   gametest32  the game: profile32.py's flight, every frame's state, against
#               build32/gate_base.txt (made by `gate32.sh base` from a known-good build)
# Prints GATE PASS and the flight's cycles a frame, or GATE FAIL <step>.
#   b32/test/gate32.sh [base] [SHIPSTEP]
cd "$(dirname "$0")/../.."
B=build32
fail() { echo "GATE FAIL $1"; exit 1; }
sh b32/build32.sh > $B/gate_build.log 2>&1 || fail build
grep -qi 'error' $B/gate_build.log && fail build
SCRIPT=$(python3 -c "import sys; sys.path.insert(0,'b32/test'); import profile32; print(profile32.SCRIPT)")
python3 b32/test/gametest32.py "$SCRIPT" > $B/gate_flight.txt 2>&1 || fail flight
cut -c19- $B/gate_flight.txt > $B/gate_state.txt
if [ "$1" = base ]; then cp $B/gate_state.txt $B/gate_base.txt; echo "baseline written"; shift; fi
cmp -s $B/gate_state.txt $B/gate_base.txt || fail "flight differs (diff $B/gate_state.txt $B/gate_base.txt)"
python3 b32/test/soak32.py 16 2 2 2>&1 | tee $B/gate_soak1.txt | grep -q ' 0 failed' || fail "soak plain"
python3 b32/test/soak32.py 16 5 3 cam 2>&1 | tee $B/gate_soak2.txt | grep -q ' 0 failed' || fail "soak cam"
python3 b32/test/shiptest32.py ${1:-5} 2>&1 | tee $B/gate_ship.txt | grep -q ' 0 failed' || fail ship
awk '{s += $3; n++} END {printf "GATE PASS %d cycles a frame (flight), ", s/n}' $B/gate_flight.txt
grep -E '^strips|^project' $B/gate_soak2.txt | awk '{printf "%s %s ", $1, $3}'; echo
