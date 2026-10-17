#!/usr/bin/env python3
"""LAYPAD for b32/src/land.s: the smallest value (0..255) with which the renderer
assembles and links (its page-phase .asserts hold), written into the source.

    python3 b32/tools/fitpad.py BUILDDIR CFG

Needs BUILDDIR's generated includes (tables.inc, b32tab.inc) in place."""
import re
import subprocess
import sys

SRC = "b32/src/land.s"
B, CFG = sys.argv[1], sys.argv[2]
text = open(SRC).read()
pat = re.compile(r'^LAYPAD  = \d+', re.M)
assert pat.search(text)
for v in range(256):
    open(SRC, 'w').write(pat.sub(f'LAYPAD  = {v}', text))
    ok = subprocess.run(f'ca65 -g --cpu 6502 -I b32/src -I {B} --bin-include-dir {B} -o {B}/fit.o {SRC} && '
                        f'ld65 -C {CFG} -o {B}/fit.bin {B}/fit.o', shell=True,
                        capture_output=True).returncode == 0
    if ok:
        print(f'LAYPAD = {v}')
        sys.exit(0)
open(SRC, 'w').write(text)
sys.exit('no LAYPAD in 0..255 links')
