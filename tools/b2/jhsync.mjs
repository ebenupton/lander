// tools/b2/jhsync.mjs: the 32K build's video timing in jsbeeb, in both phases of
// the 1 MHz clock.
//
//   [BOOTPRE=N] [JSBEEB=dir] node tools/b2/jhsync.mjs [BUILD] [--version V]
//                [--secs S] [--ula N] [--inject N] [--skip N] [--lat]
//
// Boots BUILD/lander.ssd (BUILD default build: sh build.sh) on jsbeeb's Model B
// (which has sideways RAM and a VideoNuLA), a hard reset with SHIFT held after
// BOOTPRE more 2 MHz cycles, and at the loader's menu picks the 32K build (B) and
// version V (mode1, the default, cpc, nula or arc).  It flies with keys held for S
// emulated seconds (default 60) and times every rising edge of the 6845's
// horizontal sync and every vertical sync in 2 MHz cycles, from the land's control
// write (&D8, or &F4 in a MODE 2 version) that follows --skip (default 1) earlier
// ones, each after the top's (&C4): the first is the program's set-up of the
// land's frame, the second the first field's Eb (src/video.s).  It fails
// (exit status 1) on any horizontal sync interval other than 128 cycles and on any
// field that is not 312 lines.
//
// jsbeeb keeps the CPU's 1 MHz bus (the stretch of its accesses to the VIAs and the
// 6845) and the 6845's 1 MHz clock as separate counters, and a hard reset zeroes
// the first and leaves the second, so the half microsecond between them depends on
// the reset's cycle: BOOTPRE odd or even gives the two phases.  A real machine has
// one phase (its video ULA divides both from the one crystal), which one is not
// known, so the build must pass in both.  The tool prints the run's phase.
//
// --ula N lists the first N control writes by line and cycle, and the histogram of
// all of them is always printed, as b2drive's: the vertical sync's rising edge
// starts line 160; the last horizontal sync was on cycle 90, or 42 in lines
// 256-311 and line 0; the cycle is the first at the new clock (jsbeeb has stepped
// the 6845 through the cycle before it when the write is made), so the last
// cycle at the old clock, p, is one less.
// --inject N holds the CPU for d cycles at each entry to irq for a timer event (the
// clock and every device go on, as an instruction that holds an interrupt off), d
// going 0, 1 ... N in turn.  --lat prints the histogram of each event's latency (the
// timer's latch less its count, in microseconds, at irq's read), which dejit pads
// out to DJK (it covers DJK-15 to DJK), and of the NOP of Ev's run that E0
// interrupts.
import { readFileSync } from "fs";
import { homedir } from "os";
const J = (process.env.JSBEEB || homedir() + "/.npm/_npx/e76f2a7d329553db/node_modules/jsbeeb") + "/src/";
const { MachineSession } = await import(J + "machine-session.js");
const argv = process.argv.slice(2);
const opt = (n, d) => { const i = argv.indexOf("--" + n); return i < 0 ? d : (argv[i + 1] === undefined || argv[i + 1].startsWith("--") ? true : argv[i + 1]); };
const BUILD = argv[0] && !argv[0].startsWith("--") ? argv[0] : "build";
const VER = opt("version", "mode1");
const SECS = +opt("secs", 60), ULA = +opt("ula", 0), INJ = +opt("inject", -1), LAT = opt("lat", false);
let skip = +opt("skip", 1);
const PRE = +(process.env.BOOTPRE || 0);
const lab = {};
for (const l of readFileSync(`${BUILD}/base-${VER}/labels.txt`, "utf8").split("\n")) { const p = l.split(" "); if (p.length >= 3) lab[p[2].replace(/^\./, "")] = parseInt(p[1], 16); }

const s = new MachineSession("B-DFS1.2");
await s.initialise();
await s.boot(30);
s.loadDisc(BUILD + "/lander.ssd");
if (PRE) await s.runFor(PRE);
const KEY = { mode1: 49, cpc: 50, nula: 51, arc: 52 }[VER];
s.keyDown(16);
s.reset(true);
await s.runFor(2000000);
s.keyUp(16);
for (const k of [66, KEY]) {                                // B: the 32K build; the version
    await s.runFor(6000000);
    s.keyDown(k);
    await s.runFor(400000);
    s.keyUp(k);
}

