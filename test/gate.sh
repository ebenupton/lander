#!/bin/sh
# test/gate.sh: build one program and check it against the references.
#
#   [SWR=1] [VERSION=mode1|cpc|nula|arc] [BUILD=dir] sh test/gate.sh [base] [SHIPSTEP]
#
# SWR=1: the sideways RAM build; otherwise the 32K build.  VERSION defaults to mode1.
# BUILD is build.sh's output directory (default build): the program is built into
# BUILD/<base|swr>-VERSION, and the steps' output is left there in gate_*.txt.
#
#   the build      build.sh: no errors or warnings
#   the stack      tools/stackdepth.py: the worst case fits the stack, and every
#                  bank's code runs with its bank paged in
#   the flight     test/gametest.py over test/flightprof.py's script: every frame's
#                  state the same as test/flight.txt, the one baseline for both
#                  builds and every version (`base` writes it from this build)
#   the land       test/soak.py: plain pans, pans with the camera raised, and jumps
#                  of ten tiles a frame (the map's window remade, the rare paths)
#   the ship       test/shiptest.py, every SHIPSTEP'th orientation (default 5); the
#                  sideways RAM build: test/shipswr.py
#   the maps       tools/memmap.py check: docs/'s memory maps are the builds'.  Run
#                  only with the default BUILD and all eight builds and the loader
#                  there (sh build.sh)
#
# Prints "GATE PASS <cycles> cycles a frame (flight), project: <cycles> strips:
# <cycles>" (the last two the means of the raised-camera soak), or "GATE FAIL <step>"
# and exits 1.
cd "$(dirname "$0")/.."
T=base
[ "$SWR" = 1 ] && T=swr
fail() { echo "GATE FAIL $1"; exit 1; }
case ${VERSION:=mode1} in
    mode1|cpc|nula|arc) ;;
    *) fail "version $VERSION (mode1, cpc, nula, arc)" ;;
esac
R=${BUILD:-build}
B=$R/$T-$VERSION
export VERSION BDIR=$B              # test/rig.py's: the tests' build
BASE=test/flight.txt
mkdir -p $B
sh build.sh $T $VERSION > $B/gate_build.log 2>&1 || fail "build ($B/gate_build.log)"
grep -qi 'error\|warning' $B/gate_build.log && fail "build (warnings: $B/gate_build.log)"
python3 tools/stackdepth.py $B > $B/gate_stack.txt 2>&1 || fail "stack ($B/gate_stack.txt)"
SCRIPT=$(python3 -c "import sys; sys.path.insert(0, 'test'); import flightprof; print(flightprof.SCRIPT)")
python3 test/gametest.py "$SCRIPT" > $B/gate_flight.txt 2>&1 || fail "flight ($B/gate_flight.txt)"
cut -c19- $B/gate_flight.txt > $B/gate_state.txt
if [ "$1" = base ]; then cp $B/gate_state.txt $BASE; echo "baseline written"; shift; fi
cmp -s $B/gate_state.txt $BASE || fail "flight (diff $B/gate_state.txt $BASE)"
python3 test/soak.py 16 2 2 > $B/gate_soak1.txt 2>&1 && grep -q ' 0 failed' $B/gate_soak1.txt || fail "soak plain ($B/gate_soak1.txt)"
python3 test/soak.py 16 5 3 cam > $B/gate_soak2.txt 2>&1 && grep -q ' 0 failed' $B/gate_soak2.txt || fail "soak cam ($B/gate_soak2.txt)"
python3 test/soak.py 24 9 160 > $B/gate_soak3.txt 2>&1 && grep -q ' 0 failed' $B/gate_soak3.txt || fail "soak jumps ($B/gate_soak3.txt)"
if [ "$SWR" = 1 ]; then
    python3 test/shipswr.py > $B/gate_ship.txt 2>&1 && grep -q ' 0 failed' $B/gate_ship.txt || fail "ship ($B/gate_ship.txt)"
else
    python3 test/shiptest.py ${1:-5} > $B/gate_ship.txt 2>&1 && grep -q ' 0 failed' $B/gate_ship.txt || fail "ship ($B/gate_ship.txt)"
fi
# (last: gates run side by side have all built by now)
maps=0
if [ "$R" = build ] && [ -f $R/loader/BOOT ] && [ -f $R/loader/labels.txt ]; then
    maps=1
    for t in base swr; do
        for v in mode1 cpc nula arc; do
            [ -f $R/$t-$v/lander.dbg ] && [ -f $R/$t-$v/labels.txt ] || maps=0
        done
    done
fi
if [ $maps = 1 ]; then
    python3 tools/memmap.py $R docs check > $B/gate_map.txt 2>&1 || fail "map ($B/gate_map.txt)"
fi
cut -c11-17 $B/gate_flight.txt | awk '{s += $1; n++} END {printf "GATE PASS %d cycles a frame (flight), ", s/n}'
awk '/^(project|strips):/ {printf "%s %s ", $1, $3}' $B/gate_soak2.txt; echo
