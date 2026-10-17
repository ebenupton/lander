#!/usr/bin/env python3
"""dataflow -- forward constants and backward liveness over a beebgame game's linked code.

    python3 tools/dataflow/dataflow.py [--build build/master] [--out build/dataflow]
                                       [--strict-isr] [--quiet]

Reads the build's game.dbg and output images (no reassembly), analyses every
instruction the build decoded (engine and game: the engine's routines are analysed
to give the game's JSRs real clobber summaries), and writes, for the game's code
(src/*.s):

  report.md     findings ranked by bytes saved, with file:line, instruction, evidence
  report.json   the same, machine-readable, plus per-line liveness/constants
  abi.md        per routine entered by JSR: registers/flags read on entry, what its
                callers read after it returns, call sites, staged memory parameters
  annotated/    each game source file with live-in / live-out / known values per line

See README.md for the model and its assumptions.
"""
import os, sys, json, argparse, collections
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import model, analysis, findings, gamecfg
from analysis import RF, REGS, FLAGS, A, X, Y, N, Z, C, V, rf_str, RNAME
from forward import U

ROOT = os.getcwd()                     # (the game's root: --root)


def main():
    global ROOT
    ap = argparse.ArgumentParser()
    gamecfg.add_args(ap)
    ap.add_argument('--build', default=None)
    ap.add_argument('--out', default=None)
    ap.add_argument('--strict-isr', action='store_true',
                    help="the interrupt's pointer reads may read any memory")
    ap.add_argument('--quiet', action='store_true')
    a = ap.parse_args()
    gamecfg.load(a.config)
    ROOT = os.path.abspath(a.root)
    a.build = a.build or os.path.join(ROOT, 'build', 'master')
    a.out = a.out or os.path.join(ROOT, 'build', 'dataflow')
    P = model.Program(ROOT, a.build)
    an = analysis.Analysis(P, strict_isr=a.strict_isr)
    F = findings.find(an)
    os.makedirs(os.path.join(a.out, 'annotated'), exist_ok=True)
    lines = per_line(an)
    abi = abi_table(an)
    write_report(an, F, a.out)
    write_json(an, F, lines, abi, a.out)
    write_abi(an, abi, a.out)
    write_annotated(an, lines, a.out)
    if not a.quiet:
        c = collections.Counter(f['cat'] for f in F)
        b = collections.Counter()
        for f in F:
            b[f['cat']] += f['bytes']
        print(f"{len(P.insns)} instructions ({sum(i.game for i in P.insns.values())} game), "
              f"{len(F)} findings, {sum(b.values())} bytes")
        for k, n in c.most_common():
            print(f"  {k:15} {n:4}  {b[k]:4} bytes")
        print(f"-> {a.out}/report.md, report.json, abi.md, annotated/")


# ---------------------------------------------------------------- per line
def st_known(P, st):
    return findings.known_str(P, st)


def per_line(an):
    P = an.P
    by = collections.OrderedDict()
    for i in P.order:
        if not i.game:
            continue
        key = (i.outer['file'], i.outer['line'])
        by.setdefault(key, []).append(i)
    rows = []
    for (fid, ln), ins in by.items():
        ins.sort(key=lambda i: i.addr)
        # a source line can expand at several addresses (a macro body line);
        # outer lines are unique per expansion, so group by contiguous runs
        first, last = ins[0], ins[-1]
        st = an.fin.get(first.key)
        rows.append(dict(file=P.src.short(fid), line=ln, addr=f'${first.addr:04X}',
                         seg=P.segs[first.seg]['name'],
                         insns=[P.disasm(i) for i in ins],
                         live_in=rf_str(an.live_in[first.key] & RF),
                         live_out=rf_str(an.live_out[last.key] & RF),
                         known=st_known(P, st),
                         per_insn=[dict(insn=P.disasm(i), live_in=rf_str(an.live_in[i.key] & RF),
                                        live_out=rf_str(an.live_out[i.key] & RF),
                                        known=st_known(P, an.fin.get(i.key)))
                                   for i in ins] if len(ins) > 1 else None))
    return rows


