#!/usr/bin/env python3
"""The worst-case stack, from the linked program.

    python3 b32/tools/stackdepth.py [BUILD]        (default build32; buildswr)

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


def segments(f='map.txt'):
    """{name: (start, end)} from a map's segment list (run addresses)."""
    seg, on = {}, False
    for ln in open(os.path.join(B, f)):
        if ln.startswith('Segment list'):
            on = True
        elif on and ln.startswith('Exports'):
            break
        elif on:
            p = ln.split()
            if len(p) == 5 and p[1] != 'Start':
                seg[p[0]] = (int(p[1], 16), int(p[2], 16) + 1)
    return seg


def image(lab, seg):
    """(fetch, spaces): fetch(a, bank) the byte at a with `bank` paged in; spaces the
    code's address ranges, [(lo, hi, bank)], bank None for main RAM."""
    m = bytearray(65536)
    spaces = []
    swr = 'B4CODE' in seg
    f = open(os.path.join(B, 'LAND' if swr else 'LANDER'), 'rb').read()
    base = 0x3000 if swr else 0x2000
    m[base:base + len(f)] = f
    for s in ('CODE', 'T0', 'T1', 'T2', 'T3', 'T4'):
        if f'__{s}_LOAD__' not in lab:
            continue
        ld, run, n = lab[f'__{s}_LOAD__'], lab[f'__{s}_RUN__'], lab[f'__{s}_SIZE__']
        m[run:run + n] = f[ld - base:ld - base + n]
        spaces.append((run, run + n, None))
    banks = {}
    if swr:
        for n in (4, 5, 6, 7):
            banks[n] = open(os.path.join(B, f'B{n}'), 'rb').read().ljust(0x4000, b'\0')
        spaces += [(*seg['B4CODE'], 4), (*seg['B5CODE'], 5), (*seg['B7CODE'], 7)]
        for name, (lo, hi) in segments('shipb_map.txt').items():
            if name in ('CODE', 'TAIL'):
                spaces.append((lo, hi, 6))

    def fetch(a, bank):
        if 0x8000 <= a < 0xC000 and bank in banks:
            return banks[bank][a - 0x8000]
        return m[a]
    return fetch, spaces


