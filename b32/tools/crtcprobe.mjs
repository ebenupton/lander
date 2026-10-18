// b32/tools/crtcprobe.mjs DISC: boots DISC headless in the jsbeeb the MCP server uses and logs
// every CRTC register write over a field with the CRTC's own counters (row, line, C0).
// Used to place irq's timed writes (land.s: Ea, Eb).
const J='/Users/ebenupton/.npm/_npx/e76f2a7d329553db/node_modules/jsbeeb/src/';
const { MachineSession } = await import(J+'machine-session.js');
const s = new MachineSession('B-DFS1.2');
await s.initialise();
await s.boot();
s.loadDisc(process.argv[2]);
await s.type('*RUN LANDER\r');
await s.runFor(12_000_000);
const v = s._video;
const crtc = v.crtc;
const orig = crtc.write.bind(crtc);
let log=[]; let on=false;
crtc.write = (addr,val)=>{ if((addr&1) && on) log.push([crtc.curReg, val, v.vertCounter, v.scanlineCounter, v.horizCounter]); return orig(addr,val); };
on=true;
await s.runFor(40_000*2);
on=false;
// print one field's worth: from a write of R1=64 (E0) on
let i=log.findIndex(e=>e[0]==1&&e[1]==64&&e[2]>0);
for (const e of log.slice(i, i+20)) console.log(`R${e[0]}=${e[1]}  row ${e[2]} line ${e[3]} C0 ${e[4]}`);
s.destroy?.();
process.exit(0);
