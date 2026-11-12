#!/bin/sh
# build.sh: Lander for the BBC Micro.
#
#   sh build.sh                  everything: the eight builds, the loader and the disc,
#                                build/lander.ssd, copied to lander.ssd
#   sh build.sh base VERSION     the 32K Model B build, into build/base-VERSION/
#   sh build.sh swr VERSION      the sideways RAM build, into build/swr-VERSION/
#   sh build.sh loader           the disc's !BOOT, into build/loader/
#   sh build.sh disc             the disc, from the builds as they stand
#
# VERSION: mode1, cpc, nula or arc.  BUILD=dir builds under dir instead of build/;
# SRC=dir assembles the sources there instead of src/; CAFLAGS adds assembler
# options (e.g. -D COREPAD=n).  Needs cc65 (ca65, ld65, od65) and Python 3 with numpy.
set -e
cd "$(dirname "$0")"
SRC=${SRC:-src}
BUILD=${BUILD:-build}
T=$1
V=${2:-mode1}
case $T in
"")
    mkdir -p $BUILD
    for t in base swr; do
        for v in mode1 cpc nula arc; do
            sh build.sh $t $v > $BUILD/$t-$v.log 2>&1 &
        done
    done
    wait
    for t in base swr; do
        for v in mode1 cpc nula arc; do
            tail -n 1 $BUILD/$t-$v.log | grep -q 'bytes free' || { echo "build.sh: $t $v failed ($BUILD/$t-$v.log)" >&2; exit 1; }
            echo "$t-$v: $(tail -n 1 $BUILD/$t-$v.log)"
        done
    done
    sh build.sh loader
    sh build.sh disc
    exit 0 ;;
loader)
    B=$BUILD/loader
    mkdir -p $B
    ca65 -g --cpu 6502 -o $B/loader.o $SRC/loader.s -l $B/loader.lst
    ld65 -C $SRC/loader.cfg -o $B/BOOT $B/loader.o -m $B/map.txt -Ln $B/labels.txt
    echo "loader: $(wc -c < $B/BOOT) bytes"
    exit 0 ;;
disc)
    python3 tools/mkdisc.py $BUILD $BUILD/lander.ssd
    [ "$BUILD" = build ] && cp $BUILD/lander.ssd lander.ssd
    exit 0 ;;
esac
case $V in
    mode1) export NULA=0 CPC=0 ARC=0; CA= ;;
    cpc)   export NULA=0 CPC=1 ARC=0; CA="-D MODE2 -D CPC" ;;
    nula)  export NULA=1 CPC=0 ARC=0; CA="-D MODE2 -D NULA" ;;
    arc)   export NULA=0 CPC=0 ARC=1; CA="-D MODE2 -D NULA -D ARC" ;;
    *) echo "build.sh: no version $V (mode1, cpc, nula, arc)" >&2; exit 1 ;;
esac
B=$BUILD/$T-$V
mkdir -p $B
case $T in
swr)
    export SWR=1
    python3 tools/gen.py $B
    ca65 -g --cpu 6502 -D SWR $CA $CAFLAGS -I $SRC -I $B -o $B/lander.o $SRC/lander.s -l $B/lander.lst
    PROG=$(od65 --dump-segsize $B/lander.o | awk '$1 ~ /^(FILLS|CODE):$/ {n += $2} END {print 10240 - n}')
    sed "s|\"BUILD/|\"$B/|" $SRC/landerswr.cfg > $B/lander.cfg
    ld65 -C $B/lander.cfg -D __PROG__=$PROG -o $B/x.bin $B/lander.o -m $B/map.txt \
        -Ln $B/labels.txt --dbgfile $B/lander.dbg
    python3 tools/mergebank.py $B $B/map.txt B4:B4CODE B5:B5CODE B7:B7CODE
    awk '$3 ~ /^\.(TRL|scrb|back|sidx|setTl|setTh|setBl|setBh|OVL|DBUF|GSHK)$/ \
        {printf "L_%s = $%s\n", substr($3, 2), substr($2, 3)}' $B/labels.txt > $B/landsyms.inc
    python3 tools/shipgen.py $B > /dev/null
    ca65 -g --cpu 6502 -I $SRC -I $B -o $B/shipb.o $SRC/shipb.s -l $B/shipb.lst
    ld65 -C $SRC/shipb.cfg -o $B/B6 $B/shipb.o -m $B/shipb_map.txt -Ln $B/shipb_labels.txt
    D=$(awk '$3 == ".__DATA_LAST__" {print $2}' $B/labels.txt)
    echo "MAIN: data to \$${D#00}, code from \$$(printf %04X $PROG), $((PROG - 0x$D)) bytes free"
    ;;
base)
    export SWR=0
    python3 tools/gen.py $B
    python3 tools/shipmodel.py $B
    ca65 -g --cpu 6502 $CA $CAFLAGS -I $SRC -I $B -o $B/lander.o $SRC/lander.s -l $B/lander.lst
    PROG=$(od65 --dump-segsize $B/lander.o | awk '$1 ~ /^(FILLS|CODE):$/ {n += $2} END {print 18688 - n}')
    sed "s|\"BUILD/|\"$B/|" $SRC/lander.cfg > $B/lander.cfg
    ld65 -C $B/lander.cfg -D __PROG__=$PROG -o $B/x.bin $B/lander.o -m $B/map.txt \
        -Ln $B/labels.txt --dbgfile $B/lander.dbg
    D=$(awk '$3 == ".__DATA_LAST__" {print $2}' $B/labels.txt)
    echo "BASE: data to \$${D#00}, code from \$$(printf %04X $PROG), $((PROG - 0x$D)) bytes free"
    ;;
*)
    echo "build.sh: base, swr, loader or disc" >&2; exit 1 ;;
esac
