#!/usr/bin/env python3
"""Rank the 32K build's data for zero page: from build32/profile.json (profile32.py),
each variable's accesses a frame that zero page would make a cycle cheaper (abs and
abs,X operands; LDX/STX abs,Y), per byte of it.  Variables are the data labels
(labels.txt, not code: a code label's bytes are a patched operand) and the fixed-address
equates in b32/src (NAME = $xxxx); a variable's size runs to the next one (or to the last
byte touched).  Address-taken variables (#<name, #>name in b32/src) are marked: moving
one needs its users checked.

    python3 b32/tools/zprank.py [N]
"""
import bisect, collections, glob, json, re, sys

pj = json.load(open('build32/profile.json'))
F = pj['frames']
code = set(int(a, 16) for a in pj['pcs'])
names = {}
for ln in open('build32/labels.txt'):
    _, a, n = ln.split()
    a, n = int(a, 16), n.lstrip('.')
    if not n.startswith(('__', '@')):
        names.setdefault(a, n)
src = ''.join(open(f).read() for f in glob.glob('b32/src/*.s'))
for m in re.finditer(r'^([A-Za-z_]\w*)\s*=\s*\$([0-9A-Fa-f]{4})\b', src, re.M):
    a = int(m.group(2), 16)
    if 0x200 <= a < 0x1400:
        names.setdefault(a, m.group(1))
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
