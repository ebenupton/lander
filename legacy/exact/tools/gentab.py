#!/usr/bin/env python3
"""Write the band's generated source into build/: its fixed geometry and tables, and
the code that the fixed geometry lets us specialise.

    python3 tools/gentab.py build

tables.inc   ROWn_X0, ROWn_DX, ROWn_Y0: each row's first x, spacing, first y
             NTAB: 256 normal steps (sd = prototype SD), by a random byte
             NPAL, DITHE, DITHO: the dither palette (tools/palette.py), each colour's
             byte on even and odd lines, 16 entries, black past NPAL
             Q12, R12: a rung of width 12's whole step and twice its remainder, by |dy|
across.inc   the rows' interpolation.  A segment's Bresenham steps depend only on its
             width (fixed per row) and |dy| (at most MAXDY, from NTAB), so each row has
             one routine per |dy|, storing A at TOPY/BOTY + i,X for each i and stepping
             A by `adc stp` where y steps (stp = 1 with C clear, or $FE with C set: the
             carry survives either way); then a driver per segment.
down.inc     the rungs' interpolation, one unrolled walk per rung and direction
fillcols.inc the fill's columns: each byte column's kind and boxes are fixed (see main.s)

Every row vertex is pixel 0 of a byte column, so each row is monotonic across a byte
column; this checks it, and the column kinds.
"""
import os
import sys
from statistics import NormalDist

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'proto'))
sys.path.insert(0, os.path.dirname(__file__))
import points as P  # noqa: E402
import palette as PL  # noqa: E402


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


