#!/bin/sh
# tools/b2/jsweep.sh: the 32K build's video timing in jsbeeb at many boot phases,
# in both phases of the 1 MHz clock.
#
#   [BUILD=dir] [OUT=dir] [JOBS=n] [PHASES="..."] [SECS=s] [ARGS="..."] [JSBEEB=dir]
#   sh tools/b2/jsweep.sh [VERSION]
#
# VERSION: mode1 (the default), cpc, nula or arc.  The disc is $BUILD/lander.ssd
# and the labels $BUILD/base-VERSION/labels.txt (BUILD default build: sh build.sh).
# Needs node and jsbeeb (JSBEEB: jhsync.mjs).
#
# jhsync.mjs boots the disc with a hard reset after BOOTPRE more 2 MHz cycles, for
# each BOOTPRE in PHASES (default: 16 of them, 0 to 987), and flies for SECS
# emulated seconds (default 60) with keys held.  jsbeeb's reset leaves the 6845's 1
# MHz clock where it is and zeroes the processor's cycle count, so the half
# microsecond between the 6845's clock and the processor's 1 MHz bus changes with
# BOOTPRE's parity: the runs cover both phases (each run prints its own).  ARGS adds
# jhsync.mjs options (--inject 8).
#
# JOBS runs at a time (default 4).  Each must print JHSYNC PASS: every horizontal
# sync interval 128 cycles, every field 312 lines.  Prints a line per run (the
# phase, the intervals, the fields, the switches' landing lines and cycles), then
# "JSWEEP PASS base-VERSION" or "JSWEEP FAIL base-VERSION" (exit status 1).  Logs:
# OUT (default $BUILD/js/base-VERSION), pre-BOOTPRE.txt a run.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V=${1:-mode1}
BUILD=${BUILD:-build}
SECS=${SECS:-60}
PHASES=${PHASES:-"0 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987"}
JOBS=${JOBS:-4}
OUT=${OUT:-$BUILD/js/base-$V}
[ -f "$BUILD/lander.ssd" ] || { echo "no $BUILD/lander.ssd (sh build.sh)"; exit 1; }
mkdir -p "$OUT"
n=0
for p in $PHASES; do
    BOOTPRE=$p node "$HERE/jhsync.mjs" "$BUILD" --version "$V" --secs "$SECS" ${ARGS:-} > "$OUT/pre-$p.txt" 2>&1 &
    n=$((n + 1))
    [ $((n % JOBS)) -eq 0 ] && wait
done
wait
ok=1
for p in $PHASES; do
    l="$OUT/pre-$p.txt"
    v=$(grep -E "^JHSYNC" "$l" || echo "JHSYNC NONE")
    ph=$(sed -n 's/^the 6845.*: //p' "$l")
    iv=$(sed -n 's/^hsync intervals (2 MHz cycles)://p' "$l")
    fl=$(sed -n 's/^lines per field://p' "$l")
    ula=$(sed -n 's/^ULA control writes by value and line:cycle://p' "$l")
    printf 'pre %4s  phase %s  %s  intervals%s  fields%s  ula%s\n' "$p" "$ph" "$v" "$iv" "$fl" "$ula"
    [ "$v" = "JHSYNC PASS" ] || ok=0
done
[ $ok = 1 ] && echo "JSWEEP PASS base-$V" || { echo "JSWEEP FAIL base-$V"; exit 1; }
