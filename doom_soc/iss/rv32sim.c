// rv32sim.c - RV32IM instruction-set simulator for the doom_soc memory map.
//
//   ROM   0x0040_0000  64 KB   boot ROM (ELF or $readmemh hex via -rom)
//   RAM   0x8000_0000  128 MB  DDR2
//   MMIO  0xFFFF_0000  same offsets as Wrapper.v / doom_soc mmio.v
//
// The MMIO model follows the RTL (doom_soc/rtl/soc/mmio.v): UART RX FIFO, OLED with the
// Wrapper auto-advance behaviour (writing OLED_CTRL re-arms auto-advance), PB[4:0] =
// {BTND, BTNU, BTNL, BTNC, BTNR}, CYCLECOUNT, SIM_CTRL (0xFC).
//
// Usage: rv32sim [options] [prog.elf]
//   -rom FILE         boot ROM image (ELF, or .hex = one 32-bit word per line); PC starts at ROM
//   -wad FILE         put FILE in RAM like the boot loader does (header at WAD_HDR, data after)
//   -uartin FILE      bytes fed to the UART RX FIFO (as fast as the program reads them)
//   -input FILE       timed input script: lines "<ms> pb <hex>" / "<ms> dip <hex>" / "<ms> key <hex>"
//   -frames DIR       dump OLED frames as PPM into DIR
//   -every N          dump every Nth frame (default 1)
//   -max N            stop after N instructions (millions with suffix M)
//   -cpi X            cycles per instruction for CYCLECOUNT (default 1.0)
//   -clk HZ           CPU clock used for the ms timebase of -input (default 37500000)
//   -trace FILE       write the register-write trace ("<idx> <pc> <rd> <value>")
//   -check FILE       compare against an RTL register-write trace ("<rd> <value>" per line);
//                     MMIO load results are taken from the RTL trace
//   -strict           stop on misaligned accesses (default: warn once, act like the hardware)
//   -q                quiet (no UART echo)
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

#define ROM_BASE  0x00400000u
#define ROM_SIZE  (64u * 1024u)
#define RAM_BASE  0x80000000u
#define RAM_SIZE  (128u << 20)
#define MMIO_BASE 0xFFFF0000u
#define WAD_HDR   0x86FFFFF0u    // must match sw/common/doom_soc.h
#define WAD_DATA  0x87000000u

static uint8_t  *ram;
static uint8_t   rom[ROM_SIZE];
static uint32_t  x[32];
static uint32_t  pc;
static uint64_t  instret;
static double    cpi = 1.0;
static double    clk_hz = 37500000.0;
static int       quiet, strict;
static int       misalign_warned;

// ---------------- MMIO state ----------------
#define RXQ 65536
static uint8_t  rxq[RXQ];
static unsigned rx_head, rx_tail;           // FIFO in the RTL is small; here unbounded-ish
static FILE    *uartin;
static uint32_t led, sevenseg, dip, pb;
static uint8_t  oled_ctrl, oled_col, oled_row;
static int      auto_col, auto_row;
static uint16_t oled_fb[64][96];
static unsigned oled_writes;
static unsigned long frame_no;
static const char *frame_dir;
static unsigned frame_every = 1;
static int      sim_done, sim_code;

// timed input script
typedef struct { double ms; int kind; uint32_t v; } ev_t;   // kind 0 pb, 1 dip, 2 key byte
static ev_t    *evs;
static int      n_ev, ev_pos;

// lockstep check
static FILE    *chk;
static FILE    *trc;
static uint64_t n_writes;
static int      last_load_mmio;              // set by the load currently executing

static uint64_t cycles_now(void) { return (uint64_t)(instret * cpi); }
static double   ms_now(void)     { return cycles_now() * 1000.0 / clk_hz; }

static int rx_count(void) { return (int)(rx_tail - rx_head); }
static void rx_fill(void)
{
    if (uartin) {
        int c;
        while (rx_count() < RXQ - 1 && (c = fgetc(uartin)) != EOF)
            rxq[rx_tail++ % RXQ] = (uint8_t)c;
        if (feof(uartin)) { fclose(uartin); uartin = NULL; }
    }
}

