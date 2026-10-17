"""dom -- the abstract byte: an interval reduced with known bits, and a small value set.

An abstract byte is a tuple (lo, hi, km, kv, vs): every concrete value v it stands for has
lo <= v <= hi (unsigned), v & km == kv (the bits in km are known, with values kv), and,
when vs is not None, v in vs (a frozenset of at most SETMAX values).  The set keeps
non-convex facts an interval cannot: {$FF, $00} (a dec on one path, nothing on another)
becomes {$00, $01} after an inc, where an interval would have gone to 0..255.  None is
bottom (no value).  Normalised so the three agree as far as cheaply possible.  Flags are
0, 1 or None (unknown).

The 6502's operations are given exactly on the concrete level and soundly (an
over-approximation) on the abstract one: adc/sbc with carry in and carry/overflow out,
the shifts and rotates, the logic operations, compares.  On small sets they are exact.
"""

SETMAX = 32
TOP = (0, 255, 0, 0, None)


def C(v):
    v &= 0xFF
    return (v, v, 0xFF, v, None)


def isav(x):
    return isinstance(x, tuple) and len(x) == 5 and isinstance(x[0], int)


def _bits_of(vs):
    """the known bits common to a set of values"""
    vs = list(vs)
    km = 0xFF
    for v in vs[1:]:
        km &= ~(v ^ vs[0]) & 0xFF
    return km, vs[0] & km


def norm(lo, hi, km=0, kv=0, vs=None):
    if lo > hi:
        return None
    kv &= km
    if vs is not None:
        vs = frozenset(v for v in vs if lo <= v <= hi and (v & km) == kv)
        if not vs:
            return None
        if len(vs) == 1:
            v = next(iter(vs))
            return (v, v, 0xFF, v, None)
        if len(vs) > SETMAX:
            vs = None
        else:
            k2, v2 = _bits_of(vs)
            return (min(vs), max(vs), k2 | km, (v2 & k2) | kv, vs)
    lo2 = max(lo, kv)                       # the least value with the known bits
    hi2 = min(hi, kv | (~km & 0xFF))        # the greatest
    if lo2 > hi2:
        return None
    x = lo2 ^ hi2                           # the interval's common high bits are known
    p = 0xFF if x == 0 else (0xFF << x.bit_length()) & 0xFF
    if (kv & km & p) != (lo2 & p & km):
        return None
    km2 = km | p
    kv2 = (kv & km) | (lo2 & p)
    if lo2 == hi2:
        return (lo2, lo2, 0xFF, lo2, None)
    for _ in range(3):
        if (lo2 & km2) != kv2:
            lo2 = _next_fit(lo2, km2, kv2, up=True)
            if lo2 is None or lo2 > hi2:
                return None
        if (hi2 & km2) != kv2:
            hi2 = _next_fit(hi2, km2, kv2, up=False)
            if hi2 is None or hi2 < lo2:
                return None
    if lo2 == hi2:
        return (lo2, lo2, 0xFF, lo2, None)
    return (lo2, hi2, km2, kv2, None)


def _next_fit(v, km, kv, up):
    rng = range(v, 256) if up else range(v, -1, -1)
    for w in rng:
        if (w & km) == kv:
            return w
    return None


def single(a):
    return a is not None and a[0] == a[1]


def vset(a):
    """the value set (a frozenset) if the byte is small enough to list, else None"""
    if a is None:
        return frozenset()
    if a[4] is not None:
        return a[4]
    if a[0] == a[1]:
        return frozenset([a[0]])
    if a[1] - a[0] < SETMAX and a[2] == 0:
        return frozenset(range(a[0], a[1] + 1))
    if a[1] - a[0] < 4 * SETMAX:
        s = frozenset(v for v in range(a[0], a[1] + 1) if (v & a[2]) == a[3])
        return s if len(s) <= SETMAX else None
    return None


def from_set(vs):
    if not vs:
        return None
    if len(vs) > SETMAX:
        k, v = _bits_of(vs)
        return norm(min(vs), max(vs), k, v)
    return norm(min(vs), max(vs), 0, 0, vs)