def tables(xs, ntab):
    out = []
    for r, (cx, spacing, y0) in enumerate(P.ROWS):
        out += [f'ROW{r}_X0 = {xs[r][0]}', f'ROW{r}_DX = {spacing}', f'ROW{r}_Y0 = {y0}']
    out.append(f'NPAL = {len(PL.PALETTE)}')
    pad = [0] * (16 - len(PL.PALETTE))
    dithe = [PL.byte(i, 0) for i in range(len(PL.PALETTE))] + pad
    ditho = [PL.byte(i, 1) for i in range(len(PL.PALETTE))] + pad
    q12 = [a // 12 for a in range(160)]
    r12 = [2 * (a % 12) for a in range(160)]
    for name, vals in (('DITHE', dithe), ('DITHO', ditho), ('NTAB', [v & 0xFF for v in ntab]),
                       ('Q12', q12), ('R12', r12)):
        out.append(f'{name}:')
        out += row('$%02X', vals)
    return out


def across(xs, maxdy):
    """Per row: ROWr_V<d>, the routine for |dy| = d; ROWrVL/H its address by d; then
    `across`, the sixteen segments and the two rows' last points."""
    out = []
    for r, (tab, pts) in enumerate((('TOPY', 'PTS0'), ('BOTY', 'PTS1'))):
        dx = P.ROWS[r][1]
        for d in range(maxdy + 1):
            ys = P.bresenham_ys(0, 0, dx, d)
            out.append(f'ROW{r}_V{d}:')
            for i in range(dx):
                if i and ys[i] != ys[i - 1]:
                    out.append('        adc stp')
                out.append(f'        sta {tab}+{i},x')
            out.append('        rts')
        for hl in 'LH':
            op = '<' if hl == 'L' else '>'
            out.append(f'ROW{r}V{hl}:')
            out.append('        .byte ' + ', '.join(f'{op}ROW{r}_V{d}' for d in range(maxdy + 1)))
    out.append('across:')
    for r, (tab, pts) in enumerate((('TOPY', 'PTS0'), ('BOTY', 'PTS1'))):
        for s in range(P.N - 1):
            out += [f'        lda {pts}+{2*s+3}',      # y1 - y0: C set if down
                    f'        sec',
                    f'        sbc {pts}+{2*s+1}',
                    f'        SEG {r}, {xs[r][s]}, {pts}+{2*s+1}']
        out += [f'        lda {pts}+{2*(P.N-1)+1}', f'        sta {tab}+{xs[r][-1]}']
    out.append('        rts')
    return out


def down(xs):
    """`down`: each rung from its top point to its bottom point, as prototype line_ys.
    From the left end (xl, yl) to the right (xr, yr), dx = xr - xl: going down (dy >= 0)
    the walk is left to right from yl, Bresenham's error starting at dx; going up it is
    right to left from yr with the error starting at dx - 1, which rounds ties as the
    left-to-right walk does.  Each x adds q = |dy| div dx and the error's carry.  A
    power-of-two dx keeps the error as an 8-bit fraction (f = |dy| mod dx scaled to
    256, starting at 128 or 128 - 128/dx); dx = 12 keeps it biased by 232 below 256, so
    that reaching 2dx carries (R12 = 2 * rem)."""
    out = ['down:']
    for i, (xt, xb) in enumerate(zip(*xs)):
        ttop, tbot = f'PTS0+{2*i+1}', f'PTS1+{2*i+1}'
        if xt == xb:
            out += [f'        lda {ttop}', f'        sta RUNGY+{xt}']
            continue
        xl, xr = min(xt, xb), max(xt, xb)
        yl, yr = (tbot, ttop) if xb < xt else (ttop, tbot)
        dx = xr - xl
        out += [f'        lda {yr}', '        sec', f'        sbc {yl}',
                f'        bcs :+', f'        jmp rup{i}',
                f':       RUNGSET {dx}, 0', f'        ldx {yl}']
        out += walk(dx, xl, +1)
        out += [f'        jmp rend{i}',
                f'rup{i}:  eor #$FF', '        adc #1',
                f'        RUNGSET {dx}, 1', f'        ldx {yr}']
        out += walk(dx, xr, -1)
        out.append(f'rend{i}:')
    out.append('        rts')
    return out


def walk(dx, x0, sx):
    out = [f'        stx RUNGY+{x0}']
    for j in range(1, dx + 1):
        if dx == 12:
            out += ['        tya', '        adc rr2', '        bcc :+', '        adc #231',
                    '        inx', ':       tay']
        else:
            out += ['        tya', '        adc rf', '        tay']
        out += ['        txa', '        adc rq', '        tax', f'        stx RUNGY+{x0 + sx * j}']
    return out


def columns(xs):
    """Classify each byte column from the leftmost point's to the rightmost's:
    ONE_T b   one box b between the top row and the bottom row
    ONE_R b   one box b between the rung and the bottom row (no box above the rung)
    TWO u, d  every pixel on one rung, box u above it and d below
    FIX u, d  ONE_T u, but pixel 0 is a rung's bottom point: its last line is d
    PIX d     pixel 0 alone, a rung's bottom point: d on its last line"""
    rungs = [({}, xt, xb) for xt, xb in zip(*xs)]
    top = range(xs[0][0], xs[0][-1] + 1)
    bot = range(xs[1][0], xs[1][-1] + 1)
    rungat = {}
    for i, (xt, xb) in enumerate(zip(*xs)):
        for x in range(min(xt, xb), max(xt, xb) + 1):
            rungat[x] = i

    def ends(i):
        return min(xs[0][i], xs[1][i]), max(xs[0][i], xs[1][i])

    def boxes(x):
        up = P.span_box(x, False, rungs) if x in top else 8
        dn = P.span_box(x, True, rungs)
        return up, dn
    cols = []
    for c in range(min(xs[0][0], xs[1][0]) // 4, max(xs[0][-1], xs[1][-1]) // 4 + 1):
        px = range(4 * c, 4 * c + 4)
        assert all(x in bot for x in px) or px[0] == xs[1][-1]
        inr = [x in rungat for x in px]
        bx = [boxes(x) for x in px]
        if all(inr) and len(set(bx)) == 1 and bx[0][0] != bx[0][1] and bx[0][0] != 8:
            cols.append((c, 'TWO', bx[0], ends(rungat[px[0]])))
        elif all(inr) or (inr[0] and not any(x in top for x in px[1:])):
            # no top row: black above the rung; the vertex pixel, if one, is a rung end
            # whose rung record is its row's record
            if px[0] == xs[1][-1]:
                assert not any(inr[1:]) and not any(x in bot for x in px[1:])
                cols.append((c, 'PIX', (bx[0][1],), None))
                continue
            assert {d for _, d in bx} == {bx[-1][1]}
            assert all(u == 8 or x in xs[0] for x, (u, _) in zip(px, bx))
            cols.append((c, 'ONE_R', (bx[-1][1],), ends(rungat[px[-1]])))
        elif inr[0] and not any(inr[1:]):
            x = px[0]
            assert all(x in top for x in px)
            if x in xs[0]:                      # a rung's top point: its row's record
                assert bx[0][1] == bx[1][0] == bx[1][1]
                cols.append((c, 'ONE_T', (bx[1][0],), None))
            else:                               # a rung's bottom point
                assert x in xs[1] and bx[0][0] == bx[1][0] == bx[1][1] != bx[0][1]
                cols.append((c, 'FIX', bx[0], None))
        else:
            assert not any(inr) and all(x in top for x in px) and len(set(bx)) == 1
            assert bx[0][0] == bx[0][1]
            cols.append((c, 'ONE_T', (bx[0][0],), None))
    return cols


def fillcols(cols):
    out = []
    last = lastr = None
    for c, kind, bx, rung in cols:
        if c == 32:
            out.append('        jsr half_right')
            last = None
        out.append(f'        ; column {c}: {kind} {bx}')
        ud = {'ONE_T': (bx[0], bx[0]), 'ONE_R': (8, bx[0]), 'PIX': (8, bx[0])}.get(kind, bx)
        if ud != last:
            out.append(f'        SETUD {ud[0]}, {ud[1]}')
            last = ud
            lastr = None
        if kind in ('TWO', 'ONE_R') and rung != lastr:
            out.append(f'        RPREP {rung[0]}, {rung[1]}')
            lastr = rung
        out += [f'        COL {c}', f'        jsr {kind.lower()}']
    return out


def main():
    nd = NormalDist(0, P.SD)
    ntab = [round(nd.inv_cdf((i + 0.5) / 256)) for i in range(256)]
    maxdy = max(abs(v) for v in ntab)
    xs = geometry()
    assert maxdy < min(r[1] for r in P.ROWS)
    cols = columns(xs)
    files = {'tables.inc': tables(xs, ntab), 'across.inc': across(xs, maxdy),
             'down.inc': down(xs), 'fillcols.inc': fillcols(cols)}
    for name, lines in files.items():
        with open(os.path.join(sys.argv[1], name), 'w') as f:
            f.write('; generated by tools/gentab.py\n' + '\n'.join(lines) + '\n')


main()