static void poll_input(void)
{
    double now = ms_now();
    while (ev_pos < n_ev && evs[ev_pos].ms <= now) {
        ev_t *e = &evs[ev_pos++];
        if (e->kind == 0) pb = e->v;
        else if (e->kind == 1) dip = e->v;
        else rxq[rx_tail++ % RXQ] = (uint8_t)e->v;
    }
}

static void dump_frame(void)
{
    char name[512];
    if (!frame_dir || (frame_no % frame_every)) return;
    snprintf(name, sizeof name, "%s/frame_%05lu.ppm", frame_dir, frame_no);
    FILE *f = fopen(name, "wb");
    if (!f) return;
    fprintf(f, "P6\n96 64\n255\n");
    for (int r = 0; r < 64; r++)
        for (int c = 0; c < 96; c++) {
            uint16_t p = oled_fb[r][c];
            uint8_t rgb[3] = { (uint8_t)((p >> 11) << 3), (uint8_t)(((p >> 5) & 63) << 2), (uint8_t)((p & 31) << 3) };
            fwrite(rgb, 1, 3, f);
        }
    fclose(f);
}

// OLED: same register behaviour as Wrapper.v. The pixel lands at the post-increment address.
static void oled_data_write(uint32_t v, unsigned mask)
{
    unsigned mode = oled_ctrl & 15;
    if (mode == 4) {                                   // autoadvance_col (row major)
        if (auto_col) {
            if (oled_col >= 95) { oled_col = 0; oled_row = (oled_row + 1) & 63; }
            else oled_col++;
        }
        auto_col = 1; auto_row = 0;
    } else if (mode == 5) {                            // autoadvance_row (column major)
        if (auto_row) {
            if (oled_row == 63) { oled_row = 0; oled_col = oled_col >= 95 ? 0 : oled_col + 1; }
            else oled_row++;
        }
        auto_row = 1; auto_col = 0;
    } else if (mode == 1 || mode == 2) {
        return;                                        // data writes don't trigger a pixel write there
    } else { auto_col = auto_row = 0; }
    uint16_t p;
    switch (oled_ctrl >> 4) {
    case 1:  if ((mask & 3) != 3) return; p = (uint16_t)v; break;
    case 2:  p = (uint16_t)((((v >> 19) & 31) << 11) | (((v >> 10) & 63) << 5) | ((v >> 3) & 31)); break;
    default: p = (uint16_t)((((v >> 5) & 7) << 13) | (((v >> 2) & 7) << 8) | ((v & 3) << 3)); break;
    }
    if (oled_col < 96) oled_fb[oled_row][oled_col] = p;
    if (++oled_writes % 6144 == 0) { dump_frame(); frame_no++; }
}

static uint32_t mmio_read(uint32_t off)
{
    last_load_mmio = 1;
    switch (off) {
    case 0x00: rx_fill(); return rx_count() > 0;
    case 0x04: rx_fill(); if (rx_count() > 0) return rxq[rx_head++ % RXQ]; return 0;
    case 0x08: return 1;
    case 0x40: case 0x44: return 0;
    case 0x64: return dip & 0xFFFF;
    case 0x68: return pb & 0x1F;
    case 0xA0: return (uint32_t)cycles_now();
    default:   return 0;
    }
}

static void mmio_write(uint32_t off, uint32_t v, unsigned mask)
{
    switch (off) {
    case 0x0C: if (mask & 1) { if (!quiet) { putchar((int)(v & 0xFF)); fflush(stdout); } } break;
    case 0x20: if (mask & 1) oled_col = v & 0x7F; break;
    case 0x24: if (mask & 1) oled_row = v & 0x3F; break;
    case 0x28: oled_data_write(v, mask); break;
    case 0x2C: if (mask & 1) { oled_ctrl = (uint8_t)v; auto_col = auto_row = 0; } break;
    case 0x60: if (mask & 1) led = v & 0xFF; break;
    case 0x80: for (int i = 0; i < 4; i++) if (mask & (1u << i)) sevenseg = (sevenseg & ~(0xFFu << 8*i)) | (v & (0xFFu << 8*i)); break;
    case 0xFC: sim_done = 1; sim_code = (int)(v >> 1); break;
    default: break;
    }
}