def main():
    lab, seg = labels(), segments()
    fetch, spaces = image(lab, seg)
    pages = {lab[f'pg{n}']: n for n in (4, 5, 6, 7) if f'pg{n}' in lab}

    def space(a, bank):
        """the code range holding a with `bank` paged in, or None"""
        for lo, hi, b in spaces:
            if lo <= a < hi and (b is None or b == bank):
                return (lo, hi, b)
        return None
    rev = {}
    for n, a in sorted(lab.items()):
        if not n.startswith(('@', '__')):
            rev.setdefault(a, n)

    def name(a, bank=None):
        if not space(a, bank):
            return rev.get(a, f'${a:04X}')
        best = max(x for x in rev if x <= a)
        return rev[best] if a == best else f'{rev[best]}+{a - best}'

    def decode(pc, bank):
        mn, mode = OPS.get(fetch(pc, bank), ('???', 'imp'))
        n = MODES[mode]
        b1, b2 = fetch(pc + 1, bank), fetch(pc + 2, bank)
        opnd = b1 | b2 << 8 if n == 3 else b1
        return mn, mode, n, opnd

    patched = set()                 # (address, bank): bytes an absolute store in the code
    for lo, hi, b in spaces:        # writes (its own space's)
        pc = lo
        while pc < hi:
            mn, mode, n, opnd = decode(pc, b)
            if mn in ('STA', 'STX', 'STY') and mode in ('abs', 'abx', 'aby'):
                sp = space(opnd, b)
                if sp:
                    patched.add((opnd, sp[2]))
            pc += n

    memo, exits, reached, varied, errors = {}, {}, set(), set(), []

    def walk(entry, bank, nest=0):
        """(the most bytes pushed below entry's stack pointer on any path from it, the
        bank paged in at its RTS)"""
        key = (entry, bank, nest)
        if key in memo:
            return memo[key]
        memo[key] = (0, bank)
        peak, out, todo, seen = 0, set(), [(entry, 0, bank)], set()
        while todo:
            pc, d, bk = todo.pop()
            if (pc, d, bk) in seen or d > 64:
                continue
            seen.add((pc, d, bk))
            here = space(pc, bk)
            if not here:
                errors.append(f'{name(pc)} (${pc:04X}) run with bank {bk} paged: not code there')
                continue
            reached.add((pc, here[2]))
            peak = max(peak, d)
            mn, mode, n, opnd = decode(pc, bk)
            nxt = pc + n
            if mn in ('JMP', 'JSR') and {(pc, here[2]), (pc + 1, here[2]), (pc + 2, here[2])} & patched:
                varied.add((pc, here[2]))
            if mn in ('JMP', 'JSR') and mode != 'ind' and opnd in pages:
                nb = pages[opnd]
                if here[2] is not None and nb != here[2]:
                    errors.append(f'{name(pc, bk)}: bank {here[2]}\'s code pages in bank {nb}')
                peak = max(peak, d + 2)
                if mn == 'JSR':
                    todo.append((nxt, d, nb))
                else:
                    out.add(nb)
                continue
            if mn in ('JMP', 'JSR') and (mode == 'ind' or not space(opnd, bk)):
                exits.setdefault(pc, f'{mn} {name(opnd, bk)}' if mode != 'ind' else 'JMP (ind)')
                if mn == 'JSR':
                    peak = max(peak, d + 2)
                    todo.append((nxt, d, bk))
                continue
            if mn in ('PHA', 'PHP'):
                todo.append((nxt, d + 1, bk))
                peak = max(peak, d + 1)
            elif mn in ('PLA', 'PLP'):
                todo.append((nxt, d - 1, bk))
            elif mn in ('RTS', 'RTI'):
                out.add(bk)
            elif mn == 'JSR':
                cp, cb = walk(opnd, bk, nest)
                peak = max(peak, d + 2 + cp)
                todo.append((nxt, d, cb))
            elif mn == 'JMP':
                todo.append((opnd, d, bk))
            elif mode == 'rel':
                todo.append((nxt, d, bk))
                todo.append((nxt + (opnd - 256 if opnd & 128 else opnd), d, bk))
            elif mn == 'CLI' and nest:
                peak = max(peak, d + 3 + nest)
                todo.append((nxt, d, bk))
            elif mn in ('BRK', '???'):
                exits.setdefault(pc, f'{mn} at {name(pc, bk)}')
            else:
                todo.append((nxt, d, bk))
        if len(out) > 1:
            errors.append(f'{name(entry, bank)}: returns with banks {sorted(out)} paged')
        memo[key] = (peak, min(out) if out else bank)
        return memo[key]

    home = 4 if pages else None
    loop, _ = walk(lab['loop'], home)
    irq0, _ = walk(lab['irq'], home)
    irq1, _ = walk(lab['irq'], home, nest=irq0)
    print(f'loop: {loop} bytes')
    print(f'irq: {irq1} bytes ({irq0} unnested)')
    total = loop + 3 + irq1 + 3
    print(f'total: {total} bytes (loop + an IRQ + an NMI); the stack holds {0x200 - lab["STACK"]}')
    print('patched jumps, followed as assembled:', ' '.join(name(pc, b) for pc, b in sorted(varied, key=str)))
    print('exits not followed:')
    for pc in sorted(exits):
        print(f'  {name(pc):14s} {exits[pc]}')
    unreached = sorted(a for a in rev if any(space(a, b) for b in (None, 4, 5, 6, 7))
                       and not any((a, b) in reached for b in (None, 4, 5, 6, 7))
                       and not rev[a].startswith('LOCAL'))
    print('code labels no root reaches:', ' '.join(rev[a] for a in unreached) or 'none')
    for e in sorted(set(errors)):
        print('ERROR', e)
    return total <= 0x200 - lab['STACK'] and not errors


if __name__ == '__main__':
    sys.exit(0 if main() else 1)
