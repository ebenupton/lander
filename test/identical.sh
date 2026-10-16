#!/bin/sh
# Rebuild both versions and check that each build/lander.ssd is byte for byte the disc
# checked in at the repository root: lander.ssd (MODE 1), lander-nula.ssd (NULA).  The
# MODE 1 build is left in build/.  Exit 0 when both are.
cd "$(dirname "$0")/.."
sh build.sh nula > /dev/null && cmp lander-nula.ssd build/lander.ssd && echo "PASS lander-nula.ssd identical" &&
sh build.sh > /dev/null && cmp lander.ssd build/lander.ssd && echo "PASS lander.ssd identical"
