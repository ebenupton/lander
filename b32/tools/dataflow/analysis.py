"""analysis -- CFG, interprocedural summaries, backward liveness, forward constants.

The domain is one Python int per program point:
    bit 0..6   A X Y N Z C V
    bit 7..    one bit per memory byte in the UNIVERSE: every address any decoded
               instruction (or inline helper operand) names directly, less the stack
               page and the I/O pages.  Memory nobody names directly cannot be the
               target of a dead store, so it needs no bit; reads of it through
               pointers are covered by MALL (every universe bit).

Soundness rules (unknown means everything live, every value unknown):
  * an edge the CFG cannot resolve (jmp (ind), jmp (a,x), BRK, a branch or
    fall-through into data, a JSR/JMP to an address several banks share, a
    self-modified opcode) is an exit where everything is live;
  * RTS: all memory live, plus the registers/flags any caller of any routine whose
    body contains this RTS reads after its JSR.  A routine entered other than by a
    resolved JSR (address-taken, a dispatch table, the interrupt, code with no
    known predecessor) returns with everything live;
  * JSR to a routine whose body plays stack games (PHA/PLA imbalance, TSX/TXS),
    leaves the model, or is unresolved: callee reads and clobbers everything;
  * the interrupt (irq_handler / isr_body and everything they reach) may run
    between any two instructions: memory it reads is live everywhere, memory it
    writes is never a known constant;
  * paged memory ($3000-$DFFF: shadow screen, sideways banks, HAZEL) is made live
    by every JSR and every I/O write, so a store is never called dead because a
    store to "the same" address in a different bank follows it;
  * stores into code (self-modification) mark the patched instruction: an operand
    patch makes its operand unknown, an opcode patch makes it a barrier.
"""
import bisect, collections, re
from model import BRANCHES, LEN, Insn

A, X, Y, N, Z, C, V = (1 << k for k in range(7))
REGS = A | X | Y
FLAGS = N | Z | C | V
RF = REGS | FLAGS
RNAME = [(A, 'A'), (X, 'X'), (Y, 'Y'), (N, 'N'), (Z, 'Z'), (C, 'C'), (V, 'V')]


def rf_str(m):
    s = ''.join(n for b, n in RNAME if m & b)
    return s or '-'


IO_LO, IO_HI = 0xFC00, 0xFEFF
PAGED_LO, PAGED_HI = 0x3000, 0xDFFF
STACK_LO, STACK_HI = 0x0100, 0x01FF

# The game's inline-operand helpers, their scratch words and the interrupt's data
# pointers: the game's config (gamecfg.py).  A helper's contract is (roles, uses): see there.
import gamecfg


def helpers():
    """{label: (roles, uses as register bits)} from the game's config"""
    bits = {'A': A, 'X': X, 'Y': Y}
    out = {}
    for k, (roles, uses) in gamecfg.C.INLINE_HELPERS.items():
        u = 0
        if isinstance(uses, int):
            u = uses
        else:
            for r in uses or ():
                u |= bits[r]
        out[k] = (list(roles), u)
    return out


STORES = {'STA', 'STX', 'STY', 'STZ'}
RMW = {'INC', 'DEC', 'ASL', 'LSR', 'ROL', 'ROR', 'TSB', 'TRB'}
READS_MEM = {'LDA', 'LDX', 'LDY', 'ADC', 'SBC', 'AND', 'ORA', 'EOR', 'CMP', 'CPX', 'CPY',
             'BIT'} | RMW
ZNSET = {'LDA', 'LDX', 'LDY', 'TAX', 'TAY', 'TXA', 'TYA', 'TSX', 'PLA', 'PLX', 'PLY',
         'INX', 'INY', 'DEX', 'DEY', 'INC', 'DEC', 'AND', 'ORA', 'EOR', 'ADC', 'SBC',
         'ASL', 'LSR', 'ROL', 'ROR', 'CMP', 'CPX', 'CPY'}


