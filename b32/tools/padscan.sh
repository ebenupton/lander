#!/bin/sh
# b32/tools/padscan.sh VERSION PAD FROM TO: the flight's cycles a frame for each value of
# a page-phase pad (COREPAD, LAYPAD), FROM to TO.  A pad moves the code before it, so
# its best value changes when code after it does.  "fail": the build's page asserts.
#   e.g.  sh b32/tools/padscan.sh mode1 COREPAD 0 95
cd "$(dirname "$0")/../.."
V=$1; P=$2; n=$3
mkdir -p build32
case $V in
    cpc) export CPC=1 NULA=0 ARC=0 ;; nula) export NULA=1 CPC=0 ARC=0 ;;
    arc) export ARC=1 CPC=0 NULA=0 ;; *) export CPC=0 NULA=0 ARC=0 ;;
esac
SCRIPT=$(python3 -c "import sys; sys.path.insert(0, 'b32/test'); import profile32; print(profile32.SCRIPT)")
while [ $n -le $4 ]; do
    if CAFLAGS="$CAFLAGS -D $P=$n" sh b32/build32.sh $V > build32/padscan.log 2>&1; then
        c=$(python3 b32/test/gametest32.py "$SCRIPT" | cut -c11-17 | awk '{s += $1; n++} END {printf "%d", s/n}')
    else
        c=fail
    fi
    echo "$P=$n $c"
    n=$((n + 1))
done