def join(a, b):
    if a is None:
        return b
    if b is None:
        return a
    if a == b:
        return a
    sa, sb = vset(a), vset(b)
    if sa is not None and sb is not None and len(sa | sb) <= SETMAX:
        return from_set(sa | sb)
    km = a[2] & b[2] & ~(a[3] ^ b[3]) & 0xFF
    return norm(min(a[0], b[0]), max(a[1], b[1]), km, a[3] & km)


def meet(a, b):
    if a is None or b is None:
        return None
    if a[2] & b[2] & (a[3] ^ b[3]):
        return None
    sa, sb = a[4], b[4]
    vs = None
    if sa is not None and sb is not None:
        vs = sa & sb
    elif sa is not None:
        vs = sa
    elif sb is not None:
        vs = sb
    return norm(max(a[0], b[0]), min(a[1], b[1]), a[2] | b[2], (a[3] & a[2]) | (b[3] & b[2]), vs)


def leq(a, b):
    if a is None:
        return True
    if b is None:
        return False
    if b[4] is not None:
        sa = vset(a)
        return sa is not None and sa <= b[4]
    return b[0] <= a[0] and a[1] <= b[1] and (a[2] & b[2]) == b[2] and (a[3] & b[2]) == b[3]


def widen(old, new):
    if old is None:
        return new
    j = join(old, new)
    if j == old:
        return old
    # thresholds: a bound that moves goes to the next power-of-two boundary, not straight to
    # the end of the byte (0..80 widens to 0..127, not to 0..255)
    lo = j[0] if j[0] >= old[0] else max(0, (j[0] >> 1) and (1 << (j[0].bit_length() - 1)) - 1 or 0)
    hi = j[1] if j[1] <= old[1] else (1 << j[1].bit_length()) - 1
    if lo < old[0] and lo == j[0]:
        lo = 0
    return norm(lo, hi, j[2], j[3])        # (the set goes: widening is the interval's)


def contains(a, v):
    if a is None:
        return False
    if a[4] is not None:
        return v in a[4]
    return a[0] <= v <= a[1] and (v & a[2]) == a[3]


def values(a, limit=256):
    if a is None:
        return []
    if a[4] is not None:
        return sorted(a[4]) if len(a[4]) <= limit else None
    if a[1] - a[0] + 1 > 4 * limit and a[2] == 0:
        return None
    out = [v for v in range(a[0], a[1] + 1) if (v & a[2]) == a[3]]
    return out if len(out) <= limit else None


# ---------------------------------------------------------------- the flags of a value
def zero_of(a):
    if a is None:
        return None
    if a[0] == a[1] == 0:
        return 1
    if not contains(a, 0):
        return 0
    return None


def neg_of(a):
    if a is None:
        return None
    if a[0] >= 0x80:
        return 1
    if a[1] < 0x80:
        return 0
    if a[2] & 0x80:
        return (a[3] >> 7) & 1
    return None


def bit_of(a, n):
    if a is None:
        return None
    if a[2] & (1 << n):
        return (a[3] >> n) & 1
    if a[0] == a[1]:
        return (a[0] >> n) & 1
    return None


def signed(a):
    if a[4] is not None:
        s = [v - 256 if v > 127 else v for v in a[4]]
        return min(s), max(s)
    if a[1] < 0x80:
        return a[0], a[1]
    if a[0] >= 0x80:
        return a[0] - 256, a[1] - 256
    return -128, 127


# ---------------------------------------------------------------- tnum helpers
def _tn(a):
    return a[3] & a[2], ~a[2] & 0xFF


def _tn_add(av, am, bv, bm, n=9):
    lim = (1 << n) - 1
    sm = am + bm
    sv = av + bv
    sigma = sm + sv
    chi = sigma ^ sv
    mu = (chi | am | bm) & lim
    return (sv & ~mu) & lim, mu


def _bound_of_or(h):
    return (1 << h.bit_length()) - 1 if h else 0


def _flag(vals):
    s = set(vals)
    return s.pop() if len(s) == 1 else None