def write_annotated(an, rows, out):
    P = an.P
    byf = collections.defaultdict(dict)
    for r in rows:
        byf[r['file']][r['line']] = r
    for fid in P.game_files:
        fn = P.src.short(fid)
        L = P.src.lines.get(fid)
        if L is None or fn not in byf:
            continue
        o = []
        o.append(f"; {fn} annotated by tools/dataflow: live-in > live-out (A X Y N Z C V) | known before")
        o.append(f"; '-' = nothing live / nothing known.  [m] = equals memory byte m.  NZ~r = N,Z reflect r")
        for n, t in enumerate(L, 1):
            r = byf[fn].get(n)
            if r:
                ann = f"{r['live_in']:>7} > {r['live_out']:<7}| {r['known'][:40]:<40}"
            else:
                ann = ' ' * 58
            o.append(f"{n:5} {ann} |{t}")
            if r and r['per_insn']:
                for p in r['per_insn']:
                    o.append(f"      {p['live_in']:>7} > {p['live_out']:<7}| {p['known'][:40]:<40} |      ;   {p['insn']}")
        path = os.path.join(out, 'annotated', os.path.basename(fn) + '.txt')
        with open(path, 'w') as fh:
            fh.write('\n'.join(o) + '\n')


# ---------------------------------------------------------------- ABI
def abi_table(an):
    P = an.P
    res = []
    for ek, sites in an.jsr_sites.items():
        e = P.insns[ek]
        labs = P.code_label.get(ek, [])
        name = sorted(labs, key=lambda s: (s['name'].startswith('@'), len(s['name'])))[0]['name'] \
            if labs else f'${e.addr:04X}'
        game_sites = [s for s in sites if s.game]
        if not e.game and not game_sites:
            continue
        S = an.S.get(ek)
        ok = an.sum_why.get(ek) is None
        entry = rf_str(S['use'] & RF) if ok else 'unknown'
        mem_in = an.names_of(S['use'] & an.MALL & ~an.isr_r) if ok else []
        ret = an.retlive.get(ek, RF)
        rely = collections.Counter()
        for s in sites:
            lo = an.live_out[s.key]
            for b, nm in RNAME:
                if lo & b:
                    rely[nm] += 1
        # register values at the call
        vals = {r: collections.Counter() for r in 'AXY'}
        flags = {f: collections.Counter() for f in 'C'}
        for s in sites:
            st = an.fin.get(s.key)
            for r in 'AXY':
                v = '?' if st is None or st.r[r] == U else findings.vstr(P, st.r[r])
                vals[r][v] += 1
            for f in 'C':
                v = '?' if st is None or st.f[f] is None else str(st.f[f])
                flags[f][v] += 1
        # memory staged just before the call, in the caller's straight-line code
        staged = collections.defaultdict(list)
        for s in sites:
            j = s
            back = 0
            while back < 12:
                ps = an.pred.get(j.key, [])
                if len(ps) != 1 or ps[0][1] is not None and ps[0][1][0] == 'br' and False:
                    break
                p = ps[0][0]
                if p.mn in ('JSR', 'RTS', 'JMP') or p.mode == 'rel':
                    break
                if p.mn in ('STA', 'STX', 'STY', 'STZ') and p.mode in ('zp', 'abs'):
                    b = an.mb(p.opnd)
                    if ok and b and (S['use'] & b):
                        staged[p.opnd].append(dict(site=P.where(s), store=P.where(p),
                                                   insn=P.disasm(p),
                                                   free=rf_str(REGS & ~an.live_in[s.key]),
                                                   dead_after=not (an.live_out[s.key] & b)))
                j = p; back += 1
        if name in analysis.helpers():
            ok = False
        res.append(dict(name=name, addr=f'${e.addr:04X}', seg=P.segs[e.seg]['name'],
                        where=P.where(e), game=e.game, summarised=ok,
                        why_unknown=("inline-operand helper: its call sites use the contract in "
                                     "analysis.helpers() (X, Y preserved; A, N, Z, C, V "
                                     "out; operands' bytes read/written)")
                        if name in analysis.helpers() else an.sum_why.get(ek),
                        entry_reads=entry, entry_mem=[P.name(m) for m in mem_in][:40],
                        n_entry_mem=len(mem_in),
                        mustdef=rf_str(S['mustdef'] & RF) if ok else '-',
                        maydef=rf_str(S['maydef'] & RF) if ok else 'all',
                        exit_live=rf_str(ret & RF),
                        exit_rely={k: v for k, v in rely.items()},
                        kinds=an.entries.get(ek, []),
                        sites=len(sites), game_sites=len(game_sites),
                        callers=sorted({P.routine_of(s) for s in sites}),
                        at_call={r: dict(vals[r]) for r in 'AXY'},
                        carry_at_call=dict(flags['C']),
                        staged={P.name(a): v for a, v in staged.items()}))
    res.sort(key=lambda r: (not r['game'], r['where']))
    return res


