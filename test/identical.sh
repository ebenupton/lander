#!/bin/sh
# Rebuild the disc (every version; MODE 1 is left in build/) and check that
# build/lander.ssd is byte for byte the lander.ssd checked in at the repository root.
# Exit 0 when it is.
cd "$(dirname "$0")/.."
sh build.sh > /dev/null && cmp lander.ssd build/lander.ssd && echo "PASS lander.ssd identical"
