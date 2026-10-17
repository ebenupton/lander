#!/usr/bin/env python3
"""annotate -- a copy of the game's source with what the analyses know at every instruction.

    python3 tools/dataflow/annotate.py [--build build/master] [--out DIR]

Runs ranges.py's analysis (and analysis.py's liveness) and writes DIR/src/<file>.s: each
source line that assembles to instructions gets a trailing comment

    ;| A=0..3 X=? Y=$0B C=1 Z=? N=0 V=? | damage=0..80 | ty=barrel | in:AXC out:A

  before the instruction: each register's range (dom.fmt: $xx one value, lo..hi, ? any,
  %bits for known bits, {type:range ...} per object type), the flags (0/1/?), the memory
  operand's range when it has one, the object types the code can be handling there
  (when not all), and the registers/flags live in (needed by this instruction or later)
  and live out (needed after it).  A branch says 'never' or 'always' when one way is
  infeasible.  A line no analysis reached says UNREACHED.  A macro's line lists each
  instruction it expands to, `[insn] state`, separated by ‖ (the line numbers stay the
  source's).  DIR/summary.md: the record invariant per object type,
  unresolved exits, unbounded pointer stores, coverage.
"""
import os, sys, json, argparse, collections
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ranges, dom
from ranges import collapse, comp, isP, vjoin, vfmt, join
from analysis import rf_str, RF, REGS, FLAGS



def per_insn(R):
    """insn key -> joined state over every node (procedure, partition)"""
    by = {}
    for (proc, k, part), st in R.IN.items():
        if k in by:
            by[k], _ = R.join_into(by[k], st)
        else:
            by[k] = st.clone()
    return by


def operand_value(R, i, nodes):
    v = None
    for st in nodes:
        try:
            x = R.read_operand(st, i)
        except Exception:
            x = dom.TOP
        v = vjoin(v, x)
    return v


