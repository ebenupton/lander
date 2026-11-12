// b2drive: a headless driver for Tom Seddon's b2 emulator core (libbeeb), for
// Lander's video timing check: every horizontal sync 64us (128 2 MHz cycles)
// from the last, every field 312 lines.
//
// It never opens a window: it builds a BBCMicro from b2's core library, as
// b2's own test program (src/beeb/tests/test_beeb.cpp) does, and feeds its
// video output to b2's TVOutput, the TV model that b2's picture comes from.
//
//   b2drive --disc D.ssd --roms B2/etc/roms --out DIR [--script FILE]
//           [--secs S] [--pre N] [--cold] [--machine b|bplus|master]
//           [--ram LIST]
//           [--nula] [--judge-ula HEX] [--panel-ula HEX] [--judge-skip N]
//           [--judge-reg N] [--judge-after S] [--snap-every S] [--ula N]
//           [--crtc N] [--peek HEX]
//
// The machine: --machine b (the default) is b2's Model B (OS 1.20, BASIC II
// in bank 15, Acorn's 1770 DFS 2.26 in bank 14); --machine bplus is its B+
// (the B+ MOS, the same two ROMs); --machine master is its Master 128 (MOS
// 3.20 and its ROMs in banks 9 to 15, DFS the filing system, no Tube).
// --ram LIST puts sideways RAM in the banks listed (4,5,6,7), or in none
// (--ram none, the default: a plain Model B; the Master always has its own
// banks 4 to 7).  --nula fits a VideoNuLA.  The boot: power on, run
// --pre 2 MHz cycles (and a second), then SHIFT+BREAK; or with --cold, power
// on with SHIFT held, b2's cycle count starting at --pre (its 4 MHz ticks:
// b2 derives the 2 MHz and 1 MHz clocks' phases from the count's low bits,
// so this moves the power-on against them; b2's power-on is otherwise the
// same every time).  Times in the script are in emulated seconds from the
// BREAK key's release (the power-on, with --cold).  Script lines:
//
//   T key NAME [HOLD]     press a key (b2's BeebKey name: Shift, Space, Z, X,
//                         K, M ...) for HOLD seconds (0.2)
//   T poke ADDR VALUE     write a byte to main RAM (hex)
//   T snap NAME           write the TV's last whole field to DIR/NAME.png
//   T end                 stop
//
// What it measures, from the handover on: a write of --judge-ula (hex,
// default D8: the land's control value, MODE 1; F4 for the MODE 2 versions)
// to the video ULA's control register after a write of --panel-ula (default
// C4, the top's MODE 5), passing over the first --judge-skip (default 0) of
// them.  The 32K build's first is its set-up of the land's frame (the lines
// keep the MOS's MODE 7 timing, at C4, until then), and its second is the
// first field's Eb (src/video.s), from which every line is exact: b2sweep.sh
// passes --judge-skip 1.  The lines of the set-up itself and the first Ez,
// which a polled vertical sync places, come before it.  With --panel-ula 0
// any write of --judge-ula counts (the sideways RAM build, whose display has
// one mode and writes it once), and with --judge-reg N the handover is the
// first write of the 6845's register N after it (13: the last of that
// build's set-up of its frame).  Or from --judge-after seconds.  A field is
// counted when it starts after the handover.
//
// * the 6845's syncs, as b2 emits them: every rising edge of the horizontal
//   sync, timed in 2 MHz cycles (b2 emits one video unit per 2 MHz cycle),
//   the intervals' histogram, and the lines (horizontal syncs) per field
//   (between rising edges of the vertical sync);
// * b2's TV, from its first vertical retrace on a sync after the handover
//   (the program's change of mode moves the vertical sync, and the TV's
//   vertical hold takes a field or two to follow; the time is printed), by
//   a mirror of TVOutput::Update's state machine (b2's
//   src/beeb/src/TVOutput.cpp, at the commit in build.sh), unit for unit:
//   horizontal retraces started by a sync against those started by the TV's
//   own timeout (a line with no sync in its 52 microseconds), syncs that
//   fall in the TV's retrace or back porch and so are ignored, vertical syncs
//   that the TV accepts or rejects (it takes one only 1/65 to 1/45 second
//   after the last), the retraces it forces after 500 lines, and the lines
//   and units between its vertical retraces;
// * the writes to the ULA's control register after the handover, by value,
//   field line and cycle, and with --ula N the first N of them in order;
//   with --crtc N the first N writes to the 6845's registers too.  The line
//   is counted from the vertical sync's rising edge, which is the start of
//   line 160 (the land's frame is lines 0-247, the top's 248-311); the
//   cycle from the last horizontal sync, which is on cycle 90 of lines
//   1-255 and on cycle 42 of lines 256-311 and line 0 (line 255 is 176
//   cycles and line 0 is 80, their syncs 128 apart all the same).  A write
//   on cycle c takes effect from cycle c, so the last cycle at the old
//   clock, p, is c - 1;
// * with --peek HEX, the byte of main RAM there at the end.
//
// Exit status 0 when every interval is 128 cycles, every field has the same
// line count, the TV never times out, never ignores a sync and accepts every
// vertical sync (B2SYNC PASS); 1 otherwise.  The PNG files are b2's TV
// texture, 736 x 576 (each line doubled).

