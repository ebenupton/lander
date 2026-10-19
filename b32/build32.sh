#!/bin/sh
# b32/build32.sh: Lander for the 32K BBC Micro Model B.
#
#   sh b32/build32.sh [mode1|cpc|nula|arc]   one version: build32/lander32[-VERSION].ssd
#   sh b32/build32.sh disc                   all four and a chooser: build32/lander32-all.ssd
#
# The versions: mode1 (MODE 1's four colours), cpc (MODE 2: the CPC's 27 colours as
# dithers), nula (MODE 2: the VideoNULA's 16) and arc (MODE 2: Lander's own colours as
# dithers of the NULA's).  A disc boots with SHIFT+BREAK; the chooser (src/menu32.bas)
# offers the NULA versions only on a machine with a VideoNULA.
#
# The steps: b32/tools/gen32.py and ship32.py write the generated includes; ca65
# assembles b32/src/lander.s; the code's size (od65) places it to end at the screen;
# ld65 links LANDER (loaded at $2000, run at its loader, `start`).  Extra assembler
# options in CAFLAGS (e.g. -D COREPAD=n).  Needs cc65, Python 3 with numpy.
set -e
cd "$(dirname "$0")/.."
B=build32
[ "$SWR" = 1 ] && B=${BDIR:-buildswr}
mkdir -p $B
if [ "$1" = disc ]; then
    F=
    for v in cpc:C nula:N arc:A mode1:M; do
        sh b32/build32.sh ${v%:*} > /dev/null 2>&1 || { echo "build32.sh: ${v%:*} failed" >&2; exit 1; }
        mkdir -p $B/disc/${v#*:}
        cp $B/LANDER $B/disc/${v#*:}/LANDER
        X=$(awk '$3 == ".start" {print $2}' $B/labels.txt | sed 's/^00//')
        F="$F ${v#*:}.LANDER:$B/disc/${v#*:}/LANDER:2000:$X"
    done
    { printf 'VDU21\rNEW\r'; tr '\n' '\r' < b32/src/menu32.bas; printf 'RUN\r'; } > $B/BOOTM
    python3 tools/mkdfs.py build $B/lander32-all.ssd LANDER32 "!BOOT:$B/BOOTM:0000:FFFF" $F
    echo "$B/lander32-all.ssd: MODE 1 (M), CPC (C), NULA (N), arc (A)"
    exit 0
fi
V=${1:-mode1}
case $V in
    mode1) export NULA=0 CPC=0 ARC=0; CA=; DISK=lander32 ;;
    cpc)   export NULA=0 CPC=1 ARC=0; CA="-D MODE2 -D CPC"; DISK=lander32-cpc ;;
    nula)  export NULA=1 CPC=0 ARC=0; CA="-D MODE2 -D NULA"; DISK=lander32-nula ;;
    arc)   export NULA=0 CPC=0 ARC=1; CA="-D MODE2 -D NULA -D ARC"; DISK=lander32-arc ;;
    *) echo "build32.sh: no version $V (mode1, cpc, nula, arc)" >&2; exit 1 ;;
esac
[ "$SWR" = 1 ] && DISK=$(echo $DISK | sed s/lander32/landerswr/)
if [ "$SWR" = 1 ]; then
    python3 b32/tools/gen32.py $B
    ca65 -g --cpu 6502 -D SWR $CA $CAFLAGS -I b32/src -I $B -o $B/lander.o b32/src/lander.s -l $B/lander.lst
    PROG=$(od65 --dump-segsize $B/lander.o | awk '$1 ~ /^(FILLS|CODE):$/ {n += $2} END {print 10240 - n}')
    sed "s|\"buildswr/|\"$B/|" b32/src/landerswr.cfg > $B/lander.cfg
    ld65 -C $B/lander.cfg -D __PROG__=$PROG -o $B/x.bin $B/lander.o -m $B/map.txt \
        -Ln $B/labels.txt --dbgfile $B/lander.dbg
    python3 tools/mergebank.py $B $B/map.txt B4:B4CODE B7:B7CODE
    awk '$3 ~ /^\.(TRL|scrb|back|sidx|setTl|setTh|setBl|setBh|OVL|DBUF|GSHK)$/ \
        {printf "L_%s = $%s\n", substr($3, 2), substr($2, 3)}' $B/labels.txt > $B/landsyms.inc
    python3 tools/shipgen.py $B > /dev/null
    ca65 -g --cpu 6502 -I b32/src -I $B -o $B/shipb.o b32/src/shipb.s -l $B/shipb.lst
    ld65 -C b32/src/shipb.cfg -o $B/B6 $B/shipb.o -m $B/shipb_map.txt -Ln $B/shipb_labels.txt
    EXEC=$(awk '$3 == ".start" {print $2}' $B/labels.txt | sed 's/^00//')
    printf '*RUN LANDER\r' > $B/BOOT
    python3 tools/mkdfs.py build $B/$DISK.ssd LANDER "!BOOT:$B/BOOT:0000:FFFF" \
        "LANDER:$B/LANDER:7000:$EXEC" "LAND:$B/LAND:3000:3000" \
        "B4:$B/B4:3000:3000" "B5:$B/B5:3000:3000" "B6:$B/B6:3000:3000" "B7:$B/B7:3000:3000"
    D=$(awk '$3 == ".__DATA_LAST__" {print $2}' $B/labels.txt)
    echo "LAND: data to \$${D#00}, code from \$$(printf %04X $PROG), $((PROG - 0x$D)) bytes free"
    echo "$B/$DISK.ssd"
    exit 0
fi
python3 b32/tools/gen32.py $B
python3 b32/tools/ship32.py $B
ca65 -g --cpu 6502 $CA $CAFLAGS -I b32/src -I $B -o $B/lander.o b32/src/lander.s -l $B/lander.lst
PROG=$(od65 --dump-segsize $B/lander.o | awk '$1 ~ /^(FILLS|CODE):$/ {n += $2} END {print 18688 - n}')
ld65 -C b32/src/lander.cfg -D __PROG__=$PROG -o $B/x.bin $B/lander.o -m $B/map.txt \
    -Ln $B/labels.txt --dbgfile $B/lander.dbg
EXEC=$(awk '$3 == ".start" {print $2}' $B/labels.txt | sed 's/^00//')
printf '*RUN LANDER\r' > $B/BOOT
python3 tools/mkdfs.py build $B/$DISK.ssd LANDER32 "!BOOT:$B/BOOT:0000:FFFF" "LANDER:$B/LANDER:2000:$EXEC"
D=$(awk '$3 == ".__DATA_LAST__" {print $2}' $B/labels.txt)
echo "LANDER: data to \$${D#00}, code from \$$(printf %04X $PROG), $((PROG - 0x$D)) bytes free"
echo "$B/$DISK.ssd"