def _sets(*avs, limit=256):
    """the operands' value sets if all are small and the product of their sizes is small"""
    ss = [vset(a) for a in avs]
    if any(s is None for s in ss):
        return None
    n = 1
    for s in ss:
        n *= len(s)
    return ss if n <= limit else None


# ---------------------------------------------------------------- arithmetic
def add(a, b, c):
    """a + b + c (c: 0, 1 or None) -> (result, carry out, overflow)"""
    if a is None or b is None:
        return None, None, None
    cs = [c] if c in (0, 1) else [0, 1]
    ss = _sets(a, b, limit=128)
    if ss is not None:
        res, co, ov = set(), [], []
        for x in ss[0]:
            for y in ss[1]:
                for cc in cs:
                    s = x + y + cc
                    res.add(s & 0xFF); co.append(s >> 8)
                    sx = (x - 256 if x > 127 else x) + (y - 256 if y > 127 else y) + cc
                    ov.append(0 if -128 <= sx <= 127 else 1)
        return from_set(res), _flag(co), _flag(ov)
    cmin = 1 if c == 1 else 0
    cmax = 0 if c == 0 else 1
    slo = a[0] + b[0] + cmin
    shi = a[1] + b[1] + cmax
    if shi <= 255:
        r = (slo, shi); co = 0
    elif slo > 255:
        r = (slo - 256, shi - 256); co = 1
    else:
        r = (0, 255); co = None
    av, am = _tn(a)
    bv, bm = _tn(b)
    cv, cm = (c, 0) if c in (0, 1) else (0, 1)
    sv, sm = _tn_add(av, am, bv, bm)
    sv, sm = _tn_add(sv, sm, cv, cm)
    km = ~sm & 0xFF
    res = norm(r[0], r[1], km, sv & 0xFF)
    if co is None and not (sm & 0x100):
        co = (sv >> 8) & 1
    a0, a1 = signed(a)
    b0, b1 = signed(b)
    s0, s1 = a0 + b0 + cmin, a1 + b1 + cmax
    if s0 >= -128 and s1 <= 127:
        ov = 0
    elif s1 < -128 or s0 > 127:
        ov = 1
    else:
        ov = None
    if res is None:
        res = TOP
    return res, co, ov


def lnot(a):
    if a is None:
        return None
    vs = frozenset(255 - v for v in a[4]) if a[4] is not None else None
    return norm(255 - a[1], 255 - a[0], a[2], ~a[3] & a[2], vs)


def sub(a, b, c):
    return add(a, lnot(b), c)


def _setop(f, a, b):
    ss = _sets(a, b)
    if ss is None:
        return None
    return from_set({f(x, y) & 0xFF for x in ss[0] for y in ss[1]})


def land(a, b):
    if a is None or b is None:
        return None
    r = _setop(lambda x, y: x & y, a, b)
    if r is not None:
        return r
    hi = min(a[1], b[1])
    km = (a[2] & b[2]) | (a[2] & ~a[3]) | (b[2] & ~b[3])
    kv = a[3] & b[3]
    return norm(0, hi, km & 0xFF, kv & km)


def lor(a, b):
    if a is None or b is None:
        return None
    r = _setop(lambda x, y: x | y, a, b)
    if r is not None:
        return r
    lo = max(a[0], b[0])
    hi = _bound_of_or(a[1] | b[1])
    km = (a[2] & b[2]) | (a[2] & a[3]) | (b[2] & b[3])
    kv = (a[3] | b[3]) & km
    return norm(lo, min(hi, 255), km & 0xFF, kv)


def leor(a, b):
    if a is None or b is None:
        return None
    r = _setop(lambda x, y: x ^ y, a, b)
    if r is not None:
        return r
    hi = _bound_of_or(a[1] | b[1])
    km = a[2] & b[2]
    kv = (a[3] ^ b[3]) & km
    return norm(0, min(hi, 255), km, kv)


