#!/usr/bin/env python3
"""The memory maps, from the builds themselves.

    python3 tools/memmap.py BUILD [DOCS]       write the maps (DOCS default docs)
    python3 tools/memmap.py BUILD DOCS check   exit 1 if they are not current

Writes DOCS/map-base.md and DOCS/map-swr.md whole, and the blocks of
DOCS/memory-map.md between its `<!-- generated: summary -->` and `<!-- generated: disc
-->` markers and their `<!-- end -->`.

BUILD is build.sh's output directory, with its eight builds and the loader (the disc's
catalogue is tools/mkdisc.py's).  Every address and size is read from the link: ld65's
debug file (lander.dbg: each label's address and size, each segment, each source line's
bytes), its labels (labels.txt), the bank tables' list (banktab.txt, from tools/gen.py),
bank 6's own link (shipb_map.txt) and tools/stackdepth.py's total.  The words beside
each variable are its comment in src/ram.s.  Nothing is typed in by hand, so the maps
cannot differ from the program; test/gate.sh runs `check` on the default build.

Each file has: the regions of main RAM (MODE 1 version) with every byte accounted for;
the sizes that differ by version; every variable of zero page, pages 1 and 2 and the
workspace by address; the stored tables; the code by source file; the generated pages;
the screen; and, for the sideways RAM build, each bank by address.
"""
import os
import re
import subprocess
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')
VERSIONS = ('mode1', 'cpc', 'nula', 'arc')
TITLE = {'base': 'the 32K build', 'swr': 'the sideways RAM build'}


def fields(ln):
    out = {}
    for kv in re.findall(r'(\w+)=("[^"]*"|[^,]*)', ln.rstrip('\n').split('\t', 1)[1]):
        out[kv[0]] = kv[1].strip('"')
    return out


class Build:
    def __init__(self, path):
        self.path = path
        self.segs, self.files, self.spans, self.lines, self.syms = {}, {}, {}, [], []
        for ln in open(os.path.join(path, 'lander.dbg')):
            kind = ln.split('\t', 1)[0]
            if kind not in ('seg', 'file', 'span', 'line', 'sym'):
                continue
            f = fields(ln)
            if kind == 'seg':
                self.segs[int(f['id'])] = (f['name'], int(f['start'], 16), int(f['size'], 16))
            elif kind == 'file':
                self.files[int(f['id'])] = os.path.basename(f['name'])
            elif kind == 'span':
                self.spans[int(f['id'])] = (int(f['seg']), int(f['start']), int(f['size']))
            elif kind == 'line' and 'span' in f and 'type' not in f:
                self.lines.append((int(f['file']), [int(s) for s in f['span'].split('+')]))
            elif kind == 'sym' and f.get('type') == 'lab':
                self.syms.append((int(f['val'], 16), f['name'], int(f['size']) if 'size' in f else None,
                                  int(f['seg']) if 'seg' in f else None))
        self.syms = [(a, n, s, None if g is None else self.segs[g][0]) for a, n, s, g in self.syms]
        self.lab = {}
        for ln in open(os.path.join(path, 'labels.txt')):
            _, a, name = ln.split()
            self.lab[name.lstrip('.')] = int(a, 16)
        self.seg = {name: (start, size) for name, start, size in self.segs.values()}

    def by_file(self, segnames):
        """{source file: bytes} of the segments named."""
        owner = {}                      # each byte's line: the shortest span over it
        for fid, spans in self.lines:
            for s in spans:
                seg, start, size = self.spans[s]
                if self.segs[seg][0] in segnames:
                    for i in range(start, start + size):
                        if (seg, i) not in owner or size < owner[seg, i][0]:
                            owner[seg, i] = (size, fid)
        out = {}
        for size, fid in owner.values():
            out[self.files[fid]] = out.get(self.files[fid], 0) + 1
        return out

    def data(self, lo, hi):
        """The .org'd labels (src/ram.s's) in lo .. hi-1: [(address, name, size)]."""
        v = sorted((a, n, s) for a, n, s, seg in self.syms if seg is None and lo <= a < hi and s)
        return v

    def stored(self, segname):
        """A stored segment's labels with the bytes to the next: [(address, name, size)]."""
        start, size = self.seg[segname]
        v = sorted((a, n) for a, n, s, seg in self.syms if seg == segname)
        out = []
        for i, (a, n) in enumerate(v):
            end = v[i + 1][0] if i + 1 < len(v) else start + size
            if end > a:
                out.append((a, n, end - a))
        return out


