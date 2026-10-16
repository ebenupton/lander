#!/usr/bin/env python3
"""The game loop run in py65 with scripted keys, the ship's state printed each
frame.  For debugging src/game.s; exit status 0 unless a frame fails to run.

    python3 test/gametest.py [script]      default "10:,20:T,30:"

    script  frames:keys, comma separated: that many frames with those keys
            held.  Keys (the game's, src/game.s `keys`): L Z (yaw left),
            R X (yaw right), F K (nose down), B M (nose up), T SPACE (thrust),
            H SHIFT (full thrust too), P F (LAND's frame-rate readout on or
            off: fpson, which nothing here reads).  The cursor keys, which
            `keys` also scans for the same bits, are not faked.  A part
            may end in @dx,dy[,buttons]: the mouse moved dx, dy units in
            each of those frames (multiples of 4, y up) with the buttons
            held (L left: full thrust, M middle: hover, R right: nothing).

    --mouse  the mouse fitted ($FCAC..$FCAF; else they read 0, no mouse)

Each line: the frame number, the keys, the frame's cycles (frame()'s: see
there), then state(): x, z (tiles), y (height units, 16 a tile), v (gvx,
gvy, gvz, 16-bit), k, p (direction, pitch), fuel, landed, ctim (crash steps
left), hg (HGV: the ground under the ship), came (CAME), shy (GSHY: the
ship's line).

Importable: Game() builds the machine and runs G_INIT; frame(keys) runs a
frame; state() describes the ship; rd(name, n) reads n bytes at a label.

The machine: build/LAND at $1900; TABLES, TABLES2, SHIPB and TABLES7 as
sideways banks 4..7, a write to ROMSEL ($FE30) paging one in at $8000 (the
bank paged out keeps the writes made to it).  The keyboard at the system
VIA's port A ($FE4F): the game writes a key's number there and reads bit 7
for pressed; here the write selects the key and the read returns bit 7 set
if it is in the held set (psg's bytes to the sound chip go through the same
register: each only selects a key, which the next key's write replaces; the
VIA's and CRTC's other registers are plain memory).  No OS and no LANDS: the
game's letters at GLY5 (bank 5's $BE00, which LANDS's glyphs5 fills from the
OS's character set) are zero in build/TABLES2, so G_INIT's FUEL label draws
blank.  `init` run, `back` set to 0 and `setback` run, as LAND's start does,
then G_INIT.

A frame, as LAND's main loop without the readout: vcount advanced by vs (the
vertical syncs the event handler would have counted: `strips` waits for one
since the flip and `flip` for FMIN, 4); G_STEP (the keys, a step of flight,
the camera); B6_KEYS (the ship's attitude and place into bank 6); `project`;
`strips`; G_PRE (the dots beyond the ship); B6_SHIP if GSHV (not while
crashed); G_POST (the other dots, the map, the status); `flip`.
"""
import os
import sys

from py65.devices.mpu6502 import MPU
from py65.memory import ObservableMemory

ROOT = os.path.join(os.path.dirname(__file__), '..')
B = os.path.join(ROOT, 'build')
RET = 0xFF00                                     # where a call returns to
ROMSEL = 0xFE30
SVIA_ORA_NH = 0xFE4F
B6_KEYS, B6_SHIP = 0x00, 0x03                    # bank 6's entries, call6's A
G_INIT, G_STEP, G_POST, G_PRE = 0x00, 0x03, 0x06, 0x09   # bank 5's, call5's A
CAME, HGV, GSHY, GSHV = 0x07D6, 0x07D7, 0x07DE, 0x07DF   # LAND's and the game's
KEYS = {'L': 0x61, 'R': 0x42, 'F': 0x46, 'B': 0x65, 'T': 0x62, 'H': 0x00, 'P': 0x43}


def labels(f='labels.txt'):
    """ld65's label file in build/ (lines "al <hex> .<name>"): {name: address}."""
    out = {}
    for ln in open(os.path.join(B, f)):
        _, a, name = ln.split()
        out[name.lstrip('.')] = int(a, 16)
    return out