def asl(a, cin=0):
    """a << 1 | cin -> (result, carry out)"""
    if a is None:
        return None, None
    s = vset(a)
    if s is not None:
        cs = [cin] if cin in (0, 1) else [0, 1]
        res, co = set(), []
        for x in s:
            for cc in cs:
                v = x << 1 | cc
                res.add(v & 0xFF); co.append(v >> 8)
        return from_set(res), _flag(co)
    co = bit_of(a, 7)
    if a[1] < 0x80:
        lo, hi = 2 * a[0], 2 * a[1]
    elif a[0] >= 0x80:
        lo, hi = 2 * a[0] - 256, 2 * a[1] - 256
    else:
        lo, hi = 0, 254
    km = (a[2] << 1) & 0xFF
    kv = (a[3] << 1) & 0xFF
    if cin in (0, 1):
        km |= 1; kv |= cin
        lo += cin; hi += cin
    else:
        hi += 1
    return norm(lo, min(hi, 255), km, kv), co


def lsr(a, cin=0):
    """a >> 1 | cin << 7 -> (result, carry out)"""
    if a is None:
        return None, None
    s = vset(a)
    if s is not None:
        cs = [cin] if cin in (0, 1) else [0, 1]
        res, co = set(), []
        for x in s:
            for cc in cs:
                res.add(x >> 1 | cc << 7); co.append(x & 1)
        return from_set(res), _flag(co)
    co = bit_of(a, 0)
    lo, hi = a[0] >> 1, a[1] >> 1
    km = a[2] >> 1
    kv = a[3] >> 1
    if cin in (0, 1):
        km |= 0x80; kv |= cin << 7
        lo += cin << 7; hi += cin << 7
    else:
        hi += 0x80
    return norm(lo, min(hi, 255), km, kv), co


def cmp(a, b):
    """CMP a, b -> (C, Z, N, the difference)"""
    if a is None or b is None:
        return None, None, None, None
    ss = _sets(a, b)
    if ss is not None:
        cf, z, n, d = [], [], [], set()
        for x in ss[0]:
            for y in ss[1]:
                cf.append(1 if x >= y else 0); z.append(1 if x == y else 0)
                n.append(((x - y) >> 7) & 1); d.add((x - y) & 0xFF)
        return _flag(cf), _flag(z), _flag(n), from_set(d)
    d, c, _ = sub(a, b, 1)
    if a[0] >= b[1]:
        cf = 1
    elif a[1] < b[0]:
        cf = 0
    else:
        cf = c
    if single(a) and single(b):
        z = 1 if a[0] == b[0] else 0
    elif meet(a, b) is None:
        z = 0
    else:
        z = None
    return cf, z, neg_of(d), d


# ---------------------------------------------------------------- refinement
def refine_lt(a, b):
    if a is None or b is None:
        return None
    return meet(a, norm(0, b[1] - 1)) if b[1] > 0 else None


def refine_ge(a, b):
    if a is None or b is None:
        return None
    return meet(a, norm(b[0], 255))


def refine_eq(a, b):
    return meet(a, b)


def refine_ne(a, b):
    if a is None or b is None:
        return None
    if single(b):
        v = b[0]
        s = vset(a)
        if s is not None:
            return from_set(s - {v})
        if a[0] == v:
            return norm(v + 1, a[1], a[2], a[3]) if v < 255 else None
        if a[1] == v:
            return norm(a[0], v - 1, a[2], a[3]) if v > 0 else None
    return a


def refine_zero(a, z):
    return meet(a, C(0)) if z == 1 else refine_ne(a, C(0))


def refine_neg(a, n):
    return meet(a, norm(0x80, 0xFF)) if n == 1 else meet(a, norm(0, 0x7F))


# ---------------------------------------------------------------- text
def fmt(a):
    if a is None:
        return '⊥'
    if a[0] == a[1]:
        return f'${a[0]:02X}'
    if a[4] is not None:
        vs = sorted(a[4])
        if vs == list(range(vs[0], vs[-1] + 1)):
            return f'{vs[0]}..{vs[-1]}'
        return '{' + ','.join(f'${v:02X}' if v > 9 else str(v) for v in vs) + '}'
    if a[:4] == TOP[:4]:
        return '?'
    s = f'{a[0]}..{a[1]}'
    x = a[0] ^ a[1]
    p = 0xFF if x == 0 else (0xFF << x.bit_length()) & 0xFF
    extra = a[2] & ~p & 0xFF
    if extra:
        bits = ''.join(('1' if a[3] >> k & 1 else '0') if extra >> k & 1 else 'x'
                       for k in range(7, -1, -1))
        s += f' %{bits}'
    return s


