#!/usr/bin/env python3
"""The worst-case stack, from the linked program.

    python3 b32/tools/stackdepth.py [BUILD]        (default build32)

The image is rebuilt from LANDER as the loader places it, and its code walked from
`loop` and from `irq`: every path, a JSR adding 2 and its callee's depth, PHA/PHP 1 and
PLA/PLP -1.  A jump or call whose bytes the program patches (an absolute store in the code
lands on it) is followed as assembled, and listed; one whose target is outside the code
(the generated parity tables and fills, which return or jump straight back) ends the
path there, listed too.  In irq, a CLI lets the
vertical sync's interrupt nest (3 bytes and irq again, without nesting).

Prints each root's depth, the exits, the code no root reaches (the loader's apart), and
the total the stack must hold: loop + an IRQ (3 + irq) + an NMI (3, its RTI).
"""
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
B = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'build32')

# mode: (bytes, kind); kinds: '' plain, 'rel' branch, 'abs' absolute operand
MODES = {'imp': 1, 'acc': 1, 'imm': 2, 'zp': 2, 'zpx': 2, 'zpy': 2, 'izx': 2, 'izy': 2,
         'rel': 2, 'abs': 3, 'abx': 3, 'aby': 3, 'ind': 3}
OPS = {}
for row in """
ADC 69imm 65zp 75zpx 6Dabs 7Dabx 79aby 61izx 71izy|AND 29imm 25zp 35zpx 2Dabs 3Dabx 39aby 21izx 31izy
ASL 0Aacc 06zp 16zpx 0Eabs 1Eabx|BIT 24zp 2Cabs|BPL 10rel|BMI 30rel|BVC 50rel|BVS 70rel|BCC 90rel
BCS B0rel|BNE D0rel|BEQ F0rel|BRK 00imp|CMP C9imm C5zp D5zpx CDabs DDabx D9aby C1izx D1izy
CPX E0imm E4zp ECabs|CPY C0imm C4zp CCabs|DEC C6zp D6zpx CEabs DEabx|EOR 49imm 45zp 55zpx 4Dabs 5Dabx 59aby 41izx 51izy
CLC 18imp|SEC 38imp|CLI 58imp|SEI 78imp|CLV B8imp|CLD D8imp|SED F8imp|INC E6zp F6zpx EEabs FEabx
JMP 4Cabs 6Cind|JSR 20abs|LDA A9imm A5zp B5zpx ADabs BDabx B9aby A1izx B1izy|LDX A2imm A6zp B6zpy AEabs BEaby
LDY A0imm A4zp B4zpx ACabs BCabx|LSR 4Aacc 46zp 56zpx 4Eabs 5Eabx|NOP EAimp|ORA 09imm 05zp 15zpx 0Dabs 1Dabx 19aby 01izx 11izy
TAX AAimp|TXA 8Aimp|DEX CAimp|INX E8imp|TAY A8imp|TYA 98imp|DEY 88imp|INY C8imp
ROL 2Aacc 26zp 36zpx 2Eabs 3Eabx|ROR 6Aacc 66zp 76zpx 6Eabs 7Eabx|RTI 40imp|RTS 60imp
SBC E9imm E5zp F5zpx EDabs FDabx F9aby E1izx F1izy|STA 85zp 95zpx 8Dabs 9Dabx 99aby 81izx 91izy
TXS 9Aimp|TSX BAimp|PHA 48imp|PLA 68imp|PHP 08imp|PLP 28imp|STX 86zp 96zpy 8Eabs|STY 84zp 94zpx 8Cabs
""".replace('\n', '|').split('|'):
    if row.strip():
        mn, *codes = row.split()
        for c in codes:
            OPS[int(c[:2], 16)] = (mn, c[2:])


def labels():
    lab = {}
    for ln in open(os.path.join(B, 'labels.txt')):
        _, a, n = ln.split()
        lab[n.lstrip('.')] = int(a, 16)
    return lab


def segments():
    """{name: (start, end)} from the map's segment list (run addresses)."""
    seg, on = {}, False
    for ln in open(os.path.join(B, 'map.txt')):
        if ln.startswith('Segment list'):
            on = True
        elif on and ln.startswith('Exports'):
            break
        elif on:
            p = ln.split()
            if len(p) == 5 and p[1] != 'Start':
                seg[p[0]] = (int(p[1], 16), int(p[2], 16) + 1)
    return seg


