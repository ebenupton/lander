#!/usr/bin/env python3
"""The 32K build's game loop in py65 (build32/, b32/build32.sh), test/gametest.py's
harness for the flat machine: LAND at $1900, DEV at $8000, no banks.

    python3 b32/test/gametest32.py [SCRIPT]

SCRIPT as test/gametest.py's: comma-separated N:KEYS parts, N frames with KEYS held
(L left, R right, F nose down, B nose up, T thrust, H shift, P F's key).  Each line:
the frame, the keys, the frame's cycles (gstep, project, strips, gpre, ship, gpost,
readout, flip: everything the main loop runs), then the ship's state.  vcount moves on 4 syncs a frame (FMIN), or with
GT_VS=real as many as its cycles would take; the game takes one step a frame either
way, so the state is the same.  Importable: Game().frame(keys, vs) and state().
"""
import os
import random
import re
import sys

from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
B = os.path.join(ROOT, 'build32')
RET = 0xFF00
SVIA_ORA_NH = 0xFE4F


def equ(name):
    """A fixed-address equate's value (NAME = $xxxx in b32/src)."""
    for f in os.listdir(os.path.join(ROOT, 'b32', 'src')):
        if f.endswith('.s'):
            m = re.search(r'^' + name + r'\s*=\s*\$([0-9A-Fa-f]+)\b', open(os.path.join(ROOT, 'b32', 'src', f)).read(), re.M)
            if m:
                return int(m.group(1), 16)
    raise KeyError(name)


CAME, HGV, GSHY, GSHV = equ('CAME'), equ('HGV'), equ('GSHY'), equ('GSHV')
KEYS = {'L': 0x61, 'R': 0x42, 'F': 0x46, 'B': 0x65, 'T': 0x62, 'H': 0x00, 'P': 0x43}


def labels():
    out = {}
    for ln in open(os.path.join(B, 'labels.txt')):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


class Game:
    def __init__(self):
        self.lab = labels()
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
        for addr, name in ((0x1900, 'L32M'), (0x7000, 'L32')):
            data = open(os.path.join(B, name), 'rb').read()
            mem._subject[addr:addr + len(data)] = data
        self.call(self.lab['takeover'])                # (the loader's start-up)
        self.mpu.memory[self.lab['back']] = 0
        self.call(self.lab['setback'])
        self.call(self.lab['ginit'])
        mem._subject[0x5000:0x8000] = bytes(0x3000)   # (clr's: the loader's pages)

    def call(self, addr):
        m = self.mpu
        m.memory[0x1FF], m.memory[0x1FE] = (RET - 1) >> 8, (RET - 1) & 0xFF
        m.sp = 0xFD
        m.pc = addr
        start = m.processorCycles
        while m.pc != RET:
            m.step()
            if m.processorCycles - start > 3000000:
                raise RuntimeError(f'${addr:04X} still running at ${m.pc:04X}')
        return m.processorCycles - start

    def rd(self, name, n=1):
        a = self.lab[name]
        return [self.mpu.memory[a + i] for i in range(n)]

    def frame(self, keys, vs=None):
        self.held = {KEYS[k] for k in keys}
        m = self.mpu.memory
        c = 0
        if vs is None and os.environ.get('GT_VS') == 'real':   # the syncs vcount moves
            vs = max(4, -(-getattr(self, 'last', 0) // 40000))   # on (no interrupts
        elif vs is None:                                         # here): FMIN, or with
            vs = 4                      # GT_VS=real what the last frame's cycles would
                                        # take; only flip, strips' wait and the readout
                                        # read vcount: one step a frame whatever it is
        m[self.lab['vcount']] = (m[self.lab['vcount']] + vs) & 255
        for r in ('gstep', 'project', 'strips', 'gpre', 'ship', 'gpost', 'readout'):
            if r == 'ship' and not m[GSHV]:
                continue
            c += self.call(self.lab[r])
        c += self.call(self.lab['flip'])  # (with setback: the frame's own work)
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
                f"k {r('gk')[0]:2d} p {r('gp')[0]:2d} landed {r('landed')[0]} ctim {r('ctim')[0]:2d} "
                f"hg {self.mpu.memory[HGV]} came {self.mpu.memory[CAME]} shy {self.mpu.memory[GSHY]}")


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