def comments(defs):
    """src/ram.s's comment for each label, with `defs` defined (SWR, ARC, MODE2)."""
    out, stack, last = {}, [], None
    for ln in open(os.path.join(ROOT, 'src', 'ram.s')):
        ln = ln.rstrip('\n')
        m = re.match(r'\.(ifdef|ifndef|else|endif)\s*(\w*)', ln)
        if m:
            if m.group(1) == 'ifdef':
                stack.append(m.group(2) in defs)
            elif m.group(1) == 'ifndef':
                stack.append(m.group(2) not in defs)
            elif m.group(1) == 'else':
                stack[-1] = not stack[-1]
            else:
                stack.pop()
            last = None
            continue
        if not all(stack):
            continue
        m = re.match(r'(\w+):\s+\.res\s+[^;]*(?:;\s*(.*))?$', ln)
        if m:
            last = m.group(1)
            out[last] = m.group(2) or ''
            continue
        m = re.match(r'\s{20,};\s*(.*)$', ln)
        if m and last:
            out[last] = (out[last] + ' ' + m.group(1)).strip()
        elif not re.match(r'\s*$', ln):
            if not re.match(r'\s+\.res', ln):
                last = None
    return out


def h(a):
    return f'`${a:04X}`'


def rows(items, lo, hi, cm):
    """Table rows for [(address, name, size)] in lo .. hi-1, the gaps as free; and the
    free bytes."""
    out, at, free = [], lo, 0
    for a, n, s in items:
        if a > at:
            out.append(f'| {h(at)} | {a - at} | | free |')
            free += a - at
        out.append(f'| {h(a)} | {s} | `{n}` | {cm.get(n, "")} |')
        at = max(at, a + s)
    if hi > at:
        out.append(f'| {h(at)} | {hi - at} | | free |')
        free += hi - at
    return out, free


def table(head, body):
    return ['| ' + ' | '.join(head) + ' |', '|' + '---|' * len(head)] + body + ['']


def region_rows(b, swr):
    """The regions of main RAM: [(from, to (exclusive), what)]."""
    L, S = b.lab, b.seg
    r = [(0x0000, S['ZEROPAGE'][0] + S['ZEROPAGE'][1], 'zero page: the variables'),
         (None, 0x00FC, 'free'),
         (0x00FC, 0x0100, 'the MOS\'s: `$FC`, where its interrupt entry saves A; `$FD`-`$FF`'),
         (0x0100, L['STACK'], 'page 1: variables and tables below the stack'),
         (L['STACK'], 0x0200, 'the stack'),
         (0x0200, 0x0206, 'the MOS\'s vectors: `USERV`, `BRKV`, `IRQ1V` (the program\'s `irq`)'),
         (0x0206, 0x0200 + S['PAGE2'][1], 'page 2: variables'),
         (None, 0x0300, 'free')]
    if swr:
        r += [(0x0300, 0x0D00, 'the workspace: buffers and tables'),
              (0x0D00, 0x0E00, 'the MOS\'s: page `$0D`, a Master\'s NMI code and extended vectors'),
              (0x0E00, S['RAM2'][0] + S['RAM2'][1], 'the workspace')]
    else:
        r += [(0x0300, S['RAM'][0] + S['RAM'][1], 'the workspace: buffers and tables (`$0D00`: the NMI\'s `RTI`)')]
    t = S['TABLES']
    r += [(None, t[0], 'free'), (t[0], t[0] + t[1], 'the stored tables'),
          (None, L['__PROG_START__'], 'free: the free block')]
    c = S['CODE']
    if 'FILLS' in S and S['FILLS'][1]:
        f = S['FILLS']
        r.append((f[0], f[0] + f[1], 'the fills (generated code)'))
    r.append((c[0], c[0] + c[1], 'the code'))
    if swr:
        for i in range(8):
            t = S[f'T{i}']
            r.append((t[0], t[0] + t[1], f'store page {i}: code'))
            r.append((None, 0x2800 + 256 * i + L_R2OFF(b), 'free'))
            r.append((0x2800 + 256 * i + L_R2OFF(b), 0x2900 + 256 * i, f'store page {i}: the store table (generated code)'))
        r += [(L['LAND0'], L['LAND1'], 'screen 0: the panel\'s 8 rows, the land\'s 12'),
              (L['LAND1'], 0x8000, 'screen 1')]
    else:
        for i in range(4):
            st, t = S[f'STAB{i}'], S[f'T{i}']
            r.append((st[0], st[0] + st[1], f'parity table {i} (generated code)'))
            r.append((t[0], t[0] + t[1], f'parity page {i}: code'))
            r.append((None, 0x4A00 + 256 * i, 'free'))
        t = S['T4']
        r += [(t[0], t[0] + t[1], 'code'), (None, L['TOP'], 'free'),
              (L['TOP'], L['MAP'], 'the panel\'s row 0: FUEL and the gauge'),
              (L['MAP'], L['LAND0'], 'the panel\'s map'),
              (L['LAND0'], L['LAND1'], 'land buffer 0'), (L['LAND1'], 0x8000, 'land buffer 1')]
    out, at = [], 0
    for lo, hi, what in r:
        lo = at if lo is None else lo
        assert lo == at or what.startswith('page 2') or lo >= at, (hex(lo), hex(at), what)
        if lo > at:
            out.append((at, lo, 'free'))
        if hi > lo:
            out.append((lo, hi, what))
        at = max(at, hi)
    assert at == 0x8000
    return out


