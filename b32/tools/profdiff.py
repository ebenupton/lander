#!/usr/bin/env python3
"""Per-routine cycles of two profile32.py runs (each build's profile.json and labels.txt):
    python3 b32/tools/profdiff.py OLD_BUILD_DIR NEW_BUILD_DIR"""
import bisect, collections, json, sys
def per(d):
    pj = json.load(open(d + '/profile.json'))
    lab = sorted((int(a, 16), n.lstrip('.')) for _, a, n in (l.split() for l in open(d + '/labels.txt'))
                 if not n.lstrip('.').startswith(('@', '__')))
    ks = [a for a, _ in lab]
    c = collections.Counter()
    for pc, cy in pj['pcs'].items():
        i = bisect.bisect_right(ks, int(pc, 16)) - 1
        c[lab[i][1]] += cy
    return c, pj['frames']
a, fa = per(sys.argv[1]); b, fb = per(sys.argv[2])
rows = sorted(((b[k] / fb - a[k] / fa, k) for k in set(a) | set(b)), key=lambda t: t[0])
print('cycles a frame, new - old (most saved first, most lost last)')
for d, k in rows[:15]:
    print(f'  {d:+9.1f}  {k}')
print('  ...')
for d, k in rows[-15:]:
    print(f'  {d:+9.1f}  {k}')
print(f'  total {sum(d for d, _ in rows):+.1f}')
