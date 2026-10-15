#!/usr/bin/env python3
"""Run LAND's game loop in py65 (no OS: the keyboard faked at the system VIA), with
scripted keys, and print the ship's state each frame.  For debugging src/game.s.

    python3 test/gametest.py [script]     script: frames:keys,... e.g. "20:,30:T,40:TK"
                                          keys: L R F B (mouse), T thrust, H hover, P the F key (frame rate)
"""
import os
import sys

from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROOT = os.path.join(os.path.dirname(__file__), '..')
B = os.path.join(ROOT, 'build')
RET = 0xFF00
KEYS = {'L': 0x61, 'R': 0x42, 'F': 0x46, 'B': 0x65, 'T': 0x62, 'H': 0x00, 'P': 0x43}


def labels(f='labels.txt'):
    out = {}
    for ln in open(os.path.join(B, f)):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


class Game:
    def __init__(self):
        self.lab = labels()
        self.banks = {4: bytearray(open(os.path.join(B, 'TABLES'), 'rb').read()),
                      5: bytearray(open(os.path.join(B, 'TABLES2'), 'rb').read()),
                      6: bytearray(open(os.path.join(B, 'SHIPB'), 'rb').read().ljust(0x4000, b'\0')),
                      7: bytearray(open(os.path.join(B, 'TABLES7'), 'rb').read())}
        self.mem = mem = ObservableMemory()
        self.cur = 4
        self.held = set()
        self.sel = 0

        def romsel(addr, value):
            if value in self.banks and value != self.cur:
                self.banks[self.cur][:] = bytes(mem._subject[0x8000:0xC000])
                mem._subject[0x8000:0xC000] = self.banks[value]
                self.cur = value
            return value

        def ora_w(addr, value):
            self.sel = value & 0x7F
            return value

        def ora_r(addr):
            return self.sel | (0x80 if self.sel in self.held else 0)
        mem.subscribe_to_write([0xFE30], romsel)
        mem.subscribe_to_write([0xFE4F], ora_w)
        mem.subscribe_to_read([0xFE4F], ora_r)
        self.mpu = MPU(memory=mem)
        code = open(os.path.join(B, 'LAND'), 'rb').read()
        self.mpu.memory[0x1900:0x1900 + len(code)] = code
        mem._subject[0x8000:0xC000] = self.banks[4]
        # GLY digits: fake glyphs (the OS makes them)
        for i in range(256):
            self.mpu.memory[0x1800 + i] = 0
        self.call(self.lab['init'])
        self.mpu.memory[self.lab['back']] = 0
        self.call(self.lab['setback'])
        self.call5(0x00)

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

    def call5(self, a):
        self.mpu.a = a
        return self.call(self.lab['call5'])

    def rd(self, name, n=1, bank=5):
        a = self.lab[name]
        if 0x8000 <= a < 0xC000:
            src = self.mem._subject if self.cur == bank else self.banks[bank]
            off = a if self.cur == bank else a - 0x8000
            v = [src[off + i] for i in range(n)]
        else:
            v = [self.mpu.memory[a + i] for i in range(n)]
        return v

    def frame(self, keys, vs=4):
        self.held = {KEYS[k] for k in keys}
        m = self.mpu.memory
        m[self.lab['vcount']] = (m[self.lab['vcount']] + vs) & 255
        c = self.call5(0x03)
        self.mpu.a = 0x00
        self.call(self.lab['call6'])
        c += self.call(self.lab['project'])
        c += self.call(self.lab['strips'])
        c += self.call5(0x09)
        if m[0x07DF]:
            self.mpu.a = 0x03
            c += self.call(self.lab['call6'])
        c += self.call5(0x06)
        self.call(self.lab['flip'])
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
                f"m {r('gmx')[0]:3d} {r('gmz')[0]:3d} k {r('gk')[0]:2d} p {r('gp')[0]} "
                f"fuel {r('fuel', 2)[0] | r('fuel', 2)[1] << 8:5d} landed {r('landed')[0]} "
                f"ctim {r('ctim')[0]:2d} L {r('nland')[0]:02X} C {r('ncrash')[0]:02X} "
                f"hg {self.mpu.memory[0x07D7]} came {self.mpu.memory[0x07D6]} shy {self.mpu.memory[0x07DE]}")


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