#include <shared/system.h>
#include <beeb/BBCMicro.h>
#include <beeb/TVOutput.h>
#include <beeb/MemoryDiscImage.h>
#include <beeb/DiscGeometry.h>
#include <beeb/DiscInterface.h>
#include <beeb/sound.h>
#include <beeb/video.h>
#include <beeb/type.h>
#include <beeb/keys.h>
#include <6502/6502.h>
#include <shared/file_io.h>
#include <shared/path.h>
#include <shared/strings.h>
#include <shared/mutex.h>
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <array>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifdef __GNUC__
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wsign-conversion"
#pragma GCC diagnostic ignored "-Wconversion"
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
#pragma GCC diagnostic ignored "-Wmissing-field-initializers"
#endif
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image_write.h>
#ifdef __GNUC__
#pragma GCC diagnostic pop
#endif

static const uint64_t TICKS_PER_SEC = 4000000; // b2's cycle count: 4 MHz

static void Die(const char *msg, const std::string &arg = "") {
    fprintf(stderr, "b2drive: %s%s\n", msg, arg.c_str());
    exit(2);
}

static std::vector<uint8_t> Load(const std::string &path) {
    std::vector<uint8_t> d;
    if (!LoadFile(&d, path, nullptr)) {
        Die("cannot load ", path);
    }
    return d;
}

// The mirror of b2's TV (TVOutput::Update), for its sync handling only.
struct TVMirror {
    enum State { VR,
                 VRW,
                 SCAN,
                 HR,
                 HRW,
                 BP };
    State st = VR;
    int timer = 0;
    uint64_t total = 0, last_vr = 0;
    bool any_vr = false, whole = false;
    // counts
    uint64_t h_by_sync = 0, h_by_timeout = 0, v_accepted = 0, v_rejected = 0, v_forced = 0;
    bool prev_vs = false;
    uint64_t lines_this_field = 0;
    std::map<uint64_t, uint64_t> lines_per_field, units_per_field;
    bool judging = false, armed = false;
    uint64_t locked_at = 0;

    // Feed one unit (2 MHz cycle) of the 6845's sync outputs.
    void Unit(bool hsync, bool vsync) {
        bool edge = vsync && !prev_vs;
        prev_vs = vsync;
        static const int HRC = 2 * 4, BPC = 2 * 8, SOC = 2 * 52, LINE = 128, VRL = 12;
        static const uint64_t MINV = 2000000 / 65, MAXV = 2000000 / 45;
        switch (st) {
        case VR:
            if (judging && any_vr && whole) { // (a field judged from its start)
                lines_per_field[lines_this_field]++;
                units_per_field[total - last_vr]++;
            }
            whole = judging;
            last_vr = total;
            any_vr = true;
            lines_this_field = 0;
            st = VRW;
            timer = 1;
            break;
        case VRW:
            if (timer++ >= VRL * LINE) {
                timer = 0;
                st = SCAN;
            }
            break;
        case SCAN:
            if (vsync) {
                uint64_t since = total - last_vr;
                if ((since >= MINV && since <= MAXV) || last_vr == 0) { // (b2: the first ever is taken)
                    if (armed && !judging) { // (the TV's vertical hold has the new display)
                        judging = true;
                        locked_at = total;
                    }
                    if (judging) v_accepted++;
                    st = VR;
                    break;
                }
                if (judging && edge) v_rejected++; // (once a pulse)
            }
            if (hsync) {
                if (judging) h_by_sync++;
                st = HR;
                break;
            }
            if (timer++ >= SOC) {
                if (judging) h_by_timeout++;
                st = HR;
            }
            break;
        case HR:
            // (b2's TV retraces anyway after MAX_NUM_SCANNED_LINES, 500,
            // lines with no vertical sync it takes)
            if (++lines_this_field >= 500) {
                if (judging) v_forced++;
                st = VR;
                break;
            }
            timer = 2;
            st = HRW;
            break;
        case HRW:
            if (++timer >= HRC) {
                timer = 0;
                st = BP;
            }
            break;
        case BP:
            if (++timer >= BPC) {
                timer = 0;
                st = SCAN;
            }
            break;
        }
        total++;
    }
};

