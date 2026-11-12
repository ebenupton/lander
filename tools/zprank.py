#!/usr/bin/env python3
"""The data that zero page would make cheapest, from a flight's profile.

    [SWR=1] [VERSION=v] [BUILD=dir] python3 test/flightprof.py
    [SWR=1] [VERSION=v] [BUILD=dir] python3 tools/zprank.py [N]

Reads profile.json (test/flightprof.py's) and labels.txt in the build's directory,
test/rig.py's (SWR, VERSION, BUILD, BDIR), and src/*.s.  Prints the best N variables
(default 60) by the cycles a frame that zero page would save for each byte of them: a
cycle for each access by an abs or abs,X operand (LDX and STX: abs,Y).  A variable is a
data label below $5000 (src/ram.s's, the tables'), its size running to the next label or
the last byte touched; one whose address the code takes (#<name, #>name) is marked:
moving it needs its users checked.
"""
import bisect
import collections
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'test'))
import rig  # noqa: E402

pj = json.load(open(os.path.join(rig.B, 'profile.json')))
F = pj['frames']
code = set(int(a, 16) for a in pj['pcs'])
names = {}
for n, a in rig.labels().items():
    if not n.startswith(('__', '@')):
        names.setdefault(a, n)
src = ''.join(open(f).read() for f in glob.glob(os.path.join(rig.ROOT, 'src', '*.s')))
taken = set(re.findall(r'#[<>]\(?([A-Za-z_]\w*)', src))
keys = sorted(names)
gain, top, ins = collections.Counter(), {}, collections.defaultdict(set)
for a, (r, w, modes, pcs) in pj['data'].items():
    a = int(a, 16)
    if a < 0x200 or a >= 0x5000:
        continue
    i = bisect.bisect_right(keys, a) - 1
    if i < 0:
        continue
    o = keys[i]
    if any(int(p, 16) == o for p in pcs) or o in code:
        continue
    g = sum(n for md, n in modes.items() if md.endswith((' abs', ' abx')) or md in ('LDX aby', 'STX aby'))
    gain[o] += g
    top[o] = max(top.get(o, o), a)
    ins[o].update(pcs)
rows = []
for o, g in gain.items():
    if not g:
        continue
    i = keys.index(o)
    nxt = keys[i + 1] if i + 1 < len(keys) else top[o] + 1
    sz = min(nxt, top[o] + 1) - o
    rows.append((g / F / sz, g / F, sz, o, names[o], names[o] in taken))
rows.sort(reverse=True)
cum = 0
for per, g, sz, o, n, t in rows[:int(sys.argv[1]) if len(sys.argv) > 1 else 60]:
    cum += sz
    print(f'${o:04X} {n:10s} {sz:3d} bytes  {g:7.1f} cycles/frame  {per:6.1f}/byte  cum {cum:3d}{"  (address taken)" if t else ""}')