def L_R2OFF(b):
    """The sideways RAM build's store pages' code room: src/landerswr.cfg's S0 .. S7."""
    return 0x6F


# The banks' tables: what each holds (a name ending in a digit: the family's).
BANKTAB = {
    'B4MAP': 'the map: a height for each of 64 x 64 corners',
    'DQT': 'the quotients d / a, a row of 64 for each divisor a 0 .. 31',
    'DRT': 'the remainders, 2 (d mod a), in the same order',
    'DVH': 'DQT\'s row for a divisor: its page',
    'DVL': 'DQT\'s row for a divisor: its low byte',
    'CLMP1': 'a difference of lines plus one, clamped to 0 .. 4',
    'DIV4': 'x / 4: a pixel\'s byte column',
    'LAHSn': 'a line\'s page in one half of one screen, by line',
    'MRL': 'the map\'s row z: its address\'s low byte',
    'MRH': 'the map\'s row z: its page',
    'RSMT': 'a line\'s character row less one line, by line',
    'TEN4H': 'the fills\' entries by stores, row 4: page',
    'TEN5H': 'the fills\' entries by stores, row 5: page',
    'TENL': 'the fills\' entries by stores: low byte, both rows\'',
    'TBLK4': 'the fill for row 4: a chain of STA abs,X',
    'TBLK5': 'the fill for row 5',
    'TRn': 'a rung to the right, by its shape: each pixel\'s box',
    'TLn': 'a rung to the left',
    'BLKn': 'a black run\'s store table for one half of one screen: a STA for each line',
    'KENL': 'a line\'s slot in a black run\'s store table: low byte',
    'KENH': 'a line\'s slot in a black run\'s store table: page offset',
    'CMAPE': 'each tile\'s colour byte on even lines',
    'CMAPO': 'each tile\'s colour byte on odd lines',
    'R7L': 'a row\'s scale r by its depth: low byte',
    'R7H': 'a row\'s scale r by its depth: high byte',
    'SYT7': 'a corner\'s screen line by depth and height, 32 heights a depth',
    'SYL7': 'SYT7\'s row for a depth: low byte',
    'SYH7': 'SYT7\'s row for a depth: page',
    'B1T': 'a row\'s x by depth and the camera\'s sixteenth: corner 1\'s x and the corners\' carries',
    'PINL7': 'the left clip plane\'s x by depth',
    'PINR7': 'the right clip plane\'s x by depth',
    'LERPQ7': 'interpolation: lerp(0, d, q / 16) - 1, 32 differences d for each q',
    'LQLO': 'LERPQ7\'s row for q: low byte',
    'LQHI': 'LERPQ7\'s row for q: page',
    'PXF7': 'the far clip row\'s x by the camera\'s sixteenth',
    'PXN7': 'the near clip row\'s x by the camera\'s sixteenth',
}


