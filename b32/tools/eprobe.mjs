// b32/tools/eprobe.mjs DISC [FIELDS] [KEYS]: irq's events timed in jsbeeb, in us (to the 2MHz
// tick) from the vertical sync's start, field by field: timer 1 underflows (U), each
// handler's timer 1 count read (R<evn>=count), the ULA's control writes (C<value>) and
// the CRTC's (R<reg>=<value>); then, per kind, the delay from its underflow to each
// write (the handlers' fixed delays), and the hsync intervals that are not 64us.
const J='/Users/ebenupton/.npm/_npx/e76f2a7d329553db/node_modules/jsbeeb/src/';
const { MachineSession } = await import(J+'machine-session.js');
const fs = await import('fs');
const s = new MachineSession('B-DFS1.2');
await s.initialise(); await s.boot();
s.loadDisc(process.argv[2]); await s.type('*RUN LANDER\r');
await s.runFor(+(process.env.SETTLE || 30_000_000));
const N = +(process.argv[3] || 20);
for (const k of (process.argv[4] || '').split(',').filter(Boolean).map(Number)) s.keyDown(k);
const lab = {};
for (const l of fs.readFileSync('build32/labels.txt', 'utf8').split('\n')) { const p = l.split(' '); if (p.length >= 3) lab[p[2].replace(/^\./, '')] = parseInt(p[1], 16); }
const cpu = s._machine.processor, v = s._video, uv = cpu.uservia;
let T = 0, fields = [], cur = null, vs = 0;
const sv = v.sysvia.setVBlankInt.bind(v.sysvia);
v.sysvia.setVBlankInt = (lvl) => { if (lvl) { if (cur) fields.push(cur); cur = { ev: [], syncs: [] }; vs = T; } return sv(lvl); };
const t = () => ((T - vs) / 2);
const ur = uv.read.bind(uv);
uv.read = (addr) => { const r = ur(addr); if ((addr & 15) === 4 && cur) cur.ev.push([t(), `R${cpu.readmem(lab.evn)}=${r}`]); return r; };
const sv2 = cpu.sysvia, sr = sv2.read.bind(sv2);
sv2.read = (addr) => { const r = sr(addr); if ((addr & 15) === 13 && (r & 2) && cur) cur.ev.push([t(), 'CA1']); return r; };
const vw = v.ula.write.bind(v.ula);
v.ula.write = (addr, val) => { if ((addr & 3) === 0 && cur) cur.ev.push([t(), `C${val.toString(16)}`]); return vw(addr, val); };
const cw = v.crtc.write.bind(v.crtc);
v.crtc.write = (addr, val) => { if ((addr & 1) && cur) cur.ev.push([t(), `R${v.crtc.curReg}:${val}`]); return cw(addr, val); };
const uw = uv.write.bind(uv);
uv.write = (addr, val) => { if ((addr & 15) === 5 && cur) cur.ev.push([t(), `W${val}`]); return uw(addr, val); };
// underflows: watch uservia's IFR timer-1 bit rising
const up = uv._polltime.bind(uv);
uv._polltime = (c) => { const before = uv.ifr & 0x40; up(c); if (!before && (uv.ifr & 0x40) && cur) cur.ev.push([t(), 'U']); };
const orig = v.polltime.bind(v);
v.polltime = (clocks) => { while (clocks-- > 0) { const was = v.inHSync; orig(1); T++; if (!was && v.inHSync && cur) cur.syncs.push(t()); } };
for (let i = 0; i < N + 2; i++) await s.runFor(40_000);
for (const f of fields.slice(1, 4)) {
  console.log('field: vsync->next', f.syncs.length, 'syncs');
  console.log('  ' + f.ev.map(([a, b]) => `${b}@${a}`).join(' '));
  const odd = [];
  for (let i = 1; i < f.syncs.length; i++) { const d = f.syncs[i] - f.syncs[i - 1]; if (d !== 64) odd.push(`${i}(${f.syncs[i]}):${d}`); }
  console.log('  odd:', odd.join(' '));
}
process.exit(0);
