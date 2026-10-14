#!/usr/bin/env python3
"""Write the band's generated source into build/: its fixed geometry and tables, and
the code that the fixed geometry lets us specialise.  The band is proto/ragged.py's.

    python3 tools/gentab.py build

tables.inc   ROWn_X0, ROWn_DX, ROWn_Y0: each row's first x, spacing, first y
             (NTAB, Q12, TC1 in segment LOW1, R12, TC2 in LOW2, TC3 in LOW3: copied
             to low memory at the start)
             NTAB: 256 normal steps (sd = prototype SD), by a random byte
             NPAL, DITHE, DITHO: the dither palette (tools/palette.py)
             Q12, R12: n div 12 and PI12[n mod 24], for rungs 12 wide
             TC1, TC2, TC3: the top row's offsets at a byte column's pixels 1-3
             from its first, by column in its segment * (MAXDY + 1) + |dy|
             RUNGA: each rung's width
             PAT4, PAT8, PAT12A/B, PAT16A/B: a rung's carries by dy mod 2a (down)
across.inc   the rows, straight-line: the top row's segment looks its shape up by
             y0 - y1 (TOPVT: SEGV = 2 |dy| + rising) and steps from its first y to each
             byte column's (TOPC) by a table per column (TSj) by shape; the bottom row's
             each column's lowest y + 1 (BOTC), by 2 |dy| + 1 falling or 2 |dy| - 2 rising
             (TBj).
             Then the TOPs: a routine per byte column top shape (the pixels the top
             row steps at, and which way), making the lines above the column's first
             full one (each entered in page TOPPG); and TBLjL, for column j of a segment,
             its TOP's low byte in TOPPG (0: none) by SEGV.
down.inc     the rungs: for each pixel a rung passes, the first line where it changes
             sides (RT), an unrolled walk per rung (each steep, its direction fixed)
fillcols.inc the fill's columns, each with its kind and boxes
"""
import os
import sys
from statistics import NormalDist

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'proto'))
sys.path.insert(0, os.path.dirname(__file__))
import points as P  # noqa: E402
import palette as PL  # noqa: E402

WIDE = int(os.environ.get('WIDE', 0))   # rungs wider than this are walked (all)
PAIR = int(os.environ.get('PAIR', 1))   # neighbouring one-box columns filled together


def row(fmt, vals):
    return ['        .byte ' + ', '.join(fmt % v for v in vals[i:i + 16])
            for i in range(0, len(vals), 16)]


