#!/bin/sh
# Rebuild each version and check that build/lander.ssd is byte for byte the disc checked
# in at the repository root: lander-nula.ssd (NULA), lander-cpc.ssd (CPC palette),
# lander.ssd (MODE 1).  The MODE 1 build is left in build/.  Exit 0 when all are.
cd "$(dirname "$0")/.."
sh build.sh nula > /dev/null && cmp lander-nula.ssd build/lander.ssd && echo "PASS lander-nula.ssd identical" &&
sh build.sh cpc > /dev/null && cmp lander-cpc.ssd build/lander.ssd && echo "PASS lander-cpc.ssd identical" &&
sh build.sh > /dev/null && cmp lander.ssd build/lander.ssd && echo "PASS lander.ssd identical"
