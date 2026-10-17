#!/usr/bin/env python3
"""The 32K build's profile in py65: gametest32's game loop over a scripted flight, every
instruction's cycles, every data byte's reads and writes, the stack's depth.

    python3 b32/test/profile32.py [SCRIPT] [OUT]     (OUT default build32/profile.json)

SCRIPT: gametest32's (N:KEYS parts); the default flies off the pad, pitches, turns, climbs
and comes down over the land.  A data access is any read or write outside the executing
instruction's own bytes (so operand patches by other code count as writes, an
instruction's fetch does not); each is recorded with the addressing mode that made it (an
abs or abs,X/Y operand is what moving the byte to zero page would make one cycle and one
byte cheaper).  Writes build32/profile.json:
    frames, cycles                      the frames run and their cycles (the loop's routines)
    pcs   {addr: cycles}                per instruction (hex address)
    xpage {addr: cycles}                per instruction: page crossings' extra cycles
    data  {addr: [reads, writes, {mode: n}, [pcs]]}  per data byte touched
    sp_min                              the lowest stack pointer seen (the harness calls
                                        each routine with S = $FD)
and prints the hottest data bytes outside zero page.
"""
import collections
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import gametest32 as G     # noqa: E402

SCRIPT = ('6:,10:T,3:TF,6:T,4:TL,4:TLB,6:T,4:TR,8:,6:TB,6:T,4:TF,10:,6:TL,10:T,12:,'
          '6:TR,8:T,10:')
LEN = {'imp': 1, 'acc': 1, 'imm': 2, 'zpg': 2, 'zpx': 2, 'zpy': 2, 'inx': 2, 'iny': 2,
       'rel': 2, 'abs': 3, 'abx': 3, 'aby': 3, 'ind': 3}


class Counting:
    """The machine's memory with every access counted (wraps gametest32's)."""
    def __init__(self, inner):
        self.inner = inner
        self.lo = self.hi = 0
        self.mode = 'imp'
        self.pc = 0
        self.r = [0] * 65536
        self.w = [0] * 65536
        self.modes = collections.defaultdict(collections.Counter)
        self.who = collections.defaultdict(set)

    def __getitem__(self, a):
        if isinstance(a, int) and not (self.lo <= a < self.hi):
            self.r[a] += 1
            self.modes[a][self.mode] += 1
            self.who[a].add(self.pc)
        return self.inner[a]

    def __setitem__(self, a, v):
        if isinstance(a, int):
            self.w[a] += 1
            self.modes[a][self.mode] += 1
            self.who[a].add(self.pc)
        self.inner[a] = v

    def __len__(self):
        return len(self.inner)


def main():
    script = sys.argv[1] if len(sys.argv) > 1 else SCRIPT
    out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(G.B, 'profile.json')
    g = G.Game()
    cm = Counting(g.mpu.memory)
    mpu = g.mpu
    dis = mpu.disassemble
    pcs = collections.Counter()
    xpage = collections.Counter()        # page-crossing cycles by instruction
    spmin = [0xFF]
    base = mpu.cycletime

    def call(addr):
        mpu.memory = cm
        m = mpu
        cm.inner[0x1FF], cm.inner[0x1FE] = (G.RET - 1) >> 8, (G.RET - 1) & 0xFF
        m.sp = 0xFD
        m.pc = addr
        start = m.processorCycles
        while m.pc != G.RET:
            pc = m.pc
            op = cm.inner[pc]
            mode = dis[op][1]
            cm.lo, cm.hi, cm.mode, cm.pc = pc, pc + LEN[mode], dis[op][0] + ' ' + mode, pc
            c0 = m.processorCycles
            m.step()
            c = m.processorCycles - c0
            pcs[pc] += c
            extra = c - base[op]
            if mode == 'rel' and m.pc != pc + 2:
                extra -= 1                   # (a taken branch's own cycle)
            if extra > 0:
                xpage[pc] += extra
            if m.sp < spmin[0]:
                spmin[0] = m.sp
        return m.processorCycles - start
    g.call = call
    total = frames = 0
    for part in script.split(','):
        n, keys = part.split(':')
        for _ in range(int(n)):
            total += g.frame(keys)
            frames += 1
    lab = {}
    for name, a in g.lab.items():
        lab.setdefault(a, name)
    names = sorted(lab)

    def sym(a):
        import bisect
        i = bisect.bisect_right(names, a) - 1
        b = names[i] if i >= 0 else 0
        return lab.get(b, '?') + (f'+{a - b}' if a != b else '')
    data = {}
    for a in range(65536):
        if cm.r[a] or cm.w[a]:
            data[f'{a:04X}'] = [cm.r[a], cm.w[a], dict(cm.modes[a]), sorted(f'{p:04X}' for p in cm.who[a])]
    json.dump(dict(frames=frames, cycles=total, sp_min=spmin[0],
                   pcs={f'{a:04X}': c for a, c in pcs.items()},
                   xpage={f'{a:04X}': c for a, c in xpage.items()}, data=data), open(out, 'w'))
    print(f'{frames} frames, {total} cycles, {total // frames} a frame; lowest S ${spmin[0]:02X}')
    xs = sorted(((c, a) for a, c in xpage.items()), reverse=True)
    print(f'page crossings: {sum(xpage.values()) / frames:.1f} cycles a frame; the costliest:')
    for c, a in xs[:25]:
        print(f'  ${a:04X} {sym(a):24s} {c / frames:8.1f}')
    rows = []
    for a in range(0x100, 0x8000):
        if not (0x100 <= a < 0x200) and (cm.r[a] or cm.w[a]):
            ab = sum(n for md, n in cm.modes[a].items() if md.endswith((' abs', ' abx')) or md in ('LDX aby', 'STX aby'))
            rows.append((ab, a))
    rows.sort(reverse=True)
    print('hottest data bytes outside zero page (accesses a frame by abs / abs,X: one cycle each in zero page)')
    for ab, a in rows[:60]:
        print(f'  ${a:04X} {sym(a):24s} {ab / frames:8.1f}  r {cm.r[a] / frames:8.1f} w {cm.w[a] / frames:7.1f}  insns {len(cm.who[a]):3d}')


if __name__ == '__main__':
    main()
