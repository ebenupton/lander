// b32/tools/hprobe.mjs DISC [FIELDS] [KEYS]: boots DISC headless in the MCP server's jsbeeb and
// times every horizontal sync's start to the 2MHz clock (0.5us), field by field from the
// vertical sync; prints, for each line whose sync-to-sync interval is not 64us in some field,
// the intervals seen (us) and how often, and the sync pulse widths seen.  KEYS: browser key
// codes held (16 SHIFT: thrust, 90 Z: turn).
const J='/Users/ebenupton/.npm/_npx/e76f2a7d329553db/node_modules/jsbeeb/src/';
const { MachineSession } = await import(J+'machine-session.js');
const s = new MachineSession('B-DFS1.2');
await s.initialise();
await s.boot();
s.loadDisc(process.argv[2]);
await s.type('*RUN LANDER\r');
await s.runFor(40_000_000);
const N = +(process.argv[3] || 50);
for (const k of (process.argv[4] || '').split(',').filter(Boolean).map(Number)) s.keyDown(k);
const v = s._video;
let T = 0, fields = [], cur = null, lastStart = null, pulse = null;
const sv = v.sysvia.setVBlankInt.bind(v.sysvia);
v.sysvia.setVBlankInt = (lvl) => { if (lvl) { if (cur) fields.push(cur); cur = { syncs: [], widths: [] }; } return sv(lvl); };
const orig = v.polltime.bind(v);
v.polltime = (clocks) => {
  while (clocks-- > 0) {
    const was = v.inHSync;
    orig(1); T++;
    if (!was && v.inHSync && cur) { cur.syncs.push(T); pulse = T; }
    if (was && !v.inHSync && cur && pulse !== null) { cur.widths.push(T - pulse); pulse = null; }
  }
};
for (let i = 0; i < N + 2; i++) await s.runFor(40_000);
const byLine = {}, widths = {};
for (const f of fields.slice(1, N + 1)) {
  for (let i = 1; i < f.syncs.length; i++) {
    const d = (f.syncs[i] - f.syncs[i - 1]) / 2;
    (byLine[i] = byLine[i] || {})[d] = (byLine[i][d] || 0) + 1;
  }
  f.widths.forEach((w, i) => { (widths[i] = widths[i] || {})[w / 2] = (widths[i][w / 2] || 0) + 1; });
}
console.log(`${Math.min(N, fields.length - 1)} fields; syncs a field: ${fields.slice(1, 4).map(f => f.syncs.length)}`);
for (const [l, h] of Object.entries(byLine)) {
  if (Object.keys(h).some(d => +d !== 64)) console.log(`line ${l}: intervals`, JSON.stringify(h), ' widths', JSON.stringify(widths[l] || {}));
}
process.exit(0);
