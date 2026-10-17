"""forward -- constant / copy propagation (adapted from doom's tools/dfscan.py).

Per instruction, the state BEFORE it:
  r     A, X, Y: U (unknown) | ('c', v) known byte | ('m', a) equal to memory byte a
  f     C, Z, N, V: None | 0 | 1
  mem   {address: ('c', v)} for trackable bytes (in the universe, not written by the
        interrupt, not I/O, not the stack page)
  zn    'A'/'X'/'Y': N and Z currently reflect that register
  cmpm  (reg, imm): Z is (reg == imm)  (BEQ's taken edge learns reg == imm)

Differences from dfscan: driven by the static CFG (no trace); per-instruction
states; JSR kills only what the callee summary may define/write (dfscan havocked
everything); edges a known flag makes infeasible are not followed, so code reached
only through them is reported as dead; the interrupt's writes, I/O, and paged
memory across JSRs / I/O writes are never constants.
"""
from analysis import A, X, Y, N, Z, C, V, RF, IO_LO, IO_HI, STACK_LO, STACK_HI, \
    PAGED_LO, PAGED_HI, STORES, RMW

U = ('u',)
def K(v): return ('c', v & 0xFF)
def M(a): return ('m', a)
REGB = {'A': A, 'X': X, 'Y': Y}
FLB = {'C': C, 'Z': Z, 'N': N, 'V': V}


class St:
    __slots__ = ('r', 'f', 'mem', 'zn', 'cmpm')

    def __init__(s):
        s.r = {'A': U, 'X': U, 'Y': U}
        s.f = {'C': None, 'Z': None, 'N': None, 'V': None}
        s.mem = {}; s.zn = None; s.cmpm = None

    def clone(s):
        t = St.__new__(St)
        t.r = dict(s.r); t.f = dict(s.f); t.mem = dict(s.mem)
        t.zn = s.zn; t.cmpm = s.cmpm
        return t

    def join(s, o):
        ch = False
        for k in 'AXY':
            if s.r[k] != o.r[k] and s.r[k] != U:
                s.r[k] = U; ch = True
        for k in 'CZNV':
            if s.f[k] != o.f[k] and s.f[k] is not None:
                s.f[k] = None; ch = True
        for a in list(s.mem):
            if o.mem.get(a) != s.mem[a]:
                del s.mem[a]; ch = True
        if s.zn != o.zn and s.zn is not None:
            s.zn = None; ch = True
        if s.cmpm != o.cmpm and s.cmpm is not None:
            s.cmpm = None; ch = True
        return ch


def setZN(st, val, src):
    if val != U and val[0] == 'c':
        st.f['Z'] = 1 if val[1] == 0 else 0
        st.f['N'] = 1 if val[1] & 0x80 else 0
    else:
        st.f['Z'] = st.f['N'] = None
    st.zn = src
    st.cmpm = None


def kill_mirrors(st, addr):
    for k in 'AXY':
        if st.r[k] == ('m', addr):
            st.r[k] = U


def kill_mem(st, pred):
    for a in list(st.mem):
        if pred(a):
            del st.mem[a]
    for k in 'AXY':
        v = st.r[k]
        if v != U and v[0] == 'm' and pred(v[1]):
            st.r[k] = U


