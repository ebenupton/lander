#!/usr/bin/env python3
"""The game in py65: the loader's start-up, then the main loop's routines frame by frame.

    python3 b32/test/gametest32.py [SCRIPT]

SCRIPT: comma-separated N:KEYS parts, N frames with KEYS held (L left, R right, F nose
down, B nose up, T thrust, H SHIFT, P F's key); default '10:,20:T,30:'.  Prints a line a
frame: its number, the keys, its cycles (gstep through flip) and the ship's state.  Each
frame moves vcount on FMIN fields (GT_VS=real: as many as the last frame's cycles would
take); the game steps once a frame either way, so the state does not depend on it.

Importable: Game() (the machine after start-up), .frame(keys), .state(), .call(addr).
"""
import os
import random
import sys

from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
B = os.path.join(ROOT, 'build32')
RET = 0xFF00                       # where a call returns to
SVIA_ORA_NH = 0xFE4F               # the keyboard's port
KEYS = {'L': 0x61, 'R': 0x42, 'F': 0x46, 'B': 0x65, 'T': 0x62, 'H': 0x00, 'P': 0x43}


def labels():
    """The link's labels: {name: address}."""
    out = {}
    for ln in open(os.path.join(B, 'labels.txt')):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


class Game:
    def __init__(self):
        self.lab = lab = labels()
        self.mem = mem = ObservableMemory()
        self.held = set()
        self.sel = 0

        def ora_w(addr, value):
            self.sel = value & 0x7F
            return value

        def ora_r(addr):
            return self.sel | (0x80 if self.sel in self.held else 0)
        mem.subscribe_to_write([SVIA_ORA_NH], ora_w)
        mem.subscribe_to_read([SVIA_ORA_NH], ora_r)
        self.mpu = MPU(memory=mem)
        mem._subject[0:0x8000] = random.Random(32).randbytes(0x8000)   # the MOS's leftovers
        data = open(os.path.join(B, 'LANDER'), 'rb').read()
        mem._subject[0x2000:0x2000 + len(data)] = data
        self.call(lab['takeover'])
        self.mpu.memory[lab['back']] = 0
        self.call(lab['setback'])
        self.call(lab['ginit'])
        mem._subject[0x5000:0x8000] = bytes(0x3000)   # clr's work: the loader gone

    def call(self, addr):
        """Run the routine at addr until it returns; its cycles."""
        m = self.mpu
        m.memory[0x1FF], m.memory[0x1FE] = (RET - 1) >> 8, (RET - 1) & 0xFF
        m.sp = 0xFD
        m.pc = addr
        start = m.processorCycles
        while m.pc != RET:
            m.step()
            if m.processorCycles - start > 10000000:
                raise RuntimeError(f'${addr:04X} still running at ${m.pc:04X}')
        return m.processorCycles - start

    def rd(self, name, n=1):
        a = self.lab[name]
        return [self.mpu.memory[a + i] for i in range(n)]

    def frame(self, keys, vs=None):
        """One frame with keys held: the main loop's routines in turn; its cycles."""
        self.held = {KEYS[k] for k in keys}
        m = self.mpu.memory
        if vs is None:
            vs = max(4, -(-getattr(self, 'last', 0) // 40000)) if os.environ.get('GT_VS') == 'real' else 4
        m[self.lab['vcount']] = (m[self.lab['vcount']] + vs) & 255
        c = 0
        for r in ('gstep', 'project', 'strips', 'gpre', 'ship', 'gpost', 'flip'):
            if r == 'ship' and not m[self.lab['GSHV']]:
                continue
            c += self.call(self.lab[r])
        self.last = c
        return c

    def state(self):
        def s24(v):
            x = v[0] | v[1] << 8 | v[2] << 16
            return (x - (1 << 24) if x & 0x800000 else x) / 65536

        def s16(v):
            x = v[0] | v[1] << 8
            return x - 65536 if x & 0x8000 else x
        r = self.rd
        return (f"x {s24(r('sx', 3)):7.3f} z {s24(r('sz', 3)):7.3f} y {s24(r('sy', 3)) * 16:6.2f}u "
                f"v {s16(r('gvx', 2)):6d} {s16(r('gvy', 2)):6d} {s16(r('gvz', 2)):6d} "
                f"k {r('gk')[0]:2d} p {r('gp')[0]:2d} fuel {r('fuel')[0] | r('fuel', 2)[1] << 8:5d} "
                f"landed {r('landed')[0]} ctim {r('ctim')[0]:2d} "
                f"hg {r('HGV')[0]} came {r('CAME')[0]} shy {r('GSHY')[0]}")


def main():
    script = sys.argv[1] if len(sys.argv) > 1 else '10:,20:T,30:'
    g = Game()
    f = 0
    for part in script.split(','):
        n, keys = part.split(':')
        for _ in range(int(n)):
            c = g.frame(keys)
            print(f'{f:4d} {keys:4s} {c:7d} {g.state()}')
            f += 1


if __name__ == '__main__':
    main()
