#!/usr/bin/env python3
"""ranges -- forward abstract interpretation of a beebgame game's linked code, with ranges.

What it knows, before every instruction:
  * A, X, Y: an abstract byte (dom.py: an interval reduced with known bits and a small
    value set), or one per object type (below);
  * C Z N V: 0, 1 or unknown, with where Z/N/C came from (a register or memory byte, a
    compare) so a branch refines the value it tested -- and the memory byte a register
    was loaded from, which a branch on the register refines too;
  * every memory byte an instruction can name: flow-sensitively where the code writes it,
    else its link-time content if nothing ever writes it (tables), else unknown;
  * the stack, as the values pushed: an RTS whose top two bytes are known (the
    `pha / pha / rts` dispatches) is a jump to them, so dispatched handlers are analysed
    with the state their dispatcher had;
  * with an object model (the game's config: gamecfg OBJECTS), the records: per object type
    and field, a range over every record of that type (flow-insensitive, every write joined
    in, to a fixpoint).  A record read through the current-record pointer gives a value per
    type -- keyed on the type of that record -- and the state carries the types it may be;
    a test of such a value removes the types it rules out, and a dispatch on it splits by
    type.  (Commando: inside ob_barrel, ohealth is a barrel's health.)  When the game's
    loader builds the records, the load-time program is analysed first for their initial
    values.

Procedures are analysed per entry, small ones once per call site; entered with the join of
their callers' states, a callee gives back to each caller its own state for whatever it
cannot write.  Loop heads keep one state per value of the counter their exit test reads,
so an accumulator a counted loop adds to stays bounded (Commando's hitscan damage: 0..80);
states are kept apart by stack height too.  Unbounded pointer stores, indexes into sized
arrays and the like are assumptions, listed by annotate.py's summary.md.

    python3 <beebgame>/tools/dataflow/ranges.py [--config game_config.py] [--root DIR]
                                                [--build DIR]

annotate.py and patterns.py are its front ends.
"""
import os, sys, re, json, argparse, collections, time
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import model, analysis, gamecfg
import dom
from dom import TOP, C as K, join, meet, single, contains
from analysis import IO_LO, IO_HI, STACK_LO, STACK_HI, STORES, RMW

ROOT = os.getcwd()                     # (the game's root: set by --root)

# ---------------------------------------------------------------- values with types
# A value is an abstract byte (a 4-tuple) or ('P', ((t, av), ...)): one per object type.


def isP(v):
    return v is not None and len(v) == 2 and v[0] == 'P'


def P(m):
    """a per-type value from {t: av}: plain when every type agrees"""
    items = tuple(sorted(m.items()))
    if not items:
        return None
    vs = {av for _, av in items}
    if len(vs) == 1:
        return next(iter(vs))
    return ('P', items)


def comp(v, t):
    if isP(v):
        for tt, av in v[1]:
            if tt == t:
                return av
        return None
    return v


def collapse(v, types):
    if not isP(v):
        return v
    r = None
    for t, av in v[1]:
        if t in types:
            r = join(r, av)
    return r