def write_abi(an, abi, out):
    P = an.P
    o = ["# Routine ABIs (tools/dataflow)", "",
         "Per routine entered by JSR from the game (the game's routines first, then the "
         "engine's the game calls).  Registers/flags: A X Y N Z C V.", "",
         "* **entry reads**: registers/flags the body (and its callees) reads before writing "
         "them -- the routine's register inputs.  `unknown`: the body could not be "
         "summarised (stack games, an unresolved jump), so every call is treated as "
         "reading and clobbering everything.",
         "* **exit live**: registers/flags some caller reads after the JSR returns (the "
         "routine's register outputs as used; a routine entered other than by JSR "
         "returns with everything live).  `rely` counts call sites per register.",
         "* **must / may def**: written on every path to RTS / on some path.",
         "* **at call**: what the forward pass knows of A, X, Y, C at each call site "
         "(`?` unknown, `$nn` constant, `[m]` equal to memory byte m).",
         "* **staged**: a byte the routine reads on entry that a caller stores in the "
         "straight-line code just before the JSR -- candidates for passing in a register. "
         "`free` = registers not live into the JSR at that site (neither the callee nor "
         "the caller after the call needs them); `dead after` = the caller does not read "
         "the byte after the call.", ""]
    for r in abi:
        if r['game'] is False and not r['game_sites']:
            continue
        o.append(f"## {r['name']}  ({r['where']}, {r['addr']} {r['seg']})" +
                 ("" if r['game'] else "  -- engine"))
        o.append("")
        o.append(f"- call sites: {r['sites']} ({r['game_sites']} in the game); callers: "
                 + ', '.join(r['callers'][:12]) + (' ...' if len(r['callers']) > 12 else ''))
        if r['kinds'] and r['kinds'] != ['jsr']:
            o.append(f"- also entered as: {', '.join(k for k in r['kinds'] if k != 'jsr')} "
                     f"(returns with everything live)")
        if r['summarised']:
            o.append(f"- entry reads: **{r['entry_reads']}**; memory read before written "
                     f"(less the interrupt's, live everywhere): "
                     f"{r['n_entry_mem']} bytes" + (": " + ', '.join(r['entry_mem'][:16]) +
                                                    (' ...' if r['n_entry_mem'] > 16 else '')
                                                    if r['entry_mem'] else ''))
            o.append(f"- must def: {r['mustdef']}; may def: {r['maydef']}")
        else:
            o.append(f"- entry reads: **unknown** ({r['why_unknown']})")
        rely = ' '.join(f"{k}:{v}" for k, v in sorted(r['exit_rely'].items(),
                                                      key=lambda kv: 'AXYNZCV'.index(kv[0])))
        o.append(f"- exit live: **{r['exit_live']}**" + (f" (rely: {rely})" if rely else ''))
        ac = '; '.join(f"{k}: " + ', '.join(f"{v}x{n}" for v, n in sorted(d.items(), key=lambda kv: -kv[1]))
                       for k, d in r['at_call'].items())
        o.append(f"- at call: {ac}; C: " + ', '.join(f"{v}x{n}" for v, n in r['carry_at_call'].items()))
        if r['staged']:
            o.append("- staged through memory before the call:")
            for m, lst in r['staged'].items():
                o.append(f"    - `{m}`: {len(lst)}/{r['sites']} sites")
                for s in lst[:6]:
                    o.append(f"        - {s['store']} `{s['insn']}` -> call {s['site']}; "
                             f"free {s['free']}; {'dead after' if s['dead_after'] else 'read after'}")
        o.append("")
    with open(os.path.join(out, 'abi.md'), 'w') as fh:
        fh.write('\n'.join(o) + '\n')


