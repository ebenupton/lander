#!/usr/bin/env python3
"""patterns -- mechanical finds over the range analysis (ranges.py) and the liveness
(analysis.py): the shapes the user's barrel edit showed.

  reload_via_test   lda M2 (A held M1, A is reloaded with M1 soon after; only flags of M2
                    are used before that) where X or Y is dead: ldx/ldy M2 keeps M1 in A
  known_and         and #m / ora #m / eor #m whose result is known from the ranges
  known_cmp         cmp/cpx/cpy whose flags the ranges decide (and every branch on them)
  const_load        lda/ldx/ldy of a memory byte that is one known value everywhere (an
                    immediate would do: -1 byte for an absolute operand)

    python3 tools/dataflow/patterns.py [--build build/master]
"""
import os, sys, argparse, collections
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ranges, dom, gamecfg
from ranges import collapse, vjoin
from analysis import A as bA, X as bX, Y as bY, N as bN, Z as bZ, C as bC, V as bV

def main():
    a = ranges.setup()
    R = ranges.analyse(a.build, quiet=True)
    P, an = R.P, R.an
    by = {}
    for (proc, k, part), st in R.IN.items():
        by[k] = R.join_into(by[k], st)[0] if k in by else st.clone()
    order = [i for i in P.order if i.game and i.key in by]
    nxt = {order[n].key: order[n + 1] for n in range(len(order) - 1)}
    out = collections.defaultdict(list)
    for i in order:
        st = by[i.key]
        lo = an.live_out.get(i.key, 0)
        # reload_via_test
        if i.mn == 'LDA' and i.mode in ('zp', 'abs'):
            m1 = st.mir.get('A')
            if m1 is not None and m1 != i.opnd:
                j, flags_only, steps = nxt.get(i.key), True, 0
                while j is not None and steps < 6:
                    if j.mn == 'LDA' and j.mode in ('zp', 'abs') and j.opnd == m1:
                        free = [r for r, b in (('X', bX), ('Y', bY)) if not lo & b]
                        if free and flags_only:
                            out['reload_via_test'].append((i, f"lda {P.name(i.opnd)} only for its flags, A held {P.name(m1)}, reloaded at {P.where(j)}; {'/'.join(free)} dead: ld{free[0].lower()} {P.name(i.opnd)} saves the reload (2-3 bytes)"))
                        break
                    if j.mode == 'rel' or j.mn in ('CLC', 'SEC', 'NOP'):
                        j = nxt.get(j.key); steps += 1; continue
                    break
        # known logic op results / compares
        if i.mn in ('AND', 'ORA', 'EOR') and i.mode == 'imm':
            av = collapse(st.r['A'], st.ty)
            fn = {'AND': dom.land, 'ORA': dom.lor, 'EOR': dom.leor}[i.mn]
            r = fn(av, dom.C(i.opnd))
            vals = dom.values(av, 256)
            f2 = {'AND': lambda v: v & i.opnd, 'ORA': lambda v: v | i.opnd, 'EOR': lambda v: v ^ i.opnd}[i.mn]
            if vals and all(f2(v) == v for v in vals) and not lo & (bN | bZ):
                out['known_and'].append((i, f"{i.mn.lower()} #${i.opnd:02X} leaves A ({dom.fmt(av)}) unchanged, and N/Z are not used after"))
            elif r is not None and dom.single(r):
                out['known_and'].append((i, f"{i.mn.lower()} #${i.opnd:02X}: A is always ${r[0]:02X} after it"))
        if i.mn in ('CMP', 'CPX', 'CPY') and i.mode in ('imm', 'zp', 'abs'):
            reg = {'CMP': 'A', 'CPX': 'X', 'CPY': 'Y'}[i.mn]
            b = R.read_operand(st, i)
            c, z, n, d = dom.cmp(collapse(st.r[reg], st.ty), collapse(b, st.ty))
            used = lo & (bC | bZ | bN)
            dec = [f for f, v, bb in (('C', c, bC), ('Z', z, bZ), ('N', n, bN)) if bb & used and v is not None]
            if used and len(dec) == bin(used).count('1'):
                out['known_cmp'].append((i, f"{P.disasm(i)}: every flag used after it is known ({', '.join(dec)})"))
        if i.mn in ('LDA', 'LDX', 'LDY') and i.mode in ('zp', 'abs') and R.trackable(i.opnd):
            v = collapse(R.read_operand(st, i), st.ty)
            if v is not None and dom.single(v) and R.rom(i.opnd, i) is None:
                out['const_load'].append((i, f"{P.disasm(i)} is always ${v[0]:02X} here ({'-1 byte' if i.mode == 'abs' else 'same size'}, the immediate)"))
    # const_var: a variable every store gives the same one value (and the image starts it
    # at: the game's variables are zeroed as the image comes in)
    stored = collections.defaultdict(lambda: None)
    top = set()
    for RR, (proc, k, part), st in [(R, n, s_) for n, s_ in R.IN.items()] + \
            ([(R.ldprog, n, s_) for n, s_ in R.ldprog.IN.items()] if R.ldprog else []):
        i = RR.P.insns[k]
        if i.mn in ('STA', 'STX', 'STY', 'STZ', 'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR'):
            A_, via = RR.addrs(st, i)
            if A_ is None:
                continue                              # (unbounded: the screen pointer's)
            if i.mn.startswith('ST'):
                v = dom.C(0) if i.mn == 'STZ' else collapse(st.r[i.mn[2]], st.ty)
                for a in A_:
                    stored[a] = dom.join(stored[a], v)
            else:
                top.update(A_)
        elif i.mn == 'JSR' and RR.an.helper.get(k):
            for role, v in zip(RR.an.helper[k][1], RR.an.helper[k][3]):
                if role in ('rw16', 'w16'):
                    top.update((v, v + 1))
    for sid, sg in P.segs.items():
        if sg['name'] not in gamecfg.C.VAR_SEGMENTS:
            continue
        for a in range(sg['start'], sg['start'] + sg['size']):
            v = stored.get(a)
            if v is None or a in top or not dom.single(v) or R.objfield(a) is not None:
                continue
            # every store that names it must have been analysed (an unreached store's value is unknown)
            unr = [i for RR in (R, R.ldprog) if RR is not None for i in RR.P.insns.values()
                   if i.opnd is not None and i.mn in ('STA', 'STX', 'STY', 'STZ', 'INC', 'DEC') and
                   i.mode in ('zp', 'abs', 'abx', 'aby', 'zpx', 'zpy') and
                   (i.opnd == a or (i.mode not in ('zp', 'abs') and i.opnd <= a < i.opnd + 256 and a - i.opnd < 64))
                   and i.key not in RR.reached]
            if unr:
                continue
            reads = [i for i in P.insns.values() if i.game and i.opnd == a and i.mode in ('zp', 'abs')
                     and i.mn not in ('STA', 'STX', 'STY', 'STZ')]
            out['const_var'].append((None, f"{P.name(a)} (${a:04X}, {sg['name']}): every store writes ${v[0]:02X}"
                                     f"{' (its zeroed start)' if v[0] == 0 else ' -- check its start value'}; "
                                     f"{len(reads)} direct reads"))
    for cat, rows in out.items():
        print(f"\n## {cat}: {len(rows)}")
        for i, why in rows:
            print(f"- {P.where(i)} `{P.text(i).strip()[:60]}` -- {why}" if i is not None else f"- {why}")

if __name__ == '__main__':
    main()
