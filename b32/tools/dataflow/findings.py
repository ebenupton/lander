"""findings -- byte-saving opportunities, each cycle-neutral or better, with evidence.

Every finding is a claim about ALL modelled paths (see analysis.py for what
"modelled" assumes).  Categories and the bytes each saves:

  dead_store      store to a direct address nothing reads before it is rewritten
                  (on every path, within the routine: RTS makes all memory live)
  dead_insn       instruction whose every result (register, flag, memory) is dead
  imm_load        LDr #v with r already v (flags: equal already, or dead)
  reload          LDr m with r already holding m's value (e.g. right after STr m)
  redundant_xfer  TAX/TAY/TXA/TYA whose destination already holds that value
  reg_xfer        LDA #v / LDA m when X or Y already holds that value -> TXA/TYA
                  (or LDX/LDY when A holds it -> TAX/TAY): 1-2 bytes, cycles same
                  or fewer (N, Z come out the same)
  known_store     STr m when m provably already holds r's value
  const_operand   LDA/ADC/CMP/... m when m provably holds a constant -> #imm
                  (1 byte for absolute, 0 bytes but 1 cycle for zero page)
  clc_sec         CLC with C known 0 / SEC with C known 1
  cmp_zero        CMP/CPX/CPY #0 when N, Z already reflect the register and C is
                  dead or already 1
  identity        AND #$FF / ORA #0 / EOR #0 with N,Z already right or dead
  branch_never    conditional branch never taken (flag known): remove it
  branch_over_jmp bxx *+5 / jmp T with T in branch range -> the inverted branch to T
                  (3 bytes; every path as fast or faster)
  branch_always   conditional branch always taken (0 bytes: its fall-through is dead)
  dead_code       instructions reachable only through never-taken edges
  jmp_to_branch   JMP abs where a flag is known: a branch on it, in range, no page
                  crossing (3 cycles either way)
  tail_call       JSR x / RTS -> JMP x (1 byte when the RTS has no other entry;
                  9 cycles always)
  bit_skip_bad    .byte $2C/$24 whose skipped bytes are not one 2/1-byte
                  instruction (correctness, not size)
"""
from analysis import RF, REGS, A, X, Y, N, Z, C, V, rf_str, IO_LO, IO_HI, STACK_LO, \
    STACK_HI, STORES, RMW
from forward import U, K, edge_feasible

SCREEN_LO, SCREEN_HI = 0x3000, 0x7FFF
REGB = {'A': A, 'X': X, 'Y': Y}


def vstr(P, v):
    if v == U:
        return '?'
    if v[0] == 'c':
        return f'${v[1]:02X}'
    return f'[{P.name(v[1])}]'


def known_str(P, st):
    if st is None:
        return 'unreached'
    parts = []
    for r in 'AXY':
        if st.r[r] != U:
            parts.append(f'{r}={vstr(P, st.r[r])}')
    for f in 'CZNV':
        if st.f[f] is not None:
            parts.append(f'{f}={st.f[f]}')
    if st.zn:
        parts.append(f'NZ~{st.zn}')
    return ' '.join(parts) or '-'