// ---------------- memory ----------------
static void fatal(const char *msg, uint32_t a)
{
    fprintf(stderr, "\n[iss] %s: addr %08x pc %08x instret %llu\n", msg, a, pc, (unsigned long long)instret);
    exit(2);
}

static void misalign(uint32_t a)
{
    if (strict) fatal("misaligned access", a);
    if (!misalign_warned) { fprintf(stderr, "[iss] WARNING: misaligned access %08x at pc %08x (hardware ignores low bits)\n", a, pc); misalign_warned = 1; }
}

static uint32_t rd32(uint32_t a)        // aligned word read
{
    if (a - RAM_BASE < RAM_SIZE) { uint32_t v; memcpy(&v, ram + (a - RAM_BASE), 4); return v; }
    if (a - ROM_BASE < ROM_SIZE) { uint32_t v; memcpy(&v, rom + (a - ROM_BASE), 4); return v; }
    if (a >= MMIO_BASE)          return mmio_read(a & 0xFF);
    fatal("load from unmapped address", a);
    return 0;
}

static void wr32(uint32_t a, uint32_t v, unsigned mask)   // aligned word, byte mask
{
    if (a - RAM_BASE < RAM_SIZE) {
        uint8_t *p = ram + (a - RAM_BASE);
        for (int i = 0; i < 4; i++) if (mask & (1u << i)) p[i] = (uint8_t)(v >> (8*i));
        return;
    }
    if (a >= MMIO_BASE) { mmio_write(a & 0xFF, v, mask); return; }
    if (a - ROM_BASE < ROM_SIZE) fatal("store to ROM", a);
    fatal("store to unmapped address", a);
}

static uint32_t load(uint32_t a, unsigned f3)
{
    uint32_t w;
    switch (f3) {
    case 0: case 4: { w = rd32(a & ~3u); uint32_t b = (w >> (8*(a & 3))) & 0xFF;
                      return f3 == 0 ? (uint32_t)(int32_t)(int8_t)b : b; }
    case 1: case 5: { if (a & 1) misalign(a); w = rd32(a & ~3u); uint32_t h = (a & 2) ? w >> 16 : w & 0xFFFF;
                      return f3 == 1 ? (uint32_t)(int32_t)(int16_t)h : h; }
    default:        if (a & 3) misalign(a); return rd32(a & ~3u);
    }
}

static void store(uint32_t a, uint32_t v, unsigned f3)
{
    switch (f3) {
    case 0:  wr32(a & ~3u, (v & 0xFF) * 0x01010101u, 1u << (a & 3)); break;
    case 1:  if (a & 1) misalign(a); wr32(a & ~3u, (v & 0xFFFF) * 0x00010001u, (a & 2) ? 0xC : 0x3); break;
    default: if (a & 3) misalign(a); wr32(a & ~3u, v, 0xF); break;
    }
}

static uint32_t fetch(uint32_t a)
{
    if (a & 3) fatal("misaligned fetch", a);
    if (a - RAM_BASE < RAM_SIZE) { uint32_t v; memcpy(&v, ram + (a - RAM_BASE), 4); return v; }
    if (a - ROM_BASE < ROM_SIZE) { uint32_t v; memcpy(&v, rom + (a - ROM_BASE), 4); return v; }
    fatal("fetch from unmapped address", a);
    return 0;
}

// ---------------- loading ----------------
static long file_size(FILE *f) { long s; fseek(f, 0, SEEK_END); s = ftell(f); fseek(f, 0, SEEK_SET); return s; }

static uint8_t *host_ptr(uint32_t a, uint32_t n)
{
    if (a - RAM_BASE < RAM_SIZE && a - RAM_BASE + n <= RAM_SIZE) return ram + (a - RAM_BASE);
    if (a - ROM_BASE < ROM_SIZE && a - ROM_BASE + n <= ROM_SIZE) return rom + (a - ROM_BASE);
    fatal("image outside memory", a);
    return NULL;
}