if __name__ == '__main__':
    import random
    random.seed(1)
    def rand_av():
        k = random.random()
        if k < 0.3:
            vs = random.sample(range(256), random.randint(2, 6))
            return from_set(set(vs))
        lo = random.randint(0, 255); hi = random.randint(lo, min(255, lo + random.choice([0, 1, 3, 15, 80, 255])))
        km = random.choice([0, 0, 0x0F, 0xF0, 0x01, 0x80, random.randint(0, 255)])
        v = random.randint(lo, hi)
        return norm(lo, hi, km, v & km)
    def conc(a):
        if a is None:
            return []
        return [v for v in range(a[0], a[1] + 1) if contains(a, v)]
    bad = 0
    for _ in range(4000):
        a, b = rand_av(), rand_av()
        if a is None or b is None:
            continue
        for c in (0, 1, None):
            r, co, ov = add(a, b, c)
            for x in conc(a)[:40]:
                for y in conc(b)[:40]:
                    for cc in ([c] if c is not None else [0, 1]):
                        s = x + y + cc
                        if not contains(r, s & 255) or (co is not None and co != s >> 8):
                            bad += 1
                        sx = (x - 256 if x > 127 else x) + (y - 256 if y > 127 else y) + cc
                        if ov is not None and ov != (0 if -128 <= sx <= 127 else 1):
                            bad += 1
            r, co, ov = sub(a, b, c)
            for x in conc(a)[:20]:
                for y in conc(b)[:20]:
                    for cc in ([c] if c is not None else [0, 1]):
                        s = x - y - (1 - cc)
                        if not contains(r, s & 255) or (co is not None and co != (1 if s >= 0 else 0)):
                            bad += 1
        for op, f in ((land, lambda x, y: x & y), (lor, lambda x, y: x | y), (leor, lambda x, y: x ^ y)):
            r = op(a, b)
            for x in conc(a)[:30]:
                for y in conc(b)[:30]:
                    if not contains(r, f(x, y)):
                        bad += 1
        for cin in (0, 1, None):
            r, co = asl(a, cin)
            for x in conc(a):
                for cc in ([cin] if cin is not None else [0, 1]):
                    v = (x << 1 | cc)
                    if not contains(r, v & 255) or (co is not None and co != v >> 8):
                        bad += 1
            r, co = lsr(a, cin)
            for x in conc(a):
                for cc in ([cin] if cin is not None else [0, 1]):
                    v = x >> 1 | cc << 7
                    if not contains(r, v) or (co is not None and co != x & 1):
                        bad += 1
        j = join(a, b)
        for x in conc(a) + conc(b):
            if not contains(j, x):
                bad += 1
        m = meet(a, b)
        for x in conc(a):
            if contains(b, x) and not contains(m, x):
                bad += 1
        w = widen(a, b)
        for x in conc(a) + conc(b):
            if not contains(w, x):
                bad += 1
        cf, z, n, d = cmp(a, b)
        for x in conc(a)[:30]:
            for y in conc(b)[:30]:
                if cf is not None and cf != (1 if x >= y else 0): bad += 1
                if z is not None and z != (1 if x == y else 0): bad += 1
                if n is not None and n != ((x - y) >> 7 & 1): bad += 1
                if not contains(d, (x - y) & 255): bad += 1
        for y in conc(b)[:10]:
            bb = C(y)
            for x in conc(a):
                if x < y and not contains(refine_lt(a, bb), x): bad += 1
                if x >= y and not contains(refine_ge(a, bb), x): bad += 1
                if x != y and not contains(refine_ne(a, bb), x): bad += 1
    # the case that motivated the sets
    s = join(C(0xFF), C(0))
    r = add(s, C(1), 0)[0]
    assert fmt(r) == '0..1', fmt(r)
    print('dom self-test: bad', bad)