def vjoin(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if a == b:
        return a
    if not isP(a) and not isP(b):
        return join(a, b)
    ts = {t for t, _ in (a[1] if isP(a) else ())} | {t for t, _ in (b[1] if isP(b) else ())}
    if not isP(a):
        return P({t: join(a, comp(b, t)) for t in ts})
    if not isP(b):
        return P({t: join(comp(a, t), b) for t in ts})
    return P({t: join(comp(a, t), comp(b, t)) for t in ts})


def vwiden(a, b):
    if a is None:
        return b
    if not isP(a) and not isP(b):
        return dom.widen(a, b)
    ts = {t for t, _ in (a[1] if isP(a) else ())} | {t for t, _ in (b[1] if isP(b) else ())}
    return P({t: dom.widen(comp(a, t), comp(b, t)) for t in ts})


def lift(f, types, *vs):
    """apply f (abstract bytes -> abstract byte) per type when any value is per-type"""
    if not any(isP(v) for v in vs):
        return f(*vs)
    return P({t: f(*[comp(v, t) for v in vs]) for t in types})


def lift_multi(f, types, *vs):
    """f returns (value, flag, flag...): the value per type, each flag joined"""
    if not any(isP(v) for v in vs):
        return f(*vs)
    res = {}
    flags = None
    for t in types:
        out = f(*[comp(v, t) for v in vs])
        res[t] = out[0]
        fl = out[1:]
        if flags is None:
            flags = list(fl)
        else:
            flags = [x if x == y else None for x, y in zip(flags, fl)]
    return (P(res),) + tuple(flags or [None] * 0)


def expand(v, types):
    """v as a value per type over types (a plain value holds for each of them)"""
    if v is None:
        return None
    # (not P(): a map over fewer types than the other state's must stay a map)
    if isP(v):
        items = tuple((t, av) for t, av in v[1] if t in types)
    else:
        items = tuple((t, v) for t in sorted(types))
    return ('P', items) if items else None


def vfmt(v, tname=None):
    if v is None:
        return '⊥'
    if not isP(v):
        return dom.fmt(v)
    parts = []
    for t, av in v[1]:
        parts.append(f"{tname(t) if tname else t}:{dom.fmt(av)}")
    return '{' + ' '.join(parts) + '}'


def fjoin(a, b):
    return a if a == b else None


# ---------------------------------------------------------------- the state
RH, RL, UNK = 'RH', 'RL', '?'          # stack tokens: a JSR's return address, an unknown base


class St:
    __slots__ = ('r', 'f', 'znp', 'cmpp', 'mir', 'mem', 'stk', 'ty')

    def __init__(s, types):
        s.r = {'A': TOP, 'X': TOP, 'Y': TOP}
        s.f = {'C': None, 'Z': None, 'N': None, 'V': None, 'D': None}
        s.znp = None          # ('r', 'A') | ('m', addr): Z and N are that value's
        s.cmpp = None         # (loc, operand value): C (and Z) from CMP loc, operand
        s.mir = {}            # register -> memory address it equals
        s.mem = {}            # address -> value (flow-sensitive bytes)
        s.stk = (UNK,)
        s.ty = frozenset(types)

    def clone(s):
        t = St.__new__(St)
        t.r = dict(s.r); t.f = dict(s.f); t.znp = s.znp; t.cmpp = s.cmpp
        t.mir = dict(s.mir); t.mem = dict(s.mem); t.stk = s.stk; t.ty = s.ty
        return t

    def key(s):
        return (tuple(sorted(s.r.items())), tuple(sorted(s.f.items())), s.znp, s.cmpp,
                tuple(sorted(s.mir.items())), tuple(sorted(s.mem.items())), s.stk, s.ty)


# ---------------------------------------------------------------- the interpreter
class Ranges:
    def __init__(self, P_, an, types, objst=None, iread=None, lv_data=None, notes=None,
                 hints=None, external=None):
        self.P = P_
        self.an = an
        self.types = frozenset(types)
        self.objst = objst                    # (base, nrec, stride) or None
        # the records' layout: 'aos', a record of `stride` bytes after another (field =
        # offset in the record), or 'soa', one array of nrec bytes a field (`stride` the
        # field count: field = which array), the current record the index register equal
        # to the current-record byte (hints 'op')
        self.soa = bool((hints or {}).get('soa'))
        self.I = iread or {}                  # (t, field) -> abstract byte (the reads)
        self.Iw = collections.defaultdict(lambda: None)   # (t, field) -> written
        self.notes = notes if notes is not None else []
        self.hints = hints or {}
        self.external = external              # callable(addr) -> summary for calls out
        self.isr_w = an.isr_w
        self._succ_fix()
        self._written_direct()
        self._loops()
        self.ptr_unknown = collections.Counter()
        self.unresolved = collections.Counter()
        self.rts_dispatch = collections.Counter()
        # steps a run may take before it stops; a run that stops is not a fixpoint, and
        # analyse() says so (RANGES_BUDGET raises it for a large program)
        self.budget = int(os.environ.get('RANGES_BUDGET', '3000000'))
        self.exhausted = False
        self.check = bool(os.environ.get('RANGES_CHECK'))
        self.bad = collections.Counter()
        self.WIDEN = 12
        self._names = {}
        self._canp = {}
        self._clone = {}
        self._leaves = {}
        self._wd = {}
        self.prebuild = set(self.hints.get('prebuild', ()))
        self.pw = collections.defaultdict(set)
        self.pw_grew = False
        self.pw_all = set()
        self.cur_proc = None
        self.clone_max = 150
        self.debug = int(os.environ.get('RANGES_DEBUG', '0'))

    # ---- the CFG, with the instructions analysis.py calls self-modified given back their
    #      edges: the stores it found into them are the boot code copying the low-RAM code
    #      into place (load -> run), not patches (an assumption: summary.md lists them)
    def _succ_fix(self):
        an, P = self.an, self.P
        if hasattr(an, '_volatile_used'):
            self.volatile_used = an._volatile_used
            return
        self.volatile_used = an._volatile_used = []
        for i in P.insns.values():
            if not i.volatile or an.succ.get(i.key):
                continue
            if i.mn in ('RTS', 'RTI', 'BRK', 'JMP', 'JSR'):
                continue
            nxt = P.insns.get((i.seg, i.addr + i.len))
            S = []
            if i.mode == 'rel':
                t = P.resolve(i.opnd, i.seg)
                if t is not None:
                    S.append((t, ('br', i.mn, True)))
                if i.mn != 'BRA' and nxt is not None:
                    S.append((nxt, ('br', i.mn, False)))
            elif nxt is not None:
                S.append((nxt, None))
            if S:
                an.succ[i.key] = S
                an.unk.discard(i.key)
                for (t, e) in S:
                    an.pred[t.key].append((i, e))
                self.volatile_used.append(i.key)

    # ---- what is read-only: link-time bytes no instruction writes
    def _written_direct(self):
        # an indexed store's reach: the size of the array its base names (a `.res`), else
        # the 256 bytes an index can add
        sized = {}
        for sy in self.P.syms:
            if sy.get('size') and sy['type'] == 'lab':
                sized[sy['val']] = max(sized.get(sy['val'], 0), sy['size'])
        self.sized = sized
        self.clamped = collections.Counter()
        self.op_assumed = collections.Counter()
        self._ext = {}
        W = set()
        for i in self.P.insns.values():
            if (i.mn in STORES or i.mn in RMW) and i.opnd is not None and i.mode != 'acc':
                if i.mode in ('zp', 'abs'):
                    W.add(i.opnd)
                elif i.mode in ('abx', 'aby'):
                    W.update(range(i.opnd, i.opnd + sized.get(i.opnd, 256)))
                elif i.mode in ('zpx', 'zpy'):
                    W.update(range(0, 256))
        self.written = W
        self.romseg = collections.defaultdict(list)   # page -> [seg]
        for sid, sg in self.P.segs.items():
            if sg['data'] is None or not sg['size']:
                continue
            for pg in range(sg['start'] >> 8, (sg['start'] + sg['size'] - 1 >> 8) + 1):
                self.romseg[pg].append(sid)

    def rom(self, a, i):
        """the link-time byte at a as instruction i sees it, if nothing writes it"""
        if a in self.written or a < 0x200 or IO_LO <= a <= IO_HI:
            return None
        if self.an.bit.get(a) and (self.isr_w & self.an.bit[a]):
            return None
        cands = []
        for sid in self.romseg.get(a >> 8, ()):
            sg = self.P.segs[sid]
            if sg['start'] <= a < sg['start'] + sg['size']:
                cands.append(sid)
        if not cands:
            return None
        if len(cands) > 1:
            if i is None:
                return None
            same = [s for s in cands if s == i.seg]
            if not same:
                b = self.P.segs[i.seg].get('bank')
                same = [s for s in cands if self.P.segs[s].get('bank') == b]
            if len(same) != 1:
                return None
            cands = same
        sg = self.P.segs[cands[0]]
        if sg['name'].endswith('BSS'):
            return None
        return sg['data'][a - sg['start']]

    # ---- loops: heads (targets of backward edges) and their natural bodies
    def _loops(self):
        an, P = self.an, self.P
        back = collections.defaultdict(set)
        for k, S in an.succ.items():
            i = P.insns[k]
            for (t, e) in S:
                if t.seg == i.seg and t.addr <= i.addr:
                    back[t.key].add(k)
        body = {}
        for h, srcs in back.items():
            # forward from the head (not into callees: a JSR's edge is its return)
            fw = {h}
            st = [h]
            while st and len(fw) < 4000:
                k = st.pop()
                for (t, e) in an.succ.get(k, []):
                    if t.key not in fw:
                        fw.add(t.key); st.append(t.key)
            b = {h}
            st = [s for s in srcs if s != h and s in fw]
            b.update(st)
            while st:
                k = st.pop()
                for (p, e) in an.pred.get(k, []):
                    if p.key not in b and p.key in fw:
                        b.add(p.key); st.append(p.key)
            # a real loop: the head reaches every node of it and every node reaches a
            # back edge; a backward jump to a shared tail is no loop of the code before it
            if len(b) > 1 or h in srcs:
                body[h] = b
        self.loop_body = body
        # each loop's exit test: what the flag of a branch leaving the loop was set from
        # (a register or a byte: the loop's counter).  States at the head are kept apart
        # by the counter's value while it is one value.
        self.loop_ctr = {}
        for h, b in body.items():
            keys = set()
            for src in back.get(h, ()):
                if src not in b:
                    continue
                # the latch: src is a branch leaving the loop, or a jmp right after one
                cands = [src]
                if P.insns[src].mn == 'JMP':
                    ps = an.pred.get(src, [])
                    if len(ps) == 1:
                        cands.append(ps[0][0].key)
                for k in cands:
                    i = P.insns[k]
                    if i.mode != 'rel':
                        continue
                    if not any(t.key not in b for (t, e) in an.succ[k]):
                        continue
                    loc = self._tested(k, b)
                    if loc is not None:
                        keys.add(loc)
            if keys:
                self.loop_ctr[h] = tuple(sorted(keys, key=str))

    def _tested(self, k, b):
        """the location the flag a branch at k tests was set from (a few instructions back
        on its straight line), or None"""
        an, P = self.an, self.P
        cur = k
        for _ in range(5):
            ps = an.pred.get(cur, [])
            if len(ps) != 1:
                return None
            j = ps[0][0]
            mn = j.mn
            if mn in ('INX', 'DEX'):
                return ('r', 'X')
            if mn in ('INY', 'DEY'):
                return ('r', 'Y')
            if mn in ('INC', 'DEC') and j.mode in ('zp', 'abs'):
                return ('m', j.opnd)
            if mn in ('LDA', 'LDX', 'LDY') and j.mode in ('zp', 'abs'):
                return ('m', j.opnd)
            if mn in ('CMP', 'CPX', 'CPY'):
                r = {'CMP': 'A', 'CPX': 'X', 'CPY': 'Y'}[mn]
                # the register compared: loaded from a byte just before?
                ps2 = an.pred.get(j.key, [])
                if len(ps2) == 1:
                    q = ps2[0][0]
                    if q.mn == 'LD' + r and q.mode in ('zp', 'abs'):
                        return ('m', q.opnd)
                return ('r', r)
            if mn in ('TAX', 'TAY', 'TXA', 'TYA'):
                return ('r', mn[2])
            if mn in STORES or mn in ('CLC', 'SEC', 'NOP', 'PHA', 'PHP') or j.mode == 'rel':
                cur = j.key
                continue
            return None
        return None

    # ---- the bytes a procedure (and what it calls) names directly
    def names(self, ek):
        c = self._names.get(ek)
        if c is not None:
            return c
        an, P = self.an, self.P
        seen, stack, procs = set(), [ek], set()
        while stack:
            e = stack.pop()
            if e in procs:
                continue
            procs.add(e)
            for k in an.body(e):
                i = P.insns[k]
                if i.mn == 'JSR':
                    for t in an.call.get(k) or []:
                        stack.append(t.key)
                    h = an.helper.get(k)
                    if h:
                        for role, v in zip(h[1], h[3]):
                            if role != 'i':
                                seen.add(v); seen.add((v + 1) & 0xFF)
                    continue
                o = i.opnd
                if o is None or i.mode in ('imp', 'acc', 'imm', 'rel') or i.mn == 'JMP':
                    continue
                if i.mode in ('zp', 'abs'):
                    seen.add(o)
                elif i.mode in ('zpx', 'zpy'):
                    seen.update(range(256))
                elif i.mode in ('abx', 'aby'):
                    seen.update(range(o, o + 256))
                elif i.mode in ('iny', 'zpi', 'inx'):
                    seen.add(o); seen.add((o + 1) & 0xFF)
                    if i.mode == 'inx':
                        seen.update(range(256))
        # the dispatches the analysis resolves can lead anywhere: their targets are not in
        # the body (an RTS ends it), so a body with an RTS-dispatch keeps everything
        self._names[ek] = frozenset(seen)
        return self._names[ek]

    def cloned(self, ek):
        """a small routine is analysed once per call site (one level of call string)"""
        c = self._clone.get(ek)
        if c is None:
            c = len(self.an.body(ek)) <= self.clone_max
            self._clone[ek] = c
        return c

    def can_project(self, ek):
        """a callee whose body pushes and RTSes into code outside it must see everything"""
        c = self._canp.get(ek)
        if c is None:
            push = pull = 0
            for k in self.an.body(ek):
                mn = self.P.insns[k].mn
                if mn in ('PHA', 'PHX', 'PHY', 'PHP'):
                    push += 1
                elif mn in ('PLA', 'PLX', 'PLY', 'PLP'):
                    pull += 1
                elif mn in ('TXS', 'TSX'):
                    push += 99
            c = push <= pull
            self._canp[ek] = c
        return c

    def project(self, st, keep):
        """st with only the bytes in keep tracked (the rest read as their defaults)"""
        if self.soa and self.hints.get('op') is not None:
            # the current record's index: a callee's indexed field accesses are keyed on it
            # (a register equal to it), whether or not the callee names it
            keep = set(keep) | {self.hints['op']}
        s = st.clone()
        s.mem = {a: v for a, v in st.mem.items() if a in keep}
        s.mir = {r: a for r, a in st.mir.items() if a in keep}
        if s.znp and s.znp[0] == 'm' and s.znp[1] not in keep:
            s.znp = None
        if s.cmpp and s.cmpp[0][0] == 'm' and s.cmpp[0][1] not in keep:
            s.cmpp = None
        return s

    # ---- memory
    def objfield(self, a):
        if self.objst is None:
            return None
        base, n, stride = self.objst
        if base <= a < base + n * stride:
            return (a - base) // n if self.soa else (a - base) % stride
        return None

    def trackable(self, a):
        if a is None or IO_LO <= a <= IO_HI or STACK_LO <= a <= STACK_HI:
            return False
        b = self.an.bit.get(a)
        if b is not None and (self.isr_w & b):
            return False
        if self.objfield(a) is not None:
            return False
        return True

    def iread(self, t, f):
        return self.I.get((t, f), TOP)

    def default(self, a, i, st, via_op=False):
        f = self.objfield(a)
        if f is not None:
            if via_op:
                if f == self.hints.get('O_TYPE'):
                    return P({t: K(t) for t in st.ty})
                return P({t: self.iread(t, f) for t in st.ty})
            r = None
            for t in self.types:
                r = join(r, self.iread(t, f))
            return r
        if not self.trackable(a):
            return TOP
        v = self.rom(a, i)
        if v is not None:
            return K(v)
        return TOP

    def mread(self, st, a, i, via_op=False):
        if a in st.mem:
            return st.mem[a]
        return self.default(a, i, st, via_op)

    def mwrite(self, st, addrs, v, i, via_op=False, strong=True):
        """store v to every address in addrs (one: a strong update)"""
        if len(addrs) > 32:
            return self._mwrite_many(st, addrs, v, i, via_op)
        self._note_pw(addrs, i)
        many = len(addrs) != 1
        for a in addrs:
            f = self.objfield(a)
            if f is not None:
                if i is not None and (not i.game or (not via_op and i.key in self.prebuild)):
                    continue        # (the engine's bulk copies and clears, and ld_game's own
                                    #  state clear: all before ld_game writes every field of
                                    #  every live record through op -- README)
                if via_op:
                    for t in st.ty:
                        self.Iw[(t, f)] = join(self.Iw[(t, f)], comp(v, t))
                else:
                    c = collapse(v, st.ty)
                    for t in self.types:
                        self.Iw[(t, f)] = join(self.Iw[(t, f)], c)
                continue
            if not self.trackable(a):
                continue
            nv = vjoin(self.mread(st, a, i), v) if (many or not strong) else v
            if nv == TOP and a not in st.mem and self.rom(a, i) is None:
                pass                              # (TOP is the default: nothing to keep)
            else:
                st.mem[a] = nv
            self._kill_loc(st, ('m', a))
        # the per-type keying follows `op`: a new current record, nothing known of it
        op = self.hints.get('op')
        if op is not None and (op in addrs or (not self.soa and op + 1 in addrs)):
            self._rekey(st)

    def extent(self, o):
        """the sized array (a `.res` label) an indexed base lies in: (start, end)"""
        c = self._ext.get(o, 0)
        if c != 0:
            return c
        best = None
        for a, n in self.sized.items():
            # arrays only: 16 bytes or more, off zero page (small variables are indexed
            # across on purpose: `sta a:ox,y` over ox .. otype, the asserted runs)
            if a <= o < a + n and n >= 16 and a >= 0x100:
                if best is None or n < best[1] - best[0]:
                    best = (a, a + n)
        self._ext[o] = best
        return best

    def _note_pw(self, addrs, i):
        """every byte a procedure writes, as the analysis executes it (its dispatched
        handlers included): what a return may have changed"""
        if self.cur_proc is not None:
            w = self.pw[self.cur_proc]
            n = len(w)
            w.update(addrs)
            if len(w) != n:
                self.pw_grew = True

    def _mwrite_many(self, st, addrs, v, i, via_op):
        """a weak store over many bytes: the record fields it can hit, the bytes the state
        tracks (the rest stay at their default: unknown, or a table's link-time byte --
        a pointer store into an image's bytes is taken to be its load)"""
        aset = addrs if isinstance(addrs, (set, frozenset)) else set(addrs)
        self._note_pw(aset, i)
        if self.objst is not None and (i is None or (i.game and (via_op or i.key not in self.prebuild))):
            hit = {self.objfield(a) for a in aset} - {None}
            c = collapse(v, st.ty)
            for f in hit:
                for t in (st.ty if via_op else self.types):
                    self.Iw[(t, f)] = join(self.Iw[(t, f)], comp(v, t) if via_op else c)
        for a in [a for a in st.mem if a in aset]:
            st.mem[a] = vjoin(st.mem[a], v)
        for r in [r for r, a in st.mir.items() if a in aset]:
            del st.mir[r]
        if st.znp and st.znp[0] == 'm' and st.znp[1] in aset:
            st.znp = None
        if st.cmpp and st.cmpp[0][0] == 'm' and st.cmpp[0][1] in aset:
            st.cmpp = None
        op = self.hints.get('op')
        if op is not None and (op in aset or (not self.soa and op + 1 in aset)):
            self._rekey(st)

    def _rekey(self, st):
        ty = st.ty
        for r in 'AXY':
            st.r[r] = collapse(st.r[r], ty)
        for a in list(st.mem):
            st.mem[a] = collapse(st.mem[a], ty)
        st.stk = tuple(collapse(x, ty) if isinstance(x, tuple) else x for x in st.stk) \
            if st.stk is not None else None
        st.ty = self.types

    def _kill_loc(self, st, loc):
        if st.znp == loc:
            st.znp = None
        if st.cmpp and st.cmpp[0] == loc:
            st.cmpp = None
        if loc[0] == 'm':
            for r in [r for r, a in st.mir.items() if a == loc[1]]:
                del st.mir[r]
        else:
            st.mir.pop(loc[1], None)

    def setreg(self, st, r, v):
        st.r[r] = v
        self._kill_loc(st, ('r', r))

    # ---- addresses an operand can name
    def addrs(self, st, i):
        """(addresses, via_op) or (None, False) when unbounded"""
        mode, o = i.mode, i.opnd
        if o is None:
            return None, False
        if i.opvolatile:
            return None, False
        if mode in ('zp', 'abs'):
            return [o], False
        if mode in ('zpx', 'zpy', 'abx', 'aby'):
            reg = st.r['X' if mode in ('zpx', 'abx') else 'Y']
            rv = dom.values(collapse(reg, st.ty), 256)
            if rv is None:
                return None, False
            if mode in ('zpx', 'zpy'):
                return sorted({(o + v) & 0xFF for v in rv}), False
            out = sorted({(o + v) & 0xFFFF for v in rv})
            f = self.objfield(o) if self.soa else None
            if f is not None and self.hints.get('op') is not None and \
                    st.mir.get('X' if mode == 'abx' else 'Y') == self.hints['op']:
                # a field array indexed by the current record's index: that record's field
                # (the index taken to stay inside the array, as any sized array's)
                base, n, _ = self.objst
                fb = base + f * n
                hit = [a for a in out if fb <= a < fb + n]
                if len(hit) != len(out):
                    self.op_assumed[i.key] += 1
                return (hit or list(range(fb, fb + n))), True
            ext = self.extent(o)
            if ext and any(not (ext[0] <= a < ext[1]) for a in out):
                # an index into a sized array (its base a `.res` label) stays inside it
                # (an assumption, summary.md: an index beyond is a bug the replays would
                # show); a base that is a label plus an offset keeps its 256 bytes
                self.clamped[i.key] += 1
                out = [a for a in out if ext[0] <= a < ext[1]]
            return out, False
        if mode in ('iny', 'zpi', 'inx'):
            if mode == 'inx':
                xs = dom.values(collapse(st.r['X'], st.ty), 8)
                if xs is None or len(xs) != 1:
                    return None, False
                p = (o + xs[0]) & 0xFF
            else:
                p = o
            lo = collapse(self.mread(st, p, i), st.ty) or TOP
            hi = collapse(self.mread(st, (p + 1) & 0xFF, i), st.ty) or TOP
            ys = [0] if mode in ('zpi', 'inx') else dom.values(collapse(st.r['Y'], st.ty), 256)
            if p == self.hints.get('op') and self.objst is not None and not self.soa and ys is not None and \
                    (dom.values(hi, 2) is None or dom.values(lo, 16) is None):
                # the current-record pointer: always one of the records (the record count;
                # an assumption, summary.md) when the analysis lost it
                base, n, stride = self.objst
                self.op_assumed[i.key] += 1
                return sorted({base + r * stride + y for r in range(n) for y in ys
                               if y < stride}), True
            his = dom.values(hi, 64)
            if ys is None or his is None or lo is None:
                return None, False
            if lo[1] - lo[0] > 255:
                return None, False
            los = dom.values(lo, 256)
            if los is None:
                return None, False
            n = len(los) * len(his) * len(ys)
            if n > 4096:
                # a range: base pages x low bytes + y
                lo_min, lo_max = min(los), max(los)
                out = set()
                for h in his:
                    out.update(range(h * 256 + lo_min + min(ys), h * 256 + lo_max + max(ys) + 1))
                if len(out) > 8192:
                    return None, False
                via = (p == self.hints.get('op')) and not self.soa
                return sorted(a & 0xFFFF for a in out), via
            out = sorted({(h * 256 + l + y) & 0xFFFF for h in his for l in los for y in ys})
            via = (p == self.hints.get('op')) and not self.soa
            return out, via
        return None, False

    def read_operand(self, st, i):
        """the operand's value (immediate or memory)"""
        if i.mode == 'imm':
            return TOP if i.opvolatile else K(i.opnd)
        if i.mode in ('zpx', 'zpy', 'abx', 'aby'):
            reg = st.r['X' if i.mode in ('zpx', 'abx') else 'Y']
            if isP(reg):
                # an index per object type: a value per type
                m = {}
                for t in st.ty:
                    s1 = st.clone()
                    s1.r['X' if i.mode in ('zpx', 'abx') else 'Y'] = comp(reg, t)
                    s1.ty = frozenset([t])
                    m[t] = collapse(self.read_operand(s1, i), s1.ty)
                return P(m)
        A_, via = self.addrs(st, i)
        if not A_:
            return TOP
        if len(A_) == 1:
            return self.mread(st, A_[0], i, via)
        if len(A_) > 1024:
            return TOP
        v = None
        for a in A_:
            v = vjoin(v, self.mread(st, a, i, via))
        # a per-type field read through op stays per type when every address is one field
        return v

    def operand_loc(self, i, st):
        if i.mode in ('zp', 'abs') and not i.opvolatile:
            return ('m', i.opnd)
        return None

    # ---- flags
    def setzn(self, st, v, loc):
        cv = collapse(v, st.ty)
        st.f['Z'] = dom.zero_of(cv)
        st.f['N'] = dom.neg_of(cv)
        st.znp = loc
        st.cmpp = None

    # ---- one instruction
    def transfer(self, st, i):
        """the state after i (fall-through / not a control transfer); may return None"""
        mn, mode = i.mn, i.mode
        ty = st.ty
        f = st.f
        if i.volatile and i.key not in self.volatile_used:
            return None
        if mn in ('LDA', 'LDX', 'LDY'):
            r = mn[2]
            v = self.read_operand(st, i)
            loc = self.operand_loc(i, st)
            self.setreg(st, r, v)
            if loc:
                st.mir[r] = loc[1]
            self.setzn(st, v, ('r', r))
        elif mn in STORES:
            v = K(0) if mn == 'STZ' else st.r[mn[2]]
            A_, via = self.addrs(st, i)
            if A_ is None:
                self._unknown_store(st, i, v)
            else:
                self.mwrite(st, A_, v, i, via)
                if len(A_) == 1 and mn != 'STZ' and self.trackable(A_[0]):
                    st.mir[mn[2]] = A_[0]
        elif mn in ('TAX', 'TAY', 'TXA', 'TYA'):
            s, d = mn[1], mn[2]
            v = st.r[s]
            m = st.mir.get(s)
            self.setreg(st, d, v)
            if m is not None:
                st.mir[d] = m
            self.setzn(st, v, ('r', d))
        elif mn == 'TSX':
            self.setreg(st, 'X', TOP); self.setzn(st, TOP, ('r', 'X'))
        elif mn == 'TXS':
            st.stk = None
        elif mn in ('INX', 'INY', 'DEX', 'DEY'):
            r = mn[2]
            d = 1 if mn[0] == 'I' else 255
            v = lift(lambda a: dom.add(a, K(d), 0)[0], ty, st.r[r])
            self.setreg(st, r, v)
            self.setzn(st, v, ('r', r))
        elif mn in ('INC', 'DEC') and mode == 'acc':
            d = 1 if mn == 'INC' else 255
            v = lift(lambda a: dom.add(a, K(d), 0)[0], ty, st.r['A'])
            self.setreg(st, 'A', v); self.setzn(st, v, ('r', 'A'))
        elif mn in ('ADC', 'SBC'):
            b = self.read_operand(st, i)
            fn = dom.add if mn == 'ADC' else dom.sub
            c = f['C']
            r, co, ov = lift_multi(lambda x, y: fn(x, y, c), ty, st.r['A'], b) \
                if (isP(st.r['A']) or isP(b)) else fn(st.r['A'], b, c)
            if f.get('D') != 0 and self.decimal:
                r, co, ov = TOP, None, None
            self.setreg(st, 'A', r)
            f['C'] = co; f['V'] = ov
            self.setzn(st, r, ('r', 'A'))
        elif mn in ('AND', 'ORA', 'EOR'):
            b = self.read_operand(st, i)
            fn = {'AND': dom.land, 'ORA': dom.lor, 'EOR': dom.leor}[mn]
            r = lift(fn, ty, st.r['A'], b)
            self.setreg(st, 'A', r)
            self.setzn(st, r, ('r', 'A'))
        elif mn in ('CMP', 'CPX', 'CPY'):
            reg = {'CMP': 'A', 'CPX': 'X', 'CPY': 'Y'}[mn]
            b = self.read_operand(st, i)
            a = st.r[reg]
            if isP(a) or isP(b):
                cs, zs, ns = set(), set(), set()
                for t in ty:
                    c1, z1, n1, _ = dom.cmp(comp(a, t), comp(b, t))
                    cs.add(c1); zs.add(z1); ns.add(n1)
                f['C'] = cs.pop() if len(cs) == 1 else None
                f['Z'] = zs.pop() if len(zs) == 1 else None
                f['N'] = ns.pop() if len(ns) == 1 else None
            else:
                f['C'], f['Z'], f['N'], _ = dom.cmp(a, b)
            st.znp = None
            st.cmpp = (('r', reg), b)
        elif mn == 'BIT':
            b = self.read_operand(st, i)
            cb = collapse(b, ty)
            r = lift(dom.land, ty, st.r['A'], b)
            f['Z'] = dom.zero_of(collapse(r, ty))
            if mode != 'imm':
                f['N'] = dom.bit_of(cb, 7)
                f['V'] = dom.bit_of(cb, 6)
            st.znp = None; st.cmpp = None
        elif mn in ('ASL', 'LSR', 'ROL', 'ROR'):
            cin = 0 if mn in ('ASL', 'LSR') else f['C']
            fn = dom.asl if mn in ('ASL', 'ROL') else dom.lsr
            if mode == 'acc':
                a = st.r['A']
                r, co = lift_multi(lambda x: fn(x, cin), ty, a) if isP(a) else fn(a, cin)
                self.setreg(st, 'A', r); f['C'] = co
                self.setzn(st, r, ('r', 'A'))
            else:
                A_, via = self.addrs(st, i)
                if A_ is None:
                    self._unknown_store(st, i); f['C'] = None
                    self.setzn(st, TOP, None)
                else:
                    a = self.read_operand(st, i)
                    r, co = lift_multi(lambda x: fn(x, cin), ty, a) if isP(a) else fn(a, cin)
                    self.mwrite(st, A_, r, i, via)
                    f['C'] = co
                    self.setzn(st, r, ('m', A_[0]) if len(A_) == 1 else None)
        elif mn in ('INC', 'DEC'):
            A_, via = self.addrs(st, i)
            d = 1 if mn == 'INC' else 255
            if A_ is None:
                self._unknown_store(st, i); self.setzn(st, TOP, None)
            else:
                a = self.read_operand(st, i)
                r = lift(lambda x: dom.add(x, K(d), 0)[0], ty, a)
                self.mwrite(st, A_, r, i, via)
                self.setzn(st, r, ('m', A_[0]) if len(A_) == 1 else None)
        elif mn in ('TSB', 'TRB'):
            A_, via = self.addrs(st, i)
            a = self.read_operand(st, i)
            f['Z'] = dom.zero_of(collapse(lift(dom.land, ty, st.r['A'], a), ty))
            if A_ is None:
                self._unknown_store(st, i)
            else:
                if mn == 'TSB':
                    r = lift(dom.lor, ty, a, st.r['A'])
                else:
                    r = lift(lambda x, y: dom.land(x, dom.lnot(y)), ty, a, st.r['A'])
                self.mwrite(st, A_, r, i, via)
            st.znp = None; st.cmpp = None
        elif mn == 'CLC':
            f['C'] = 0
        elif mn == 'SEC':
            f['C'] = 1
        elif mn == 'CLV':
            f['V'] = 0
        elif mn == 'CLD':
            f['D'] = 0
        elif mn == 'SED':
            f['D'] = 1
        elif mn in ('PHA', 'PHX', 'PHY'):
            if st.stk is not None:
                st.stk = st.stk + (st.r[mn[2]],)
                if len(st.stk) > 40:
                    st.stk = None
        elif mn == 'PHP':
            if st.stk is not None:
                st.stk = st.stk + (('F', tuple(sorted(f.items()))),)
        elif mn in ('PLA', 'PLX', 'PLY'):
            r = mn[2]
            v = TOP
            if st.stk is not None and st.stk and st.stk[-1] != UNK:
                x = st.stk[-1]
                st.stk = st.stk[:-1]
                v = x if (dom.isav(x) or isP(x)) else TOP
            else:
                st.stk = None
            self.setreg(st, r, v)
            self.setzn(st, v, ('r', r))
        elif mn == 'PLP':
            if st.stk is not None and st.stk and isinstance(st.stk[-1], tuple) and st.stk[-1][0] == 'F':
                st.f = dict(st.stk[-1][1]); st.stk = st.stk[:-1]
            else:
                st.stk = None if not st.stk or st.stk[-1] == UNK else st.stk[:-1]
                for k in st.f:
                    st.f[k] = None
            st.znp = None; st.cmpp = None
        elif mn in ('NOP', 'SEI', 'CLI', 'JMP', 'RTS', 'RTI', 'BRK', 'JSR') or mode == 'rel':
            pass
        else:
            self.notes.append(f"ranges: no transfer for {mn} {mode} at {self.P.where(i)}")
            return None
        return st

    def _unknown_store(self, st, i, v=TOP):
        """a store through a pointer nobody bounded: assumed not to hit a tracked byte
        (screen or bank data: the engine's blitters) -- counted in the report -- except
        the object records, where game code's store goes into every field of every type"""
        self.ptr_unknown[i.key] += 1
        screen = self.hints.get('screen_ptrs', ())
        if i.mode in ('iny', 'zpi', 'inx') and i.opnd in screen:
            return                         # (the screen pointer: the text's glyphs)
        if self.objst is not None and i.game and i.key not in self.prebuild:
            c = collapse(v, st.ty) if v is not None else TOP
            for t in self.types:
                for f in range(self.objst[2]):
                    self.Iw[(t, f)] = join(self.Iw[(t, f)], c)

    # ---- branches
    def branch(self, st, i, taken):
        """the state on one edge of a conditional branch, or None if infeasible"""
        mn = i.mn
        if mn == 'BRA':
            return st if taken else None
        fl, tv = {'BPL': ('N', 0), 'BMI': ('N', 1), 'BVC': ('V', 0), 'BVS': ('V', 1),
                  'BCC': ('C', 0), 'BCS': ('C', 1), 'BNE': ('Z', 0), 'BEQ': ('Z', 1)}[mn]
        want = tv if taken else 1 - tv
        if st.f[fl] is not None and st.f[fl] != want:
            return None
        st = st.clone()
        st.f[fl] = want
        ok = True
        if fl == 'Z' and want == 1 and (st.znp is not None or st.cmpp is not None):
            # Z=1 from a value: it is 0, so N=0; from a compare: equal, so N=0 and C=1
            if st.f['N'] == 1:
                return None
            st.f['N'] = 0
            if st.cmpp is not None and st.znp is None:
                if st.f['C'] == 0:
                    return None
                st.f['C'] = 1
        if fl in ('Z', 'N') and st.znp is not None:
            ok = self._refine(st, st.znp, lambda a: dom.refine_zero(a, want) if fl == 'Z'
                              else dom.refine_neg(a, want))
        elif fl in ('C', 'Z') and st.cmpp is not None:
            loc, b = st.cmpp
            if fl == 'C':
                g = (lambda a, bb: dom.refine_ge(a, bb)) if want == 1 else (lambda a, bb: dom.refine_lt(a, bb))
            else:
                g = (lambda a, bb: dom.refine_eq(a, bb)) if want == 1 else (lambda a, bb: dom.refine_ne(a, bb))
            ok = self._refine2(st, loc, b, g)
        return st if ok else None

    def _getloc(self, st, loc):
        if loc[0] == 'r':
            return st.r[loc[1]]
        return st.mem.get(loc[1])

    def _setloc(self, st, loc, v):
        if loc[0] == 'r':
            st.r[loc[1]] = v
            m = st.mir.get(loc[1])
            if m is not None and self.trackable(m):
                st.mem[m] = v
        else:
            if self.trackable(loc[1]):
                st.mem[loc[1]] = v
            for r, a in st.mir.items():
                if a == loc[1]:
                    st.r[r] = v

    def _refine(self, st, loc, g):
        v = self._getloc(st, loc)
        if v is None:
            return True
        if isP(v):
            m = {}
            keep = set()
            for t in st.ty:
                r = g(comp(v, t))
                if r is not None:
                    m[t] = r; keep.add(t)
            if not keep:
                return False
            self._narrow_types(st, frozenset(keep))
            self._setloc(st, loc, P(m))
            return True
        r = g(v)
        if r is None:
            return False
        self._setloc(st, loc, r)
        return True

    def _refine2(self, st, loc, b, g):
        v = self._getloc(st, loc)
        if v is None:
            return True
        if isP(v) or isP(b):
            m = {}
            for t in st.ty:
                r = g(comp(v, t), comp(b, t))
                if r is not None:
                    m[t] = r
            if not m:
                return False
            self._narrow_types(st, frozenset(m))
            self._setloc(st, loc, P(m))
            return True
        r = g(v, b)
        if r is None:
            return False
        self._setloc(st, loc, r)
        return True

    def _narrow_types(self, st, keep):
        if keep == st.ty:
            return
        st.ty = st.ty & keep
        def nar(v):
            if isP(v):
                return P({t: av for t, av in v[1] if t in st.ty})
            return v
        for r in 'AXY':
            st.r[r] = nar(st.r[r])
        for a in list(st.mem):
            st.mem[a] = nar(st.mem[a])

    # ---- joins
    def join_into(self, old, new, widen=False, wc=None):
        """old := old joined with new; returns (state, changed).  With wc (a counter per
        value at this node), a value that has changed here more than WIDEN times is widened
        (only it: the others keep joining)"""
        if old is None:
            return new.clone(), True
        ch = False
        r = old.clone()
        oty, nty = old.ty, new.ty
        def jj(a, b, key=None):
            if a == b:
                return a
            f = vjoin
            if widen or (wc is not None and key is not None and wc[key] > self.WIDEN):
                f = vwiden
            if oty != nty:
                return f(expand(a, oty), expand(b, nty))
            return f(a, b)
        for k in 'AXY':
            v = jj(old.r[k], new.r[k], k)
            if v != old.r[k]:
                r.r[k] = v; ch = True
                if wc is not None:
                    wc[k] += 1
        for k in r.f:
            v = fjoin(old.f[k], new.f[k])
            if v != old.f[k]:
                r.f[k] = v; ch = True
        if old.znp != new.znp and old.znp is not None:
            r.znp = None; ch = True
        if old.cmpp != new.cmpp and old.cmpp is not None:
            r.cmpp = None; ch = True
        for k in list(r.mir):
            if new.mir.get(k) != r.mir[k]:
                del r.mir[k]; ch = True
        keys = {a for a, _ in (old.mem.items() ^ new.mem.items())}
        for a in keys:
            ov = old.mem.get(a)
            nv = new.mem.get(a)
            if ov is None:
                ov = self.default(a, None, old)
            if nv is None:
                nv = self.default(a, None, new)
            v = jj(ov, nv, a)
            if old.mem.get(a, ov) != v:
                r.mem[a] = v; ch = True
                if wc is not None:
                    wc[a] += 1
        if old.stk != new.stk:
            if old.stk is None:
                pass
            elif new.stk is None or len(old.stk) != len(new.stk):
                r.stk = None; ch = True
            else:
                s = []
                for x, y in zip(old.stk, new.stk):
                    if x == y:
                        s.append(x)
                    elif isinstance(x, tuple) and isinstance(y, tuple) and \
                            (dom.isav(x) or isP(x)) and (dom.isav(y) or isP(y)):
                        s.append(jj(x, y))
                    elif isinstance(x, tuple) and isinstance(y, tuple) and x[0] == 'F' and y[0] == 'F':
                        fx, fy = dict(x[1]), dict(y[1])
                        s.append(('F', tuple(sorted((k, fx[k] if fx[k] == fy.get(k) else None) for k in fx))))
                    else:
                        s = None; break
                ns = tuple(s) if s is not None else None
                if ns != old.stk:
                    r.stk = ns; ch = True
        t = old.ty | new.ty
        if t != old.ty:
            r.ty = t; ch = True
        return r, ch

    # ---- the driver
    def run(self, seeds):
        """seeds: [(entry key, St)].  Nodes are (proc, insn key, part)."""
        P, an = self.P, self.an
        self.decimal = any(i.mn == 'SED' for i in P.insns.values())
        IN = {}
        visits = collections.Counter()
        wcount = {}
        wl = collections.deque()
        inwl = set()
        self.callers = collections.defaultdict(set)    # callee proc -> {(proc, jsr key, part)}
        self.callst = {}                               # (proc, jsr key, part) -> state at the JSR
        self.retst = {}                                # proc -> joined state at its returns
        self.parts = collections.defaultdict(set)      # (proc, head) -> keys seen
        self.reached = set()

        def push(node, st, widen=False):
            if self.check:
                for loc, v in list(st.r.items()) + list(st.mem.items()):
                    if isP(v) and not st.ty <= {t for t, _ in v[1]}:
                        self.bad[(P.where(P.insns[node[1]]), str(loc))] += 1
            old = IN.get(node)
            if old is None:
                IN[node] = st.clone(); ch = True
            else:
                wc = wcount.get(node)
                if wc is None and node[1] in self.loop_body and not self._partitioned(node):
                    wc = wcount[node] = collections.Counter()
                IN[node], ch = self.join_into(old, st, widen=visits[node] > 400, wc=wc)
                if ch:
                    visits[node] += 1         # (a backstop: everything widens after 400 changes)
            if ch and node not in inwl:
                wl.append(node); inwl.add(node)

        for ek, st in seeds:
            push(((ek, None), ek, ()), st)

        def part_for(proc, key, part, st):
            """the loop partition of the state arriving at insn key"""
            np_ = tuple((h, v) for (h, v) in part if key in self.loop_body.get(h, ()))
            if self.loop_ctr.get(key):
                kv = []
                for loc in self.loop_ctr[key]:
                    v = st.r[loc[1]] if loc[0] == 'r' else self.mread(st, loc[1], P.insns[key])
                    v = collapse(v, st.ty)
                    kv.append(v[0] if v is not None and single(v) else None)
                kv = tuple(kv)
                ps = self.parts[(proc, key)]
                if kv not in ps:
                    if len(ps) >= 64:
                        kv = '*'
                    ps.add(kv)
                np_ = tuple(x for x in np_ if x[0] != key) + ((key, kv),)
            # states are kept apart by the stack's height too: code whose pushes depend on a
            # path (ob_tank's dying age, pulled on that path alone) must not join depths
            h = len(st.stk) if st.stk is not None else -1
            if h != 2:
                np_ = np_ + (('#', h),)
            return np_

        steps = 0
        t0 = time.time()
        while wl:
            node = wl.popleft(); inwl.discard(node)
            steps += 1
            if steps > self.budget:
                self.notes.append('ranges: step budget exhausted')
                self.exhausted = True
                break
            if self.debug and steps % self.debug == 0:
                top = visits.most_common(8)
                print(f"  {steps} steps, {len(IN)} nodes, wl {len(wl)}:",
                      '; '.join(f"{P.where(P.insns[n[1]])} {P.disasm(P.insns[n[1]])} part={str(n[2])[:60]} x{c}" for n, c in top), flush=True)
            proc, k, part = node
            self.cur_proc = proc
            i = P.insns[k]
            self.reached.add(k)
            st0 = IN[node]
            mn = i.mn
            # ---- calls
            if mn == 'JSR':
                h = an.helper.get(k)
                nxt = None
                for (t, e) in an.succ[k]:
                    nxt = t
                if h:
                    st = self.helper(st0.clone(), i, h)
                    if nxt is not None:
                        push((proc, nxt.key, part_for(proc, nxt.key, part, st)), st)
                    continue
                targets = an.call.get(k) or []
                if not targets:
                    st = self.havoc_call(st0.clone(), i)
                    if nxt is not None and st is not None:
                        push((proc, nxt.key, part_for(proc, nxt.key, part, st)), st)
                    else:
                        self.unresolved[k] += 1
                    continue
                site = (proc, k, part)
                self.callst[site] = st0
                if nxt is not None and any(self.leaves(t.key) for t in targets):
                    # a callee that leaves the model (the loader takes over, an unresolved
                    # jump): it may come back having done anything
                    hv = self.havoc_all(st0.clone())
                    push((proc, nxt.key, part_for(proc, nxt.key, part, hv)), hv)
                for t in targets:
                    pid = (t.key, k if self.cloned(t.key) else None)
                    self.callers[pid].add(site)
                    cst = self.project(st0, self.names(t.key)) if self.can_project(t.key) else st0.clone()
                    cst.stk = (RH, RL)
                    push((pid, t.key, ()), cst)
                    if pid in self.retst and nxt is not None:
                        rs = self.combine(st0, self.retst[pid], k, pid, proc)
                        if rs is not None:
                            push((proc, nxt.key, part_for(proc, nxt.key, part, rs)), rs)
                continue
            # ---- returns and stack dispatch
            if mn == 'RTS':
                stk = st0.stk
                if stk is not None and len(stk) >= 2 and stk[-1] == RL and stk[-2] == RH:
                    old = self.retst.get(proc)
                    new, ch = self.join_into(old, st0) if old is not None else (st0.clone(), True)
                    if ch:
                        self.retst[proc] = new
                        for site in list(self.callers.get(proc, ())):
                            cp, jk, cpart = site
                            for (t, e) in an.succ[jk]:
                                rs = self.combine(self.callst[site], new, jk, proc, cp)
                                if rs is not None:
                                    push((cp, t.key, part_for(cp, t.key, cpart, rs)), rs)
                    continue
                if stk is not None and len(stk) >= 2 and all(dom.isav(x) or isP(x) for x in stk[-2:]):
                    lo, hi = stk[-1], stk[-2]
                    outs = self.dispatch(st0, i, lo, hi)
                    if outs is None:
                        self.unresolved[k] += 1
                        continue
                    for tk, st in outs:
                        st.stk = stk[:-2]
                        self.rts_dispatch[(k, tk)] += 1
                        push((proc, tk, part_for(proc, tk, part, st)), st)
                    continue
                if stk is not None and stk and stk[-1] == UNK:
                    continue                     # an unknown caller: the analysis ends here
                self.unresolved[k] += 1
                continue
            if mn in ('RTI', 'BRK'):
                continue
            if mn == 'JMP' and i.mode in ('ind', 'iax'):
                outs = self.jmp_ind(st0, i)
                if outs is None:
                    self.unresolved[k] += 1
                    continue
                for tk, st in outs:
                    push((proc, tk, part_for(proc, tk, part, st)), st)
                continue
            if mn == 'JMP' and i.mode == 'abs' and not an.succ[k] and self.external is not None:
                # a tail jump out of this program (LDPROG -> bank 7): the callee's effects,
                # then its RTS returns to this procedure's caller
                st = self.havoc_call(st0.clone(), i)
                stk = st.stk
                if stk is not None and len(stk) >= 2 and stk[-1] == RL and stk[-2] == RH:
                    old = self.retst.get(proc)
                    new, ch = self.join_into(old, st) if old is not None else (st.clone(), True)
                    if ch:
                        self.retst[proc] = new
                        for site in list(self.callers.get(proc, ())):
                            cp, jk, cpart = site
                            for (t, e) in an.succ[jk]:
                                rs = self.combine(self.callst[site], new, jk, proc, cp)
                                if rs is not None:
                                    push((cp, t.key, part_for(cp, t.key, cpart, rs)), rs)
                continue
            if k in an.unk and not an.succ[k]:
                self.unresolved[k] += 1
                continue
            st = self.transfer(st0.clone(), i)
            if st is None:
                self.unresolved[k] += 1
                continue
            hint = self.hints.get('bind', {}).get(k)
            if hint:
                self.bind_type(st, hint)
            for (t, e) in an.succ[k]:
                if e is not None:
                    s2 = self.branch(st, i, e[2])
                    if s2 is None:
                        continue
                else:
                    s2 = st
                push((proc, t.key, part_for(proc, t.key, part, s2)), s2)
        self.IN = IN
        self.visits = visits
        self.steps = steps
        self.secs = time.time() - t0
        return IN

    def _partitioned(self, node):
        """a loop head whose state here is one iteration's (its counter one value): no
        widening needed -- each partition grows finitely"""
        h = node[1]
        if not self.loop_ctr.get(h):
            return False
        for (hh, kv) in node[2]:
            if hh == h and isinstance(kv, tuple):
                return None not in kv
            if hh == h:
                return kv != '*'
        return False

    def bind_type(self, st, addr):
        """kappa := the value of the byte at addr (ld_game: the record being built gets
        this type): the state's per-type values are dropped, the types narrowed"""
        self._rekey(st)
        v = collapse(self.mread(st, addr, None), st.ty)
        vs = dom.values(v, 64) or []
        keep = frozenset(t for t in vs if t in self.types) or self.types
        st.ty = keep
        st.mem[addr] = P({t: K(t) for t in keep})
        for r, a in list(st.mir.items()):
            if a == addr:
                st.r[r] = st.mem[addr]

    def combine(self, caller, ret, jk, pid=None, cpid=None):
        """the state after a JSR: the callee's for what it may change, the caller's else.
        What it may change: the bytes it (or what it calls) names in a store, and those it
        stored to through pointers or indexes (self.pw, from this and earlier rounds)"""
        an = self.an
        e = an.callee_eff(jk)
        st = caller.clone()
        from analysis import A as bA, X as bX, Y as bY
        for r, b in (('A', bA), ('X', bX), ('Y', bY)):
            if e['maydef'] & b or e.get('mw') == an.MALL:
                st.r[r] = ret.r[r]
        st.f = dict(ret.f)
        st.znp = ret.znp if ret.znp and ret.znp[0] == 'r' else None
        st.cmpp = None
        st.mir = {}
        if pid is None or pid in self.pw_all:
            W = None
            if cpid is not None:
                self.pw_all.add(cpid)
        else:
            W = self.wdirect(pid[0]) | self.pw.get(pid, frozenset())
            if cpid is not None and self.pw.get(pid):
                n = len(self.pw[cpid])
                self.pw[cpid] |= self.pw[pid]
                if len(self.pw[cpid]) != n:
                    self.pw_grew = True
        for a, v in ret.mem.items():
            if W is None or a in W:
                st.mem[a] = v
        for a in list(st.mem):
            if (W is None or a in W) and a not in ret.mem:
                del st.mem[a]
        # the types that come back are the callee's returns' (a per-type value from the callee
        # holds for those alone): never more than the caller sent in
        op = self.hints.get('op')
        if W is None or (op is not None and (op in W or op + 1 in W)):
            st.ty = ret.ty
        else:
            st.ty = caller.ty & ret.ty
        st.stk = caller.stk
        if not st.ty:
            return None
        self._narrow_types(st, st.ty)
        return st

    def wdirect(self, ek):
        """the bytes a procedure (and what it calls) stores to by name"""
        c = self._wd.get(ek)
        if c is not None:
            return c
        an, P = self.an, self.P
        seen, stack, procs = set(), [ek], set()
        while stack:
            e = stack.pop()
            if e in procs:
                continue
            procs.add(e)
            for k in an.body(e):
                i = P.insns[k]
                if i.mn == 'JSR':
                    for t in an.call.get(k) or []:
                        stack.append(t.key)
                    h = an.helper.get(k)
                    if h:
                        for role, v in zip(h[1], h[3]):
                            if role in ('rw16', 'w16'):
                                seen.add(v); seen.add((v + 1) & 0xFF)
                        for nm in gamecfg.C.HELPER_SCRATCH:
                            for sy in P.syms:
                                if sy['name'] == nm:
                                    seen.add(sy['val']); seen.add(sy['val'] + 1)
                    continue
                if (i.mn in STORES or i.mn in RMW) and i.mode in ('zp', 'abs'):
                    seen.add(i.opnd)
        self._wd[ek] = frozenset(seen)
        return self._wd[ek]

    def helper(self, st, i, h):
        """an inline-operand helper: its contract (the game's config: gamecfg)"""
        name, roles, uses, ops = h
        for role, v in zip(roles, ops):
            if role in ('rw16', 'w16'):
                self.mwrite(st, [v, (v + 1) & 0xFF], TOP, i, strong=True)
        for nm in gamecfg.C.HELPER_SCRATCH:
            for s in self.P.syms:
                if s['name'] == nm:
                    self.mwrite(st, [s['val'], s['val'] + 1], TOP, i)
        cx = dom.bit_of(collapse(st.r['X'], st.ty), 0)
        self.setreg(st, 'A', TOP)
        for k in ('N', 'Z', 'C', 'V'):
            st.f[k] = None
        if any(name.startswith(p_) for p_ in gamecfg.C.HELPER_CARRY_X0):
            # (the config's: a helper that returns C = bit 0 of the caller's X)
            st.f['C'] = cx
        st.znp = None; st.cmpp = None
        return st

    def leaves(self, ek):
        c = self._leaves.get(ek)
        if c is None:
            an = self.an
            c = False
            seen, stack = set(), [ek]
            while stack and not c:
                e = stack.pop()
                if e in seen:
                    continue
                seen.add(e)
                for k in an.body(e):
                    i = self.P.insns[k]
                    if k in an.unk and not an.succ.get(k) and i.mn == 'JMP':
                        c = True; break
                    if i.mn == 'JSR':
                        stack.extend(t.key for t in an.call.get(k) or [])
            self._leaves[ek] = c
        return c

    def havoc_all(self, st):
        if self.cur_proc is not None:
            self.pw_all.add(self.cur_proc)
        for r in 'AXY':
            st.r[r] = TOP
        for k in st.f:
            st.f[k] = None
        st.znp = None; st.cmpp = None; st.mir = {}; st.mem = {}
        st.ty = self.types
        return st

    def havoc_call(self, st, i):
        """a JSR whose target is outside this program (LDPROG -> bank 7): its summary
        from the other program if there is one, else everything"""
        s = self.external(i.opnd) if self.external else None
        for r in 'AXY':
            self.setreg(st, r, TOP)
        for k in st.f:
            st.f[k] = None
        st.znp = None; st.cmpp = None; st.mir = {}
        if s is None:
            st.mem = {}
            self._rekey(st)
        else:
            for a in list(st.mem):
                if a in s:
                    del st.mem[a]
            op = self.hints.get('op')
            if op in s or (op is not None and op + 1 in s):
                self._rekey(st)
        return st

    def dispatch(self, st, i, lo, hi):
        """RTS to the pushed address + 1: [(insn key, state)], split by type"""
        P = self.P
        groups = collections.defaultdict(set)
        tys = st.ty if (isP(lo) or isP(hi)) else [None]
        for t in tys:
            l = comp(lo, t) if t is not None else lo
            h = comp(hi, t) if t is not None else hi
            ls, hs = dom.values(l, 16), dom.values(h, 16)
            if ls is None or hs is None or len(ls) * len(hs) > 32:
                return None
            for a in ls:
                for b in hs:
                    tgt = (b * 256 + a + 1) & 0xFFFF
                    groups[tgt].add(t)
        out = []
        for tgt, ts in groups.items():
            j = P.resolve(tgt, i.seg)
            if j is None:
                js = P.resolve_all(tgt, i.seg, i)
                if not js:
                    self.notes.append(f"ranges: rts dispatch at {P.where(i)} to ${tgt:04X}: no code")
                    continue
                j = js[0]
            s = st.clone()
            if None not in ts:
                self._narrow_types(s, frozenset(ts))
            out.append((j.key, s))
        return out

    def jmp_ind(self, st, i):
        """JMP (ind) / JMP (abs,X): [(insn key, state)] -- split by object type when the
        pointer or the index is a value per type (a dispatch on the type)"""
        P = self.P
        if i.mode == 'ind':
            lo, hi = self.mread(st, i.opnd, i), self.mread(st, i.opnd + 1, i)
            per = isP(lo) or isP(hi)
        else:
            per = isP(st.r['X'])
        groups = collections.defaultdict(set)
        for t in (sorted(st.ty) if per else [None]):
            if i.mode == 'ind':
                l = comp(lo, t) if t is not None else collapse(lo, st.ty)
                h = comp(hi, t) if t is not None else collapse(hi, st.ty)
                ls, hs = dom.values(l, 16), dom.values(h, 16)
                if ls is None or hs is None:
                    return None
                tg = {b * 256 + a for a in ls for b in hs}
            else:
                x = comp(st.r['X'], t) if t is not None else collapse(st.r['X'], st.ty)
                xs = dom.values(x, 64)
                if xs is None:
                    return None
                tg = set()
                for xv in xs:
                    a = i.opnd + xv
                    l = self.default(a, i, st); h = self.default(a + 1, i, st)
                    if not (single(l) and single(h)):
                        return None
                    tg.add(h[0] * 256 + l[0])
            for g in tg:
                groups[g].add(t)
        out = []
        for g, ts in groups.items():
            j = P.resolve(g, i.seg)
            if j is None:
                return None
            s = st.clone()
            if None not in ts:
                self._narrow_types(s, frozenset(ts))
            out.append((j.key, s))
        return out


# ---------------------------------------------------------------- setting up a program
def find_sym(P_, name):
    for s in P_.syms:
        if s['name'] == name:
            return s['val']
    return None


def program(build, dbg='game.dbg'):
    """model.Program over another debug file in the same build directory"""
    if dbg == 'game.dbg':
        return model.Program(ROOT, build)
    d = os.path.join(build, '_dbg_' + dbg.replace('.', '_'))
    os.makedirs(d, exist_ok=True)
    link = os.path.join(d, 'game.dbg')
    if os.path.lexists(link):
        os.remove(link)
    os.symlink(os.path.abspath(os.path.join(build, dbg)), link)
    for f in os.listdir(build):
        p = os.path.join(build, f)
        q = os.path.join(d, f)
        if os.path.isfile(p) and f != 'game.dbg':
            if os.path.lexists(q):
                os.remove(q)               # (always this build's: a copied tree's links are stale)
            os.symlink(os.path.abspath(p), q)
    return model.Program(ROOT, d)


def table_taken(an, ek):
    """an entry address-taken only by a data table (a dispatch table: resolved by the
    analysis's stack model when its dispatcher is reached)"""
    why = an.taken.get(ek, '')
    return 'data byte' in why or why.startswith('.word')


def run_phased(make, an, types, notes, label):
    """seed the interrupt, orphans and non-table address-taken entries; then, round by
    round, the table-taken entries no resolved dispatch reached"""
    isr = set(getattr(an, 'isr_roots', ()))
    base = [ek for ek, kinds in an.entries.items()
            if ek in isr or (('orphan' in kinds or 'taken' in kinds) and not table_taken(an, ek))]
    seeds = list(base)
    pw, pwa = {}, set()
    cut = False
    for rnd in range(12):
        R = make()
        for k, v in pw.items():
            R.pw[k] |= v
        R.pw_all |= pwa
        n0 = sum(map(len, R.pw.values())) + len(R.pw_all)
        R.run([(ek, St(types)) for ek in seeds])
        cut = cut or R.exhausted
        grew = sum(map(len, R.pw.values())) + len(R.pw_all) != n0
        pw, pwa = R.pw, R.pw_all
        missing = [ek for ek, kinds in an.entries.items()
                   if ('taken' in kinds or 'orphan' in kinds) and ek not in R.reached and ek not in seeds]
        notes.append(f"{label} round {rnd}: {len(seeds)} seeds, {len(R.reached)} reached, "
                     f"{R.steps} steps, {R.secs:.1f}s; {len(missing)} table entries unreached; "
                     f"written sets {'grew' if grew else 'stable'}")
        if not missing and not grew:
            R.exhausted = cut
            return R
        seeds += missing
    notes.append(f"{label}: did not settle in 12 rounds")
    R.exhausted = cut
    return R


def seeds_for(an, R, types, allow_taken=False, only=None):
    """entries nobody resolved: the interrupt, code with no known predecessor, the
    address-taken entries no dispatch reached"""
    out = []
    for ek, kinds in an.entries.items():
        if only is not None and ek not in only:
            continue
        if 'orphan' in kinds or ek in getattr(an, 'isr_roots', ()) or (allow_taken and 'taken' in kinds):
            st = St(types)
            out.append((ek, st))
    return out


def analyse(build, out=None, quiet=False, rounds=12):
    """the game's program (and, with an object model built by the loader, the load-time
    program first): the record invariant to a fixpoint.  The game's specifics come from
    gamecfg (the game's config file)"""
    C = gamecfg.C
    notes = []
    # ---- the game's program
    PG = model.Program(ROOT, build)
    anG = analysis.Analysis(PG)
    OB = C.OBJECTS
    if OB:
        types = list(OB['types'])
        O = {n: find_sym(PG, n) for n in OB.get('fields', ())}
        objst = find_sym(PG, OB['records'])
        nobj = OB['count'] if isinstance(OB['count'], int) else (find_sym(PG, OB['count']) or 32)
        stride = OB['stride']
        tf = find_sym(PG, OB['type_field'])
        soa = OB.get('layout', 'aos') == 'soa'
        if soa:
            tf = (tf - objst) // nobj           # (the type array's label: which field)
            O = {n: (v - objst) // nobj if v is not None else None for n, v in O.items()}
        op = find_sym(PG, OB['current'])
        otype = find_sym(PG, OB.get('type_var')) if OB.get('type_var') else None
        rec = (objst, nobj, stride)
    else:
        types, O, rec, op, tf, otype, soa = [0], {}, None, None, None, None, False
    scr = {find_sym(PG, n) for n in C.SCREEN_POINTERS} - {None}
    hintsG = dict(op=op, O_TYPE=tf, screen_ptrs=scr, soa=soa)
    if OB and OB.get('game_bind'):
        # the game builds the records itself (no load-time program): where its own code
        # stores a record's type into the type variable, the type is bound -- (file,
        # a regex of the instruction, the routine it is in)
        gf, grx, gproc = OB['game_bind']
        hintsG['bind'] = {i.key: otype for i in PG.insns.values()
                          if i.game and PG.src.short(i.outer['file']).endswith(gf)
                          and re.match(grx, PG.text(i).split(';')[0].strip())
                          and PG.routine_of(i) == gproc}
        notes.append(f"game binds the record type at {len(hintsG['bind'])} instruction(s)")
    # ---- the load-time program, when it builds the records
    I0, RL_ = {}, None
    if OB and C.LOADER_DBG and os.path.exists(os.path.join(build, C.LOADER_DBG)):
        PL = program(build, C.LOADER_DBG)
        anL = analysis.Analysis(PL)
        anL.isr_w = 0                 # (a load runs with interrupts off: no interrupt writes)
        lf = OB.get('loader_file', '')
        # the loader binds kappa where it loads the record's type into the type variable
        bind = {}
        for i in PL.insns.values():
            t = PL.text(i).split(';')[0]
            if lf and PL.src.short(i.outer['file']).endswith(lf) and re.match(OB.get('bind', '$^'), t.strip()):
                bind[i.key] = otype
        # the loader's stores that are not through the current-record pointer: its clear
        prebuild = [i.key for i in PL.insns.values()
                    if lf and PL.src.short(i.outer['file']).endswith(lf) and i.mn in STORES and i.mode != 'iny']
        hintsL = dict(op=op, O_TYPE=tf, bind=bind, prebuild=prebuild, soa=soa)
        # summaries of the game's routines for the loader's calls out (what they may write)
        mwG = {}
        for t, s_ in anG.S.items():
            a_ = PG.insns[t].addr
            mwG[a_] = None if s_['mw'] == anG.MALL else {x for x, b_ in anG.bit.items() if s_['mw'] & b_}
        RL_ = run_phased(lambda: Ranges(PL, anL, types, objst=rec, iread={}, notes=notes,
                                        hints=hintsL, external=lambda a_: mwG.get(a_, None)),
                         anL, types, notes, 'loader')
        I0 = {k: v for k, v in RL_.Iw.items() if v is not None}
        notes.append(f"loader: {len(RL_.reached)} of {len(PL.insns)} instructions reached, "
                     f"{RL_.steps} steps, {RL_.secs:.1f}s; record fields written per type: {len(I0)}")
    # ---- the game, rounds until the record invariant is stable.  A cached invariant from an
    # earlier run (this build's: keyed by the debug file's size and time) is a sound start
    # when the rounds confirm it (nothing written outside it): an inductive invariant
    I = dict(I0)
    cache = os.path.join(build, 'ranges_I.json')
    st_ = os.stat(os.path.join(build, 'game.dbg'))
    ckey = f"{st_.st_size}:{int(st_.st_mtime)}"
    try:
        c = json.load(open(cache))
        if c.get('key') == ckey:
            for k, v in c['I']:
                kk = tuple(k)
                I[kk] = join(I.get(kk), tuple(v[:4]) + (frozenset(v[4]) if v[4] is not None else None,))
            notes.append('record invariant: started from the cached one (to be confirmed)')
    except Exception:
        pass
    R = None
    for rnd in range(rounds):
        pw = R.pw if R is not None else None
        pwa = R.pw_all if R is not None else set()
        def make():
            r = Ranges(PG, anG, types, objst=rec, iread=I, notes=notes, hints=hintsG)
            if pw:
                for k, v in pw.items():
                    r.pw[k] |= v
            r.pw_all |= pwa
            return r
        R = run_phased(make, anG, types, notes, f'game round {rnd}')
        if not quiet:
            print(notes[-1], flush=True)
        newI = dict(I)
        ch = False
        last = rnd == rounds - 1
        for k, v in R.Iw.items():
            if v is None:
                continue
            j = join(newI.get(k), v)
            if rnd >= 2 and newI.get(k) is not None and j != newI[k]:
                # the record invariant must converge: widen (thresholds), and from round 6 a
                # field still growing is unknown
                j = dom.widen(newI[k], j) if rnd < 6 else TOP
            if j != newI.get(k):
                newI[k] = j; ch = True
        notes.append(f"round {rnd}: {len(R.reached)} of {len(PG.insns)} instructions reached, "
                     f"{R.steps} steps, {R.secs:.1f}s, record invariant {'changed' if ch else 'stable'}")
        if not quiet:
            print(notes[-1], flush=True)
        I = newI
        grew = R.pw_grew or (pw is not None and sum(map(len, R.pw.values())) != sum(map(len, pw.values())))
        if not ch and not grew:
            R.converged = True
            break
    else:
        # not settled in the rounds allowed: the analysis's states are not a fixpoint, and so
        # not sound.  Say so loudly (annotate.py prints it at the top of every file)
        R.converged = False
        notes.append('WARNING: the record invariant did not converge: the states are NOT sound')
    # a run cut off by its step budget stopped with work still on its worklist: its states
    # are not a fixpoint, whatever the rounds above concluded, so not sound and not a cache
    cut = [n for n, r_ in (('game', R), ('loader', RL_)) if r_ is not None and r_.exhausted]
    if cut:
        R.converged = False
        notes.append(f"WARNING: the step budget ({R.budget:,} a run; RANGES_BUDGET raises it) ran "
                     f"out in the {' and '.join(cut)} analysis: the states are NOT sound")
    R.I_final = I
    if getattr(R, 'converged', False):
        try:
            json.dump({'key': ckey, 'I': [[list(k), list(v[:4]) + [sorted(v[4]) if v[4] is not None else None]]
                                          for k, v in I.items() if v is not None]}, open(cache, 'w'))
        except Exception:
            pass
    R.ldprog = RL_
    R.notes_all = notes
    R.O = O
    return R


def tname_fn(PG):
    """object type names, from the type equates (the config's type_prefix)"""
    OB = gamecfg.C.OBJECTS or {}
    pre = OB.get('type_prefix')
    names = {}
    if pre:
        for s_ in PG.syms:
            if s_['name'].startswith(pre) and s_['type'] == 'equ':
                names.setdefault(s_['val'], s_['name'][len(pre):].lower())
    return lambda t: names.get(t, str(t))


def setup(argv=None, extra=None):
    """the tools' common arguments: --config, --root, --build"""
    global ROOT
    ap = argparse.ArgumentParser()
    gamecfg.add_args(ap)
    ap.add_argument('--build', default=None)
    if extra:
        extra(ap)
    a = ap.parse_args(argv)
    gamecfg.load(a.config)
    ROOT = os.path.abspath(a.root)
    a.build = a.build or os.path.join(ROOT, 'build', 'master')
    return a


if __name__ == '__main__':
    a = setup()
    R = analyse(a.build)
    for n in R.notes_all[-12:]:
        print(n)
