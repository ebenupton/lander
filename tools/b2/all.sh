#!/bin/sh
# tools/b2/all.sh: the video timing of every build on every machine: b2sweep.sh and
# jsweep.sh over the whole matrix, one sweep after another.
#
#   [BUILD=dir] [OUT=dir] [JOBS=n] sh tools/b2/all.sh
#
# The disc is $BUILD/lander.ssd (BUILD default build: sh build.sh).  The sweeps, V
# each of mode1, cpc, nula and arc:
#
#   b2 base-V           the 32K build on a Model B with no sideways RAM
#   b2 swr-V            the sideways RAM build on a Model B with RAM in banks 4 to 7
#   b2 master-swr-V     the sideways RAM build on a Master 128
#   b2 base-mode1-ram   the 32K build, MODE 1, on a Model B with RAM in banks 4 to 7
#                       (picked with the menu's B)
#   js base-V           the 32K build in jsbeeb, both phases of the 1 MHz clock
#
# JOBS runs of a sweep go at a time (default 8).  PHASES, COLD and SECS, if set,
# are the sweeps' (b2sweep.sh, jsweep.sh: fewer phases or seconds for a quick
# run), as are B2SRC, B2DRIVE and JSBEEB; ARGS, MACHINE and RAM are not passed on.
# The whole matrix takes about 45 minutes at the defaults.  (A SECS under 30 ends a
# Model B's sideways RAM runs before their handover, 21 seconds in: they fail.)
#
# Prints a line per sweep, its name and its verdict (the sweep's last line), then
# "B2ALL PASS" or "B2ALL FAIL" (exit status 1).  Each sweep's own output is in
# OUT/b2/NAME.txt or OUT/js/NAME.txt and its runs' logs in the directory NAME
# beside it (OUT default $BUILD).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
export BUILD=${BUILD:-build}
export JOBS=${JOBS:-8}
O=${OUT:-$BUILD}
unset ARGS
mkdir -p "$O/b2" "$O/js"
ok=1
sweep() { # kind name machine ram version type
    if [ "$1" = b2 ]; then
        OUT="$O/b2/$2" MACHINE=$3 RAM=$4 sh "$HERE/b2sweep.sh" "$5" "$6" > "$O/b2/$2.txt" 2>&1 || ok=0
    else
        OUT="$O/js/$2" sh "$HERE/jsweep.sh" "$5" > "$O/js/$2.txt" 2>&1 || ok=0
    fi
    printf '%s %-17s %s\n' "$1" "$2" "$(tail -n 1 "$O/$1/$2.txt")"
}
for v in mode1 cpc nula arc; do sweep b2 base-$v b none $v base; done
for v in mode1 cpc nula arc; do sweep b2 swr-$v b 4,5,6,7 $v swr; done
for v in mode1 cpc nula arc; do sweep b2 master-swr-$v master 4,5,6,7 $v swr; done
sweep b2 base-mode1-ram b 4,5,6,7 mode1 base
for v in mode1 cpc nula arc; do sweep js base-$v - - $v base; done
[ $ok = 1 ] && echo "B2ALL PASS" || { echo "B2ALL FAIL"; exit 1; }