# ---------------------------------------------------------------- report
CAT_ORDER = ['bit_skip_bad', 'dead_store', 'dead_insn', 'dead_code', 'imm_load', 'reload',
             'reg_xfer', 'redundant_xfer', 'known_store', 'const_operand', 'clc_sec', 'cmp_zero', 'identity',
             'branch_never', 'branch_over_jmp', 'jmp_to_branch', 'tail_call', 'branch_always']


def write_report(an, F, out):
    P = an.P
    F.sort(key=lambda f: (-f['bytes'], CAT_ORDER.index(f['cat']), f['file'], f['line']))
    c = collections.Counter(f['cat'] for f in F)
    b = collections.Counter()
    for f in F:
        b[f['cat']] += f['bytes']
    o = ["# Dataflow findings (tools/dataflow)", "",
         f"Build: `{os.path.relpath(P.build, ROOT)}` ({len(P.insns)} instructions decoded, "
         f"{sum(i.game for i in P.insns.values())} of them the game's).  Every finding holds "
         "on every modelled path; each is a pointer for a human, to go through the gate "
         "like any other change.  `bytes` = bytes saved; `cycles` = cycles saved per "
         "execution (never negative).", "",
         "## Summary", "", "| category | count | bytes |", "|---|---:|---:|"]
    for k in CAT_ORDER:
        if c[k]:
            o.append(f"| {k} | {c[k]} | {b[k]} |")
    o.append(f"| **total** | {len(F)} | {sum(b.values())} |")
    o += ["", "Overlapping findings (e.g. a dead store whose value-producing load is then "
          "also dead) are listed separately: the totals are an upper bound, not additive "
          "for neighbouring lines.", "", "## Model notes", ""]
    for n in an.notes:
        o.append(f"- {n}")
    o += ["", "## Findings (ranked by bytes saved)", ""]
    for f in F:
        o.append(f"### {f['cat']}: {f['file']}:{f['line']}  (-{f['bytes']} bytes, "
                 f"-{f['cycles']} cycles)")
        o.append("")
        o.append(f"- `{f['insn']}` at {f['addr']} ({f['seg']}), in `{f['routine']}`")
        o.append(f"- source: `{f['source']}`")
        o.append(f"- {f['detail']}")
        o.append(f"- evidence: {f['evidence']}")
        if f.get('insns'):
            o.append(f"- instructions: `" + '; '.join(f['insns'][:12]) + "`")
        o.append("")
    with open(os.path.join(out, 'report.md'), 'w') as fh:
        fh.write('\n'.join(o) + '\n')


def write_json(an, F, lines, abi, out):
    P = an.P
    c = collections.Counter(f['cat'] for f in F)
    b = collections.Counter()
    for f in F:
        b[f['cat']] += f['bytes']
    doc = dict(build=os.path.relpath(P.build, ROOT), notes=an.notes,
               summary={k: dict(count=c[k], bytes=b[k]) for k in c},
               findings=F, abi=abi, lines=lines)
    with open(os.path.join(out, 'report.json'), 'w') as fh:
        json.dump(doc, fh, indent=1)


if __name__ == '__main__':
    main()