class Game:
    """LAND and the game in py65, with the faked bank switching and keyboard."""

    def __init__(self, mouse=False):
        self.lab = labels()
        self.mouse = mouse                       # the mouse at $FCAC..$FCAF:
        self.mdx = self.mdy = 0                  # movement since the last read
        self.mbut = ''                           # and the buttons held
        self.mlat = (0, 0)                       # (as latched by $FCAC's read)
        self.banks = {4: bytearray(open(os.path.join(B, 'TABLES'), 'rb').read()),
                      5: bytearray(open(os.path.join(B, 'TABLES2'), 'rb').read()),
                      6: bytearray(open(os.path.join(B, 'SHIPB'), 'rb').read().ljust(0x4000, b'\0')),
                      7: bytearray(open(os.path.join(B, 'TABLES7'), 'rb').read())}
        self.mem = mem = ObservableMemory()
        self.cur = 4                             # the bank paged in
        self.held = set()                        # the keys held, by number
        self.sel = 0                             # the key the game last selected

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
        def mouse_r(addr):
            if not self.mouse:
                return 0
            if addr == 0xFCAC:
                self.mlat = (self.mdx & 0x3FFF, self.mdy & 0x3FFF)
                self.mdx = self.mdy = 0
            x, y = self.mlat
            return {0xFCAC: x & 0xFF,
                    0xFCAD: x >> 8 | ('L' in self.mbut) << 6 | ('R' in self.mbut) << 7,
                    0xFCAE: y & 0xFF,
                    0xFCAF: y >> 8 | ('M' in self.mbut) << 6 | 0x80}[addr]
        mem.subscribe_to_read([0xFCAC, 0xFCAD, 0xFCAE, 0xFCAF], mouse_r)
        mem.subscribe_to_write([ROMSEL], romsel)
        mem.subscribe_to_write([SVIA_ORA_NH], ora_w)
        mem.subscribe_to_read([SVIA_ORA_NH], ora_r)
        self.mpu = MPU(memory=mem)
        code = open(os.path.join(B, 'LAND'), 'rb').read()
        self.mpu.memory[0x1900:0x1900 + len(code)] = code
        mem._subject[0x8000:0xC000] = self.banks[4]
        self.call(self.lab['init'])
        self.mpu.memory[self.lab['back']] = 0
        self.call(self.lab['setback'])
        self.call5(G_INIT)

    def call(self, addr):
        """Run the routine at addr as if by JSR (a return to RET pushed) until
        it returns; its cycles.  Raises after 3M cycles."""
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
        """LAND's call5: bank 5's routine at $A100 + a, bank 4 back after."""
        self.mpu.a = a
        return self.call(self.lab['call5'])

    def call6(self, a):
        """LAND's call6: bank 6's routine at $8000 + a, bank 4 back after."""
        self.mpu.a = a
        return self.call(self.lab['call6'])

    def rd(self, name, n=1, bank=5):
        """The n bytes at label name: a sideways address read from that bank
        (paged in or not), any other from memory."""
        a = self.lab[name]
        if 0x8000 <= a < 0xC000:
            src = self.mem._subject if self.cur == bank else self.banks[bank]
            off = a if self.cur == bank else a - 0x8000
            v = [src[off + i] for i in range(n)]
        else:
            v = [self.mpu.memory[a + i] for i in range(n)]
        return v

    def frame(self, keys, vs=4, mdx=0, mdy=0, mbut=''):
        """A frame with the keys (a string of KEYS' letters) held, vcount
        advanced by vs; the cycles of G_STEP, project, strips, G_PRE,
        B6_SHIP and G_POST, the bank calls through call5 and call6 with
        their paging (not B6_KEYS, flip or the JSRs' own 6)."""
        self.held = {KEYS[k] for k in keys}
        self.mdx += mdx
        self.mdy += mdy
        self.mbut = mbut
        m = self.mpu.memory
        m[self.lab['vcount']] = (m[self.lab['vcount']] + vs) & 255
        c = self.call5(G_STEP)
        self.call6(B6_KEYS)
        c += self.call(self.lab['project'])
        c += self.call(self.lab['strips'])
        c += self.call5(G_PRE)
        if m[GSHV]:
            c += self.call6(B6_SHIP)
        c += self.call5(G_POST)
        self.call(self.lab['flip'])
        return c

    def state(self):
        """The ship's state as one line (see the module docstring)."""
        def s24(v):
            x = v[0] | v[1] << 8 | v[2] << 16
            return (x - (1 << 24) if x & 0x800000 else x) / 65536

        def s16(v):
            x = v[0] | v[1] << 8
            return x - 65536 if x & 0x8000 else x
        def s8(v):
            return v - 256 if v & 128 else v
        r = self.rd
        return (f"x {s24(r('sx', 3)):7.3f} z {s24(r('sz', 3)):7.3f} y {s24(r('sy', 3)) * 16:6.2f}u "
                f"v {s16(r('gvx', 2)):6d} {s16(r('gvy', 2)):6d} {s16(r('gvz', 2)):6d} "
                f"k {r('gk')[0]:2d} p {r('gp')[0]:2d} ptr {s8(r('gmx')[0]):4d} {s8(r('gmy')[0]):4d} "
                f"fuel {r('fuel', 2)[0] | r('fuel', 2)[1] << 8:5d} landed {r('landed')[0]} "
                f"ctim {r('ctim')[0]:2d} "
                f"hg {self.mpu.memory[HGV]} came {self.mpu.memory[CAME]} shy {self.mpu.memory[GSHY]}")


def main():
    args = [a for a in sys.argv[1:] if a != '--mouse']
    script = args[0] if args else '10:,20:T,30:'
    g = Game(mouse='--mouse' in sys.argv[1:])
    f = 0
    for part in script.split(';' if ';' in script else ','):
        n, keys = part.split(':')
        mdx = mdy = 0
        mbut = ''
        if '@' in keys:
            keys, m = keys.split('@')
            m = m.split(',')
            mdx, mdy = int(m[0]), int(m[1])
            mbut = m[2] if len(m) > 2 else ''
        for _ in range(int(n)):
            c = g.frame(keys, mdx=mdx, mdy=mdy, mbut=mbut)
            print(f'{f:4d} {keys:4s} {c:7d} {g.state()}')
            f += 1


if __name__ == '__main__':
    main()
