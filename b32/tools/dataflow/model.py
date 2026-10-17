"""model -- the linked program, decoded from ld65's debug file and the output images.

Input is what the build leaves (build/master by default): game.dbg (every source
line's spans: segment + offset + size, macro bodies as type-2 lines) and the output
files each segment was written into (seg oname/ooffs).  Nothing is disassembled
linearly: an instruction starts exactly where a span whose innermost source line is
an instruction mnemonic starts, and its bytes are the linked image's (macros
expanded, addresses resolved).  Every other byte in a code segment is data.

Source text: the dbg names each file with its size and mtime.  A file on disk that
no longer matches (another session editing the engine) is looked for in the
beebgame submodule's history (the outer repo's pinned commit, then HEAD) by size;
a file found nowhere is treated as all-data (its code then counts as unknown).
"""
import os, re, subprocess, collections

# ---------------------------------------------------------------- opcode table
# NMOS official + the 65C02's (the engine is 65C02 on the Master).  mode names:
# imp acc imm zp zpx zpy inx iny zpi(65C02 (zp)) abs abx aby ind iax(jmp (a,x)) rel
_NMOS = """
00 BRK imp|01 ORA inx|05 ORA zp|06 ASL zp|08 PHP imp|09 ORA imm|0A ASL acc|0D ORA abs|0E ASL abs
10 BPL rel|11 ORA iny|15 ORA zpx|16 ASL zpx|18 CLC imp|19 ORA aby|1D ORA abx|1E ASL abx
20 JSR abs|21 AND inx|24 BIT zp|25 AND zp|26 ROL zp|28 PLP imp|29 AND imm|2A ROL acc|2C BIT abs
2D AND abs|2E ROL abs|30 BMI rel|31 AND iny|35 AND zpx|36 ROL zpx|38 SEC imp|39 AND aby|3D AND abx
3E ROL abx|40 RTI imp|41 EOR inx|45 EOR zp|46 LSR zp|48 PHA imp|49 EOR imm|4A LSR acc|4C JMP abs
4D EOR abs|4E LSR abs|50 BVC rel|51 EOR iny|55 EOR zpx|56 LSR zpx|58 CLI imp|59 EOR aby|5D EOR abx
5E LSR abx|60 RTS imp|61 ADC inx|65 ADC zp|66 ROR zp|68 PLA imp|69 ADC imm|6A ROR acc|6C JMP ind
6D ADC abs|6E ROR abs|70 BVS rel|71 ADC iny|75 ADC zpx|76 ROR zpx|78 SEI imp|79 ADC aby|7D ADC abx
7E ROR abx|81 STA inx|84 STY zp|85 STA zp|86 STX zp|88 DEY imp|8A TXA imp|8C STY abs|8D STA abs
8E STX abs|90 BCC rel|91 STA iny|94 STY zpx|95 STA zpx|96 STX zpy|98 TYA imp|99 STA aby|9A TXS imp
9D STA abx|A0 LDY imm|A1 LDA inx|A2 LDX imm|A4 LDY zp|A5 LDA zp|A6 LDX zp|A8 TAY imp|A9 LDA imm
AA TAX imp|AC LDY abs|AD LDA abs|AE LDX abs|B0 BCS rel|B1 LDA iny|B4 LDY zpx|B5 LDA zpx|B6 LDX zpy
B8 CLV imp|B9 LDA aby|BA TSX imp|BC LDY abx|BD LDA abx|BE LDX aby|C0 CPY imm|C1 CMP inx|C4 CPY zp
C5 CMP zp|C6 DEC zp|C8 INY imp|C9 CMP imm|CA DEX imp|CC CPY abs|CD CMP abs|CE DEC abs|D0 BNE rel
D1 CMP iny|D5 CMP zpx|D6 DEC zpx|D8 CLD imp|D9 CMP aby|DD CMP abx|DE DEC abx|E0 CPX imm|E1 SBC inx
E4 CPX zp|E5 SBC zp|E6 INC zp|E8 INX imp|E9 SBC imm|EA NOP imp|EC CPX abs|ED SBC abs|EE INC abs
F0 BEQ rel|F1 SBC iny|F5 SBC zpx|F6 INC zpx|F8 SED imp|F9 SBC aby|FD SBC abx|FE INC abx
"""
_CMOS = """
04 TSB zp|0C TSB abs|12 ORA zpi|14 TRB zp|1A INC acc|1C TRB abs|32 AND zpi|34 BIT zpx|3A DEC acc
3C BIT abx|52 EOR zpi|5A PHY imp|64 STZ zp|72 ADC zpi|74 STZ zpx|7A PLY imp|7C JMP iax|80 BRA rel
89 BIT imm|92 STA zpi|9C STZ abs|9E STZ abx|B2 LDA zpi|D2 CMP zpi|DA PHX imp|F2 SBC zpi|FA PLX imp
"""
LEN = {'imp': 1, 'acc': 1, 'imm': 2, 'zp': 2, 'zpx': 2, 'zpy': 2, 'inx': 2, 'iny': 2,
       'zpi': 2, 'rel': 2, 'abs': 3, 'abx': 3, 'aby': 3, 'ind': 3, 'iax': 3}
