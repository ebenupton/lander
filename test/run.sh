#!/bin/sh
# The test suite, run from anywhere after `sh build.sh` (or `sh build.sh cpc|nula`
# with CPC=1 / NULA=1 set; it changes to the repository root): the renderer soak with the ship and with the camera raised,
# every ship orientation, the game loop.  Each test's output is shown but the game
# loop's; exit status 1 if any test fails.
cd "$(dirname "$0")/.."
rc=0
for t in "test/landsoak.py 30 2 2 shipc" "test/landsoak.py 30 5 3 cam" "test/shipbtest.py 2"; do
    echo "== $t"
    python3 $t || rc=1
done
echo "== test/gametest.py 2:,4:T,4:TF,6:"
python3 test/gametest.py "2:,4:T,4:TF,6:" > /dev/null || rc=1
[ $rc = 0 ] && echo "PASS" || echo "FAIL"
exit $rc
