#!/bin/sh
# tools/b2/b2sweep.sh: one build's video timing on b2 at many boot phases.
#
#   [BUILD=dir] [OUT=dir] [MACHINE=b|bplus|master] [RAM=none|4,5,6,7] [JOBS=n]
#   [PHASES="..."] [COLD="..."] [SECS=s] [ARGS="..."] sh tools/b2/b2sweep.sh [VERSION] [base|swr]
#
# VERSION: mode1 (the default), cpc, nula or arc; base (the default) is the 32K
# build, swr the sideways RAM build.  The disc is $BUILD/lander.ssd (BUILD default
# build: sh build.sh).  tools/b2/all.sh runs this for every build and machine.
#
# b2drive (tools/b2/build.sh builds it; B2SRC is b2's source, default ~/b2src/b2,
# and B2DRIVE the binary, default $B2SRC/build/lander.osx/b2drive) boots the disc,
# picks the build and the version at the loader's menu and flies fly.txt (keys
# held throughout; the script ends at 100 emulated seconds, and SECS, default 105,
# is a limit), at each boot phase:
#
#  * warm: SHIFT+BREAK after PRE more 2 MHz cycles (b2drive --pre), for each PRE in
#    PHASES (default: 16 of them, 0 to 987): the program takes the display over at
#    another point of the MOS's field and line each time;
#  * cold: power on with SHIFT held, b2's cycle count starting at each of COLD
#    (--cold --pre; default 0 1 2 3): the power-on against the 2 MHz and 1 MHz
#    clocks' phases (b2's power-on is otherwise deterministic, and its 6845, VIAs
#    and CPU bus all take their 1 MHz phase from the one count, so these four cover
#    every cold boot b2 can make).
#
# The machine: a Model B with no sideways RAM for the 32K build, with RAM in banks
# 4 to 7 for the sideways RAM build; RAM="4,5,6,7" or RAM=none overrides (with RAM
# the loader offers the sideways RAM build first, and the menu's B picks the 32K
# build).  MACHINE=bplus runs b2's B+ and MACHINE=master its Master 128 (the
# sideways RAM build only).  The nula and arc versions get a VideoNuLA.
#
# The judged control value is the land's: D8 (mode1) or F4.  The 32K build is
# judged from its second write of it, the first field's Eb (b2drive.cpp; src/video.s),
# the sideways RAM build from the end of its set-up of the frame (the 6845's R13).
# ARGS adds b2drive options.
#
# JOBS runs at a time (default 3).  Each must print B2SYNC PASS: every horizontal
# sync interval 128 cycles, every field 312 lines, b2's TV never losing either
# sync.  Prints a line per run (the TV's counts: retraces on a sync / on its
# timeout / syncs ignored; vertical syncs accepted / rejected / forced; the fields
# from the handover to the TV's vertical lock; and the switches' landing lines
# and cycles), then "B2SWEEP PASS TYPE-VERSION" or "B2SWEEP FAIL TYPE-VERSION"
# (exit status 1).  Logs and the PNGs: OUT (default $BUILD/b2/TYPE-VERSION), a
# directory a run (warm-PRE, cold-PRE).
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
V=${1:-mode1}
T=${2:-base}
BUILD=${BUILD:-build}
SECS=${SECS:-105}
PHASES=${PHASES:-"0 1 2 3 5 8 13 21 34 55 89 144 233 377 610 987"}
COLD=${COLD:-"0 1 2 3"}
JOBS=${JOBS:-3}
B2SRC=${B2SRC:-$HOME/b2src/b2}
BIN=${B2DRIVE:-$B2SRC/build/lander.osx/b2drive}
OUT=${OUT:-$BUILD/b2/$T-$V}
[ -x "$BIN" ] || { echo "no b2drive at $BIN (sh tools/b2/build.sh)"; exit 1; }
[ -f "$BUILD/lander.ssd" ] || { echo "no $BUILD/lander.ssd (sh build.sh)"; exit 1; }
case $V in
    mode1) KEY=1; A="--judge-ula D8" ;;
    cpc)   KEY=2; A="--judge-ula F4" ;;
    nula)  KEY=3; A="--judge-ula F4 --nula" ;;
    arc)   KEY=4; A="--judge-ula F4 --nula" ;;
    *) echo "b2sweep.sh: no version $V (mode1, cpc, nula, arc)"; exit 1 ;;
esac
MACHINE=${MACHINE:-b}
case $T in
    swr)  RAM=${RAM:-4,5,6,7}; A="$A --panel-ula 0 --judge-reg 13"; OTHER= ;;
    base) RAM=${RAM:-none}; A="$A --judge-skip 1"; OTHER=; [ "$RAM" = none ] || OTHER="4 key B" ;;
    *) echo "b2sweep.sh: base or swr"; exit 1 ;;
esac
A="$A --ram $RAM --machine $MACHINE ${ARGS:-}"
mkdir -p "$OUT"
run() { # mode pre
    d="$OUT/$1-$2"; mkdir -p "$d"
    flag=""; [ "$1" = cold ] && flag=--cold
    { echo "$OTHER"; echo "5.5 key $KEY"; cat "$HERE/fly.txt"; } > "$d/script.txt"
    "$BIN" --disc "$BUILD/lander.ssd" --roms "$B2SRC/etc/roms" --out "$d" --script "$d/script.txt" \
        --secs "$SECS" --pre "$2" $A $flag > "$d/log.txt" 2>&1
}
n=0
for m in warm cold; do
    ps=$PHASES; [ $m = cold ] && ps=$COLD
    for p in $ps; do
        run $m $p &
        n=$((n + 1))
        [ $((n % JOBS)) -eq 0 ] && wait
    done
done
wait
ok=1
for m in warm cold; do
    ps=$PHASES; [ $m = cold ] && ps=$COLD
    for p in $ps; do
        l="$OUT/$m-$p/log.txt"
        v=$(grep -E "^B2SYNC" "$l" || echo "B2SYNC NONE")
        iv=$(sed -n 's/^6845 horizontal sync intervals (2 MHz cycles)://p' "$l")
        fl=$(sed -n 's/^6845 lines per field://p' "$l")
        tv=$(sed -n 's/^TV: \([0-9]* retraces\)/\1/p' "$l" | sed 's/ retraces on a sync, /\//; s/ on its timeout, /\//; s/ syncs ignored; vertical syncs /; v /; s/ accepted, /\//; s/ rejected, /\//; s/ forced.*//')
        lk=$(sed -n 's/^TV: its first vertical retrace on a sync \([0-9.]*\) fields.*/\1/p' "$l")
        ula=$(sed -n 's/^ULA control writes by value and line:cycle://p' "$l")
        printf '%-5s %4s  %s  intervals%s  fields%s  tv %s; locked %s  ula%s\n' "$m" "$p" "$v" "$iv" "$fl" "$tv" "${lk:--}" "$ula"
        [ "$v" = "B2SYNC PASS" ] || ok=0
    done
done
[ $ok = 1 ] && echo "B2SWEEP PASS $T-$V" || { echo "B2SWEEP FAIL $T-$V"; exit 1; }