// BBCMicro, with its test hook for writing a byte of main RAM made public.
class Beeb : public BBCMicro {
  public:
    using BBCMicro::BBCMicro;
    void Poke(uint16_t addr, uint8_t v) { this->TestSetByte(addr, v); }
};

struct Ev {
    double t;
    std::string cmd, a, b;
};

struct Driver {
    std::unique_ptr<Beeb> beeb;
    TVOutput tv;
    TVMirror mir;
    uint64_t units = 0, handover_unit = 0; // 2 MHz cycles of video output
    // 6845 sync timing
    bool judging = false;
    int judge_ula = 0xd8, panel_ula = 0xc4, judge_skip = 0;
    int judge_reg = -1;
    bool seen_panel = false, seen_land = false, whole = false;
    double judge_after = -1;
    uint64_t last_h = 0, hs_since_v = 0;
    bool have_h = false, prev_h = false, prev_v = false, have_v = false;
    std::map<uint64_t, uint64_t> intervals, fields;
    uint64_t first_field_lines = 0, nfields = 0, nh = 0;
    std::vector<std::string> bad;
    uint64_t ignored_h = 0;
    // ULA writes
    int ula_log = 0, crtc_log = 0, crtc_reg = 0;
    struct UW {
        uint64_t unit;
        uint8_t v;
        int reg; // -1: the ULA's control register; else the 6845's register
    };
    std::vector<UW> pending;
    std::vector<std::string> ula_lines;
    uint64_t ula_count = 0;
    std::map<std::string, uint64_t> ula_hist; // "value line cycle" -> count
    uint64_t v_unit = 0;                      // unit of the last vsync rising edge
    double now_s = 0;
    double t0 = 0; // seconds of the script's time 0

    void Handover(const std::string &what) {
        judging = true;
        mir.armed = true;
        handover_unit = units;
        printf("handover: %s at %.3f s\n", what.c_str(), now_s);
    }

    static bool OnWrite(const BBCMicro *, const M6502 *cpu, void *ctx) {
        auto d = (Driver *)ctx;
        uint16_t a = cpu->abus.w;
        if (a == 0xfe20) {
            if (d->panel_ula && cpu->dbus == d->panel_ula) d->seen_panel = true;
            if (!d->judging && d->judge_ula >= 0 && cpu->dbus == d->judge_ula && (d->seen_panel || !d->panel_ula)) {
                d->seen_panel = false;
                if (d->judge_skip-- <= 0) {
                    if (d->judge_reg >= 0) d->seen_land = true;
                    else d->Handover(strprintf("&%02X to &FE20", cpu->dbus));
                }
            }
            if (d->judging) {
                d->pending.push_back({d->units, cpu->dbus, -1});
            }
        } else if ((a & 0xfff8) == 0xfe00) {
            if (!(a & 1)) d->crtc_reg = cpu->dbus & 31;
            else if (!d->judging && d->seen_land && d->crtc_reg == d->judge_reg) d->Handover(strprintf("6845 R%d written", d->crtc_reg));
            else if (d->judging && d->crtc_log > 0) d->pending.push_back({d->units, cpu->dbus, d->crtc_reg});
        }
        return true;
    }