static uint32_t load_elf(const char *fn)
{
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    uint8_t eh[52];
    if (fread(eh, 1, 52, f) != 52 || memcmp(eh, "\177ELF", 4) || eh[4] != 1) { fprintf(stderr, "%s: not ELF32\n", fn); exit(1); }
    uint32_t entry, phoff; uint16_t phentsize, phnum;
    memcpy(&entry, eh + 24, 4); memcpy(&phoff, eh + 28, 4);
    memcpy(&phentsize, eh + 42, 2); memcpy(&phnum, eh + 44, 2);
    for (int i = 0; i < phnum; i++) {
        uint32_t ph[8];
        fseek(f, (long)(phoff + i * phentsize), SEEK_SET);
        if (fread(ph, 4, 8, f) != 8) break;
        if (ph[0] != 1 || ph[5] == 0) continue;          // PT_LOAD with memsz
        uint8_t *p = host_ptr(ph[3], ph[5]);              // p_paddr, p_memsz
        memset(p, 0, ph[5]);
        fseek(f, (long)ph[1], SEEK_SET);
        if (ph[4] && fread(p, 1, ph[4], f) != ph[4]) { fprintf(stderr, "%s: short read\n", fn); exit(1); }
    }
    fclose(f);
    return entry;
}

static void load_hex_rom(const char *fn)
{
    FILE *f = fopen(fn, "r");
    if (!f) { perror(fn); exit(1); }
    char line[256]; uint32_t a = 0;
    while (fgets(line, sizeof line, f)) {
        if (line[0] == '@') { a = (uint32_t)strtoul(line + 1, NULL, 16) * 4; continue; }
        char *e; unsigned long v = strtoul(line, &e, 16);
        if (e == line) continue;
        if (a + 4 <= ROM_SIZE) { uint32_t w = (uint32_t)v; memcpy(rom + a, &w, 4); }
        a += 4;
    }
    fclose(f);
}

static void load_wad(const char *fn)
{
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    long n = file_size(f);
    uint8_t *p = host_ptr(WAD_DATA, (uint32_t)n);
    if (fread(p, 1, (size_t)n, f) != (size_t)n) { fprintf(stderr, "%s: short read\n", fn); exit(1); }
    fclose(f);
    uint32_t hdr[4] = { 0x31444157u /* "WAD1" */, (uint32_t)n, WAD_DATA, 0 };
    memcpy(host_ptr(WAD_HDR, 16), hdr, 16);
}

static void load_input(const char *fn)
{
    FILE *f = fopen(fn, "r");
    if (!f) { perror(fn); exit(1); }
    char line[256]; int cap = 0;
    while (fgets(line, sizeof line, f)) {
        double ms; char kind[16]; unsigned v;
        if (line[0] == '#' || sscanf(line, "%lf %15s %x", &ms, kind, &v) != 3) continue;
        if (n_ev == cap) { cap = cap ? cap * 2 : 64; evs = realloc(evs, cap * sizeof *evs); }
        evs[n_ev].ms = ms; evs[n_ev].v = v;
        evs[n_ev].kind = !strcmp(kind, "pb") ? 0 : !strcmp(kind, "dip") ? 1 : 2;
        n_ev++;
    }
    fclose(f);
}

// ---------------- lockstep check ----------------
static void reg_write(unsigned rd, uint32_t v, uint32_t ipc)
{
    if (rd == 0) return;
    if (chk) {
        unsigned crd; unsigned long cv;
        if (fscanf(chk, "%u %lx", &crd, &cv) != 2) {
            fprintf(stderr, "[iss] check: RTL trace ended after %llu writes (pc %08x)\n", (unsigned long long)n_writes, ipc);
            exit(0);
        }
        if (last_load_mmio) v = (uint32_t)cv;              // device values come from the RTL
        if (crd != rd || (uint32_t)cv != v) {
            fprintf(stderr, "[iss] MISMATCH at write #%llu pc %08x instr %08x: ISS x%u=%08x, RTL x%u=%08lx\n",
                    (unsigned long long)n_writes, ipc, fetch(ipc), rd, v, crd, cv);
            exit(3);
        }
    }
    if (trc) fprintf(trc, "%llu %08x %u %08x\n", (unsigned long long)n_writes, ipc, rd, v);
    n_writes++;
    x[rd] = v;
}