const cpu = s._machine.processor, v = cpu.video;
const now = () => cpu.cycleSeconds * 2000000 + cpu.currentCycles;
let judging = false, seenPanel = false, phase = -1, lastH = -1, nH = 0, lines = 0, fields = 0;
let haveV = false;
const intervals = new Map(), fieldCounts = new Map(), bad = [], ulaHist = new Map(), ulaSeq = [], lat = [new Map(), new Map(), new Map(), new Map()];
function onH(t) {
    if (judging && lastH >= 0) {
        const d = t - lastH;
        intervals.set(d, (intervals.get(d) || 0) + 1);
        if (d !== 128 && bad.length < 20) bad.push(`hsync interval ${d} at ${(t / 2e6).toFixed(4)} s, line ${(159 + lines + 1) % 312}`);
        nH++;
    }
    lastH = t;
    lines++;
}
function onV(t) {
    if (judging && haveV) {
        if (fields > 0) {
            fieldCounts.set(lines, (fieldCounts.get(lines) || 0) + 1);
            if (lines !== 312 && bad.length < 20) bad.push(`a field of ${lines} lines at ${(t / 2e6).toFixed(4)} s`);
        }
        fields++;
    }
    haveV = true;
    lines = 0;
}
const orig = v.polltime.bind(v);
v.polltime = clocks => {
    const t0 = now() - clocks;
    for (let i = 1; i <= clocks; i++) {
        const was = v.inHSync;
        orig(1);
        if (!was && v.inHSync) onH(t0 + i);
    }
};
const via = cpu.sysvia, setVB = via.setVBlankInt.bind(via);
let vb = false;
via.setVBlankInt = level => { if (level && !vb) onV(now()); vb = !!level; setVB(level); };
cpu.debugWrite.add((addr, val) => {
    if (addr !== 0xfe20) return false;
    if (val === 0xc4) { seenPanel = true; }
    else if (seenPanel && (val === 0xd8 || val === 0xf4)) {
        seenPanel = false;
        if (!judging && skip-- <= 0) { judging = true; phase = (v.oddClock ? 1 : 0) ^ (cpu.currentCycles & 1); }
    }
    if (judging && lastH >= 0 && haveV) {
        let line = (159 + lines) % 312;
        let cyc = now() + 1 - lastH + ((line >= 256 || line === 0) ? 42 : 90);
        const len = line === 255 ? 176 : line === 0 ? 80 : 128;
        if (cyc >= len) { cyc -= len; line = (line + 1) % 312; }
        const k = `&${val.toString(16).toUpperCase()} ${line}:${cyc}`;
        ulaHist.set(k, (ulaHist.get(k) || 0) + 1);
        if (ulaSeq.length < ULA) ulaSeq.push(k);
    }
    return false;
});
let injN = 0, nops = 0;
const e0at = new Map();
let nopn = 0;
function findNops() {                                       // Ev's NOPs: the run of $EA after irq
    for (let a = lab.irq; a < lab.irq + 100; a++) {
        let n = 0;
        while (cpu.readmem(a + n) === 0xea) n++;
        if (n >= 16) { nopn = n; return a; }
    }
    return -100;
}
if (INJ >= 0 || LAT) cpu.debugInstruction.add(pc => {
    if (pc !== lab.irq || !judging) return false;
    if (cpu.sysvia.ifr & cpu.sysvia.ier & 2) {
        if (!nops) nops = findNops();
        // E0: the return address on the stack against Ev's NOPs
        const ret = cpu.readmem(0x102 + cpu.s) | cpu.readmem(0x103 + cpu.s) << 8;
        const k = ret >= nops && ret <= nops + nopn ? ret - nops : -1;
        e0at.set(k, (e0at.get(k) || 0) + 1);
    } else if (INJ >= 0) { const d = injN++ % (INJ + 1); if (d) cpu.polltime(d); }
    return false;
});
if (LAT) {
    const uv = cpu.uservia, ur = uv.read.bind(uv);
    uv.read = addr => {
        const r = ur(addr);
        if ((addr & 15) === 4 && judging) { const e = cpu.readmem(lab.evn) & 3, l = (uv.t1l / 2 - r) & 255; lat[e].set(l, (lat[e].get(l) || 0) + 1); }
        return r;
    };
}
// The flight: keys held throughout (16 SHIFT, 32 SPACE, 90 Z, 88 X, 75 K, 77 M).
const KEYS = [[16], [16, 90], [32, 75], [16, 88], [16, 77], [90], [32, 88, 75], [16, 90, 77], [75], [16], [88], [32, 77]];
const STEP = 3000000;
while (!judging && cpu.cycleSeconds < 60) await s.runFor(200000);
for (let t = 0, i = 0; t < SECS * 2000000; t += STEP, i++) {
    const ks = KEYS[i % KEYS.length];
    for (const k of ks) s.keyDown(k);
    await s.runFor(STEP);
    for (const k of ks) s.keyUp(k);
}
const show = m => [...m.entries()].sort((a, b) => a[0] < b[0] ? -1 : 1).map(([k, n]) => `${k} x${n}`).join(" ");
console.log(`run: ${SECS} s of flight${judging ? "" : " (never judged: no handover)"}; BOOTPRE ${PRE}; horizontal syncs ${nH}; fields ${fields}`);
console.log(`the 6845's 1 MHz clock against the CPU's 1 MHz bus (jsbeeb: the video's oddClock xor the CPU's cycle count, at the handover): ${phase}`);
console.log(`hsync intervals (2 MHz cycles): ${show(intervals)}`);
console.log(`lines per field: ${show(fieldCounts)}`);
console.log(`ULA control writes by value and line:cycle: ${[...ulaHist.entries()].map(([k, n]) => `[${k} x${n}]`).join(" ")}`);
if (ULA) console.log(`the first: ${ulaSeq.join(", ")}`);
if (INJ >= 0) console.log(`injected delays 0-${INJ} cycles at ${injN} entries to irq`);
if (LAT) console.log(`E0 interrupts Ev before its NOP (0-${nopn}; -1: not in Ev's wait): ${[...e0at.entries()].map(([k, n]) => `${k} x${n}`).join(" ")}`);
if (LAT) lat.forEach((m, e) => console.log(`latency at irq's read, evn ${e} (us): ${show(m)}`));
for (const b of bad) console.log("  BAD " + b);
const ok = judging && nH > 0 && intervals.size === 1 && intervals.has(128) && fieldCounts.size === 1 && fieldCounts.has(312);
console.log(ok ? "JHSYNC PASS" : "JHSYNC FAIL");
process.exit(ok ? 0 : 1);
