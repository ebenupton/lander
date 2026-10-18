// b32/tools/vprobe.mjs DISC [KEYS]: boots DISC headless in the MCP server's jsbeeb, runs
// the game and logs, field by field, the scanlines from one vertical sync to the next and
// from the sync to each new CRTC frame (vertCounter back to 0), with the frame's R12:
// a field whose numbers differ from the others' moves the picture.
const J='/Users/ebenupton/.npm/_npx/e76f2a7d329553db/node_modules/jsbeeb/src/';
const { MachineSession } = await import(J+'machine-session.js');
const s = new MachineSession('B-DFS1.2');
await s.initialise();
await s.boot();
s.loadDisc(process.argv[2]);
await s.type('*RUN LANDER\r');
await s.runFor(40_000_000);
const v = s._video;
let line = 0, fields = [], cur = null;
const eos = v.endOfScanline.bind(v);
v.endOfScanline = () => { line++; const r = eos(); if (cur && v.vertCounter === 0 && v.scanlineCounter === 0) cur.frames.push([line - cur.start, v.bitmapY >> 1]); return r; };
const svia = v.sysvia, sv = svia.setVBlankInt.bind(svia);
const cpu = s._machine.processor;
svia.setVBlankInt = (lvl) => { if (lvl) { if (cur) fields.push(cur); cur = { start: line, cyc: cpu.currentCycles, frames: [] }; } return sv(lvl); };
const eof = v.endOfFrame ? v.endOfFrame.bind(v) : null;
let lastVC = -1;
const step = v.polltime.bind(v);
v.polltime = (n) => { const r = step(n); return r; };
const crtcw = v.crtc.write.bind(v.crtc);
const wr = {};
v.crtc.write = (addr, val) => { if (addr & 1) { const k = `R${v.crtc.curReg}=${val}`; const p = v.vertCounter * 100000 + v.scanlineCounter * 1000 + v.horizCounter; (wr[k] = wr[k] || []).push(p); } return crtcw(addr, val); };
const ulaw = v.ula.write.bind(v.ula);
v.ula.write = (addr, val) => { if ((addr & 3) === 0) { const k = `U${val.toString(16)}`; const p = v.vertCounter * 100000 + v.scanlineCounter * 1000 + v.horizCounter; (wr[k] = wr[k] || []).push(p); } return ulaw(addr, val); };
const hs = v.handleHSync.bind(v);
v.handleHSync = () => { const b = v.bitmapY; const r = hs(); if (cur && v.bitmapY !== b && v.bitmapY > 0) { const l = line - cur.start; cur.hl = cur.hl || {}; (cur.hl[l] = cur.hl[l] || []).push(v.horizCounter); } return r; };
// frame starts: watch vertCounter going to 0
const crtc = v.crtc;
const tick = setInterval(()=>{},1000);
const t0 = Date.now();
const N = +(process.argv[3] || 60);
const keys = (process.argv[4] || '').split(',').filter(Boolean).map(Number);
for (const k of keys) s.keyDown(k);
for (let i = 0; i < N * 40; i++) {
  await s.runFor(1000);
}
clearInterval(tick);
const lens = {};
for (const f of fields.slice(1)) { }
let prev = null;
for (const f of fields.slice(1, N)) {
  const next = fields[fields.indexOf(f) + 1];
  console.log('field', next ? next.start - f.start : '-', 'lines', next ? next.cyc - f.cyc : '-', 'cycles; frame starts (line, beam row)', f.frames.map(x => x[0] + '(' + x[1] + ')').join(' '), '| odd lines:', Object.entries(f.hl || {}).filter(([l, a]) => a.length !== 1).map(([l, a]) => l + ':' + a.join('/')).join(' '), '| missing:', [...Array(310).keys()].filter(l => !(f.hl || {})[l]).join(','), '| C0 at 150-155:', [150,151,152,153,154,155].map(l => ((f.hl||{})[l]||[]).join('/')).join(' '));
}
const fmt = p => `${Math.floor(p / 100000)}.${Math.floor(p / 1000) % 100}.${p % 1000}`;
for (const [k, a] of Object.entries(wr)) { a.sort((x, y) => x - y); console.log('write', k, 'from', fmt(a[0]), 'to', fmt(a[a.length - 1]), a.length); }
process.exit(0);