def geometry():
    xs = []
    for cx, spacing, y0 in P.ROWS:
        x0 = cx - spacing * ((P.N - 1) // 2)
        xs.append([x0 + spacing * i for i in range(P.N)])
    assert all(x % 4 == 0 for r in xs for x in r), 'row vertices must be byte aligned'
    return xs


def cums(dx, d, j):
    """The top row's offsets (unsigned) at column j's pixels from its first."""
    ys = P.bresenham_ys(0, 0, dx, d)
    return [ys[4 * j + p] - ys[4 * j] for p in range(4)]


def topmasks(dx, v, j, side=None):
    """Column j's top under a segment of shape v: how many lines above its first y
    its first store is, and its partial lines' pixels from there.  side: 'L' or 'R'
    for a column of a pair (pone in main.s), whose run starts at the pair's first
    full line; the later column then has one black line above it to put back when
    the top row steps between the two."""
    d, rising = v // 2, v & 1
    cum = cums(dx, d, j)
    n = cum[3]
    if rising:              # lines t0-n .. t0-1: the pixels n-k or more up
        masks = [sum(0x88 >> p for p in range(4) if cum[p] >= n - k) for k in range(n)]
    else:                   # lines t0 .. t0+n-1: the pixels k or fewer down
        masks = [sum(0x88 >> p for p in range(4) if cum[p] <= k) for k in range(n)]
    off = n if rising else 0
    ys = P.bresenham_ys(0, 0, dx, d)
    if side == 'L' and rising and ys[4 * j + 4] != ys[4 * j + 3]:
        masks, off = [0] + masks, off + 1
    if side == 'R' and not rising and ys[4 * j] != ys[4 * j - 1]:
        masks, off = [0] + masks, off + 1
    return (off, tuple(masks))


def topcode(off, masks):
    """A TOP's body: X steps by k first (k of off), then each PART i reads its line's
    address at an offset from X (LINEL+d,x: d < 0 crosses a page, a cycle a table);
    then X steps to the first full line, X in - off + len(masks).  The cheapest k."""
    def step(n):
        if n == 0:
            return [], 0
        if abs(n) <= 3:
            return [f'        {"inx" if n > 0 else "dex"}'] * abs(n), 2 * abs(n)
        return ['        txa', '        clc' if n > 0 else '        sec',
                f'        {"adc" if n > 0 else "sbc"} #{abs(n)}', '        tax'], 8
    best = None
    for k in range(off + 1):
        pre, cp = step(-k)
        ds = [i - off + k for i in range(len(masks))]
        post, cq = step(len(masks) - off + k)
        cost = cp + cq + 2 * sum(d < 0 for d in ds)
        if best is None or cost < best[0]:
            best = (cost, pre + [f'        PART ${m:02X}, {d}' for m, d in zip(masks, ds)] + post)
    return best[1]


def pairmin(dx, v, j):
    """A pair's (columns j, j+1 of a segment of shape v) first full line, from
    column j's first y: its pixel 3's when falling, else pixel 4's (mod 256)."""
    ys = P.bresenham_ys(0, 0, dx, v // 2)
    return abs(ys[4 * j + (4 if v & 1 else 3)] - ys[4 * j]) * (-1 if v & 1 else 1) & 0xFF


def tables(xs, ntab, maxdy):
    out = []
    for r, (cx, spacing, y0) in enumerate(P.ROWS):
        out += [f'ROW{r}_X0 = {xs[r][0]}', f'ROW{r}_DX = {spacing}', f'ROW{r}_Y0 = {y0}']
    out += [f'NPAL = {len(PL.PALETTE)}', f'MAXDY = {maxdy}']
    pad = [0] * (16 - len(PL.PALETTE))
    dithe = [PL.byte(i, 0) for i in range(len(PL.PALETTE))] + pad
    ditho = [PL.byte(i, 1) for i in range(len(PL.PALETTE))] + pad
    q12 = [a // 12 for a in range(160)]
    dx0 = P.ROWS[0][1]
    tc = [[cums(dx0, d, j)[p] for j in range(dx0 // 4) for d in range(maxdy + 1)] for p in range(4)]
    runga = [abs(b - a) for a, b in zip(*xs)]
    pats = []
    for a in (4, 8, 12, 16):
        cs = [rungcarries(a, r) for r in range(2 * a)]
        gx, gy, rest = carryregs(a)           # X = PIa[r]: r = 0 first, then by gx's carry, so
        order = sorted(range(2 * a), key=lambda r: (r > 0, cs[r][gx[0] - 1], r))
        pi = [order.index(r) for r in range(2 * a)]   # cpx #1: r > 0, cpx #TPIa: gx's
        if a == 12:                           # R12: by n, PI12[n mod 24]
            r12 = [pi[n % 24] for n in range(160)]
        else:
            pats.append((f'PI{a}', pi))
        pats.append((f'PY{a}', [cs[r][gy[0] - 1] for r in order]))   # Y = PYa[X]: gy's (cpy #1)
        out.append(f'TPI{a} = {sum(1 for c in cs if not c[gx[0] - 1])}')
        for j in rest:                        # the rest: each its carry by X (CRa_j)
            if restkey(a, j) == j:
                pats.append((f'CR{a}_{j}', [cs[r][j - 1] for r in order]))
    # by segment: the load image's, and LOW1-3, copied to low memory at the start
    for seg, name, vals in (('RODATA', 'DITHE', dithe), ('RODATA', 'DITHO', ditho),
                            ('RODATA', 'RUNGA', runga), ('LOW1', 'NTAB', [v & 0xFF for v in ntab]),
                            ('LOW1', 'Q12', q12), ('LOW1', 'TC1', tc[1]), ('LOW2', 'R12', r12),
                            ('LOW2', 'TC2', tc[2]), ('LOW3', 'TC3', tc[3])) + \
            tuple(('RODATA', n, v) for n, v in pats):
        out += [f'        .segment "{seg}"']
        if name == 'DITHE':                 # (with DITHO: one 32-byte block, no page crossed)
            out.append('        .align 32')
        out.append(f'{name}:')
        out += row('$%02X', vals)
    out.append('        .rodata')
    return out


def across(xs, maxdy, pairs):
    out = []
    dx0, dx1 = P.ROWS[0][1], P.ROWS[1][1]
    # The rows straight, no routine per |dy|: each column's value the last one's plus
    # a step looked up by the segment's shape (X), ADC's carry kept track of here (a
    # step's carry out is set iff it goes down by more than the carry in).
    def steps(targets, c):
        out = []
        for a, b in zip(targets, targets[1:]):
            e = b - a - c
            out.append(e & 0xFF)
            c = int(e < 0)
        return out
    k = maxdy + 1
    ncode = 2 * maxdy + 2
    ts = [[0] * ncode for _ in range(dx0 // 4 - 1)]   # top: by SEGV, from the first y
    for v in range(ncode):
        d, rise = v // 2, v & 1
        ys = P.bresenham_ys(0, 0, dx0, d)
        sg = -1 if rise else 1
        if v == 0:
            continue
        for i, e in enumerate(steps([sg * ys[4 * j] for j in range(dx0 // 4)], rise)):
            ts[i][v] = e
    tb = [[0] * ncode for _ in range(dx1 // 4)]       # bottom: by 2|dy| + 1 falling (C set),
    for v in range(ncode):                            # 2|dy| - 2 rising (C clear), from y0
        fall = v & 1
        d = v // 2 if fall else v // 2 + 1
        if d > maxdy:
            continue
        ys = P.bresenham_ys(0, 0, dx1, d)
        tg = [ys[4 * j + 3] + 1 if fall else 1 - ys[4 * j] for j in range(dx1 // 4)]
        for i, e in enumerate(steps([0] + tg, fall)):
            tb[i][v] = e
    def topv(y):                              # by y0 - y1
        d, rise = (y, 1) if y < 128 else (256 - y, 0)
        return f'${2 * d + rise:02X}'
    def botv(y):                              # by y1 - y0
        return f'${2 * y + 1:02X}' if y < 128 else f'${2 * (256 - y) - 2:02X}'
    tabs = [(f'TS{i + 1}', vals) for i, vals in enumerate(ts)] + \
        [(f'TB{i}', vals) for i, vals in enumerate(tb)]
    for name, ent in (('TOPVT', topv), ('BOTVT', botv)):   # each by a y difference mod 256,
        out += ['        .align 256', f'{name}:']          # in a page of its own (no page
        out += row('%s', [ent(y) for y in range(k)])       # crossed), the steps between
        gap, at = 256 - maxdy - k, 0
        while tabs and at + ncode <= gap:
            tn, vals = tabs.pop(0)
            out += [f'{tn}:'] + row('$%02X', vals)
            at += ncode
        out.append(f'        .res {gap - at}')
        out += row('%s', [ent(y) for y in range(256 - maxdy, 256)])
    assert not tabs
    uses = [(j, None) for j in range(dx0 // 4)] + [(j, 'L') for j in sorted(pairs)] + \
        [(j + 1, 'R') for j in sorted(pairs)]
    tops, index = [], {}
    for j, side in uses:
        for v in range(2 * maxdy + 2):
            key = topmasks(dx0, v, j, side)
            if key not in index:
                index[key] = len(tops)
                tops.append(key)
    # One page (TOPPG) holds every TOP's entry, so TBLj needs only the low byte (0:
    # level, no TOP): the one-line TOPs in it, a JMP to each of the others.
    hot = [k for k in range(len(tops)) if len(tops[k][1]) == 1]
    cold = [k for k in range(len(tops)) if len(tops[k][1]) > 1]
    out += ['        .align 256', 'TOPPG:  .byte 0                    ; (0: level)']

    def topk(k):
        out.append(f'TOP{k}:')               # X = the column's first y; X: its first full line
        out.extend(topcode(*tops[k]))
        out.append('        rts')
    for k in hot:
        topk(k)
    out += [f'TOPJ{k}: jmp TOP{k}' for k in cold]
    out += ['TOPPGE:', '        .assert >(TOPPGE - 1) = >TOPPG, error, "TOPPG over a page"']
    for k in cold:
        topk(k)
    for j, side in uses:
        keys = [index[topmasks(dx0, v, j, side)] for v in range(2 * maxdy + 2)]
        out.append(f'TBL{side or ""}{j}L:')
        out += row('%s', ['0' if not tops[k][1] else f'<TOP{k}' if k in hot else f'<TOPJ{k}'
                          for k in keys])
    for j in sorted(pairs):
        out.append(f'PMIN{j}:')
        out += row('$%02X', [(pairmin(dx0, v, j) - 1) & 0xFF for v in range(2 * maxdy + 2)])
    out.append('across:')
    def y0(r, s):                             # (each row's first y is fixed)
        return f'#ROW{r}_Y0' if s == 0 else f'PTS{r}+{2*s+1}'
    for s in range(P.N - 1):
        cs = xs[0][s] // 4
        out += [f'        lda {y0(0, s)}', '        sec', f'        sbc PTS0+{2*s+3}',
                '        tay', '        ldx TOPVT,y', f'        stx SEGV+{s}',
                f'        lda {y0(0, s)}', f'        sta TOPC+{cs}']
        for j in range(1, dx0 // 4):
            out += [f'        adc TS{j},x', f'        sta TOPC+{cs + j}']
    for s in range(P.N - 1):
        cs = xs[1][s] // 4
        out += [f'        lda PTS1+{2*s+3}', '        sec', f'        sbc {y0(1, s)}',
                '        tay', '        ldx BOTVT,y', f'        lda {y0(1, s)}']
        for j in range(dx1 // 4):
            out += [f'        adc TB{j},x', f'        sta BOTC+{cs + j}']
    out.append('        rts')
    return out


def rungcarries(a, r):
    """A rung a wide with dy mod 2a = r: whether each pixel after its first steps
    one line more than dy div a (its first pixel: one more than dy div 2a, if r)."""
    out = []
    for j in range(1, a):
        c = -(-(2 * j + 1) * r // (2 * a)) + (-(2 * j - 1) * r // (2 * a)) - r // a
        assert c in (0, 1)
        out.append(c)
    return out


def restkey(a, j):
    """The first pixel of a rung a wide with the same carries as pixel j (CRa_j)."""
    cs = [rungcarries(a, r) for r in range(2 * a)]
    return next(k for k in range(1, a) if all(c[k - 1] == c[j - 1] for c in cs))


def carryregs(a):
    """A rung a wide's later pixels (j = 1..a-1) by where their carries come from: gx
    (cpx), the largest set with the same carry for every r, gy (cpy) the next, then the
    rest (pat)."""
    cs = [rungcarries(a, r) for r in range(2 * a)]
    groups = []
    for j in range(1, a):
        g = [k for k in range(1, a) if all(c[k - 1] == c[j - 1] for c in cs)]
        if g not in groups:
            groups.append(g)
    groups.sort(key=lambda g: -len(g))
    gx, gy = groups[0], groups[1]
    return gx, gy, [j for j in range(1, a) if j not in gx + gy]


def down(xs):
    """For each pixel x a rung passes (left of its right end), the first line RT[x]
    where B(y) <= x changes: with a = |dx| and j counting pixels from the top point,
    the top point's y + ceil((2j - 1) dy / 2a).  So the first pixel's is the top
    point's y + ceil(dy / 2a), and each next one's dy div a more, plus a carry
    that depends only on dy mod 2a: from cpx/cpy for two sets of pixels, and
    for the rest from its own table by X (CRa_j)."""
    out = ['down:']
    for i, (xt, xb) in enumerate(zip(*xs)):
        a = abs(xb - xt)
        if not a:
            continue
        xs_ = [xt - j if xb < xt else xt + j - 1 for j in range(1, a + 1)]
        if i == 0:                            # both its points the rows' first: fixed
            import ragged as R
            rt = R.transitions(xt, P.ROWS[0][2], xb, P.ROWS[1][2])
            for x in xs_:
                out += [f'        lda #{rt[x]}', f'        sta RT+{x}']
            continue
        out += [f'        lda PTS1+{2*i+1}', '        sec', f'        sbc PTS0+{2*i+1}',
                f'        RUNGSET {a}, PTS0+{2*i+1}']
        for j, x in enumerate(xs_):
            if j:
                gx, gy, rest = carryregs(a)
                if j in gx:
                    out.append(f'        cpx #TPI{a}')
                elif j in gy:
                    out.append('        cpy #1')
                else:                       # (C clear: no sum reaches 256)
                    out.append(f'        adc CR{a}_{restkey(a, j)},x')
                out.append('        adc rq')
            out.append(f'        sta RT+{x}')
    out.append('        rts')
    out.append('        .res 68                    ; (rung 0\'s RUNGSET and carries, now constants: the code after keeps its place)')
    return out


def columns(xs):
    """Each byte column with anything in it:
    ONE b      box b, from the top row
    ONE_R d    black above the rung's line, box d below (the band's two ends)
    TWO u, d   box u above the rung's line, d below
    with, under the top row, its segment and column in it; on a rung, which way
    the rung leans (L: its bottom to the left)."""
    cols = []
    rungs = list(zip(*xs))
    first = min(xs[0][0], xs[1][0]) // 4
    last = (max(xs[0][-1], xs[1][-1]) - 1) // 4
    for c in range(first, last + 1):
        px = range(4 * c, 4 * c + 4)
        on = [i for i, (xt, xb) in enumerate(rungs) if min(xt, xb) <= px[0] < max(xt, xb)]
        seg = None
        if xs[0][0] <= px[0] and px[3] < xs[0][-1]:
            s = (px[0] - xs[0][0]) // P.ROWS[0][1]
            seg = (s, (px[0] - xs[0][s]) // 4)
        if on:
            i = on[0]
            xt, xb = rungs[i]
            assert all(min(xt, xb) <= x < max(xt, xb) for x in px)
            lean = 'L' if xb < xt else 'R'
            u, d = (i - 1, i) if lean == 'L' else (i, i - 1)
            wide = int(abs(xb - xt) > WIDE)
            assert (lean == 'L') == (c < 32), 'rwalk: the half is fixed by the lean'
            # the column whose rung lines come first walks its box above too (pre),
            # the one whose come last its box below (suf): those are short
            first, last = px[0] == max(xt, xb) - 4, px[0] == min(xt, xb)
            pre, suf = (first, last) if lean == 'L' else (last, first)
            if u in (-1, 8):
                assert seg is None or px[0] == xs[0][-1]
                cols.append((c, 'ONE_R', (8, d), None, (lean, wide, 0, int(wide and suf))))
            else:
                assert seg
                cols.append((c, 'TWO', (u, d), seg,
                             (lean, wide, int(wide and pre), int(wide and suf))))
        else:
            assert seg, c
            b = sum(max(xt, xb) <= px[0] for xt, xb in rungs) - 1
            cols.append((c, 'ONE', (b, b), seg, None))
    return cols


def pairup(cols):
    """The columns, a one-box column followed by another of the same box and segment
    made a pair (kind PAIR, the first's details)."""
    out, i = [], 0
    while i < len(cols):
        c, kind, ud, seg, lean = cols[i]
        if PAIR and kind == 'ONE' and i + 1 < len(cols):
            c2, kind2, ud2, seg2, _ = cols[i + 1]
            if kind2 == 'ONE' and ud2 == ud and seg2[0] == seg[0] and c2 != 32:
                out.append((c, 'PAIR', ud, seg, None))
                i += 2
                continue
        out.append(cols[i])
        i += 1
    return out


def nested(need, ks, name):
    """Stores (c, y): the set of keys each is needed at, nested: ordered so that each
    key's are a suffix.  The list (FxSn) and its entries by key (FxL, FxH)."""
    order = sorted(need, key=lambda st: (len(need[st]), st))
    ent = {}
    for k in ks:
        i = next((i for i, st in enumerate(order) if k in need[st]), len(order))
        assert all(k in need[st] for st in order[i:]), 'nested'
        ent[k] = i
    return order, ent


def fixedrung(xs, maxdy):
    """The band's left end: rung 0 (columns ONE_R lean L) has both its points the
    rows' first, fixed, so its lines are too; its columns' bottoms, and the next
    one-box columns' (box 0 as well, wholly under both rows' first segments), depend
    only on the bottom row's second y (PTS1+3), and those columns' first full lines
    only on the top row's (PTS0+3).  Straight stores: by one entry (by PTS1+3) into
    a list of stores ordered so that every bottom's is a suffix (A = de, X = do), then
    the rung's sub-runs (de, do masked), then by PTS0+3 the one-box columns' lines from
    their first full line (the same way); then those columns' tops.  Never messy
    (asserted for every dy).  Replaces those columns' SETUD, RPREP, ONERs, SETC,
    PONE and ONE."""
    import ragged as R
    (xt, yt), (xb, yb) = (xs[0][0], P.ROWS[0][2]), (xs[1][0], P.ROWS[1][2])
    assert xb < xt
    rt = R.transitions(xt, yt, xb, yb)
    cs = list(range(xb // 4, xt // 4))
    x1, t1 = xs[1][1], xs[0][1]
    ocs = [c for c in range(xt // 4, x1 // 4) if 4 * c + 3 < x1 and 4 * c + 3 < t1]
    dx0 = P.ROWS[0][1]

    def addr(c, y):
        return 0x5800 + (y >> 3) * 512 + (y & 7) + 8 * c

    def botc(d, c):
        ly = P.line_ys(xb, yb, x1, yb + d)
        return max(ly[x] for x in range(4 * c, 4 * c + 4)) + 1

    def first(t, c):                                # the column's first full line (TOP's X out)
        top = P.line_ys(xt, yt, t1, yt + t)[4 * c]
        off, masks = topmasks(dx0, 2 * abs(t) + (t <= 0), (4 * c - xt) // 4)
        return top - off + len(masks)
    bx = [i for i, (a, b) in enumerate(zip(*xs)) if a != b][0]    # (its box below: 0)
    ks = range(-maxdy, maxdy + 1)
    mid = {c: min(botc(d, c) for d in ks) for c in ocs}
    for c in ocs:
        assert max(first(t, c) for t in ks) <= mid[c]
    need = {}                                       # bottoms: (c, y) by dy
    for d in ks:
        for c in cs:
            assert botc(d, c) >= rt[4 * c], 'the left end never messy'
            for y in range(rt[4 * c], botc(d, c)):
                need.setdefault((c, y), set()).add(d)
        for c in ocs:
            for y in range(mid[c], botc(d, c)):
                need.setdefault((c, y), set()).add(d)
    border, bent = nested(need, ks, 'FX')
    need = {}                                       # the one-box columns' upper lines by dy
    for t in ks:
        for c in ocs:
            for y in range(first(t, c), mid[c]):
                need.setdefault((c, y), set()).add(t)
    torder, tent = nested(need, ks, 'FT')
    masked = []
    for k, m in enumerate((0x11, 0x33, 0x77)):     # sub-run k: pixels 3-k.. below
        for par, src in ((0, 'tya'), (1, 'txa')):
            ys = [(c, y) for c in cs for y in range(rt[4 * c + 3 - k], rt[4 * c + 2 - k]) if y & 1 == par]
            if ys:
                masked += [f'        {src}', f'        and #${m:02X}']
                masked += [f'        sta ${addr(c, y):04X}' for c, y in ys]
    out = ['        ; the left end, fixed (only de, do, ce, co set: nothing else reads',
           '        ; the rest before the next SETUD sets it)',
           '        ldx PTS1+3', f'        lda FXL-{yb - maxdy},x', '        sta fxj+1',
           f'        lda FXH-{yb - maxdy},x', '        sta fxj+2',
           '        ldx PTS0+3', f'        lda FTL-{yt - maxdy},x', '        sta ftj+1',
           f'        lda FTH-{yt - maxdy},x', '        sta ftj+2',
           f'        ldx BOXC+{bx}', '        lda DITHE,x', '        sta de', '        sta ce',
           '        tay', '        lda DITHO,x', '        sta do', '        sta co', '        tax',
           '        tya', 'fxj:    jmp $FFFF',
           '        .pushseg', '        .rodata']        # (out of the way: the code after
    for nm, order, ent in (('FX', border, bent), ('FT', torder, tent)):   # fill keeps its place)
        for i, k in enumerate(order):
            out.append(f'{nm}S{i}:   {"sta" if k[1] % 2 == 0 else "stx"} ${addr(*k):04X}')
        out.append(f'{nm}S{len(order)}:')
        if nm == 'FX':
            out += masked
            out += ['        tya', 'ftj:    jmp $FFFF']
    out += ['        jmp fxe']
    for nm, ent in (('FX', bent), ('FT', tent)):
        out.append(f'{nm}L:')
        out += row('%s', [f'<{nm}S{ent[k]}' for k in ks])
        out.append(f'{nm}H:')
        out += row('%s', [f'>{nm}S{ent[k]}' for k in ks])
    out += ['        .popseg', 'fxe:']
    for c in ocs:
        out += [f'        lda #<(8 * {c})', '        sta coff', f'        TOP {c}, 0, {(4 * c - xt) // 4}, ""']
    return out, cs + ocs


def fillcols(cols, xs, maxdy):
    fixed, fcs = fixedrung(xs, maxdy)
    out = []
    last = lastr = tg = None
    ce_ok = True
    hold = {'c': None, 'u': None, 'd': None}   # the box whose bytes are in ce/co, ue/uo, de/do
    for i, (c, kind, ud, seg, lean) in enumerate(cols):
        if c == 32 or (kind == 'PAIR' and c == 31):
            out.append('        SETHALF 1')
        out.append(f'        ; column {c}: {kind} {ud} {seg} {lean}')
        if c in fcs:                      # (the left end: one piece)
            if c == fcs[0]:
                out += fixed
            hold = {'c': ud[1], 'u': None, 'd': ud[1]}
            last, lastr, tg = ud, None, 'u'
            continue
        if ud != last:
            grp = [k for _, k, u, _, _ in cols[i:]]
            grp = grp[:next((g for g, (_, _, u, _, _) in enumerate(cols[i:]) if u != ud), len(grp))]
            if kind in ('ONE', 'PAIR'):     # (where box b's bytes are already)
                src = (4 if hold['u'] == ud[0] else 1) if hold['c'] == ud[0] else 2 if hold['u'] == ud[0] else \
                    3 if hold['d'] == ud[0] else 0
                out.append(f'        SETC {ud[0]}, {int("ONE" in grp)}, {src}')
                assert src != 2                   # (ue, uo are ce, co: never apart)
                if hold['c'] != ud[0]:
                    hold['u'] = None              # ue, uo spoilt with ce, co (ut: no
                hold['c'] = ud[0]                 # use without them, src 4)
            else:
                out.append(f'        SETUD {ud[0]}, {ud[1]}, {int(hold["c"] == ud[0])}, '
                           f'{int(hold["c"] == ud[1])}')
                hold = {'c': ud[0], 'u': ud[0], 'd': ud[1]}
                if ud[0] == 8:                # black above: no ut, dt
                    assert all(k == 'ONE_R' for k in grp)
            tg = 'd' if ud[0] == 8 else 'u'   # tgl: the box above's (SETUD; dt if black), or the box's
            ce_ok = True                  # ce: set by SETC/SETUD, spoilt by rrun
            last, lastr = ud, None
        if lean and lean[:2] != lastr:
            assert out[-1].startswith('        SETUD')   # RPREP takes xe, xo in Y, X
            out.append(f'        RPREP {lean[0]}, {lean[1]}, {int(ud[0] == 8)}')   # (one per lean and width: lastr)
            lastr = lean[:2]
        assert kind == 'ONE_R' or ce_ok   # the TWO before ran rrun (no ue in ce)
        if kind == 'TWO' and not lean[1]:
            ce_ok = False
        if lean and not lean[1]:
            hold['c'] = None              # rrun spoils ce
        if kind == 'ONE':
            out.append(f'        ONE {c}, {seg[0]}, {seg[1]}')
        elif kind == 'PAIR':
            out.append(f'        PONE {c}, {seg[0]}, {seg[1]}')
        elif kind == 'TWO':
            out.append(f'        TWO {c}, {seg[0]}, {seg[1]}, {lean[0]}, {lean[1]}, {int(tg == "u")}, '
                       f'{lean[2]}, {lean[3]}')
        else:
            out.append(f'        ONER {c}, {lean[0]}, {lean[1]}, {int(tg == "d")}, {lean[3]}')
        tg = 'd' if kind in ('TWO', 'ONE_R') else ('u' if kind == 'ONE' else tg)
    return out


def main():
    nd = NormalDist(0, P.SD)
    ntab = [round(nd.inv_cdf((i + 0.5) / 256)) for i in range(256)]
    maxdy = max(abs(v) for v in ntab)
    xs = geometry()
    assert maxdy < min(r[1] for r in P.ROWS), 'rows must be shallow'
    cols = pairup(columns(xs))
    pairs = {seg[1] for c, kind, ud, seg, lean in cols if kind == 'PAIR'}
    files = {'tables.inc': tables(xs, ntab, maxdy), 'across.inc': across(xs, maxdy, pairs),
             'down.inc': down(xs), 'fillcols.inc': fillcols(cols, xs, maxdy)}
    for name, lines in files.items():
        with open(os.path.join(sys.argv[1], name), 'w') as f:
            f.write('; generated by tools/gentab.py\n' + '\n'.join(lines) + '\n')


main()