class Fwd:
    def __init__(self, an):
        self.an = an
        self.P = an.P
        self.decimal = any(i.mn == 'SED' for i in self.P.insns.values() if i.game)

    def trackable(self, a):
        an = self.an
        if a is None or IO_LO <= a <= IO_HI or STACK_LO <= a <= STACK_HI:
            return False
        b = an.bit.get(a)
        if b is None or (an.isr_w & b):
            return False
        if self.P.cover.get(a):
            return False                       # a code byte
        return True

    def transfer(self, st, i):
        an = self.an
        mn, mode, opnd = i.mn, i.mode, i.opnd

        def read_val():
            if mode == 'imm':
                return U if i.opvolatile else K(opnd)
            if mode in ('zp', 'abs') and not i.opvolatile:
                if opnd in st.mem:
                    return st.mem[opnd]
                if self.trackable(opnd):
                    return M(opnd)
            return U

        def mem_write_direct():
            return mode in ('zp', 'abs') and not i.opvolatile

        def generic_write():
            r, w = an._mem_rw(i)
            if w == an.MALL:
                kill_mem(st, lambda a: True)
            else:
                kill_mem(st, lambda a: an.bit.get(a, 0) & w)
            if mode in ('abs', 'abx', 'aby') and opnd is not None and \
                    (IO_LO <= opnd <= IO_HI or (mode != 'abs' and opnd < IO_LO <= opnd + 255)):
                kill_mem(st, lambda a: PAGED_LO <= a <= PAGED_HI)

        if i.volatile:
            return St()
        if mn in ('LDA', 'LDX', 'LDY'):
            v = read_val(); st.r[mn[2]] = v; setZN(st, v, mn[2])
        elif mn in STORES:
            reg = mn[2] if mn != 'STZ' else None
            v = K(0) if reg is None else st.r[reg]
            if mem_write_direct():
                a = opnd
                kill_mirrors(st, a)
                generic_write()
                if self.trackable(a):
                    if v != U and v[0] == 'c':
                        st.mem[a] = v
                    else:
                        st.mem.pop(a, None)
                        if v == U and reg:
                            st.r[reg] = M(a)
                        elif v != U and v[0] == 'm' and reg:
                            st.r[reg] = M(a)  # (both equal; keep the newest)
            else:
                generic_write()
        elif mn in ('TAX', 'TAY'):
            st.r[mn[2]] = st.r['A']; setZN(st, st.r['A'], mn[2])
        elif mn in ('TXA', 'TYA'):
            st.r['A'] = st.r[mn[1]]; setZN(st, st.r['A'], 'A')
        elif mn == 'TSX':
            st.r['X'] = U; setZN(st, U, 'X')
        elif mn == 'CLC':
            st.f['C'] = 0
        elif mn == 'SEC':
            st.f['C'] = 1
        elif mn == 'CLV':
            st.f['V'] = 0
        elif mn in ('INX', 'INY', 'DEX', 'DEY'):
            reg = mn[2]; v = st.r[reg]
            nv = K(v[1] + (1 if mn[0] == 'I' else -1)) if (v != U and v[0] == 'c') else U
            st.r[reg] = nv; setZN(st, nv, reg)
        elif mn in ('INC', 'DEC') and mode == 'acc':
            v = st.r['A']
            nv = K(v[1] + (1 if mn == 'INC' else -1)) if (v != U and v[0] == 'c') else U
            st.r['A'] = nv; setZN(st, nv, 'A')
        elif mn in ('INC', 'DEC'):
            if mem_write_direct():
                a = opnd; kill_mirrors(st, a)
                v = st.mem.get(a)
                generic_write()
                if v is not None and self.trackable(a):
                    nv = K(v[1] + (1 if mn == 'INC' else -1)); st.mem[a] = nv
                    setZN(st, nv, None)
                else:
                    st.mem.pop(a, None); setZN(st, U, None)
            else:
                generic_write(); setZN(st, U, None)
        elif mn in ('AND', 'ORA', 'EOR'):
            v = read_val(); a = st.r['A']
            if v != U and v[0] == 'c' and a != U and a[0] == 'c':
                r = {'AND': a[1] & v[1], 'ORA': a[1] | v[1], 'EOR': a[1] ^ v[1]}[mn]
                st.r['A'] = K(r)
            elif mn == 'AND' and v == K(0):
                st.r['A'] = K(0)
            elif mn == 'ORA' and v == K(0xFF):
                st.r['A'] = K(0xFF)
            elif mn == 'AND' and v == K(0xFF) or mn in ('ORA', 'EOR') and v == K(0):
                pass                               # identity: A unchanged
            else:
                st.r['A'] = U
            setZN(st, st.r['A'], 'A')
        elif mn in ('ADC', 'SBC'):
            v = read_val(); a = st.r['A']; c = st.f['C']
            if (not self.decimal and v != U and v[0] == 'c' and a != U and a[0] == 'c'
                    and c is not None):
                if mn == 'ADC':
                    t = a[1] + v[1] + c
                    st.f['V'] = 1 if (~(a[1] ^ v[1]) & (a[1] ^ t) & 0x80) else 0
                else:
                    t = a[1] + (v[1] ^ 0xFF) + c
                    st.f['V'] = 1 if ((a[1] ^ v[1]) & (a[1] ^ t) & 0x80) else 0
                st.f['C'] = 1 if t > 0xFF else 0
                st.r['A'] = K(t)
            else:
                st.r['A'] = U; st.f['C'] = st.f['V'] = None
            setZN(st, st.r['A'], 'A')
        elif mn in ('ASL', 'LSR', 'ROL', 'ROR'):
            if mode == 'acc':
                a = st.r['A']; c = st.f['C']
                if a != U and a[0] == 'c' and (mn in ('ASL', 'LSR') or c is not None):
                    v = a[1]
                    if mn == 'ASL':
                        st.f['C'] = (v >> 7) & 1; nv = (v << 1) & 0xFF
                    elif mn == 'LSR':
                        st.f['C'] = v & 1; nv = v >> 1
                    elif mn == 'ROL':
                        st.f['C'] = (v >> 7) & 1; nv = ((v << 1) | c) & 0xFF
                    else:
                        st.f['C'] = v & 1; nv = (v >> 1) | (c << 7)
                    st.r['A'] = K(nv)
                else:
                    st.r['A'] = U; st.f['C'] = None
                setZN(st, st.r['A'], 'A')
            else:
                if mem_write_direct():
                    kill_mirrors(st, opnd); st.mem.pop(opnd, None)
                generic_write()
                st.f['C'] = None; setZN(st, U, None)
        elif mn in ('CMP', 'CPX', 'CPY'):
            reg = {'CMP': 'A', 'CPX': 'X', 'CPY': 'Y'}[mn]
            v = read_val(); rv = st.r[reg]
            if v != U and v[0] == 'c' and rv != U and rv[0] == 'c':
                d = (rv[1] - v[1]) & 0x1FF
                st.f['C'] = 1 if rv[1] >= v[1] else 0
                st.f['Z'] = 1 if rv[1] == v[1] else 0
                st.f['N'] = 1 if d & 0x80 else 0
                st.zn = None; st.cmpm = None
            elif v == K(0):
                st.f['C'] = 1                      # cmp #0: C always set
                st.f['Z'] = st.f['N'] = None
                st.zn = reg; st.cmpm = None        # Z,N are reg's own
            else:
                st.f['C'] = st.f['Z'] = st.f['N'] = None
                st.zn = None
                st.cmpm = (reg, opnd) if (mode == 'imm' and not i.opvolatile) else None
        elif mn == 'BIT':
            if mode == 'imm':
                st.f['Z'] = None
            else:
                st.f['Z'] = st.f['N'] = st.f['V'] = None
            st.zn = None; st.cmpm = None
        elif mn in ('TSB', 'TRB'):
            if mem_write_direct():
                kill_mirrors(st, opnd); st.mem.pop(opnd, None)
            generic_write()
            st.f['Z'] = None; st.cmpm = None
            if st.zn:
                st.zn = None
        elif mn in ('PLA', 'PLX', 'PLY'):
            reg = mn[2] if mn != 'PLA' else 'A'
            st.r[reg] = U; setZN(st, U, reg)
        elif mn == 'PLP':
            st.f = {'C': None, 'Z': None, 'N': None, 'V': None}; st.zn = None; st.cmpm = None
        elif mn == 'JSR':
            e = an.callee_eff(i.key)
            md = e['maydef']
            for r, b in REGB.items():
                if md & b:
                    st.r[r] = U
            for f, b in FLB.items():
                if md & b:
                    st.f[f] = None
            if md & (N | Z):
                st.zn = None; st.cmpm = None
            elif st.zn and md & REGB[st.zn]:
                st.zn = None
            if st.cmpm and md & REGB[st.cmpm[0]]:
                st.cmpm = None
            w = e['mw']
            if w == an.MALL:
                kill_mem(st, lambda a: True)
            else:
                kill_mem(st, lambda a: (an.bit.get(a, 0) & w) or PAGED_LO <= a <= PAGED_HI)
        # PHA/PHP/PHX/PHY/NOP/SEI/CLI/CLD/SED/TXS/branches/JMP/RTS: no change
        return st