def bank_rows(b, n):
    """Bank n's contents: [(address, size, name, what)]."""
    items = []
    if n != 6:
        for ln in open(os.path.join(b.path, 'banktab.txt')):
            p = ln.split()
            if int(p[0]) == n:
                items.append((int(p[2], 16), int(p[3]), p[1], BANKTAB[re.sub(r'\d$', 'n', p[1]) if p[1] not in BANKTAB else p[1]] + (' (made at start-up)' if len(p) > 4 else '')))
        for name, (start, size) in b.seg.items():
            if name.startswith(f'B{n}') and size:
                items.append((start, size, name, 'code'))
    else:
        on = False
        for ln in open(os.path.join(b.path, 'shipb_map.txt')):
            if ln.startswith('Segment list'):
                on = True
            elif on and ln.startswith('Exports'):
                break
            elif on:
                p = ln.split()
                if len(p) == 5 and p[1] != 'Start':
                    items.append((int(p[1], 16), int(p[3], 16), p[0],
                                  {'CODE': 'code (keys, ship, the span walker) and its tables',
                                   'SPANS': 'the ship: every orientation\'s spans, compressed',
                                   'TAIL': 'code: the spans\' decoder',
                                   'DTAB': 'the decoder\'s nibble tables and the walker\'s pixel tables'}[p[0]]))
    return sorted(items)


def bank_table(b, n):
    out, at, free = [], 0x8000, 0
    for a, s, name, what in bank_rows(b, n):
        assert a >= at, f'bank {n}: {name} overlaps'
        if a > at:
            out.append(f'| {h(at)} | {h(a - 1)} | {a - at} | | free |')
            free += a - at
        out.append(f'| {h(a)} | {h(a + s - 1)} | {s} | `{name}` | {what} |')
        at = a + s
    if at < 0xC000:
        out.append(f'| {h(at)} | {h(0xBFFF)} | {0xC000 - at} | | free |')
        free += 0xC000 - at
    return table(['from', 'to', 'bytes', 'name', 'contents'], out), free