class Analysis:
    def __init__(self, P, isr_roots=None, strict_isr=False):
        self.P = P
        self.strict_isr = strict_isr
        self.notes = P.notes
        self.isr_names = isr_roots or tuple(gamecfg.C.ISR_ROOTS)
        self._skips()
        self._universe()
        self._smc()
        self._cfg()
        self._entries()
        self._contexts()
        self._isr()
        self._summaries()
        self._forward()
        # a branch whose other edge falls into data/unknown is an unresolved exit;
        # where the forward pass proves that edge never taken, drop it and redo
        if self._prune():
            self._isr()
            self._summaries()
            self._forward()
        self._liveness()

    # ------------------------------------------------------------ BIT skips
    def _skips(self):
        """`.byte $2C` / `.byte $24` in code: the BIT that skips the next
        instruction.  Modelled as the BIT it is (reads its operand, sets N V Z)."""
        P = self.P
        n = 0
        more = True
        while more:
          more = False
          for i in list(P.insns.values()):
            for back in (1,):
                a = i.addr - back
                seg = i.seg
                sg = P.segs[seg]
                off = a - sg['start']
                if off < 0 or (seg, a) in P.insns or not P.is_data(seg, a):
                    continue
                op = sg['data'][off]
                if op not in (0x2C, 0x24):
                    continue
                ln = 3 if op == 0x2C else 2
                if (seg, a + ln) not in P.insns:
                    continue
                b = sg['data'][off:off + ln]
                j = Insn()
                j.key = (seg, a); j.seg = seg; j.addr = a; j.op = op
                j.mn = 'BIT'; j.mode = 'abs' if ln == 3 else 'zp'; j.len = ln
                j.bytes = b; j.opnd = b[1] | (b[2] << 8) if ln == 3 else b[1]
                j.cmos = False; j.volatile = False; j.opvolatile = False
                # the source line of the .byte
                lines = [r for sp, (s2, o2, sz) in [] for r in []]
                j.inner = j.outer = i.outer
                for sid, (s2, o2, sz) in P.spans.items():
                    if s2 == seg and o2 == off and sz == 1:
                        ls = P.span_lines.get(sid, [])
                        if ls:
                            o = [r for r in ls if r['type'] == 0]
                            j.outer = o[0] if o else ls[0]
                            j.inner = max(ls, key=lambda r: (r['type'] == 2, r['count']))
                        break
                j.game = j.outer['file'] in P.game_files
                j.skip = True
                P.insns[j.key] = j
                P.by_addr[a].append(j)
                n += 1; more = True
        for i in P.insns.values():
            if not hasattr(i, 'skip'):
                pass
        self.skip_keys = {k for k, i in P.insns.items() if getattr(i, 'skip', False)}
        if n:
            self.notes.append(f"{n} BIT-skip bytes (.byte $2C/$24) modelled as BIT")
        P.order = sorted(P.insns.values(), key=lambda i: (i.seg, i.addr))
        for n_, i in enumerate(P.order):
            i.idx = n_

    # ------------------------------------------------------------ universe
    def _helper_ops(self, i):
        """For a JSR to an inline helper: (spec, operand bytes) or None."""
        P = self.P
        if i.mn != 'JSR':
            return None
        t = P.resolve(i.opnd, i.seg)
        if t is None:
            return None
        for s in P.code_label.get(t.key, []):
            H = helpers()
            if s['name'] in H:
                roles, uses = H[s['name']]
                sg = P.segs[i.seg]
                off = i.addr + 3 - sg['start']
                ops = list(sg['data'][off:off + len(roles)])
                return s['name'], roles, uses, ops
        return None

    def _universe(self):
        P = self.P
        U = set()
        def ok(a):
            return not (STACK_LO <= a <= STACK_HI or IO_LO <= a <= IO_HI)
        for i in P.insns.values():
            if i.mode in ('zp', 'abs', 'zpx', 'zpy', 'abx', 'aby') and \
                    i.mn not in ('JSR', 'JMP') and i.opnd is not None:
                if ok(i.opnd):
                    U.add(i.opnd)
                if i.mode in ('zp', 'zpx', 'zpy') or i.mode in ('abx', 'aby'):
                    pass
            if i.mode in ('inx', 'iny', 'zpi'):
                U.add(i.opnd); U.add((i.opnd + 1) & 0xFF)
            h = self._helper_ops(i)
            if h:
                for role, v in zip(h[1], h[3]):
                    if role != 'i':
                        U.add(v); U.add((v + 1) & 0xFF)
        for nm in gamecfg.C.HELPER_SCRATCH:
            for s in P.syms:
                if s['name'] == nm:
                    U.add(s['val']); U.add(s['val'] + 1)
        self.U = sorted(U)
        self.bit = {a: 1 << (7 + k) for k, a in enumerate(self.U)}
        self.MALL = ((1 << len(self.U)) - 1) << 7
        self.ALL = self.MALL | RF
        self.ZPALL = 0
        self.PAGED = 0
        for a, b in self.bit.items():
            if a < 0x100:
                self.ZPALL |= b
            if PAGED_LO <= a <= PAGED_HI:
                self.PAGED |= b
        self._rng = {}

    def mbits(self, lo, n):
        """Universe bits for addresses lo .. lo+n-1."""
        k = (lo, n)
        r = self._rng.get(k)
        if r is None:
            r = 0
            a = bisect.bisect_left(self.U, lo)
            while a < len(self.U) and self.U[a] < lo + n:
                r |= self.bit[self.U[a]]; a += 1
            self._rng[k] = r
        return r

    def mb(self, a):
        return self.bit.get(a, 0)

    def names_of(self, m):
        out = []
        m >>= 7
        k = 0
        while m:
            if m & 1:
                out.append(self.U[k])
            m >>= 1; k += 1
        return out

    # ------------------------------------------------------------ SMC
    def _smc(self):
        """Stores into code.  A direct store marks the instruction whose bytes hold
        its target (in the storer's bank when both are sideways); an indexed store
        whose base is itself inside an instruction marks the instructions over the
        base symbol's size (or just that one).  Indexed stores into data tables that
        sit among the code are not self-modification and mark nothing."""
        P = self.P
        n = 0
        size_at = {}
        for s in P.syms:
            if s['size']:
                size_at[s['val']] = s['size']
        def sideways(a):
            return 0x8000 <= a < 0xC000
        # bytes a symbol in a BSS segment (no image) names: stores there are data
        bss = set()
        for s in P.syms:
            if s['seg'] is not None and P.segs[s['seg']]['data'] is None and s['type'] == 'lab':
                bss.update(range(s['val'], s['val'] + max(1, s['size'])))
        for i in P.insns.values():
            if i.mn not in STORES and i.mn not in RMW:
                continue
            if i.opnd in bss:
                continue
            if i.mode in ('zp', 'abs'):
                rng = [i.opnd]
            elif i.mode in ('abx', 'aby'):
                if not P.cover.get(i.opnd):
                    continue
                rng = range(i.opnd, i.opnd + max(1, size_at.get(i.opnd, 1)))
            else:
                continue
            for a in rng:
                for (j, k) in P.cover.get(a, []):
                    if sideways(a) and sideways(i.addr) and \
                            P.segs[j.seg]['bank'] != P.segs[i.seg]['bank']:
                        continue
                    if k == 0:
                        j.volatile = True
                    else:
                        j.opvolatile = True
                    n += 1
        self.smc_count = n

    # ------------------------------------------------------------ CFG
    def _cfg(self):
        P = self.P
        self.succ = {}        # key -> [(Insn, edge)]  edge: None | ('br', mn, taken)
        self.unk = set()      # keys with an unresolvable exit (everything live)
        self.call = {}        # key of JSR -> callee Insn or None
        self.helper = {}      # key of JSR -> helper tuple
        self.pred = collections.defaultdict(list)
        self.unk_edge = {}    # branch key -> [taken?] edges that lead nowhere
        for i in P.insns.values():
            S = []
            nxt = P.insns.get((i.seg, i.addr + i.len))
            if i.volatile:
                self.unk.add(i.key)
            elif i.mn in ('RTS', 'RTI'):
                pass
            elif i.mn == 'BRK':
                self.unk.add(i.key)
            elif i.mn == 'JMP':
                if i.mode == 'abs' and not i.opvolatile:
                    ts = P.resolve_all(i.opnd, i.seg, i)
                    if not ts:
                        self.unk.add(i.key)
                    for t in ts:
                        S.append((t, None))
                else:
                    self.unk.add(i.key)
            elif i.mode == 'rel':
                t = P.resolve(i.opnd, i.seg)
                if t is None:
                    self.unk.add(i.key); self.unk_edge.setdefault(i.key, []).append(True)
                else:
                    S.append((t, ('br', i.mn, True)))
                if i.mn != 'BRA':
                    if nxt is None:
                        self.unk.add(i.key); self.unk_edge.setdefault(i.key, []).append(False)
                    else:
                        S.append((nxt, ('br', i.mn, False)))
            elif i.mn == 'JSR':
                ts = [] if i.opvolatile else P.resolve_all(i.opnd, i.seg, i)
                self.call[i.key] = ts
                h = self._helper_ops(i)
                if h:
                    self.helper[i.key] = h
                    nxt = P.insns.get((i.seg, i.addr + 3 + len(h[1])))
                if nxt is None:
                    self.unk.add(i.key)
                else:
                    S.append((nxt, None))
            else:
                if nxt is None:
                    self.unk.add(i.key)
                else:
                    S.append((nxt, None))
            self.succ[i.key] = S
            for (t, e) in S:
                self.pred[t.key].append((i, e))

    # ------------------------------------------------------------ entries
    def _entries(self):
        """Routine entries and how each is entered."""
        P = self.P
        self.jsr_sites = collections.defaultdict(list)   # callee key -> [JSR Insn]
        for k, ts in self.call.items():
            for t in ts:
                self.jsr_sites[t.key].append(P.insns[k])
        # address-taken: a code label referenced by anything but a direct transfer
        taken = {}
        for i in P.insns.values():
            for s in P.code_label.get(i.key, []):
                for rl in self._refs(s):
                    rec = P.lines.get(rl)
                    if rec is None:
                        taken[i.key] = f"ref line {rl}?"; continue
                    if not rec['spans']:
                        continue      # .assert / .if / an equate (followed by _refs)
                    why = self._ref_kind(rec, i.addr)
                    if why:
                        taken[i.key] = f"{s['name']} {why} at {P.src.short(rec['file'])}:{rec['line']}"
        # .word/.addr data equal to a code address (or address-1: rts dispatch) --
        # tables of unnamed (anonymous-label) targets the symbol refs cannot see
        addrs = set(P.by_addr)
        for sid_span, (seg, off, size) in P.spans.items():
            sg = P.segs[seg]
            if sg['data'] is None or size < 2:
                continue
            ls = P.span_lines.get(sid_span, [])
            if not ls:
                continue
            inner = max(ls, key=lambda r: (r['type'] == 2, r['count']))
            t = (P.src.text(inner['file'], inner['line']) or '').split(';')[0]
            if not re.search(r'\.(word|addr)\b', t, re.I):
                continue
            d = sg['data']
            for o in range(off, off + size - 1, 2):
                w = d[o] | (d[o + 1] << 8)
                for a in (w, w + 1):
                    if a in addrs:
                        for j in P.by_addr[a]:
                            taken.setdefault(j.key, f".word ${w:04X} at {P.src.short(inner['file'])}:{inner['line']}")
        self.taken = taken
        # orphans: no predecessor at all, not a JSR target
        self.entries = {}
        for i in P.insns.values():
            k = i.key
            kinds = []
            if k in self.jsr_sites:
                kinds.append('jsr')
            if k in taken:
                kinds.append('taken')
            if not self.pred.get(k) and k not in self.jsr_sites:
                kinds.append('orphan')
            if kinds:
                self.entries[k] = kinds

    def _refs(self, s, depth=0):
        """A symbol's reference lines, following equates that alias it."""
        out = list(s['refs'])
        if depth > 4:
            return out
        for t in self.P.syms:
            if t is not s and t['type'] == 'equ' and t['val'] == s['val']:
                out += self._refs(t, depth + 1)
        return out

    def _contexts(self):
        """Entry contexts: which entries' bodies contain each instruction (an
        instruction in no entry's body has the unknown context None)."""
        self.ctx = collections.defaultdict(set)
        for ek in self.entries:
            for k in self.body(ek):
                self.ctx[k].add(ek)
        for k in self.P.insns:
            if k not in self.ctx:
                self.ctx[k].add(None)

    def _ref_kind(self, rec, val):
        """None if every instruction on the referencing line uses val only as a direct
        JSR/JMP/branch target; else why the label counts as address-taken."""
        P = self.P
        direct = False
        lo, hi = val & 0xFF, val >> 8
        for sp in rec['spans']:
            seg, off, size = P.spans[sp]
            sg = P.segs[seg]
            if sg['data'] is None:
                return 'a non-code use'
            a0 = sg['start'] + off
            a = a0
            while a < a0 + size:
                i = P.insns.get((seg, a))
                if i is None:
                    if sg['data'][a - sg['start']] in (lo, hi, (val - 1) & 0xFF, (val - 1) >> 8):
                        return 'data byte'
                    a += 1
                    continue
                if i.mn in ('JSR', 'JMP') and i.mode == 'abs' or i.mode == 'rel':
                    if i.opnd == val:
                        direct = True
                elif i.opnd is not None and i.len > 1:
                    if i.len == 3 and i.opnd in (val, val - 1, val + 1, val + 2):
                        return f'operand of {i.mn}'
                    if i.len == 2 and i.mode == 'imm' and i.opnd in (lo, hi, (val - 1) & 0xFF,
                                                                     (val - 1) >> 8):
                        return f'immediate of {i.mn}'
                a += i.len
        return None if direct else 'non-transfer use'

    # ------------------------------------------------------------ bodies
    def body(self, ek):
        """Instructions reachable from entry ek without crossing a JSR's callee."""
        seen = set([ek]); st = [ek]
        while st:
            k = st.pop()
            for (t, e) in self.succ[k]:
                if t.key not in seen:
                    seen.add(t.key); st.append(t.key)
        return seen

    def _isr(self):
        P = self.P
        roots = []
        for s in P.syms:
            if s['name'] in self.isr_names:
                for i in P.by_addr.get(s['val'], []):
                    if i.seg == s['seg']:
                        roots.append(i.key)
        self.isr_roots = roots
        seen = set(); st = list(roots); calls_unknown = False
        while st:
            k = st.pop()
            if k in seen:
                continue
            seen.add(k)
            if k in self.unk:
                calls_unknown = True
            for (t, e) in self.succ[k]:
                st.append(t.key)
            if k in self.call:
                ts = self.call[k]
                if not ts:
                    calls_unknown = True
                for t in ts:
                    st.append(t.key)
        self.isr_code = seen
        r = w = 0
        dptr = set()
        if not self.strict_isr:
            for s in P.syms:
                if s['name'].lower().replace('_', '') in \
                        {n.lower().replace('_', '') for n in gamecfg.C.ISR_DATA_POINTERS}:
                    dptr.add(s['val'])
        for k in seen:
            i = P.insns[k]
            rr, ww = self._mem_rw(i)
            if i.mode in ('inx', 'iny', 'zpi') and i.opnd in dptr and i.mn not in STORES \
                    and i.mn not in RMW:
                rr = self.mb(i.opnd) | self.mb((i.opnd + 1) & 0xFF)
            r |= rr; w |= ww
        if calls_unknown or not roots:
            self.notes.append("interrupt: an unresolved exit (or no root found) -- "
                              "it is taken to read and write all memory")
            r = w = self.MALL
        self.isr_r, self.isr_w = r, w
        self.notes.append(f"interrupt roots {[P.disasm(P.insns[k]) and P.code_label[k][0]['name'] for k in roots]}: "
                          f"{len(seen)} instructions, reads {bin(r).count('1')} and writes "
                          f"{bin(w).count('1')} universe bytes")

    def _mem_rw(self, i):
        """(may-read bits, may-write bits) of one instruction's memory access."""
        mn, mode, o = i.mn, i.mode, i.opnd
        r = w = 0
        if i.opvolatile and mode in ('abs', 'abx', 'aby', 'zp', 'zpx', 'zpy'):
            acc = self.MALL
        elif mode in ('zp', 'abs'):
            acc = self.mb(o)
        elif mode in ('zpx', 'zpy'):
            acc = self.ZPALL
        elif mode in ('abx', 'aby'):
            acc = self.mbits(o, 256)
        elif mode in ('inx', 'iny', 'zpi'):
            ptr = self.mb(o) | self.mb((o + 1) & 0xFF)
            if mn in STORES:
                return ptr, self.MALL
            if mn in RMW:
                return ptr | self.MALL, self.MALL
            return ptr | self.MALL, 0
        elif mode in ('ind', 'iax'):
            return self.mbits(o, 2) if mode == 'ind' else self.MALL, 0
        else:
            return 0, 0
        if mn in STORES:
            w = acc
        elif mn in RMW:
            r = w = acc
        elif mn in READS_MEM:
            r = acc
        return r, w

    # ------------------------------------------------------------ local effects
    def effects(self, i):
        """(use, def_must, may_def_regs, mem_read, mem_write_must, mem_write_may, side)"""
        mn, mode = i.mn, i.mode
        use = d = 0
        if mode in ('zpx', 'abx', 'inx', 'iax'):
            use |= X
        if mode in ('zpy', 'aby', 'iny'):
            use |= Y
        if mn in ('LDA', 'PLA', 'TXA', 'TYA'):
            d |= A
        elif mn in ('LDX', 'TAX', 'TSX', 'PLX'):
            d |= X
        elif mn in ('LDY', 'TAY', 'PLY'):
            d |= Y
        if mn in ('STA', 'TAX', 'TAY', 'PHA', 'CMP', 'BIT', 'TSB', 'TRB'):
            use |= A
        if mn in ('STX', 'TXA', 'TXS', 'CPX', 'PHX'):
            use |= X
        if mn in ('STY', 'TYA', 'CPY', 'PHY'):
            use |= Y
        if mn in ('INX', 'DEX'):
            use |= X; d |= X
        if mn in ('INY', 'DEY'):
            use |= Y; d |= Y
        if mn in ('ADC', 'SBC', 'AND', 'ORA', 'EOR'):
            use |= A; d |= A
        if mn in ('ADC', 'SBC', 'ROL', 'ROR'):
            use |= C
        if mn in ('ASL', 'LSR', 'ROL', 'ROR', 'INC', 'DEC') and mode == 'acc':
            use |= A; d |= A
        if mn in ZNSET:
            d |= N | Z
        if mn in ('ADC', 'SBC'):
            d |= C | V
        if mn in ('ASL', 'LSR', 'ROL', 'ROR', 'CMP', 'CPX', 'CPY', 'CLC', 'SEC'):
            d |= C
        if mn == 'BIT':
            d |= Z if mode == 'imm' else (N | Z | V)
        if mn in ('TSB', 'TRB'):
            d |= Z
        if mn == 'CLV':
            d |= V
        if mn == 'PLP':
            d |= FLAGS
        if mn == 'PHP':
            use |= FLAGS
        if mode == 'rel' and mn != 'BRA':
            use |= {'BPL': N, 'BMI': N, 'BVC': V, 'BVS': V, 'BCC': C, 'BCS': C,
                    'BNE': Z, 'BEQ': Z}[mn]
        r, w = self._mem_rw(i)
        wmust = 0
        if mode in ('zp', 'abs') and (mn in STORES or mn in RMW) and not i.opvolatile:
            wmust = w
        side = False
        o = i.opnd
        if mode in ('zp', 'abs', 'abx', 'aby') and o is not None and \
                mn not in ('JSR', 'JMP') and (IO_LO <= o <= IO_HI or
                                              (mode in ('abx', 'aby') and o < IO_LO <= o + 255)):
            side = True                      # I/O: reads and writes both act
        if mode in ('zp', 'abs') and o is not None and STACK_LO <= o <= STACK_HI:
            side = True
        if mn in ('PHA', 'PHP', 'PHX', 'PHY', 'PLA', 'PLP', 'PLX', 'PLY', 'TXS', 'SEI', 'CLI',
                  'SED', 'CLD', 'BRK', 'RTI', 'RTS', 'JSR', 'JMP', 'NOP'):
            side = True
        if mode in ('inx', 'iny', 'zpi', 'abx', 'aby', 'zpx', 'zpy') and (mn in STORES or mn in RMW):
            side = True                      # an indexed/indirect write: never "dead"
        if i.volatile or i.opvolatile:
            side = True
        return use, d, d, r, wmust, w, side

    # ------------------------------------------------------------ summaries
    def _summaries(self):
        """Per JSR target: use (live-in with nothing live at RTS), must-def regs,
        may-def regs, may-read mem, may-write mem, and 'ok' (analysable)."""
        P = self.P
        targets = list(self.jsr_sites)
        self.bodies = {}
        ok = {}
        for t in targets:
            b = self.body(t)
            self.bodies[t] = b
            why = None
            push = pull = 0
            for k in b:
                i = P.insns[k]
                if k in self.unk:
                    why = f"unresolved exit at {P.where(i)} ({P.disasm(i)})"; break
                if i.mn in ('TSX', 'TXS', 'RTI', 'BRK'):
                    why = f"{i.mn} at {P.where(i)}"; break
                if i.mn in ('PHA', 'PHP', 'PHX', 'PHY'):
                    push += 1
                if i.mn in ('PLA', 'PLP', 'PLX', 'PLY'):
                    pull += 1
            if why is None and push != pull:
                why = f"pushes {push} != pulls {pull} (stack games)"
            ok[t] = why
        self.sum_why = ok
        # fixpoint: unknown callee => all
        S = {t: dict(use=0, mustdef=RF, maydef=0, mr=0, mw=0, io=False) for t in targets}
        BAD = dict(use=self.ALL, mustdef=0, maydef=RF, mr=self.MALL, mw=self.MALL, io=True)
        self.BAD = BAD
        for t in targets:
            if ok[t] is not None:
                S[t] = dict(BAD)
        self.S = S
        for rnd in range(60):
            changed = False
            for t in targets:
                if ok[t] is not None:
                    continue
                new = self._summarise(t)
                if new != S[t]:
                    S[t] = new; changed = True
            if not changed:
                break
        else:
            self.notes.append("summaries did not converge in 60 rounds")
        nb = sum(1 for t in targets if ok[t] is not None)
        self.notes.append(f"{len(targets)} JSR targets: {len(targets)-nb} summarised, {nb} unknown "
                          f"(stack games / unresolved exits)")

    def callee_eff(self, jk):
        """Summary for the JSR at key jk."""
        h = self.helper.get(jk)
        if h:
            name, roles, uses, ops = h
            mr = mw = mwm = 0
            for role, v in zip(roles, ops):
                if role == 'i':
                    continue
                bb = self.mb(v) | self.mb((v + 1) & 0xFF)
                if role in ('rw16', 'r16'):
                    mr |= bb
                if role in ('rw16', 'w16'):
                    mw |= bb; mwm |= bb
            for nm in gamecfg.C.HELPER_SCRATCH:
                for s in self.P.syms:
                    if s['name'] == nm:
                        mw |= self.mbits(s['val'], 2)
            return dict(use=uses, mustdef=A | N | Z | C | V, maydef=A | N | Z | C | V, io=False,
                        mr=mr, mw=mw, mwm=mwm)
        ts = self.call.get(jk)
        if not ts:
            return dict(self.BAD, mwm=0)
        r = None
        for t in ts:
            s = self.S.get(t.key) or self.BAD
            if r is None:
                r = dict(s, mwm=0)
            else:          # several banks' code at the address: any of them
                r = dict(use=r['use'] | s['use'], mustdef=r['mustdef'] & s['mustdef'],
                         maydef=r['maydef'] | s['maydef'], mr=r['mr'] | s['mr'],
                         mw=r['mw'] | s['mw'], mwm=0, io=r['io'] or s['io'])
        return r

    def _summarise(self, t):
        P = self.P
        b = self.bodies[t]
        # backward liveness over the body, nothing live at RTS
        live = {k: 0 for k in b}
        order = sorted(b, key=lambda k: -P.insns[k].idx)
        mustdef_in = {}
        maydef = 0; mr = 0; mw = 0; io = False
        for k in b:
            i = P.insns[k]
            if i.mn == 'JSR':
                e = self.callee_eff(k)
                maydef |= e['maydef']; mr |= e['mr']; mw |= e['mw']; io = io or e['io']
            else:
                use, d, md, r, wm, w, side = self.effects(i)
                maydef |= md; mr |= r; mw |= w
                io = io or self._io_write(i)
        changed = True
        while changed:
            changed = False
            for k in order:
                i = P.insns[k]
                out = 0
                for (s, e) in self.succ[k]:
                    out |= live.get(s.key, 0)
                new = self._xfer_back(i, out)
                if new != live[k]:
                    live[k] = new; changed = True
        # must-def forward (intersection), greatest fixpoint
        md = {k: RF for k in b}
        md[t] = 0
        changed = True
        fwd = sorted(b, key=lambda k: P.insns[k].idx)
        indeg = collections.defaultdict(list)
        for k in b:
            for (s, e) in self.succ[k]:
                indeg[s.key].append(k)
        res = RF
        while changed:
            changed = False
            for k in fwd:
                if k == t:
                    inn = 0
                else:
                    ps = indeg.get(k, [])
                    inn = RF
                    for p in ps:
                        inn &= self._md_out(P.insns[p], md[p])
                    if not ps:
                        inn = RF
                if k != t and inn != md[k]:
                    md[k] = inn; changed = True
        for k in b:
            if P.insns[k].mn == 'RTS':
                res &= md[k]
        return dict(use=live[t] & (RF | self.MALL), mustdef=res, maydef=maydef, mr=mr, mw=mw,
                    io=io)

    def _io_write(self, i):
        o = i.opnd
        return (i.mn in STORES or i.mn in RMW) and o is not None and \
            i.mode in ('abs', 'abx', 'aby') and (IO_LO <= o <= IO_HI or
                                                 (i.mode != 'abs' and o < IO_LO <= o + 255)) \
            or (i.mn in STORES or i.mn in RMW) and i.mode in ('inx', 'iny', 'zpi')

    def _md_out(self, i, inn):
        if i.mn == 'JSR':
            return inn | self.callee_eff(i.key)['mustdef']
        use, d, md, r, wm, w, side = self.effects(i)
        return inn | d

    def _xfer_back(self, i, out):
        """live-in of i given live-out, intraprocedural part (RTS/unk handled by caller)."""
        if i.key in self.unk:
            return self.ALL
        if i.mn == 'JSR':
            e = self.callee_eff(i.key)
            lin = e['use'] | (out & ~(e['mustdef'] | e['mwm'])) | e['mr']
            # a callee that may write I/O (ROMSEL, ACCCON) may leave another bank
            # paged: then no paged byte is killed across the call
            return lin | (self.PAGED if e['io'] else 0) | self.isr_r
        if i.mn == 'RTI':
            return self.ALL
        use, d, md, r, wm, w, side = self.effects(i)
        lin = (out & ~(d | wm)) | use | r | self.isr_r
        if self._io_write(i):
            lin |= self.PAGED
        return lin

    # ------------------------------------------------------------ global liveness
    def _liveness(self):
        P = self.P
        retlive = {}
        for ek, kinds in self.entries.items():
            retlive[ek] = RF if ('taken' in kinds or 'orphan' in kinds or ek in self.isr_roots) else 0
        retlive[None] = RF
        self.retlive = retlive
        order = sorted(P.insns, key=lambda k: -P.insns[k].idx)
        live_in = {k: 0 for k in P.insns}
        live_out = {k: 0 for k in P.insns}
        for rnd in range(40):
            changed = True
            while changed:
                changed = False
                for k in order:
                    i = P.insns[k]
                    if k in self.unk or i.mn == 'RTI':
                        out = self.ALL
                    elif i.mn == 'RTS':
                        out = self.MALL
                        for ek in self.ctx[k]:
                            out |= retlive[ek]
                    else:
                        out = 0
                        for (s, e) in self.succ[k]:
                            out |= live_in[s.key]
                    live_out[k] = out
                    new = self._xfer_back(i, out)
                    if new != live_in[k]:
                        live_in[k] = new; changed = True
            # callers' needs at return
            ch = False
            for ek, sites in self.jsr_sites.items():
                if retlive[ek] == RF:
                    continue
                r = retlive[ek]
                for j in sites:
                    r |= live_out[j.key] & RF
                if r != retlive[ek]:
                    retlive[ek] = r; ch = True
            if not ch:
                break
        self.live_in, self.live_out = live_in, live_out

    def _prune(self):
        from forward import edge_feasible
        n = 0
        self.pruned = []
        for k, edges in self.unk_edge.items():
            st = self.fin.get(k)
            if st is None or k not in self.unk:
                continue
            i = self.P.insns[k]
            if all(not edge_feasible(st, i.mn, tk) for tk in edges):
                self.unk.discard(k); n += 1
                self.pruned.append(k)
        if n:
            self.notes.append(f"{n} branches whose fall-through into data is never taken "
                              f"(flag known): that edge dropped")
        return n

    # ------------------------------------------------------------ forward
    def _forward(self):
        from forward import run_forward
        self.fin, self.fout_edge = run_forward(self)
