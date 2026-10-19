#!/bin/sh
# b32/test/gate32.sh: build a version and check it against the references.
#
#   [VERSION=mode1|cpc|nula|arc] sh b32/test/gate32.sh [base] [SHIPSTEP]
#
#   the build      no errors or warnings
#   the stack      b32/tools/stackdepth.py: the worst case fits the stack
#   the flight     gametest32.py over profile32.py's script: every frame's state the
#                  same as build32/gate_base.txt (`base` writes it from this build)
#   the land       soak32.py: plain pans, pans with the camera raised, and jumps of
#                  ten tiles a frame (the map's window remade, the rare paths)
#   the ship       shiptest32.py: every SHIPSTEP'th orientation (default 5)
#
# Prints "GATE PASS <cycles a frame in the flight>, project <cycles>, strips <cycles>"
# (the last two from the raised-camera soak), or "GATE FAIL <step>".
cd "$(dirname "$0")/../.."
B=build32
fail() { echo "GATE FAIL $1"; exit 1; }
case ${VERSION:=mode1} in
    cpc) export CPC=1 NULA=0 ARC=0 ;;
    nula) export NULA=1 CPC=0 ARC=0 ;;
    arc) export ARC=1 NULA=0 CPC=0 ;;
    *) export CPC=0 NULA=0 ARC=0 ;;
esac
sh b32/build32.sh $VERSION > $B/gate_build.log 2>&1 || fail build
grep -qi 'error\|warning' $B/gate_build.log && fail "build (warnings: $B/gate_build.log)"
python3 b32/tools/stackdepth.py > $B/gate_stack.txt 2>&1 || fail "stack ($B/gate_stack.txt)"
SCRIPT=$(python3 -c "import sys; sys.path.insert(0, 'b32/test'); import profile32; print(profile32.SCRIPT)")
python3 b32/test/gametest32.py "$SCRIPT" > $B/gate_flight.txt 2>&1 || fail flight
cut -c19- $B/gate_flight.txt > $B/gate_state.txt
if [ "$1" = base ]; then cp $B/gate_state.txt $B/gate_base.txt; echo "baseline written"; shift; fi
cmp -s $B/gate_state.txt $B/gate_base.txt || fail "flight (diff $B/gate_state.txt $B/gate_base.txt)"
python3 b32/test/soak32.py 16 2 2 > $B/gate_soak1.txt 2>&1 && grep -q ' 0 failed' $B/gate_soak1.txt || fail "soak plain"
python3 b32/test/soak32.py 16 5 3 cam > $B/gate_soak2.txt 2>&1 && grep -q ' 0 failed' $B/gate_soak2.txt || fail "soak cam"
python3 b32/test/soak32.py 24 9 160 > $B/gate_soak3.txt 2>&1 && grep -q ' 0 failed' $B/gate_soak3.txt || fail "soak jumps"
python3 b32/test/shiptest32.py ${1:-5} > $B/gate_ship.txt 2>&1 && grep -q ' 0 failed' $B/gate_ship.txt || fail ship
cut -c11-17 $B/gate_flight.txt | awk '{s += $1; n++} END {printf "GATE PASS %d cycles a frame (flight), ", s/n}'
awk '/^(project|strips):/ {printf "%s %s ", $1, $3}' $B/gate_soak2.txt; echo
