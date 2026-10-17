#!/usr/bin/env python3
"""What the 32K build needs at run time: the code reachable from the main loop and the
interrupt, and the labels (code and data) that code names; everything else in the
program image (L32M) is start-up only and belongs in the loader (L32, BOOT: discarded).

    python3 b32/tools/runtime.py

Reachability follows the static control flow of b32/tools/dataflow's model (branches,
JMP, JSR, fall-through) from `loop` and `irq`; a label the reached code names in an
operand (`lda #<x`, `sta x+1`, `lda x,y`, a table) is reached too -- as code if it is
an instruction (a patched jump's target), as data otherwise -- to a fixpoint.  Prints
the image's labels that are never reached, with their segment and size up to the next
label, the candidates for the loader; and the start-up routines' total.
"""
import collections
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
sys.path.insert(0, os.path.join(HERE, 'dataflow'))
import gamecfg                      # noqa: E402
gamecfg.load(os.path.join(ROOT, 'b32', 'opt', 'dataflow_b32.py'))
from model import Program           # noqa: E402
from analysis import Analysis       # noqa: E402

IMAGE = ('MAPD', 'PANELD', 'CODE', 'FILLS', 'GAME', 'SHIP')


def main():
    P = Program(ROOT, os.path.join(ROOT, 'build32'))
    A = Analysis(P, isr_roots=gamecfg.C.ISR_ROOTS)
    segname = {sid: s['name'] for sid, s in P.segs.items()}
    # every symbol: name -> (value, seg); labels in the image by address
    syms = {s['name']: s for s in P.syms}
    labels = sorted((s['val'], s['name'], segname.get(s['seg'])) for s in P.syms
                    if s['seg'] is not None and segname.get(s['seg']) in IMAGE
                    and s['type'] == 'lab')
    byaddr = collections.defaultdict(list)
    for v, n, sg in labels:
        byaddr[v].append(n)
    word = re.compile(r'[A-Za-z_@][A-Za-z0-9_@]*')

    def named(i):
        """the symbols an instruction's operand names (its source text)"""
        t = P.text(i, inner=True).split(';')[0]
        m = re.match(r'\s*(?:[A-Za-z_@][\w@]*:|:)?\s*([A-Za-z]{3})\b(.*)', t)
        ops = m.group(2) if m else ''
        return [w for w in word.findall(ops) if w in syms]
    code_at = {i.addr: i for i in P.insns.values() if segname.get(i.seg) in IMAGE + ('BOOT',)}
    seen, work, data = set(), [], set()

    def add(i):
        if i.key not in seen:
            seen.add(i.key)
            work.append(i)
    for r in ('loop', 'irq'):
        add(code_at[syms[r]['val']])
    # conservative roots: every label a data directive names (address tables, in any
    # file), and every image label the loader names other than as a JSR target (init
    # patches runtime code with addresses: those targets run at run time)
    for fn in os.listdir(os.path.join(ROOT, 'b32', 'src')):
        if fn.endswith(('.s', '.inc')):
            for ln in open(os.path.join(ROOT, 'b32', 'src', fn)):
                t = ln.split(';')[0]
                if re.search(r'\.(byte|word|addr|lobytes|hibytes|dbyt)\b', t):
                    for w in word.findall(t.split('.', 1)[1]):
                        if w in syms and syms[w]['val'] in code_at:
                            add(code_at[syms[w]['val']])
                        elif w in syms:
                            data.add(w)
    for i in list(P.insns.values()):
        if segname.get(i.seg) == 'BOOT' and i.mn != 'JSR':
            for n in named(i):
                v = syms[n]['val']
                if segname.get(syms[n]['seg']) in IMAGE:
                    if v in code_at and not (i.mn == 'JMP' and n == 'go'):
                        add(code_at[v])
    while work:
        i = work.pop()
        for t, e in A.succ.get(i.key, []):
            add(t)
        for t in A.call.get(i.key) or []:
            add(t)
        for n in named(i):
            v = syms[n]['val']
            if v in code_at and segname.get(syms[n]['seg']) in IMAGE:
                add(code_at[v])
            data.add(n)
    reached_addr = {P.insns[k].addr for k in seen if k in P.insns}
    out = []
    for k, (v, n, sg) in enumerate(labels):
        nxt = labels[k + 1][0] if k + 1 < len(labels) else v + 1
        if n.startswith('@') or v == nxt:
            continue
        is_code = v in code_at
        live = (v in reached_addr) if is_code else (n in data or any(
            m in data for m in byaddr[v]))
        if not live:
            out.append((sg, v, nxt - v, n, 'code' if is_code else 'data'))
    tot = collections.Counter()
    for sg, v, size, n, kind in out:
        print(f'{sg:7s} ${v:04X} {size:5d} {kind:4s} {n}')
        tot[kind] += size
    print(f'not needed at run time: {tot["code"]} bytes of code, {tot["data"]} of data '
          '(sizes run to the next label: check each)')


if __name__ == '__main__':
    main()
