#!/usr/bin/env python3
"""Apply the grind's candidates to b32/src one at a time, each measured and checked, with
the full gate every few.

    python3 b32/opt/apply32.py CANDIDATES.json LOG.json [--gate-every N]

CANDIDATES.json: a list of {id, file, first_line, old_text, new_text, extra_edits,
cycles_saved_per_frame, bytes_delta, kind, ...} (the farm's survivors), applied in order.
For each: its hunks replace their old_text (the occurrence nearest first_line; extra
edits anywhere, each unique), the build, then gametest32's flight against the gate's
baseline (build32/gate_base.txt): the same state every frame.  Measured: the flight's
cycles a frame (gametest32's sum, profile32.SCRIPT) and the program's bytes (L32M), each
against the last accepted state.  A candidate that fails to apply, build or match is
reverted and logged with the reason.  Every N accepted (default 8) and at the end, the full
gate (b32/test/gate32.sh); if it fails, the batch since the last pass is bisected (each
half re-gated) and the culprits reverted.  LOG.json: one record a candidate: id, status
(accepted, rejected: why), measured cycles and bytes deltas, claimed ones.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
B = os.path.join(ROOT, 'build32')


def sh(cmd, timeout=3600):
    r = subprocess.run(cmd, shell=True, cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout + r.stderr


def snapshot():
    out = {}
    for d in ('b32/src', 'b32/tools'):
        for f in os.listdir(os.path.join(ROOT, d)):
            if f.endswith(('.s', '.inc', '.cfg', '.py')):
                p = os.path.join(ROOT, d, f)
                out[p] = open(p).read()
    return out


def restore(snap):
    for p, t in snap.items():
        if open(p).read() != t:
            open(p, 'w').write(t)


def lineof(text, idx):
    return text.count('\n', 0, idx) + 1


def apply(c):
    """the candidate's hunks applied to the files, or a reason it cannot be"""
    hunks = [(c['file'], c['old_text'], c['new_text'], c.get('first_line'))]
    hunks += [(e['file'], e['old_text'], e['new_text'], None) for e in c.get('extra_edits') or []]
    new = {}
    for f, old, rep, near in hunks:
        p = os.path.join(ROOT, f) if '/' in f else os.path.join(ROOT, 'b32', 'src', f)
        f = p
        t = new.get(f) or open(p).read()
        old = old.rstrip('\n')
        rep = rep.rstrip('\n')
        if ';|' in old:
            return 'old_text has annotation text'
        idxs, k = [], t.find(old)
        while k >= 0:
            idxs.append(k)
            k = t.find(old, k + 1)
        if not idxs:
            return f'old_text not found in {f}'
        if len(idxs) > 1 and near is None:
            return f'old_text not unique in {f}'
        k = min(idxs, key=lambda i: abs(lineof(t, i) - near)) if near else idxs[0]
        if near and abs(lineof(t, k) - near) > 150:
            return f'old_text found only {abs(lineof(t, k) - near)} lines from line {near}'
        if old.count('\n:') + old.startswith(':') != rep.count('\n:') + rep.startswith(':'):
            pass                     # (the anonymous labels: counted by the build's result)
        new[f] = t[:k] + rep + t[k + len(old):]
    for p, t in new.items():
        open(p, 'w').write(t)
    return None


def measure():
    """(None, cycles a frame, bytes) or (reason, ...)"""
    rc, o = sh('sh b32/build32.sh')
    if rc or 'Error' in o:
        return 'build: ' + next((l for l in o.split('\n') if 'Error' in l), o[-200:]), 0, 0
    size = os.path.getsize(os.path.join(B, 'L32M'))
    script = sh("python3 -c \"import sys; sys.path.insert(0,'b32/test'); import profile32; print(profile32.SCRIPT)\"")[1].strip()
    rc, o = sh(f'python3 b32/test/gametest32.py "{script}"', timeout=1800)
    if rc:
        return 'flight: ' + o.strip().split('\n')[-1][:200], 0, size
    rows = o.rstrip('\n').split('\n')
    state = '\n'.join(r[18:] for r in rows) + '\n'
    if state != open(os.path.join(B, 'gate_base.txt')).read():
        bad = next(i for i, (a, b) in enumerate(zip(state.split('\n'), open(os.path.join(B, 'gate_base.txt')).read().split('\n'))) if a != b)
        return f'flight state differs from frame {bad}', 0, size
    cyc = sum(int(r[10:17]) for r in rows) / len(rows)
    return None, cyc, size


def gate():
    rc, o = sh('sh b32/test/gate32.sh', timeout=3600)
    last = o.strip().split('\n')[-1]
    return last.startswith('GATE PASS'), last


def main():
    cands = json.load(open(sys.argv[1]))
    logp = sys.argv[2]
    every = int(sys.argv[sys.argv.index('--gate-every') + 1]) if '--gate-every' in sys.argv else 8
    log = json.load(open(logp)) if os.path.exists(logp) else []
    done = {r['id'] for r in log}
    err, cyc0, size0 = measure()
    assert not err, err
    print(f'start: {cyc0:.0f} cycles a frame, {size0} bytes')
    gated = snapshot()
    pending = []                    # (candidate, snapshot before it, log record)

    def full_gate():
        nonlocal gated, pending, cyc0, size0
        ok, msg = gate()
        if ok:
            gated, pending = snapshot(), []
            print('  gate pass:', msg)
            return
        print('  gate FAIL:', msg, '- bisecting', len(pending))
        # re-apply one at a time from the last gated state, gating each
        batch, pending = pending, []
        restore(gated)
        for c, _, rec in batch:
            before = snapshot()
            apply(c)
            okc, m = gate()
            if okc:
                gated = snapshot()
            else:
                restore(before)
                rec['status'] = 'rejected: full gate: ' + m
                print('   ', c['id'], 'rejected by the full gate:', m)
        sh('sh b32/build32.sh')
        e, cyc0, size0 = measure()
        json.dump(log, open(logp, 'w'), indent=1)
    for c in cands:
        if c['id'] in done:
            continue
        before = snapshot()
        rec = dict(id=c['id'], kind=c.get('kind'), claimed_cycles=c.get('cycles_saved_per_frame'),
                   claimed_bytes=c.get('bytes_delta'))
        why = apply(c)
        if not why:
            why, cyc, size = measure()
        if why:
            restore(before)
            rec['status'] = 'rejected: ' + why
            print(f"{c['id']}: rejected: {why}")
        else:
            rec.update(status='accepted', cycles_saved=round(cyc0 - cyc, 1), bytes_delta=size - size0)
            print(f"{c['id']}: accepted: {cyc0 - cyc:+.1f} cycles a frame saved, {size - size0:+d} bytes "
                  f"(claimed {c.get('cycles_saved_per_frame')}, {c.get('bytes_delta')})")
            cyc0, size0 = cyc, size
            pending.append((c, before, rec))
        log.append(rec)
        json.dump(log, open(logp, 'w'), indent=1)
        if len(pending) >= every:
            full_gate()
    if pending:
        full_gate()
    sh('sh b32/build32.sh')
    acc = [r for r in log if r['status'] == 'accepted']
    print(f"{len(acc)} accepted of {len(log)}: {sum(r['cycles_saved'] for r in acc):+.0f} cycles a frame, "
          f"{sum(r['bytes_delta'] for r in acc):+d} bytes")


if __name__ == '__main__':
    main()