_BR = {'BPL': ('N', 0), 'BMI': ('N', 1), 'BVC': ('V', 0), 'BVS': ('V', 1),
       'BCC': ('C', 0), 'BCS': ('C', 1), 'BNE': ('Z', 0), 'BEQ': ('Z', 1)}


def edge_feasible(st, mn, taken):
    if mn == 'BRA':
        return taken
    fl, tv = _BR[mn]
    want = tv if taken else 1 - tv
    return st.f[fl] is None or st.f[fl] == want


def refine(st, mn, taken):
    if mn == 'BRA':
        return st
    fl, tv = _BR[mn]
    val = tv if taken else 1 - tv
    st.f[fl] = val
    if fl == 'Z' and val == 1:
        if st.zn in ('A', 'X', 'Y') and st.r[st.zn] == U:
            st.r[st.zn] = K(0)
        if st.cmpm is not None:
            reg, imm = st.cmpm
            if st.r[reg] == U or st.r[reg][0] == 'm':
                st.r[reg] = K(imm)
    if fl == 'N' and st.zn in ('A', 'X', 'Y'):
        pass
    return st


def run_forward(an):
    P = an.P
    F = Fwd(an)
    IN = {}
    wl = []
    seeds = set(an.entries) | {k for k, c in an.ctx.items() if None in c}
    for k in seeds:
        IN[k] = St(); wl.append(k)
    out_edge = {}
    it = 0
    while wl:
        it += 1
        if it > 2000000:
            an.notes.append("forward: iteration budget exceeded")
            break
        k = wl.pop()
        i = P.insns[k]
        st = F.transfer(IN[k].clone(), i)
        for (t, e) in an.succ[k]:
            if e is not None:
                if not edge_feasible(st, e[1], e[2]):
                    continue
                ts = refine(st.clone(), e[1], e[2])
            else:
                ts = st.clone()
            if t.key not in IN:
                IN[t.key] = ts; wl.append(t.key)
            elif IN[t.key].join(ts):
                wl.append(t.key)
    an.fwd = F
    return IN, out_edge