// ---------------- execute ----------------
static inline int32_t imm_i(uint32_t i) { return (int32_t)i >> 20; }
static inline int32_t imm_s(uint32_t i) { return ((int32_t)(i & 0xFE000000) >> 20) | ((i >> 7) & 31); }
static inline int32_t imm_b(uint32_t i) {
    return ((int32_t)(i & 0x80000000) >> 19) | ((i & 0x80) << 4) | ((i >> 20) & 0x7E0) | ((i >> 7) & 0x1E);
}
static inline int32_t imm_j(uint32_t i) {
    return ((int32_t)(i & 0x80000000) >> 11) | (i & 0xFF000) | ((i >> 9) & 0x800) | ((i >> 20) & 0x7FE);
}

static void illegal(uint32_t ins) { fprintf(stderr, "\n[iss] illegal instruction %08x at pc %08x\n", ins, pc); exit(2); }

static void step(void)
{
    uint32_t ins = fetch(pc);
    uint32_t npc = pc + 4;
    unsigned rd = (ins >> 7) & 31, rs1 = (ins >> 15) & 31, rs2 = (ins >> 20) & 31, f3 = (ins >> 12) & 7, f7 = ins >> 25;
    uint32_t a = x[rs1], b = x[rs2];
    last_load_mmio = 0;
    switch (ins & 0x7F) {
    case 0x37: reg_write(rd, ins & 0xFFFFF000u, pc); break;                       // lui
    case 0x17: reg_write(rd, pc + (ins & 0xFFFFF000u), pc); break;                // auipc
    case 0x6F: reg_write(rd, pc + 4, pc); npc = pc + imm_j(ins); break;           // jal
    case 0x67: { uint32_t t = a + imm_i(ins); reg_write(rd, pc + 4, pc); npc = t; break; }   // jalr (bit 0 kept, like the RTL)
    case 0x63: {
        int take;
        switch (f3) {
        case 0: take = a == b; break;            case 1: take = a != b; break;
        case 4: take = (int32_t)a < (int32_t)b; break; case 5: take = (int32_t)a >= (int32_t)b; break;
        case 6: take = a < b; break;             case 7: take = a >= b; break;
        default: illegal(ins); take = 0;
        }
        if (take) npc = pc + imm_b(ins);
        break;
    }
    case 0x03: { uint32_t v = load(a + imm_i(ins), f3); reg_write(rd, v, pc); break; }
    case 0x23: store(a + imm_s(ins), b, f3); break;
    case 0x13: {
        int32_t im = imm_i(ins); uint32_t v; unsigned sh = rs2;
        switch (f3) {
        case 0: v = a + im; break;
        case 1: v = a << sh; break;
        case 2: v = (int32_t)a < im; break;
        case 3: v = a < (uint32_t)im; break;
        case 4: v = a ^ im; break;
        case 5: v = (f7 & 0x20) ? (uint32_t)((int32_t)a >> sh) : a >> sh; break;
        case 6: v = a | im; break;
        default: v = a & im; break;
        }
        reg_write(rd, v, pc);
        break;
    }
    case 0x33: {
        uint32_t v;
        if (f7 == 1) {
            switch (f3) {
            case 0: v = a * b; break;
            case 1: v = (uint32_t)(((int64_t)(int32_t)a * (int64_t)(int32_t)b) >> 32); break;
            case 2: v = (uint32_t)(((int64_t)(int32_t)a * (int64_t)(uint64_t)b) >> 32); break;
            case 3: v = (uint32_t)(((uint64_t)a * (uint64_t)b) >> 32); break;
            case 4: v = b == 0 ? 0xFFFFFFFFu : (a == 0x80000000u && b == 0xFFFFFFFFu) ? a : (uint32_t)((int32_t)a / (int32_t)b); break;
            case 5: v = b == 0 ? 0xFFFFFFFFu : a / b; break;
            case 6: v = b == 0 ? a : (a == 0x80000000u && b == 0xFFFFFFFFu) ? 0 : (uint32_t)((int32_t)a % (int32_t)b); break;
            default: v = b == 0 ? a : a % b; break;
            }
        } else {
            switch (f3) {
            case 0: v = (f7 & 0x20) ? a - b : a + b; break;
            case 1: v = a << (b & 31); break;
            case 2: v = (int32_t)a < (int32_t)b; break;
            case 3: v = a < b; break;
            case 4: v = a ^ b; break;
            case 5: v = (f7 & 0x20) ? (uint32_t)((int32_t)a >> (b & 31)) : a >> (b & 31); break;
            case 6: v = a | b; break;
            default: v = a & b; break;
            }
        }
        reg_write(rd, v, pc);
        break;
    }
    case 0x0F: break;                                     // fence: no-op
    default: illegal(ins);
    }
    pc = npc;
    instret++;
}

