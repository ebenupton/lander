#!/usr/bin/env python3
"""The 32K build's worst-case stack: the most bytes any path pushes below a routine's
entry, over the static control flow of the linked program (b32/tools/dataflow's model of
build32/game.dbg).

    python3 b32/tools/stackdepth.py [ROOT ...]      (default: go, irq)

A routine's depth is the most, over the paths from its entry to an RTS (or an exit the
model cannot follow), of PHA/PHP pushes less PLA/PLP pops, a JSR counting 2 plus the
callee's own depth.  Paths are followed within the routine (JSR is not a branch); a JMP
to another routine counts that routine's depth at the jump (a tail).  An exit the model
cannot follow (a patched JMP: run's r_j into a STAB, the ship's chains) ends the path;
its targets are listed so their own depth can be checked as roots (the STABs are made
at run time by init: straight-line stores ending in a planted RTS, no pushes).
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, '..', '..')
sys.path.insert(0, os.path.join(HERE, 'dataflow'))
import gamecfg                      # noqa: E402
gamecfg.load(os.path.join(ROOT, 'b32', 'opt', 'dataflow_b32.py'))
from model import Program           # noqa: E402
from analysis import Analysis       # noqa: E402


def main():
    P = Program(ROOT, os.path.join(ROOT, 'build32'))
    A = Analysis(P, isr_roots=gamecfg.C.ISR_ROOTS)
    sym = {}
    for i in P.insns.values():
        for sy in P.code_label.get(i.key, []):
            sym.setdefault(sy['name'], i)
    memo, unres = {}, set()

    def depth(entry, stack=()):
        if entry.key in memo:
            return memo[entry.key]
        if entry.key in stack:
            return 0                 # (recursion: none expected)
        best = 0
        seen = {}
        work = [(entry, 0)]
        while work:
            i, d = work.pop()
            if seen.get(i.key, -1) >= d:
                continue
            seen[i.key] = d
            best = max(best, d)
            if i.mn in ('PHA', 'PHP'):
                d2 = d + 1
            elif i.mn in ('PLA', 'PLP'):
                d2 = d - 1
            else:
                d2 = d
            if i.mn == 'JSR':
                for t in A.call.get(i.key) or []:
                    best = max(best, d + 2 + depth(t, stack + (entry.key,)))
                if not A.call.get(i.key):
                    unres.add((P.routine_of(i) + f' ${i.addr:04X} ' + P.disasm(i), 'jsr'))
            if i.mn in ('RTS', 'RTI'):
                continue
            if i.key in A.unk:
                unres.add((P.routine_of(i) + f' ${i.addr:04X}', i.mn))
            for t, e in A.succ.get(i.key, []):
                if i.mn == 'JMP' and P.routine_of(t) != P.routine_of(i):
                    best = max(best, d2 + depth(t, stack + (entry.key,)))
                    continue
                work.append((t, d2))
        memo[entry.key] = best
        return best
    roots = sys.argv[1:] or ['go', 'irq']
    for r in roots:
        print(f'{r}: {depth(sym[r])} bytes below its entry')
    # every other entry (address-taken labels: the patched jumps' targets among them)
    deep = sorted(((depth(P.insns[k]) if k in P.insns else 0, k) for k in A.entries
                   if k in P.insns and P.insns[k].seg != 6), key=lambda t: -t[0])
    print('the deepest entries:', ', '.join(f'{P.routine_of(P.insns[k])} ${P.insns[k].addr:04X} {d}'
                                          for d, k in deep[:8]))
    for n, k in sorted(unres):
        print(f'  unfollowed: {k} at {n}')


if __name__ == '__main__':
    main()