def find(an):
    P = an.P
    out = []
    fin, lo_, li_ = an.fin, an.live_out, an.live_in

    def add(cat, i, save, cyc, txt, ev, extra=None):
        d = dict(cat=cat, file=P.src.short(i.outer['file']), line=i.outer['line'],
                 addr=f'${i.addr:04X}', seg=P.segs[i.seg]['name'], routine=P.routine_of(i),
                 insn=P.disasm(i), source=P.text(i).strip(), bytes=save, cycles=cyc,
                 detail=txt, evidence=ev)
        if extra:
            d.update(extra)
        out.append(d)

    def ev(i):
        st = fin.get(i.key)
        lo = lo_[i.key]
        mem = an.names_of(lo & an.MALL)
        return (f"live-out {rf_str(lo & RF)}; known before: {known_str(P, st)}")

    def flags_ok(st, lo, val):
        """N,Z after a load of val would be what they already are, or are dead."""
        if not (lo & (N | Z)):
            return True
        if val != U and val[0] == 'c':
            v = val[1]
            return st.f['Z'] == (1 if v == 0 else 0) and st.f['N'] == (1 if v & 0x80 else 0)
        return False

    jmp_done = set()
    for i in P.order:
        if not i.game or i.volatile or i.opvolatile:
            continue
        k = i.key
        st = fin.get(k)
        lo = lo_[k]
        mn, mode, o = i.mn, i.mode, i.opnd
        if i.skip:
            continue
        if st is None:
            continue                     # dead code: reported below
        use, d, md, r, wm, w, side = an.effects(i)
        # -- dead stores / dead instructions
        if mn in STORES or (mn in RMW and mode not in ('acc',)):
            if mode in ('zp', 'abs') and wm and not side and not (lo & wm) and \
                    not (SCREEN_LO <= o <= SCREEN_HI) and not (mn in RMW and (lo & d)):
                add('dead_store', i, i.len, cyc_of(i),
                    f"{P.name(o)} is rewritten before any read on every path",
                    ev(i) + f"; {P.name(o)} dead after")
        elif not side and mn not in ('JSR', 'JMP', 'RTS', 'RTI', 'BRK') and mode != 'rel' \
                and d and not (lo & d) and not (mode in ('zp', 'abs') and o is not None and IO_LO <= o <= IO_HI):
            add('dead_insn', i, i.len, cyc_of(i),
                f"its results ({rf_str(d)}) are all dead", ev(i))
            continue
        # -- loads
        if mn in ('LDA', 'LDX', 'LDY') and mode == 'imm':
            reg = mn[2]
            if st.r[reg] == K(o) and (flags_ok(st, lo, K(o)) or st.zn == reg):
                add('imm_load', i, 2, 2, f"{reg} is already ${o:02X}", ev(i))
                continue
        if mn in ('LDA', 'LDX', 'LDY') and mode in ('zp', 'abs'):
            reg = mn[2]
            cur = st.r[reg]
            same = (cur != U and cur[0] == 'm' and cur[1] == o) or \
                   (o in st.mem and cur != U and cur == st.mem[o])
            if same and (st.zn == reg or flags_ok(st, lo, cur)):
                add('reload', i, i.len, cyc_of(i), f"{reg} already holds {P.name(o)}", ev(i))
                continue
        if mn in ('TAX', 'TAY', 'TXA', 'TYA'):
            src, dst = (mn[1], mn[2])
            if st.r[src] != U and st.r[dst] == st.r[src] and \
                    (st.zn in (src, dst) or flags_ok(st, lo, st.r[src])):
                add('redundant_xfer', i, 1, 2, f"{dst} already equals {src}", ev(i))
                continue
        if mn in ('LDA', 'LDX', 'LDY') and mode in ('imm', 'zp', 'abs'):
            reg = mn[2]
            val = K(o) if mode == 'imm' else (st.mem.get(o) or ('m', o))
            alts = ['X', 'Y'] if reg == 'A' else ['A']
            for a2 in alts:
                cur = st.r[a2]
                if cur != U and (cur == val or (mode != 'imm' and cur == ('m', o))):
                    if reg != 'A' and a2 == 'A' or reg == 'A':
                        rep = ('T' + a2 + reg) if reg == 'A' else ('TA' + reg)
                        if rep in ('TXA', 'TYA', 'TAX', 'TAY'):
                            add('reg_xfer', i, i.len - 1, cyc_of(i) - 2,
                                f"{a2} already holds this value: {rep.lower()}", ev(i))
                            break
        # -- an absolute operand whose byte is a known constant: the immediate form
        if mode in ('abs', 'zp') and mn in ('LDA', 'LDX', 'LDY', 'ADC', 'SBC', 'AND', 'ORA',
                                            'EOR', 'CMP', 'CPX', 'CPY') \
                and o in st.mem and not any(f['addr'] == f'${i.addr:04X}' and f['seg'] ==
                                            P.segs[i.seg]['name'] for f in out[-3:]):
            v = st.mem[o]
            add('const_operand', i, i.len - 2, cyc_of(i) - 2,
                f"{P.name(o)} always holds ${v[1]:02X} here: {mn.lower()} #${v[1]:02X}", ev(i))
        # -- stores of the value already there
        if mn in ('STA', 'STX', 'STY') and mode in ('zp', 'abs') and \
                not (IO_LO <= o <= IO_HI or STACK_LO <= o <= STACK_HI or SCREEN_LO <= o <= SCREEN_HI):
            reg = mn[2]; cur = st.r[reg]
            if cur != U and ((cur[0] == 'c' and st.mem.get(o) == cur) or
                             (cur[0] == 'm' and cur[1] == o)):
                add('known_store', i, i.len, cyc_of(i), f"{P.name(o)} already holds {reg}'s value",
                    ev(i))
        if mn == 'CLC' and st.f['C'] == 0 or mn == 'SEC' and st.f['C'] == 1:
            add('clc_sec', i, 1, 2, f"C is already {st.f['C']}", ev(i))
        if mn in ('CMP', 'CPX', 'CPY') and mode == 'imm' and o == 0:
            reg = {'CMP': 'A', 'CPX': 'X', 'CPY': 'Y'}[mn]
            if st.zn == reg and (st.f['C'] == 1 or not (lo & C)):
                add('cmp_zero', i, 2, 2, f"N, Z already reflect {reg}; C "
                    + ('already 1' if st.f['C'] == 1 else 'dead'), ev(i))
        if mode == 'imm' and ((mn == 'AND' and o == 0xFF) or (mn in ('ORA', 'EOR') and o == 0)):
            if st.zn == 'A' or not (lo & (N | Z)):
                add('identity', i, 2, 2, "leaves A unchanged; N, Z already right or dead", ev(i))
        # -- a branch over a JMP: the inverted branch straight to the JMP's target
        if mode == 'rel' and mn != 'BRA' and o == i.addr + 5:
            j = P.insns.get((i.seg, i.addr + 2))
            if j is not None and j.mn == 'JMP' and j.mode == 'abs' and len(an.succ[j.key]) == 1 \
                    and [p for (p, e) in an.pred[j.key]] == [i] and not P.code_label.get(j.key) \
                    and j.key not in an.entries:
                t = an.succ[j.key][0][0]
                off = t.addr - (i.addr + 2)
                if t.seg == i.seg and -124 <= off <= 123:
                    inv = {'BPL': 'bmi', 'BMI': 'bpl', 'BVC': 'bvs', 'BVS': 'bvc', 'BCC': 'bcs',
                           'BCS': 'bcc', 'BNE': 'beq', 'BEQ': 'bne'}[mn]
                    add('branch_over_jmp', i, 3, 2,
                        f"{P.disasm(i)} / {P.disasm(j)} -> {inv} to the jmp's target "
                        f"({off:+d} from here; the target is in range)", ev(i))
                    jmp_done.add(j.key)
        # -- branches
        if mode == 'rel' and mn != 'BRA':
            tk = edge_feasible(st, mn, True)
            nt = edge_feasible(st, mn, False)
            if not tk:
                add('branch_never', i, 2, 2, "never taken (flag known)", ev(i))
            elif not nt:
                add('branch_always', i, 0, 0, "always taken (flag known): the fall-through "
                    "is reached only from elsewhere", ev(i))
        if mn == 'JMP' and mode == 'abs' and k not in jmp_done:
            t = an.succ[k][0][0] if len(an.succ[k]) == 1 else None
            if t is not None and t.seg == i.seg:
                off = t.addr - (i.addr + 2)
                cross = ((i.addr + 2) >> 8) != (t.addr >> 8)
                if -124 <= off <= 123 and not cross:
                    fl = [f for f in 'CZNV' if st.f[f] is not None]
                    if fl:
                        f = fl[0]; v = st.f[f]
                        br = {('C', 0): 'bcc', ('C', 1): 'bcs', ('Z', 0): 'bne', ('Z', 1): 'beq',
                              ('N', 0): 'bpl', ('N', 1): 'bmi', ('V', 0): 'bvc', ('V', 1): 'bvs'}[(f, v)]
                        add('jmp_to_branch', i, 1, 0, f"{f} is {v} here: {br} reaches the target "
                            f"({off:+d}, same page)", ev(i))
        if mn == 'JSR' and k not in an.helper:
            nxt = an.succ[k][0][0] if an.succ[k] else None
            if nxt is not None and nxt.mn == 'RTS':
                tgts = an.call.get(k) or []
                why = [an.sum_why.get(t.key) for t in tgts if an.sum_why.get(t.key)]
                if tgts and not why:
                    others = [p for (p, e) in an.pred[nxt.key] if p.key != k]
                    lab = P.code_label.get(nxt.key)
                    alone = not others and not lab and nxt.key not in an.entries
                    add('tail_call', i, 1 if alone else 0, 9,
                        "jsr/rts -> jmp" + ("" if alone else
                                            " (the rts has other entries: keep it; 0 bytes)"),
                        ev(i))
    # -- dead code: instructions no modelled path reaches, with a predecessor
    seen = set()
    for i in P.order:
        if not i.game or i.key in fin or i.key in seen or i.key in an.entries:
            continue
        if not an.pred.get(i.key):
            continue
        run = []
        j = i
        while j is not None and j.game and j.key not in fin and j.key not in an.entries:
            run.append(j); seen.add(j.key)
            j = P.insns.get((j.seg, j.addr + j.len))
        nb = sum(x.len for x in run)
        preds = [p for (p, e) in an.pred[i.key]]
        why = '; '.join(f"{P.where(p)} {P.disasm(p)}" for p in preds[:3])
        add('dead_code', i, nb, 0, f"{len(run)} instruction(s) reached only by never-taken "
            f"edges (from {why})", "predecessors' flags known",
            extra=dict(insns=[P.disasm(x) for x in run]))
    # -- misaligned BIT skips
    for d in _bad_skips(an):
        out.append(d)
    return out


