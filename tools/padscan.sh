#!/bin/sh
# tools/padscan.sh: the flight's cycles a frame for each value of COREPAD.
#
#   [SWR=1] [BUILD=dir] sh tools/padscan.sh VERSION FROM TO
#   e.g.  sh tools/padscan.sh mode1 0 95
#
# COREPAD (src/lander.s) is the renderer's page phase: bytes of padding after the
# renderer.  The code is linked to end at a fixed address, so the pad moves the
# code before it, and with it the branches and tables that cross pages.  For each
# value FROM .. TO this builds the program (SWR=1: the sideways RAM build) with -D
# COREPAD=n into BUILD/padscan/<base|swr>-VERSION (BUILD default build; the builds
# themselves are not touched) and flies test/gate.sh's flight (test/gametest.py over
# test/flightprof.py's SCRIPT).  Prints "COREPAD=n <cycles a frame>", or "COREPAD=n
# fail" where the build fails (an assert; the log is BUILD/padscan/log.txt).  The
# best value changes when the code changes; it goes in src/lander.s as the default.
#
# COREPAD is the only pad scanned.  The 32K build has a second, TAILPAD (src/lander.s),
# after the display's code: it is not tuned for speed, it keeps src/video.s's timed
# branches within their pages.  COREPAD does not move video.s, so when video.s's
# asserts fire ("irq: the dispatch's branches in their page", "crws: in one page",
# "dejit: its slide in one page") they fire at every COREPAD: the code after video.s
# has changed size.  Find a TAILPAD at which video.s's asserts pass in all four
# versions:
#   CAFLAGS="-D TAILPAD=n" sh build.sh base VERSION        (n from 0 up)
# TAILPAD moves the renderer too, so its asserts may fire in their turn: those are
# COREPAD's to clear.  Scan again with the TAILPAD found (CAFLAGS is passed on)
#   CAFLAGS="-D TAILPAD=n" sh tools/padscan.sh VERSION FROM TO
# and make both values lander.s's defaults.
cd "$(dirname "$0")/.."
[ $# = 3 ] || { echo "usage: [SWR=1] [BUILD=dir] sh tools/padscan.sh VERSION FROM TO" >&2; exit 1; }
V=$1; n=$2
T=base
[ "$SWR" = 1 ] && T=swr
R=${BUILD:-build}/padscan
mkdir -p $R
export VERSION=$V BDIR=$R/$T-$V     # test/rig.py's: gametest's build
SCRIPT=$(python3 -c "import sys; sys.path.insert(0, 'test'); import flightprof; print(flightprof.SCRIPT)") || exit 1
while [ $n -le $3 ]; do
    if BUILD=$R CAFLAGS="$CAFLAGS -D COREPAD=$n" sh build.sh $T $V > $R/log.txt 2>&1; then
        c=$(python3 test/gametest.py "$SCRIPT" | cut -c11-17 | awk '{s += $1; n++} END {printf "%d", s/n}')
    else
        c=fail
    fi
    echo "COREPAD=$n $c"
    n=$((n + 1))
done
