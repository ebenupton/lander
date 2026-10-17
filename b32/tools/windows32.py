#!/usr/bin/env python3
"""Cut the 32K build's run-time code into review windows for the micro-optimisation grind,
each line annotated and weighted by the measured profile.

    python3 b32/tools/windows32.py [OUT]       (default build32/grind)

Reads build32/game.dbg (b32/tools/dataflow's model), build32/profile.json (profile32.py)
and build32/annotated/<file> (annotate.py: the range analysis).  A window is 32 code lines
(source lines that assemble to instructions; a macro line counts once) in source order
within one routine (the nearest global label), a longer routine cut into windows that
overlap by 8, consecutive short routines of a file packed together; only the program
image's code (the loader's, BOOT, is discarded after start-up: its bytes and cycles are
free).  Writes OUT/w_NNN.txt:

    header   id, file, lines, routines, cycles a frame, bytes
    context  the 6 source lines before the window
    lines    every source line of the window:  line | cycles a frame | source ;| annotation
             (cycles a frame: measured over profile32.py's flight, summed over the line's
             instructions; '-' never executed there)
    entries  the window's labels and the instructions outside it that jump or branch to
             them, or call them

and OUT/windows.json: [{id, file, start, end, routines, cycles, bytes}] ranked by cycles.
"""
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
sys.path.insert(0, os.path.join(HERE, 'dataflow'))
import gamecfg                      # noqa: E402
gamecfg.load(os.path.join(ROOT, 'b32', 'opt', 'dataflow_b32.py'))
from model import Program           # noqa: E402
from analysis import Analysis       # noqa: E402

SIZE, OVERLAP, CONTEXT = 32, 8, 6
IMAGE = ('MAPD', 'PANELD', 'CODE', 'FILLS', 'GAME', 'SHIP')


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build32', 'grind')
    os.makedirs(out, exist_ok=True)
    P = Program(ROOT, os.path.join(ROOT, 'build32'))
    A = Analysis(P, isr_roots=gamecfg.C.ISR_ROOTS)
    pj = json.load(open(os.path.join(ROOT, 'build32', 'profile.json')))
    F = pj['frames']
    pcs = {int(a, 16): c for a, c in pj['pcs'].items()}
    seg = {sid: s['name'] for sid, s in P.segs.items()}
    # per source line: its instructions, cycles a frame, bytes, routine
    lines = collections.defaultdict(lambda: dict(insns=[], cyc=0.0, bytes=0, routine=None))
    for i in P.insns.values():
        if seg.get(i.seg) not in IMAGE:
            continue
        f, ln = P.src.short(i.outer['file']), i.outer['line']
        L = lines[(f, ln)]
        L['insns'].append(i)
        L['cyc'] += pcs.get(i.addr, 0) / F
        L['bytes'] += i.len
        L['routine'] = L['routine'] or P.routine_of(i)
    files = collections.defaultdict(list)
    for (f, ln) in sorted(lines):
        files[f].append(ln)
    srcs, anns = {}, {}
    for f in files:
        srcs[f] = open(os.path.join(ROOT, f)).read().split('\n')
        ap = os.path.join(ROOT, 'build32', 'annotated', f)
        anns[f] = open(ap).read().split('\n') if os.path.exists(ap) else None
    # windows: runs of code lines within a routine, packed
    wins = []
    for f, lns in files.items():
        groups, cur, rt = [], [], None
        for ln in lns:
            r = lines[(f, ln)]['routine']
            if cur and r != rt:
                groups.append(cur)
                cur = []
            cur.append(ln)
            rt = r
        if cur:
            groups.append(cur)
        pack = []
        for g in groups:
            if len(g) > SIZE:
                if pack:
                    wins.append((f, pack))
                    pack = []
                k = 0
                while True:
                    wins.append((f, g[k:k + SIZE]))
                    if k + SIZE >= len(g):
                        break
                    k += SIZE - OVERLAP
            elif len(pack) + len(g) > SIZE:
                wins.append((f, pack))
                pack = list(g)
            else:
                pack += g
        if pack:
            wins.append((f, pack))
    # label -> who enters it from outside the window
    callers = collections.defaultdict(list)
    for i in P.insns.values():
        for t, e in A.succ.get(i.key, []):
            callers[t.key].append(i)
        for t in A.call.get(i.key) or []:
            callers[t.key].append(i)
    meta = []
    for n, (f, wl) in enumerate(wins):
        wid = f'w_{n:03d}'
        lo, hi = wl[0], wl[-1]
        cyc = sum(lines[(f, ln)]['cyc'] for ln in wl)
        byt = sum(lines[(f, ln)]['bytes'] for ln in wl)
        routines = sorted({lines[(f, ln)]['routine'] for ln in wl}, key=lambda r: wl.index(next(
            ln for ln in wl if lines[(f, ln)]['routine'] == r)))
        txt = [f'# {wid}: {f} lines {lo}-{hi}, routines {", ".join(routines)}; '
               f'{cyc:.0f} cycles a frame measured, {byt} bytes',
               '# columns: line | cycles a frame | source ;| state before the instruction '
               '(range analysis: b32/opt/GRIND_BRIEF.md)', '# context:']
        for ln in range(max(1, lo - CONTEXT), lo):
            txt.append(f'{ln:5d} |        | {srcs[f][ln - 1]}')
        txt.append('# window:')
        inside = set()
        for ln in range(lo, hi + 1):
            L = lines.get((f, ln))
            src = srcs[f][ln - 1]
            ann = ''
            if anns[f] and ln - 1 < len(anns[f]) and ';|' in anns[f][ln - 1]:
                ann = ' ;|' + anns[f][ln - 1].split(';|', 1)[1]
            if L and L['insns']:
                inside.update(i.key for i in L['insns'])
                c = f'{L["cyc"]:7.1f}' if L['cyc'] else '      -'
            else:
                c = '       '
            txt.append(f'{ln:5d} | {c} | {src}{ann}')
        ent = []
        for ln in wl:
            for i in lines[(f, ln)]['insns']:
                labs = [s['name'] for s in P.code_label.get(i.key, [])]
                if labs:
                    fr = [c for c in callers.get(i.key, []) if c.key not in inside]
                    ent.append(f'#   {"/".join(labs)} (line {ln}): entered from ' +
                               (', '.join(sorted({f"{P.where(c)} {P.disasm(c)}" for c in fr}))
                                if fr else 'only within the window (or address-taken: check)'))
        if ent:
            txt.append('# labels:')
            txt += ent
        open(os.path.join(out, wid + '.txt'), 'w').write('\n'.join(txt) + '\n')
        meta.append(dict(id=wid, file=f, start=lo, end=hi, routines=routines,
                         cycles=round(cyc, 1), bytes=byt))
    meta.sort(key=lambda m: -m['cycles'])
    json.dump(meta, open(os.path.join(out, 'windows.json'), 'w'), indent=0)
    tot = sum(m['cycles'] for m in meta)
    print(f'{len(meta)} windows, {tot:.0f} cycles a frame (overlaps counted twice); hottest:')
    for m in meta[:15]:
        print(f"  {m['id']} {m['cycles']:8.0f} {m['bytes']:4d} bytes  {m['file']}:{m['start']}-{m['end']} {', '.join(m['routines'])}")


if __name__ == '__main__':
    main()