def document(root, t):
    swr = t == 'swr'
    b = Build(os.path.join(root, f'{t}-mode1'))
    cm = comments({'SWR'} if swr else set())
    o = [f'# The memory map of {TITLE[t]}', '',
         'Written by `tools/memmap.py` from the linked builds; the gate fails if it is not',
         'current. [memory-map.md](memory-map.md) explains the layout. Addresses and sizes',
         'are the MODE 1 version\'s unless a table says otherwise.', '']
    o += ['## Main RAM', '']
    body, free = [], 0
    for lo, hi, what in region_rows(b, swr):
        body.append(f'| {h(lo)} | {h(hi - 1)} | {hi - lo} | {what} |')
        if what.startswith('free'):
            free += hi - lo
    o += table(['from', 'to', 'bytes', 'contents'], body)
    inner = 0
    for lo, hi in [(0x100, b.lab['STACK']), (0x206, 0x200 + b.seg['PAGE2'][1])] + \
            ([(0x300, 0xD00), (0xE00, b.seg['RAM2'][0] + b.seg['RAM2'][1])] if swr else
             [(0x300, b.seg['RAM'][0] + b.seg['RAM'][1])]):
        inner += rows(b.data(lo, hi), lo, hi, cm)[1]
    o += [f'{free + inner} bytes are free: the {b.lab["__PROG_START__"] - b.lab["__DATA_LAST__"]} of the free block between the data and the code,',
          f'{free - (b.lab["__PROG_START__"] - b.lab["__DATA_LAST__"])} more in the table above, and {inner} within pages 1 and 2 and the workspace (the tables',
          'below show each).', '']
    o += ['## By version', '']
    body = []
    for v in VERSIONS:
        x = Build(os.path.join(root, f'{t}-{v}'))
        body.append(f'| {v} | {h(x.lab["__DATA_LAST__"] - 1)} | {h(x.lab["__PROG_START__"])} | '
                    f'{x.lab["__PROG_START__"] - x.lab["__DATA_LAST__"]} | {x.seg["TABLES"][1]} | '
                    f'{x.seg["CODE"][1] + (x.seg["FILLS"][1] if "FILLS" in x.seg else 0)} | {x.seg["BOOT"][1]} |')
    o += table(['version', 'data ends', 'code starts', 'free block', 'stored tables', 'code', 'start-up (discarded)'], body)
    for title, lo, hi in (('Zero page', 0, 0xFC), ('Page 1', 0x100, b.lab['STACK']),
                          ('Page 2', 0x206, 0x300)):
        body, free = rows(b.data(lo, hi), lo, hi, cm)
        o += [f'## {title}', ''] + table(['address', 'bytes', 'name', 'use'], body)
    o += ['## The workspace', '']
    ranges = [(0x300, 0xD00), (0xE00, b.seg['RAM2'][0] + b.seg['RAM2'][1])] if swr else \
        [(0x300, b.seg['RAM'][0] + b.seg['RAM'][1])]
    for lo, hi in ranges:
        body, free = rows(b.data(lo, hi), lo, hi, cm)
        o += table(['address', 'bytes', 'name', 'use'], body)
    o += ['## The stored tables', '',
          'Segment `TABLES`: constant tables that the file holds and the start-up copies here.', '']
    o += table(['address', 'bytes', 'name'], [f'| {h(a)} | {s} | `{n}` |' for a, n, s in b.stored('TABLES')])
    o += ['## The code by source file', '']
    segs = ['CODE'] + [f'T{i}' for i in range(8)]
    banks = {4: ['B4CODE', 'B4BODY'], 5: ['B5CODE'], 7: ['B7CODE']} if swr else {}
    cols = {'main RAM': b.by_file(segs)}
    for n, names in banks.items():
        cols[f'bank {n}'] = b.by_file(names)
    cols['start-up'] = b.by_file(['BOOT'])
    names = sorted({f for c in cols.values() for f in c}, key=lambda f: -sum(c.get(f, 0) for c in cols.values()))
    body = ['| `' + f + '` | ' + ' | '.join(str(c.get(f, 0) or '') for c in cols.values()) + ' |' for f in names]
    body.append('| total | ' + ' | '.join(str(sum(c.values())) for c in cols.values()) + ' |')
    o += table(['file'] + list(cols), body)
    if swr:
        o += ['Bank 6 is assembled apart (`shipb.s`, `shipspan.s`): its bytes are in its bank\'s table below.', '']
        o += ['## The banks', '']
        for n in (4, 5, 6, 7):
            t_, free = bank_table(b, n)
            o += [f'### Bank {n}', ''] + t_ + [f'{free} bytes free.', '']
    return '\n'.join(o).rstrip('\n') + '\n'


def stack(path):
    """(bytes the stack holds, bytes its worst case needs), from tools/stackdepth.py."""
    out = subprocess.run([sys.executable, os.path.join(ROOT, 'tools', 'stackdepth.py'), path],
                         capture_output=True, text=True, check=True).stdout
    m = re.search(r'total: (\d+) bytes.*the stack holds (\d+)', out)
    return int(m.group(2)), int(m.group(1))


