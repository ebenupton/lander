// b32/tools/tprobe.mjs DISC [FIELDS] [KEYS]: irq's timer chain in jsbeeb: per field, the
// user VIA timer 1 count each handler read (E0's, Ez's, Ea's, Eb's, E2's by evn), the
// position (row.line.C0) of the clock switches (ULA writes) and of each CRTC write, and
// the hsync intervals that are not 64us (by line from the vsync).
const J='/Users/ebenupton/.npm/_npx/e76f2a7d329553db/node_modules/jsbeeb/src/';
const { MachineSession } = await import(J+'machine-session.js');
const fs = await import('fs');
const s = new MachineSession('B-DFS1.2');
await s.initialise();
await s.boot();
s.loadDisc(process.argv[2]);
await s.type('*RUN LANDER\r');
await s.runFor(+(process.env.SETTLE || 40_000_000));
const N = +(process.argv[3] || 30);
for (const k of (process.argv[4] || '').split(',').filter(Boolean).map(Number)) s.keyDown(k);
const lab = {};
for (const l of fs.readFileSync('build32/labels.txt', 'utf8').split('\n')) { const p = l.split(' '); if (p.length >= 3) lab[p[2].replace(/^\./, '')] = parseInt(p[1], 16); }
const cpu = s._machine.processor, v = s._video, uv = cpu.uservia;
const mem = a => cpu.readmem(a);
let T = 0, fields = [], cur = null;
const sv = v.sysvia.setVBlankInt.bind(v.sysvia);
v.sysvia.setVBlankInt = (lvl) => { if (lvl) { if (cur) fields.push(cur); cur = { syncs: [], ev: [] }; } return sv(lvl); };
const pos = () => `${v.vertCounter}.${v.scanlineCounter}.${v.horizCounter}`;
const ur = uv.read.bind(uv);
let lastL = 0;
uv.read = (addr) => { const r = ur(addr); if ((addr & 15) === 6) lastL = r; if ((addr & 15) === 4 && cur) cur.ev.push(`T${mem(lab.evn)}=${((lastL - r) & 255).toString(16)}/${r.toString(16)}@${pos()}`); return r; };
const vw = v.ula.write.bind(v.ula);
v.ula.write = (addr, val) => { if ((addr & 3) === 0 && cur) cur.ev.push(`U${val.toString(16)}@${pos()}`); return vw(addr, val); };
const cw = v.crtc.write.bind(v.crtc);
v.crtc.write = (addr, val) => { if ((addr & 1) && cur) cur.ev.push(`R${v.crtc.curReg}=${val}@${pos()}`); return cw(addr, val); };
const orig = v.polltime.bind(v);
v.polltime = (clocks) => { while (clocks-- > 0) { const was = v.inHSync; orig(1); T++; if (!was && v.inHSync && cur) cur.syncs.push(T); } };
for (let i = 0; i < N + 2; i++) await s.runFor(40_000);
for (const f of (process.env.FIRST ? fields.slice(0, 8) : fields.slice(-Math.min(N, 6)))) {
  const odd = [];
  for (let i = 1; i < f.syncs.length; i++) { const d = (f.syncs[i] - f.syncs[i - 1]) / 2; if (d !== 64) odd.push(`${i}:${d}`); }
  console.log('syncs', f.syncs.length, 'odd', odd.slice(0, 12).join(' '));
  console.log('  ', f.ev.join(' '));
}
const all = {};
for (const f of fields.slice(1)) for (let i = 1; i < f.syncs.length; i++) { const d = (f.syncs[i] - f.syncs[i - 1]) / 2; if (d !== 64) { all[i] = all[i] || {}; all[i][d] = (all[i][d] || 0) + 1; } }
console.log('odd intervals over', fields.length - 1, 'fields:', JSON.stringify(all));
process.exit(0);