def _bad_skips(an):
    P = an.P
    res = []
    for i in P.order:
        if not i.game:
            continue
        a = i.addr + i.len
        sg = P.segs[i.seg]
        off = a - sg['start']
        if not (0 <= off < sg['size']) or (i.seg, a) in P.insns or not P.is_data(i.seg, a):
            continue
        op = sg['data'][off]
        if op not in (0x2C, 0x24):
            continue
        ln = 3 if op == 0x2C else 2
        nxt = P.insns.get((i.seg, a + 1))
        if nxt is None:
            continue
        if (i.seg, a + ln) in P.insns:
            continue
        falls = i.mn not in ('JMP', 'RTS', 'RTI', 'BRA')
        res.append(dict(cat='bit_skip_bad', file=P.src.short(i.outer['file']),
                        line=i.outer['line'] + 1, addr=f'${a:04X}', seg=sg['name'],
                        routine=P.routine_of(i), insn=f".byte ${op:02X}",
                        source=f"(after {P.disasm(i)}) skipping {P.disasm(nxt)} "
                               f"({nxt.len} bytes, the skip covers {ln - 1})",
                        bytes=0, cycles=0,
                        detail=f"the BIT skip swallows {ln - 1} byte(s) but the skipped "
                               f"instruction is {nxt.len}: execution resumes at ${a + ln:04X}, "
                               f"inside it (byte ${sg['data'][off + ln]:02X} executes as an opcode)"
                               + ("" if falls else " -- reached only if something falls into it"),
                        evidence=' '.join(f'{b:02X}' for b in sg['data'][off:off + 6])))
    return res


def cyc_of(i):
    base = {'imp': 2, 'acc': 2, 'imm': 2, 'zp': 3, 'zpx': 4, 'zpy': 4, 'abs': 4, 'abx': 4,
            'aby': 4, 'inx': 6, 'iny': 5, 'zpi': 5, 'rel': 2}.get(i.mode, 3)
    if i.mn in RMW and i.mode != 'acc':
        base += 2 if i.mode in ('zp', 'abs') else 3
    if i.mn in STORES and i.mode in ('abx', 'aby', 'iny'):
        base += 1
    return base