def summary(root):
    """The two builds side by side (MODE 1 versions)."""
    col = {}
    for t in ('base', 'swr'):
        swr = t == 'swr'
        b = Build(os.path.join(root, f'{t}-mode1'))
        L, S = b.lab, b.seg
        reg = region_rows(b, swr)
        size = lambda pre: sum(hi - lo for lo, hi, w in reg if w.startswith(pre))
        zp = S['ZEROPAGE'][0] + S['ZEROPAGE'][1]
        holds, needs = stack(b.path)
        cm = comments({'SWR'} if swr else set())
        inner = 0
        ranges = [(0x100, L['STACK']), (0x206, 0x200 + S['PAGE2'][1])] + \
            ([(0x300, 0xD00), (0xE00, S['RAM2'][0] + S['RAM2'][1])] if swr else [(0x300, S['RAM'][0] + S['RAM'][1])])
        for lo, hi in ranges:
            inner += rows(b.data(lo, hi), lo, hi, cm)[1]
        free = sum(hi - lo for lo, hi, w in reg if w.startswith('free')) + inner
        code = S['CODE'][1] + sum(S[f'T{i}'][1] for i in range(8) if f'T{i}' in S)
        gen = size('the fills') + size('parity table') + sum(hi - lo for lo, hi, w in reg if 'the store table' in w)
        c = [f'`$00`-`${zp - 1:02X}`, {0xFC - zp} bytes free below `$FC`',
             f'{L["STACK"] - 0x100} bytes of data',
             f'{holds} bytes; the worst case needs {needs}',
             f'{S["PAGE2"][1] - 6} bytes',
             (f'`$0300`-`$0CFF`, `$0E00`-{h(S["RAM2"][0] + S["RAM2"][1] - 1)}' if swr else
              f'`$0300`-{h(S["RAM"][0] + S["RAM"][1] - 1)}'),
             f'{S["TABLES"][1]} bytes at {h(S["TABLES"][0])}',
             f'{L["__PROG_START__"] - L["__DATA_LAST__"]} bytes at {h(L["__DATA_LAST__"])}',
             f'{code} bytes, {h(L["__PROG_START__"] + (S["FILLS"][1] if "FILLS" in S else 0))}-{h(0x27FF if swr else 0x48FF)} and the pages after',
             f'{gen} bytes',
             ('two screens of 10240 bytes, `$3000` and `$5800`' if swr else
              f'the panel, {L["LAND0"] - L["TOP"]} bytes at {h(L["TOP"])}; two land buffers of {L["LAND1"] - L["LAND0"]}, {h(L["LAND0"])} and {h(L["LAND1"])}'),
             f'{S["BOOT"][1]} bytes',
             f'{free} bytes',
             ', '.join(f'{n}: {bank_table(b, n)[1]}' for n in (4, 5, 6, 7)) if swr else 'none']
        col[t] = c
    names = ['zero page', 'page 1 below the stack', 'the stack', 'page 2', 'the workspace', 'the stored tables',
             'the free block', 'the code', 'code made at start-up', 'the screen', 'the start-up code (discarded)',
             'free in main RAM, in all', 'free in the banks']
    body = [f'| {n} | {a} | {b_} |' for n, a, b_ in zip(names, col['base'], col['swr'])]
    return table(['', 'the 32K build', 'the sideways RAM build'], body)


def disc(root):
    """The disc's catalogue."""
    import mkdisc
    files, patched = mkdisc.catalogue(root)
    body, used = [], 2
    for name, data, load, exe in files:
        n = (len(data) + 255) // 256
        used += n
        body.append(f'| `{name if "." in name else "$." + name}` | {h(load & 0xFFFF)} | {h(exe & 0xFFFF)} | {len(data)} | {n} |')
    return ['The disc is an 80-track single-sided DFS image, boot option 2 (`*RUN !BOOT`):', ''] + \
        table(['file', 'load', 'exec', 'bytes', 'sectors'], body) + \
        [f'{len(files)} files in {used} of the disc\'s 800 sectors (two are the catalogue), {800 - used} free.',
         f'The patch records are {patched} bytes in all.', '']


def fill(text, name, lines):
    """text with the block between the `generated: name` marker and its end replaced."""
    a = text.index(f'<!-- generated: {name} -->') + len(f'<!-- generated: {name} -->')
    b = text.index('<!-- end -->', a)
    return text[:a] + '\n' + '\n'.join(lines).rstrip('\n') + '\n' + text[b:]


def main():
    root = sys.argv[1]
    docs = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'docs')
    check = len(sys.argv) > 3 and sys.argv[3] == 'check'
    stale = []
    out = {f'map-{t}.md': document(root, t) for t in ('base', 'swr')}
    path = os.path.join(docs, 'memory-map.md')
    out['memory-map.md'] = fill(fill(open(path).read(), 'summary', summary(root)), 'disc', disc(root))
    for name, text in out.items():
        path = os.path.join(docs, name)
        if check:
            if not os.path.exists(path) or open(path).read() != text:
                stale.append(path)
        else:
            open(path, 'w').write(text)
            print(path)
    if stale:
        sys.exit(f'not current (python3 tools/memmap.py {root} {docs}): ' + ', '.join(stale))


if __name__ == '__main__':
    main()