NMOS, CMOS = {}, {}
for tab, spec in ((NMOS, _NMOS), (CMOS, _CMOS)):
    for ent in spec.replace('\n', '|').split('|'):
        p = ent.split()
        if p:
            tab[int(p[0], 16)] = (p[1], p[2])
OPS = dict(NMOS); OPS.update(CMOS)
MNEMONICS = {m.lower() for m, _ in OPS.values()}
BRANCHES = {'BPL', 'BMI', 'BVC', 'BVS', 'BCC', 'BCS', 'BNE', 'BEQ', 'BRA'}

# directives that emit data bytes
DATA_DIRS = {'.byte', '.byt', '.word', '.addr', '.dbyt', '.res', '.lobytes', '.hibytes',
             '.bankbytes', '.faraddr', '.dword', '.incbin', '.asciiz', '.align', '.tag',
             '.literal', '.fill'}


def parse_dbg(path):
    recs = collections.defaultdict(list)
    with open(path) as fh:
        for ln in fh:
            t, _, rest = ln.rstrip('\n').partition('\t')
            d = {}
            for m in re.finditer(r'(\w+)=("[^"]*"|[^,]*)', rest):
                v = m.group(2)
                d[m.group(1)] = v[1:-1] if v.startswith('"') else v
            recs[t].append(d)
    return recs


class Source:
    """file id -> list of lines, resolving stale files through git history."""
    def __init__(self, root, recs, notes):
        self.root, self.lines, self.names, self.status = root, {}, {}, {}
        cands = []
        bgsub = os.path.join(root, 'beebgame')
        try:
            pin = subprocess.run(['git', '-C', root, 'ls-tree', 'HEAD', 'beebgame'],
                                 capture_output=True, text=True).stdout.split()
            if len(pin) >= 3:
                cands.append(pin[2])
        except Exception:
            pass
        cands.append('HEAD')
        for d in recs['file']:
            fid = int(d['id']); name = d['name']; size = int(d['size'].split('+')[0])
            self.names[fid] = name
            path = name if os.path.isabs(name) else os.path.join(root, name)
            text = None
            if os.path.exists(path) and os.path.getsize(path) == size:
                text = open(path, 'rb').read(); self.status[fid] = 'disk'
            else:
                ap = os.path.abspath(path)
                tries = []
                if ap.startswith(os.path.abspath(bgsub) + os.sep):
                    tries += [(bgsub, os.path.relpath(ap, bgsub), c) for c in cands]
                if ap.startswith(os.path.abspath(root) + os.sep):
                    tries.append((root, os.path.relpath(ap, root), 'HEAD'))
                for repo, rel, c in tries:
                    r = subprocess.run(['git', '-C', repo, 'show', f'{c}:./{rel}'],
                                       capture_output=True)
                    if r.returncode == 0 and len(r.stdout) == size:
                        text = r.stdout
                        self.status[fid] = f'git {os.path.basename(repo)}@{c[:7]}'
                        break
                if text is None and os.path.exists(path):
                    # generated includes rewritten by a later build: usable only if
                    # the size still matches (checked above) -- else unknown
                    self.status[fid] = 'STALE'
                elif text is None:
                    self.status[fid] = 'MISSING'
            if text is not None:
                self.lines[fid] = text.decode('latin-1').split('\n')
            if self.status[fid] in ('STALE', 'MISSING'):
                notes.append(f"source {name}: {self.status[fid]} (its lines count as data)")

    def text(self, fid, line):
        L = self.lines.get(fid)
        if L is None or not (1 <= line <= len(L)):
            return None
        return L[line - 1]

    def short(self, fid):
        n = self.names[fid]
        ap = n if os.path.isabs(n) else os.path.join(self.root, n)
        # '/' on every host: callers compare with it (game_dir + '/'), and a
        # Windows relpath has backslashes
        return os.path.relpath(ap, self.root).replace(os.sep, '/')