    // Line and cycle of a write at unit u: the field's line counted from the
    // vertical sync's rising edge (the start of line 160), the cycle from the
    // last horizontal sync (cycle 90 of lines 1-255, cycle 42 of lines
    // 256-311 and line 0; line 255 is 176 cycles, line 0 is 80).
    void Resolve(const UW &w) {
        if (!have_h || !have_v) return;
        long line = (159 + (long)hs_since_v) % 312; // the last sync's line
        long cyc = (long)(w.unit - last_h) + ((line >= 256 || line == 0) ? 42 : 90);
        long len = line == 255 ? 176 : line == 0 ? 80 : 128;
        if (cyc >= len) {
            cyc -= len;
            line = (line + 1) % 312;
        }
        char buf[64];
        if (w.reg < 0) {
            snprintf(buf, sizeof buf, "&%02X %ld:%ld", w.v, line, cyc);
            ula_hist[buf]++;
            if (ula_count < (uint64_t)ula_log) {
                ula_lines.push_back(strprintf("%.3f s: %s", now_s, buf));
            }
            ula_count++;
        } else if (crtc_log > 0) {
            crtc_log--;
            ula_lines.push_back(strprintf("%.3f s: R%d=%u %ld:%ld", now_s, w.reg, w.v, line, cyc));
        }
    }

    void Video(const VideoDataUnit &u) {
        bool h = (u.pixels.pixels[1].bits.x & VideoDataUnitFlag_HSync) != 0;
        bool v = (u.pixels.pixels[1].bits.x & VideoDataUnitFlag_VSync) != 0;
        if (h && !prev_h) {
            // ULA writes since the last hsync resolve against it
            for (const UW &w : pending) Resolve(w);
            pending.clear();
            if (judging && have_h) {
                uint64_t d = units - last_h;
                intervals[d]++;
                if (d != 128 && bad.size() < 40) {
                    bad.push_back(strprintf("%.4f s: horizontal sync interval %llu", now_s, (unsigned long long)d));
                }
                nh++;
            }
            if (mir.judging && (mir.st == TVMirror::HRW || mir.st == TVMirror::BP || mir.st == TVMirror::HR)) {
                ignored_h++;
                if (bad.size() < 40) bad.push_back(strprintf("%.4f s: TV ignored a horizontal sync (in its retrace)", now_s));
            }
            last_h = units;
            have_h = true;
            hs_since_v++;
        }
        if (v && !prev_v) {
            if (judging && have_v && whole) {
                if (nfields == 0) first_field_lines = hs_since_v;
                fields[hs_since_v]++;
                if (hs_since_v != first_field_lines && bad.size() < 40) {
                    bad.push_back(strprintf("%.4f s: field of %llu lines", now_s, (unsigned long long)hs_since_v));
                }
                nfields++;
            }
            whole = judging;
            have_v = true;
            hs_since_v = 0;
            v_unit = units;
        }
        prev_h = h;
        prev_v = v;
        uint64_t to = mir.h_by_timeout, vr = mir.v_rejected;
        mir.Unit(h, v);
        if (mir.h_by_timeout != to && bad.size() < 40) bad.push_back(strprintf("%.4f s: TV line timed out (no sync)", now_s));
        if (mir.v_rejected != vr && bad.size() < 40) bad.push_back(strprintf("%.4f s: TV rejected a vertical sync", now_s));
        units++;
    }
};

static bool Key(const std::string &name, BeebKey *k) {
    for (int i = 0; i < 128; ++i) {
        const char *n = GetBeebKeyEnumName(i);
        if (n && name == n) {
            *k = (BeebKey)i;
            return true;
        }
    }
    if (name == "Break") {
        *k = BeebKey_Break;
        return true;
    }
    return false;
}

static void SnapPNG(Driver &d, const std::string &path) {
    UniqueLock<Mutex> lock;
    const uint32_t *px = d.tv.GetLastVSyncTexturePixels(&lock);
    std::vector<uint8_t> rgb((size_t)TV_TEXTURE_WIDTH * TV_TEXTURE_HEIGHT * 3);
    for (size_t i = 0; i < (size_t)TV_TEXTURE_WIDTH * TV_TEXTURE_HEIGHT; ++i) {
        uint32_t p = px[i];
        rgb[i * 3 + 0] = (uint8_t)(p >> 16);
        rgb[i * 3 + 1] = (uint8_t)(p >> 8);
        rgb[i * 3 + 2] = (uint8_t)p;
    }
    if (!stbi_write_png(path.c_str(), TV_TEXTURE_WIDTH, TV_TEXTURE_HEIGHT, 3, rgb.data(), TV_TEXTURE_WIDTH * 3)) {
        Die("cannot write ", path);
    }
    printf("snap %s (%.2f s)\n", path.c_str(), d.now_s);
}

