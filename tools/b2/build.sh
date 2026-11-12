#!/bin/sh
# Builds b2drive (b2drive.cpp) against Tom Seddon's b2 emulator core.
#
#   sh tools/b2/build.sh            (or B2SRC=/path/to/b2 sh ...)
#
# Clones b2 (https://github.com/tom-seddon/b2, with its submodules) into
# $B2SRC (default ~/b2src/b2) at the commit below if it is not there (a
# clone already there is used as it stands, at whatever commit it is on),
# then configures it with CMake and Ninja (RelWithDebInfo) in its own build
# directory, $B2SRC/build/lander.osx, with b2drive.cmake hooked in, and
# builds only the b2drive target and the core libraries it needs (no GUI,
# no SDL window).  The binary: $B2SRC/build/lander.osx/b2drive.  b2 itself
# is not part of this repository and is not changed.
set -e
B2COMMIT=2cd8e53a8ab3c366f8b0c015770f724fe49d8533
B2SRC=${B2SRC:-$HOME/b2src/b2}
HERE=$(cd "$(dirname "$0")" && pwd)
if [ ! -d "$B2SRC/.git" ]; then
  git clone --recursive https://github.com/tom-seddon/b2.git "$B2SRC"
  ( cd "$B2SRC" && git checkout -q $B2COMMIT && git submodule update --init --recursive -q )
fi
OUT="$B2SRC/build/lander.osx"
mkdir -p "$OUT"
( cd "$OUT" && cmake -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=$(sw_vers -productVersion 2>/dev/null || echo 12.0) \
    -DCMAKE_OSX_SYSROOT=macosx \
    -DCMAKE_PROJECT_b2_INCLUDE="$HERE/b2drive.cmake" ../.. > cmake.log )
ninja -C "$OUT" b2drive
echo "built $OUT/b2drive"