def main():
    a = ranges.setup(extra=lambda ap: ap.add_argument('--out', default=None))
    a.out = a.out or os.path.join(ranges.ROOT, 'build', 'annotated')
    R = ranges.analyse(a.build)
    P, an = R.P, R.an
    tn = ranges.tname_fn(P)
    allty = R.types
    nodes_of = collections.defaultdict(list)
    for (proc, k, part), st in R.IN.items():
        nodes_of[k].append(st)
    by = per_insn(R)

    def regs(st):
        out = []
        for r in 'AXY':
            m = st.mir.get(r)
            eq = f"≡{P.name(m)}" if m is not None else ''
            out.append(f"{r}={vfmt(st.r[r], tn)}{eq}")
        for fl in 'CZNV':
            v = st.f[fl]
            out.append(f"{fl}={'?' if v is None else v}")
        return ' '.join(out)

    def row(i):
        k = i.key
        st = by.get(k)
        if st is None:
            return 'UNREACHED'
        parts = [regs(st)]
        if i.mode not in ('imp', 'acc', 'imm', 'rel') and i.mn not in ('JSR', 'JMP'):
            v = operand_value(R, i, nodes_of[k])
            nm = P.name(i.opnd) if i.opnd is not None else '?'
            if i.mode in ('zp', 'abs'):
                parts.append(f"{nm}={vfmt(v, tn)}")
            else:
                parts.append(f"[{P.disasm(i).split(' ', 1)[-1]}]={vfmt(v, tn)}")
        if st.ty != allty:
            parts.append('ty=' + ','.join(tn(t) for t in sorted(st.ty)))
        if i.mode == 'rel' and i.mn != 'BRA':
            ok_t = any(R.branch(s, i, True) is not None for s in nodes_of[k])
            ok_f = any(R.branch(s, i, False) is not None for s in nodes_of[k])
            if not ok_t:
                parts.append('never')
            elif not ok_f:
                parts.append('always')
        if i.mn == 'RTS' and st.stk and len(st.stk) >= 2 and st.stk[-1] != ranges.RL and st.stk[-1] != ranges.UNK:
            tg = sorted({P.name(P.insns[t].addr) if P.insns.get(t) else '?' for (kk, t) in R.rts_dispatch if kk == k})
            if tg:
                parts.append('dispatch->' + ','.join(tg[:12]))
        li = an.live_in.get(k, 0) & RF
        lo = an.live_out.get(k, 0) & RF
        parts.append(f"in:{rf_str(li)} out:{rf_str(lo)}")
        return ' | '.join(parts)

    # source lines -> instructions, in address order
    lines = collections.defaultdict(list)
    for i in P.order:
        if not i.game:
            continue
        lines[(i.outer['file'], i.outer['line'])].append(i)
    files = collections.defaultdict(dict)
    for (fid, ln), ins in lines.items():
        files[fid][ln] = sorted(ins, key=lambda i: i.addr)
    os.makedirs(os.path.join(a.out, 'src'), exist_ok=True)
    nann = 0
    for fid, m in files.items():
        name = P.src.short(fid)
        text = P.src.lines.get(fid)
        if text is None:
            continue
        out = []
        if not getattr(R, 'converged', True):
            out.append(';| WARNING: the range analysis did not converge: these annotations are NOT sound')
        for n, t in enumerate(text, 1):
            t = t.rstrip('\n')
            ins = m.get(n)
            if not ins:
                out.append(t); continue
            if len(ins) == 1:
                out.append(f"{t:<92};| {row(ins[0])}")
            else:
                # a macro: its instructions on this one line, so the numbering is the source's
                out.append(f"{t:<92};| " + ' ‖ '.join(f"[{P.disasm(i)}] {row(i)}" for i in ins))
            nann += len(ins)
        p = os.path.join(a.out, name)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w') as fh:
            fh.write('\n'.join(out) + '\n')
    # summary
    with open(os.path.join(a.out, 'summary.md'), 'w') as fh:
        fh.write('# Range analysis summary\n\n')
        for n in R.notes_all:
            fh.write(f'- {n}\n')
        fh.write('\n## The object records, per type (every record of the type, all game long)\n\n')
        fields = sorted((v, k) for k, v in R.O.items() if v is not None)
        if not fields:
            fields = []
        fh.write('| type | ' + ' | '.join(k for _, k in fields) + ' |\n|---|' + '---|' * len(fields) + '\n')
        for t in sorted(R.types):
            fh.write(f'| {tn(t)} | ' + ' | '.join(dom.fmt(R.I_final.get((t, f))) for f, _ in fields) + ' |\n')
        fh.write('\n## Instructions analysis.py marks self-modified, analysed as written (assumption: the boot copy)\n\n')
        for k in R.volatile_used:
            i = P.insns[k]
            fh.write(f'- {P.where(i)} `{P.disasm(i)}`\n')
        fh.write('\n## Indexed accesses clamped to their array (assumption: an index stays inside the `.res` its base names)\n\n')
        for k, c in sorted(R.clamped.items(), key=lambda x: P.insns[x[0]].idx):
            i = P.insns[k]
            fh.write(f'- {P.where(i)} `{P.disasm(i)}`\n')
        fh.write('\n## Accesses through the current-record pointer taken to be in the records (assumption: at most the record count)\n\n')
        for RR_ in [x for x in (R.ldprog, R) if x is not None]:
            for k, c in sorted(RR_.op_assumed.items(), key=lambda x: RR_.P.insns[x[0]].idx):
                i = RR_.P.insns[k]
                fh.write(f'- {RR_.P.where(i)} `{RR_.P.disasm(i)}`\n')
        fh.write('\n## Unresolved exits (the analysis stops there)\n\n')
        for k, c in sorted(R.unresolved.items(), key=lambda x: P.insns[x[0]].idx):
            i = P.insns[k]
            fh.write(f'- {P.where(i)} `{P.disasm(i)}` ({P.routine_of(i)})\n')
        fh.write('\n## Stores through pointers the analysis could not bound (assumed not to hit a tracked byte)\n\n')
        for k, c in sorted(R.ptr_unknown.items(), key=lambda x: P.insns[x[0]].idx):
            i = P.insns[k]
            fh.write(f'- {P.where(i)} `{P.disasm(i)}` ({P.routine_of(i)}){" [game]" if i.game else ""}\n')
        g = [i for i in P.insns.values() if i.game]
        ur = [i for i in g if i.key not in R.reached]
        fh.write(f'\n## Coverage\n\n{len(g) - len(ur)} of {len(g)} game instructions reached.\n\n')
        for i in sorted(ur, key=lambda i: i.idx)[:300]:
            fh.write(f'- {P.where(i)} `{P.disasm(i)}`\n')
    print(f"{nann} instructions annotated -> {a.out}/src, summary.md")


if __name__ == '__main__':
    main()