int main(int argc, char **argv)
{
    const char *elf = NULL, *romf = NULL, *wad = NULL;
    uint64_t maxi = 0;
    for (int i = 1; i < argc; i++) {
        const char *s = argv[i];
        #define ARG (i + 1 < argc ? argv[++i] : (fprintf(stderr, "missing value for %s\n", s), exit(1), ""))
        if      (!strcmp(s, "-rom"))    romf = ARG;
        else if (!strcmp(s, "-wad"))    wad = ARG;
        else if (!strcmp(s, "-uartin")) { const char *fn = ARG; uartin = fopen(fn, "rb"); if (!uartin) { perror(fn); return 1; } }
        else if (!strcmp(s, "-input"))  load_input(ARG);
        else if (!strcmp(s, "-frames")) frame_dir = ARG;
        else if (!strcmp(s, "-every"))  frame_every = (unsigned)atoi(ARG);
        else if (!strcmp(s, "-max"))    { char *e; maxi = strtoull(ARG, &e, 10); if (*e == 'M') maxi *= 1000000ull; }
        else if (!strcmp(s, "-cpi"))    cpi = atof(ARG);
        else if (!strcmp(s, "-clk"))    clk_hz = atof(ARG);
        else if (!strcmp(s, "-trace"))  { const char *fn = ARG; trc = fopen(fn, "w"); }
        else if (!strcmp(s, "-check"))  { const char *fn = ARG; chk = fopen(fn, "r"); if (!chk) { perror(fn); return 1; } }
        else if (!strcmp(s, "-strict")) strict = 1;
        else if (!strcmp(s, "-q"))      quiet = 1;
        else if (s[0] != '-')           elf = s;
        else { fprintf(stderr, "unknown option %s\n", s); return 1; }
    }
    ram = calloc(1, RAM_SIZE);
    memset(rom, 0, sizeof rom);
    pc = ROM_BASE;
    if (elf) pc = load_elf(elf);
    if (romf) {
        size_t n = strlen(romf);
        if (n > 4 && !strcmp(romf + n - 4, ".hex")) load_hex_rom(romf); else load_elf(romf);
        pc = ROM_BASE;
    }
    if (wad) load_wad(wad);

    clock_t t0 = clock();
    while (!sim_done) {
        if ((instret & 0x3FF) == 0) poll_input();
        step();
        if (maxi && instret >= maxi) break;
    }
    double secs = (double)(clock() - t0) / CLOCKS_PER_SEC;
    fprintf(stderr, "\n[iss] %s: instret %llu, frames %lu, %.1f s host (%.1f MIPS), sim time %.1f ms, LED %02x 7SEG %08x\n",
            sim_done ? (sim_code ? "EXIT FAIL" : "EXIT PASS") : "STOP",
            (unsigned long long)instret, frame_no, secs, secs > 0 ? instret / secs / 1e6 : 0.0, ms_now(), led, sevenseg);
    if (trc) fclose(trc);
    return sim_done ? (sim_code ? 1 : 0) : 0;
}