def main():
    lab, seg = labels(), segments()
    m = bytearray(65536)
    f = open(os.path.join(B, 'LANDER'), 'rb').read()
    m[0x2000:0x2000 + len(f)] = f
    code = []
    for s in ('CODE', 'T0', 'T1', 'T2', 'T3', 'T4'):
        ld, run, n = lab[f'__{s}_LOAD__'], lab[f'__{s}_RUN__'], lab[f'__{s}_SIZE__']
        m[run:run + n] = f[ld - 0x2000:ld - 0x2000 + n]
        code.append((run, run + n))
    incode = lambda a: any(lo <= a < hi for lo, hi in code)
    rev = {}
    for n, a in sorted(lab.items()):
        if not n.startswith(('@', '__')):
            rev.setdefault(a, n)

    def name(a):
        if not incode(a):
            return rev.get(a, f'${a:04X}')
        best = max(x for x in rev if x <= a)
        return rev[best] if a == best else f'{rev[best]}+{a - best}'

    def decode(pc):
        mn, mode = OPS.get(m[pc], ('???', 'imp'))
        n = MODES[mode]
        opnd = m[pc + 1] | m[pc + 2] << 8 if n == 3 else m[pc + 1]
        return mn, mode, n, opnd

    patched = set()                 # every byte an absolute store in the code writes
    for lo, hi in code:
        pc = lo
        while pc < hi:
            mn, mode, n, opnd = decode(pc)
            if mn in ('STA', 'STX', 'STY') and mode in ('abs', 'abx', 'aby') and incode(opnd):
                patched.add(opnd)
            pc += n

    memo, exits, reached, varied = {}, {}, set(), set()

    def walk(entry, nest=0):
        """the most bytes pushed below entry's stack pointer on any path from it"""
        key = (entry, nest)
        if key in memo:
            return memo[key]
        memo[key] = 0
        peak, todo, seen = 0, [(entry, 0)], set()
        while todo:
            pc, d = todo.pop()
            if (pc, d) in seen or d > 64:
                continue
            seen.add((pc, d))
            reached.add(pc)
            peak = max(peak, d)
            mn, mode, n, opnd = decode(pc)
            nxt = pc + n
            if mn in ('JMP', 'JSR') and {pc, pc + 1, pc + 2} & patched:
                varied.add(pc)
            if mn in ('JMP', 'JSR') and (mode == 'ind' or not incode(opnd)):
                exits.setdefault(pc, f'{mn} {name(opnd)}' if mode != 'ind' else 'JMP (ind)')
                if mn == 'JSR':
                    peak = max(peak, d + 2)
                    todo.append((nxt, d))
                continue
            if mn in ('PHA', 'PHP'):
                todo.append((nxt, d + 1))
                peak = max(peak, d + 1)
            elif mn in ('PLA', 'PLP'):
                todo.append((nxt, d - 1))
            elif mn in ('RTS', 'RTI'):
                pass
            elif mn == 'JSR':
                peak = max(peak, d + 2 + walk(opnd, nest))
                todo.append((nxt, d))
            elif mn == 'JMP':
                todo.append((opnd, d))
            elif mode == 'rel':
                todo.append((nxt, d))
                todo.append((nxt + (opnd - 256 if opnd & 128 else opnd), d))
            elif mn == 'CLI' and nest:
                peak = max(peak, d + 3 + nest)
                todo.append((nxt, d))
            elif mn in ('BRK', '???'):
                exits.setdefault(pc, f'{mn} at {name(pc)}')
            else:
                todo.append((nxt, d))
        memo[key] = peak
        return peak

    loop = walk(lab['loop'])
    irq0 = walk(lab['irq'])
    irq1 = walk(lab['irq'], nest=irq0)
    print(f'loop: {loop} bytes')
    print(f'irq: {irq1} bytes ({irq0} unnested)')
    total = loop + 3 + irq1 + 3
    print(f'total: {total} bytes (loop + an IRQ + an NMI); the stack holds {0x200 - lab["STACK"]}')
    print('patched jumps, followed as assembled:', ' '.join(name(pc) for pc in sorted(varied)))
    print('exits not followed:')
    for pc in sorted(exits):
        print(f'  {name(pc):14s} {exits[pc]}')
    unreached = sorted(a for a in rev if incode(a) and a not in reached and not rev[a].startswith('LOCAL'))
    print('code labels no root reaches:', ' '.join(rev[a] for a in unreached) or 'none')
    return total <= 0x200 - lab['STACK']


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