int main(int argc, char *argv[]) {
    std::string disc, roms, out = ".", script;
    double secs = 60, judge_after = -1, snap_every = 0;
    uint64_t pre = 0;
    bool cold = false;
    int judge_ula = 0xd8, panel_ula = 0xc4, judge_skip = 0, judge_reg = -1, ula_log = 0, crtc_log = 0, peek_addr = -1;
    bool master = false, bplus = false, nula = false;
    std::vector<int> ram;
    for (int i = 1; i < argc; ++i) {
        std::string a = argv[i];
        auto next = [&]() -> std::string { if (i + 1 >= argc) Die("missing value for ", a); return argv[++i]; };
        if (a == "--disc") disc = next();
        else if (a == "--roms") roms = next();
        else if (a == "--out") out = next();
        else if (a == "--script") script = next();
        else if (a == "--secs") secs = atof(next().c_str());
        else if (a == "--pre") pre = strtoull(next().c_str(), nullptr, 0);
        else if (a == "--cold") cold = true;
        else if (a == "--judge-ula") judge_ula = (int)strtol(next().c_str(), nullptr, 16);
        else if (a == "--judge-after") { judge_after = atof(next().c_str()); judge_ula = -1; }
        else if (a == "--snap-every") snap_every = atof(next().c_str());
        else if (a == "--ula") ula_log = atoi(next().c_str());
        else if (a == "--crtc") crtc_log = atoi(next().c_str());
        else if (a == "--panel-ula") panel_ula = (int)strtol(next().c_str(), nullptr, 16);
        else if (a == "--judge-skip") judge_skip = atoi(next().c_str());
        else if (a == "--judge-reg") judge_reg = atoi(next().c_str());
        else if (a == "--peek") peek_addr = (int)strtol(next().c_str(), nullptr, 16);
        else if (a == "--nula") nula = true;
        else if (a == "--machine") {
            std::string m = next();
            if (m == "master") master = true;
            else if (m == "bplus") bplus = true;
            else if (m != "b") Die("unknown machine ", m);
        }
        else if (a == "--ram") {
            ram.clear();
            std::string s = next();
            if (s == "none") s = "";
            for (char *p = &s[0]; *p;) {
                ram.push_back((int)strtol(p, &p, 10));
                if (*p == ',') ++p;
            }
        } else Die("unknown option ", a);
    }
    if (disc.empty() || roms.empty()) Die("need --disc and --roms");

    std::vector<Ev> evs;
    if (!script.empty()) {
        FILE *f = fopen(script.c_str(), "r");
        if (!f) Die("cannot open ", script);
        char line[512];
        while (fgets(line, sizeof line, f)) {
            if (line[0] == '#' || line[0] == '\n') continue;
            char c[64] = "", x[128] = "", y[128] = "";
            double t;
            if (sscanf(line, "%lf %63s %127s %127s", &t, c, x, y) >= 2) evs.push_back({t, c, x, y});
        }
        fclose(f);
    }

    // The machine: b2's default B or B+ (its BeebConfig's, with the Acorn 1770
    // DFS) and sideways RAM in --ram, or its Master 128 (MOS 3.20, as b2's tests
    // configure it: language BASIC in 12, filing system DFS in 9, no Tube).
    ROMType rom_types[16] = {};
    Driver d;
    d.judge_ula = judge_ula;
    d.panel_ula = panel_ula;
    d.judge_skip = judge_skip;
    d.judge_reg = judge_reg;
    d.judge_after = judge_after;
    d.ula_log = ula_log;
    d.crtc_log = crtc_log;
    uint32_t init_flags = BBCMicroInitFlag_Serial | (nula ? BBCMicroInitFlag_VideoNuLA : 0);
    auto rom = [&](const char *name) {
        auto r = std::make_shared<std::vector<uint8_t>>(Load(PathJoined(roms, name)));
        r->resize(16384);
        return r;
    };
    auto os = [&](const char *name) {
        std::vector<uint8_t> o = Load(PathJoined(roms, name));
        auto osr = std::make_shared<std::array<uint8_t, 16384>>();
        memcpy(osr->data(), o.data(), std::min(o.size(), osr->size()));
        return osr;
    };
    if (master) {
        std::vector<uint8_t> nvram(50);
        nvram[5] = 0xC9;   // LANG 12, FS 9
        nvram[6] = 0xFF;   // every ROM inserted
        nvram[7] = 0xFF;
        nvram[10] = 0x17;  // MODE 7, TV 0 1
        nvram[11] = 0x80;  // FLOPPY
        nvram[12] = 55;    // DELAY
        nvram[13] = 0x03;  // REPEAT
        nvram[15] = 1 << 5; // PRINT 1, NOTUBE
        nvram[16] = 0x02;  // LOUD
        d.beeb = std::make_unique<Beeb>(CreateBBCMicroType(BBCMicroTypeID_Master, rom_types, BBCMicroTypeFlag_ROMBoard),
                                        &DISC_INTERFACE_MASTER128, BBCMicroParasiteType_None, nvram, nullptr,
                                        init_flags, nullptr, HardDiskImageSet{}, std::string(), CycleCount{cold ? pre : 0});
        d.beeb->SetOSROM(os("M128/3.20/mos.rom"));
        static const char *const M[7] = {"terminal", "view", "adfs", "basic4", "edit", "viewsht", "dfs"};
        for (int i = 0; i < 7; ++i) d.beeb->SetSidewaysROM((uint8_t)(15 - i), rom(strprintf("M128/3.20/%s.rom", M[i]).c_str()), ROMType_16KB);
        for (uint8_t b = 4; b < 8; ++b) d.beeb->SetSidewaysRAM(b, nullptr);
    } else {
        d.beeb = std::make_unique<Beeb>(CreateBBCMicroType(bplus ? BBCMicroTypeID_BPlus : BBCMicroTypeID_B, rom_types, BBCMicroTypeFlag_ROMBoard),
                                        &DISC_INTERFACE_ACORN_1770, BBCMicroParasiteType_None, std::vector<uint8_t>(), nullptr,
                                        init_flags, nullptr, HardDiskImageSet{}, std::string(), CycleCount{cold ? pre : 0});
        d.beeb->SetOSROM(os(bplus ? "B+MOS.rom" : "OS12.ROM"));
        d.beeb->SetSidewaysROM(15, rom("BASIC2.ROM"), ROMType_16KB);
        d.beeb->SetSidewaysROM(14, rom("acorn/DFS-2.26.rom"), ROMType_16KB);
        for (int b : ram) d.beeb->SetSidewaysRAM((uint8_t)b, nullptr);
    }
    {
        std::vector<uint8_t> img = Load(disc);
        DiscGeometry g;
        if (!FindDiscGeometryFromFileDetails(&g, disc.c_str(), img.size(), nullptr)) Die("unknown disc geometry: ", disc);
        auto mdi = MemoryDiscImage::LoadFromBuffer(disc, "file", img.data(), img.size(), g, nullptr);
        if (!mdi) Die("cannot load disc ", disc);
        d.beeb->SetDiscImage(0, mdi);
    }
    d.beeb->AddHostWriteCallback(&Driver::OnWrite, &d);

    const CycleCount *cc = d.beeb->GetCycleCountPtr();
    d.now_s = (double)cc->n / TICKS_PER_SEC;
    VideoDataUnit vu[1024];
    SoundDataUnit su;
    size_t nvu = 0;
    auto run_ticks = [&](uint64_t n) {
        for (uint64_t i = 0; i < n; ++i) {
            uint32_t r = d.beeb->Update(&vu[nvu], &su);
            if (r & BBCMicroUpdateResultFlag_VideoUnit) {
                d.Video(vu[nvu]);
                if (++nvu == 1024) {
                    d.tv.Update(vu, nvu);
                    nvu = 0;
                }
            }
        }
        d.now_s = (double)cc->n / TICKS_PER_SEC;
    };
    auto flush = [&]() { if (nvu) { d.tv.Update(vu, nvu); nvu = 0; } };

    // Boot.
    if (cold) {
        d.beeb->SetKeyState(BeebKey_Shift, true);
        d.t0 = d.now_s;
        run_ticks(TICKS_PER_SEC);
        d.beeb->SetKeyState(BeebKey_Shift, false);
    } else {
        run_ticks(TICKS_PER_SEC + 2 * pre);
        d.beeb->SetKeyState(BeebKey_Shift, true);
        d.beeb->SetKeyState(BeebKey_Break, true);
        run_ticks(TICKS_PER_SEC / 20);
        d.beeb->SetKeyState(BeebKey_Break, false);
        d.t0 = d.now_s;
        run_ticks(TICKS_PER_SEC);
        d.beeb->SetKeyState(BeebKey_Shift, false);
    }

    // Script.
    size_t ei = 0;
    double next_snap = snap_every > 0 ? snap_every : 1e30;
    int snapn = 0;
    std::vector<std::pair<double, BeebKey>> releases;
    const double step = 0.01;
    for (double t = d.now_s - d.t0; t < secs; t = d.now_s - d.t0) {
        if (d.judge_after >= 0 && !d.judging && t >= d.judge_after) {
            d.judging = true;
            d.mir.armed = true;
            d.handover_unit = d.units;
        }
        for (size_t r = 0; r < releases.size();) {
            if (t >= releases[r].first) {
                d.beeb->SetKeyState(releases[r].second, false);
                releases.erase(releases.begin() + (long)r);
            } else ++r;
        }
        bool stop = false;
        while (ei < evs.size() && evs[ei].t <= t) {
            const Ev &e = evs[ei++];
            if (e.cmd == "key") {
                BeebKey k;
                if (!Key(e.a, &k)) Die("unknown key ", e.a);
                d.beeb->SetKeyState(k, true);
                releases.push_back({t + (e.b.empty() ? 0.2 : atof(e.b.c_str())), k});
            } else if (e.cmd == "poke") {
                d.beeb->Poke((uint16_t)strtol(e.a.c_str(), nullptr, 16), (uint8_t)strtol(e.b.c_str(), nullptr, 16));
            } else if (e.cmd == "snap") {
                flush();
                SnapPNG(d, PathJoined(out, e.a + ".png"));
            } else if (e.cmd == "end") {
                stop = true;
            } else Die("unknown command ", e.cmd);
        }
        if (stop) break;
        if (t >= next_snap) {
            flush();
            SnapPNG(d, PathJoined(out, strprintf("t%03d", snapn++) + ".png"));
            next_snap += snap_every;
        }
        run_ticks((uint64_t)(step * TICKS_PER_SEC));
    }
    flush();

    // Report.
    const uint8_t *ram_p = d.beeb->GetRAM();
    printf("run: %.2f emulated s from the boot%s\n", d.now_s - d.t0, d.judging ? "" : " (never judged: no handover)");
    printf("6845 horizontal sync intervals (2 MHz cycles):");
    for (auto &kv : d.intervals) printf(" %llu x%llu", (unsigned long long)kv.first, (unsigned long long)kv.second);
    printf("\n6845 lines per field:");
    for (auto &kv : d.fields) printf(" %llu x%llu", (unsigned long long)kv.first, (unsigned long long)kv.second);
    printf("\nTV: %llu retraces on a sync, %llu on its timeout, %llu syncs ignored; vertical syncs %llu accepted, %llu rejected, %llu forced retraces (500 lines)\n",
           (unsigned long long)d.mir.h_by_sync, (unsigned long long)d.mir.h_by_timeout, (unsigned long long)d.ignored_h,
           (unsigned long long)d.mir.v_accepted, (unsigned long long)d.mir.v_rejected, (unsigned long long)d.mir.v_forced);
    if (d.mir.judging) printf("TV: its first vertical retrace on a sync %.1f fields after the handover\n", (double)(d.mir.locked_at - d.handover_unit) / 39936.0);
    else printf("TV: no vertical retrace on a sync after the handover\n");
    printf("TV lines per field:");
    for (auto &kv : d.mir.lines_per_field) printf(" %llu x%llu", (unsigned long long)kv.first, (unsigned long long)kv.second);
    printf("\nTV units per field:");
    for (auto &kv : d.mir.units_per_field) printf(" %llu x%llu", (unsigned long long)kv.first, (unsigned long long)kv.second);
    printf("\n");
    for (auto &s : d.ula_lines) printf("  ula %s\n", s.c_str());
    printf("ULA control writes by value and line:cycle:");
    for (auto &kv : d.ula_hist) printf(" [%s x%llu]", kv.first.c_str(), (unsigned long long)kv.second);
    printf("\n");
    if (peek_addr >= 0) printf("peek &%04X = %u\n", peek_addr, ram_p[peek_addr & 0xffff]);
    for (auto &s : d.bad) printf("  BAD %s\n", s.c_str());
    bool ok = d.judging && d.mir.judging && d.nh > 0 && d.intervals.size() == 1 && d.intervals.count(128) && d.fields.size() == 1 &&
              d.mir.h_by_timeout == 0 && d.ignored_h == 0 && d.mir.v_rejected == 0 && d.mir.v_forced == 0 && d.mir.lines_per_field.size() <= 1;
    printf(ok ? "B2SYNC PASS\n" : "B2SYNC FAIL\n");
    return ok ? 0 : 1;
}