_LABEL = re.compile(r'^\s*(?:(?:[@A-Za-z_][\w@.]*|):)?\s*')


def classify(text, macros):
    """'insn' | 'data' | 'macro' | 'other' | None (text unknown)."""
    if text is None:
        return None
    s = text.split(';', 1)[0]
    s = _LABEL.sub('', s, count=1).strip()
    if not s:
        return 'other'
    tok = s.split()[0].lower()
    if tok in MNEMONICS:
        return 'insn'
    if tok.startswith('.'):
        return 'data' if tok in DATA_DIRS else 'other'
    if tok in macros:
        return 'macro'
    # "name = expr" / "name := expr"
    return 'other'


def bank_of(oname):
    b = os.path.basename(oname)
    m = re.match(r'b(\d)', b)
    if m:
        return 'bank' + m.group(1)
    return b


class Insn:
    __slots__ = ('key', 'seg', 'addr', 'op', 'mn', 'mode', 'len', 'opnd', 'bytes',
                 'outer', 'inner', 'game', 'volatile', 'opvolatile', 'idx', 'cmos', 'skip')

    def __repr__(self):
        return f"{self.mn} {self.mode} ${self.addr:04X}"


class Program:
    def __init__(self, root, build, game_dir=None):
        import gamecfg
        game_dir = game_dir or gamecfg.C.GAME_DIR
        self.root, self.build, self.notes = root, build, []
        dbgp = os.path.join(build, 'game.dbg')
        R = self.recs = parse_dbg(dbgp)
        self.src = Source(root, R, self.notes)
        # macros defined anywhere (name -> True): from the source texts
        self.macros = set()
        for L in self.src.lines.values():
            for t in L:
                m = re.match(r'\s*\.mac(?:ro)?\s+([A-Za-z_]\w*)', t, re.I)
                if m:
                    self.macros.add(m.group(1).lower())
        self.game_files = {fid for fid, n in self.src.names.items()
                           if self.src.short(fid).startswith(game_dir + '/')}
        # segments
        self.segs = {}
        for d in R['seg']:
            sid = int(d['id'])
            seg = dict(name=d['name'], start=int(d['start'], 16), size=int(d['size'], 16),
                       oname=d.get('oname'), ooffs=int(d.get('ooffs', 0) or 0))
            seg['data'] = None
            if seg['oname'] and seg['size']:
                p = os.path.join(build, os.path.basename(seg['oname']))
                try:
                    with open(p, 'rb') as fh:
                        fh.seek(seg['ooffs']); seg['data'] = fh.read(seg['size'])
                except OSError:
                    self.notes.append(f"segment {seg['name']}: image {p} unreadable")
                seg['bank'] = bank_of(seg['oname'])
            else:
                seg['bank'] = None
            self.segs[sid] = seg
        self.spans = {int(d['id']): (int(d['seg']), int(d['start']), int(d['size']))
                      for d in R['span']}
        self.lines = {}
        span_lines = collections.defaultdict(list)
        for d in R['line']:
            lid = int(d['id'])
            rec = dict(id=lid, file=int(d['file']), line=int(d['line']),
                       type=int(d.get('type', 0) or 0), count=int(d.get('count', 0) or 0),
                       spans=[int(s) for s in d.get('span', '').split('+') if s])
            self.lines[lid] = rec
            for s in rec['spans']:
                span_lines[s].append(rec)
        self.span_lines = span_lines
        self._decode()
        self._symbols()

    # ------------------------------------------------------------ decoding
    def _decode(self):
        S = self.src
        insn_at = {}            # (seg, addr) -> Insn
        datab = collections.defaultdict(set)   # seg -> data offsets
        bad = []
        # spans per segment, with innermost line + outermost type-0 line
        for sid_span, (seg, off, size) in self.spans.items():
            sg = self.segs[seg]
            if sg['data'] is None or size == 0:
                continue
            lines = self.span_lines.get(sid_span, [])
            if not lines:
                continue
            inner = max(lines, key=lambda r: (r['type'] == 2, r['count']))
            kind = classify(S.text(inner['file'], inner['line']), self.macros)
            if kind == 'other' and inner['type'] == 2:
                # a macro body line whose mnemonic is a parameter ("op #n"): an
                # instruction if the bytes decode to exactly the span
                ent = OPS.get(sg['data'][off])
                if ent and LEN[ent[1]] == size:
                    kind = 'insn'
            if kind == 'insn':
                addr = sg['start'] + off
                op = sg['data'][off]
                ent = OPS.get(op)
                if ent is None or LEN[ent[1]] != size:
                    bad.append((seg, addr, size, op))
                    datab[seg].update(range(off, off + size))
                    continue
                i = Insn()
                i.key = (seg, addr); i.seg = seg; i.addr = addr; i.op = op
                i.mn, i.mode = ent; i.len = size; i.cmos = op in CMOS
                b = sg['data'][off:off + size]; i.bytes = b
                if i.mode == 'rel':
                    d = b[1]
                    i.opnd = (addr + 2 + (d - 256 if d >= 128 else d)) & 0xFFFF
                elif size == 2:
                    i.opnd = b[1]
                elif size == 3:
                    i.opnd = b[1] | (b[2] << 8)
                else:
                    i.opnd = None
                i.outer = None
                i.inner = inner
                i.volatile = False; i.opvolatile = False; i.skip = False
                insn_at[(seg, addr)] = i
            elif kind in ('data', None):
                datab[seg].update(range(off, off + size))
        # outermost source line: the smallest assembler-source (type 0) line span
        # covering the instruction's first byte (a macro invocation's span covers
        # its whole expansion; the body lines have their own spans)
        cov = collections.defaultdict(list)
        for sid_span, (seg, off, size) in self.spans.items():
            if size == 0:
                continue
            for r in self.span_lines.get(sid_span, []):
                if r['type'] == 0:
                    cov[seg].append((off, off + size, r))
        for seg in cov:
            cov[seg].sort(key=lambda t: (t[0], t[1]))
        starts = {seg: [t[0] for t in v] for seg, v in cov.items()}
        import bisect
        for i in insn_at.values():
            off = i.addr - self.segs[i.seg]['start']
            best = None
            v = cov.get(i.seg, [])
            k = bisect.bisect_right(starts.get(i.seg, []), off)
            j = k - 1
            while j >= 0 and j >= k - 64:
                a, b, r = v[j]
                if a <= off < b and (best is None or b - a < best[1] - best[0]):
                    best = (a, b, r)
                j -= 1
            i.outer = best[2] if best else i.inner
            i.game = i.outer['file'] in self.game_files
        # an instruction span that overlaps data, or two instructions overlapping
        self.insns = insn_at
        self.data_off = datab
        self.bad = bad
        # address -> [Insn] (several segments share addresses: the banks)
        self.by_addr = collections.defaultdict(list)
        for i in insn_at.values():
            self.by_addr[i.addr].append(i)
        # covering map for SMC: address -> instructions whose bytes include it
        self.cover = collections.defaultdict(list)
        for i in insn_at.values():
            for k in range(i.len):
                self.cover[(i.addr + k) & 0xFFFF].append((i, k))
        order = sorted(insn_at.values(), key=lambda i: (i.seg, i.addr))
        for n, i in enumerate(order):
            i.idx = n
        self.order = order
        if bad:
            self.notes.append(f"{len(bad)} instruction spans whose bytes did not decode to "
                              f"their span's length (counted as data)")

    def code_segs(self):
        return {i.seg for i in self.insns.values()}

    def is_data(self, seg, addr):
        sg = self.segs[seg]
        return (addr - sg['start']) in self.data_off[seg]

    def resolve(self, addr, from_seg):
        """The instruction a JSR/JMP/branch to addr from code in from_seg reaches, or
        None (no instruction there / several banks could be paged in)."""
        c = self.by_addr.get(addr, [])
        if not c:
            return None
        for i in c:
            if i.seg == from_seg:
                return i
        fb = self.segs[from_seg]['bank']
        same = [i for i in c if self.segs[i.seg]['bank'] == fb]
        if len(same) == 1:
            return same[0]
        if len(c) == 1:
            return c[0]
        return None

    def resolve_all(self, addr, from_seg, insn=None):
        """Every instruction a transfer to addr could reach: the one resolve() picks;
        else, when several banks share the address, the one the source line names
        (jsr music_tick: the symbol's segment); else all of them -- sound as long
        as the bank paged in at the time is one of this build's."""
        t = self.resolve(addr, from_seg)
        if t is not None:
            return [t]
        c = list(self.by_addr.get(addr, []))
        if insn is not None and len(c) > 1:
            m = re.search(r'\b[a-zA-Z]{3}\s+([@A-Za-z_][\w@.]*)\s*$',
                          (self.text(insn, inner=True).split(';')[0]).rstrip())
            if m:
                segs = {s['seg'] for s in self.syms if s['name'] == m.group(1) and s['val'] == addr}
                hit = [j for j in c if j.seg in segs]
                if len(hit) == 1:
                    return hit
        return c

    def in_seg(self, seg, addr):
        sg = self.segs[seg]
        return sg['start'] <= addr < sg['start'] + sg['size']

    # ------------------------------------------------------------ symbols
    def _symbols(self):
        self.syms = []          # (name, val, seg or None, type, refs)
        for d in self.recs['sym']:
            if d.get('type') == 'imp':
                continue
            try:
                val = int(d['val'], 16)
            except (KeyError, ValueError):
                continue
            seg = int(d['seg']) if 'seg' in d else None
            refs = [int(r) for r in d.get('ref', '').split('+') if r]
            self.syms.append(dict(name=d['name'], val=val, seg=seg, type=d.get('type'),
                                  refs=refs, size=int(d.get('size', 0) or 0),
                                  parent=d.get('parent'), scope=d.get('scope')))
        # names for data addresses (zero page and absolute): prefer globals
        self.addr_name = {}
        for s in sorted(self.syms, key=lambda s: (s['name'].startswith('@'),
                                                 s['type'] != 'lab', len(s['name']))):
            if s['seg'] is not None and self.segs[s['seg']]['data'] is not None and \
                    s['seg'] in self.code_segs():
                continue                 # a code label, named via code_name
            self.addr_name.setdefault(s['val'], s['name'])
        self.code_label = collections.defaultdict(list)
        for s in self.syms:
            if s['seg'] is not None:
                for i in self.by_addr.get(s['val'], []):
                    if i.seg == s['seg']:
                        self.code_label[i.key].append(s)
        # nearest preceding global code label for context
        self.glob = collections.defaultdict(list)   # seg -> sorted [(addr, name)]
        for s in self.syms:
            if s['seg'] is not None and not s['name'].startswith('@') and \
                    s['type'] == 'lab' and s['parent'] is None:
                self.glob[s['seg']].append((s['val'], s['name']))
        for v in self.glob.values():
            v.sort()

    def where(self, i):
        """'file:line' of an instruction's outermost source line."""
        return f"{self.src.short(i.outer['file'])}:{i.outer['line']}"

    def text(self, i, inner=False):
        r = i.inner if inner else i.outer
        t = self.src.text(r['file'], r['line'])
        return (t or '').rstrip()

    def routine_of(self, i):
        import bisect
        g = self.glob.get(i.seg, [])
        k = bisect.bisect_right(g, (i.addr, '￿')) - 1
        return g[k][1] if k >= 0 else '?'

    def name(self, addr):
        n = self.addr_name.get(addr)
        if n:
            return n
        if addr - 1 in self.addr_name:
            return self.addr_name[addr - 1] + '+1'
        return f"${addr:04X}" if addr > 0xFF else f"${addr:02X}"

    def disasm(self, i):
        m = i.mn.lower(); o = i.opnd
        nm = lambda a: self.name(a) if a is not None else '?'
        fmt = {'imp': '{}', 'acc': 'a', 'imm': '#${:02X}', 'zp': '{}', 'zpx': '{},x',
               'zpy': '{},y', 'inx': '({},x)', 'iny': '({}),y', 'zpi': '({})', 'abs': '{}',
               'abx': '{},x', 'aby': '{},y', 'ind': '({})', 'iax': '({},x)', 'rel': '${:04X}'}[i.mode]
        if i.mode == 'imp':
            s = ''
        elif i.mode in ('imm', 'rel'):
            s = fmt.format(o if o is not None else 0)
        else:
            s = fmt.format(nm(o))
        if i.mn in ('JSR', 'JMP') and i.mode == 'abs' or i.mode == 'rel':
            t = self.resolve(o, i.seg)
            labs = self.code_label.get(t.key) if t else None
            if labs:
                s = sorted(labs, key=lambda s: (s['name'].startswith('@'), len(s['name'])))[0]['name']
                if s.startswith('@') or not labs:
                    s = f"{s} (${o:04X})"
            else:
                s = f"${o:04X}"
        return (m + ' ' + s).strip()
