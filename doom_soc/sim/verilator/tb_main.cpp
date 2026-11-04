// Verilator harness for doom_soc (sim/tb_soc.v).
//
//   tb_soc.exe [options] [prog.elf]
//     prog.elf         loaded into DDR2 (PT_LOAD segments at their physical addresses)
//     -wad FILE        WAD into DDR2 like the boot loader (header 0x86FFFFF0, data 0x87000000)
//     -uartin FILE     bytes sent to the board UART at 1.5 Mbaud (DIV cycles per bit)
//     -uartgap N       idle CPU cycles between UART bytes (default 0)
//     -frames DIR      dump OLED frames (96x64 PPM), -every N
//     -max N[M]        stop after N CPU cycles
//     -trace FILE      commit trace "<rd> <value>" (for: rv32sim -check FILE)
//     -input FILE      timed button/switch script "<ms> pb|dip <hex>" (ms of simulated time)
//     -q               don't echo UART output
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <ctime>
#include <string>
#include <vector>
#include <deque>
#include "Vtb_soc.h"
#include "verilated.h"
#include "svdpi.h"

static const uint32_t DDR_BASE = 0x80000000u, DDR_SIZE = 128u << 20;
static const uint32_t WAD_HDR = 0x86FFFFF0u, WAD_DATA = 0x87000000u;
static const int      UART_DIV = 25;
static const double   CPU_HZ = 37.5e6;
static uint8_t *ddr;
static uint64_t sim_time;
double sc_time_stamp() { return (double)sim_time; }

extern "C" void ddr_read(int line, svBitVecVal *data)
{
    memcpy(data, ddr + ((uint32_t)line << 4), 16);
}

extern "C" void ddr_write(int line, const svBitVecVal *data, const svBitVecVal *mask)
{
    uint8_t *p = ddr + ((uint32_t)line << 4);
    const uint8_t *d = (const uint8_t *)data;
    for (int b = 0; b < 16; b++)
        if (!((mask[0] >> b) & 1)) p[b] = d[b];
}

static uint8_t *ddr_ptr(uint32_t a, uint32_t n)
{
    if (a - DDR_BASE >= DDR_SIZE || a - DDR_BASE + n > DDR_SIZE) { fprintf(stderr, "address %08x outside DDR2\n", a); exit(1); }
    return ddr + (a - DDR_BASE);
}

static void load_elf(const char *fn)
{
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    uint8_t eh[52];
    if (fread(eh, 1, 52, f) != 52 || memcmp(eh, "\177ELF", 4)) { fprintf(stderr, "%s: not ELF\n", fn); exit(1); }
    uint32_t phoff; uint16_t phentsize, phnum;
    memcpy(&phoff, eh + 28, 4); memcpy(&phentsize, eh + 42, 2); memcpy(&phnum, eh + 44, 2);
    for (int i = 0; i < phnum; i++) {
        uint32_t ph[8];
        fseek(f, phoff + i * phentsize, SEEK_SET);
        if (fread(ph, 4, 8, f) != 8) break;
        if (ph[0] != 1 || ph[5] == 0) continue;
        uint8_t *p = ddr_ptr(ph[3], ph[5]);
        memset(p, 0, ph[5]);
        fseek(f, ph[1], SEEK_SET);
        if (ph[4] && fread(p, 1, ph[4], f) != ph[4]) { fprintf(stderr, "%s: short read\n", fn); exit(1); }
    }
    fclose(f);
}

static void load_wad(const char *fn)
{
    FILE *f = fopen(fn, "rb");
    if (!f) { perror(fn); exit(1); }
    fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
    if (fread(ddr_ptr(WAD_DATA, n), 1, n, f) != (size_t)n) { fprintf(stderr, "%s: short read\n", fn); exit(1); }
    fclose(f);
    uint32_t hdr[4] = { 0x31444157u, (uint32_t)n, WAD_DATA, 0 };
    memcpy(ddr_ptr(WAD_HDR, 16), hdr, 16);
}

struct Ev { double ms; int kind; uint32_t v; };

int main(int argc, char **argv)
{
    Verilated::commandArgs(argc, argv);
    const char *elf = nullptr, *wad = nullptr, *frame_dir = nullptr, *trace_fn = nullptr;
    std::deque<uint8_t> uart_in;
    std::vector<Ev> evs;
    uint64_t max_cycles = 0;
    int every = 1, quiet = 0, uart_gap = 0;
    for (int i = 1; i < argc; i++) {
        std::string s = argv[i];
        auto next = [&]() -> const char * { if (i + 1 >= argc) { fprintf(stderr, "missing value for %s\n", s.c_str()); exit(1); } return argv[++i]; };
        if (s == "-wad") wad = next();
        else if (s == "-uartin") {
            const char *fn = next(); FILE *f = fopen(fn, "rb"); if (!f) { perror(fn); return 1; }
            int c; while ((c = fgetc(f)) != EOF) uart_in.push_back((uint8_t)c); fclose(f);
        }
        else if (s == "-uartgap") uart_gap = atoi(next());
        else if (s == "-frames") frame_dir = next();
        else if (s == "-every") every = atoi(next());
        else if (s == "-max") { char *e; max_cycles = strtoull(next(), &e, 10); if (*e == 'M') max_cycles *= 1000000ull; }
        else if (s == "-trace") trace_fn = next();
        else if (s == "-input") {
            const char *fn = next(); FILE *f = fopen(fn, "r"); if (!f) { perror(fn); return 1; }
            char line[256];
            while (fgets(line, sizeof line, f)) {
                double ms; char kind[16]; unsigned v;
                if (line[0] == '#' || sscanf(line, "%lf %15s %x", &ms, kind, &v) != 3) continue;
                evs.push_back({ms, strcmp(kind, "pb") == 0 ? 0 : 1, v});
            }
            fclose(f);
        }
        else if (s == "-q") quiet = 1;
        else if (s[0] == '+') ;                       // plusargs for Verilog
        else if (s[0] != '-') elf = argv[i];
        else { fprintf(stderr, "unknown option %s\n", s.c_str()); return 1; }
    }

    ddr = (uint8_t *)calloc(1, DDR_SIZE);
    if (elf) load_elf(elf);
    if (wad) load_wad(wad);
    FILE *trace = trace_fn ? fopen(trace_fn, "w") : nullptr;

    Vtb_soc *top = new Vtb_soc;
    top->clk_cpu = 0; top->clk_ui = 0; top->rst_in = 1; top->dip = 0; top->pb = 0; top->uart_rxd = 1;
    top->eval();

    // UART RX driver (host -> board) and TX decoder (board -> host), in CPU cycles
    int rx_bit = -1, rx_cnt = 0, rx_gap = 0; uint16_t rx_sh = 0;
    int tx_state = -1, tx_cnt = 0, tx_bits = 0; uint8_t tx_sh = 0;
    uint64_t uart_bytes_in = 0;

    // OLED frame buffer
    static uint16_t fb[64][96];
    uint64_t oled_writes = 0, frames = 0;

    uint64_t cyc = 0, commits = 0, stall_cycles = 0;
    size_t ev_pos = 0;
    clock_t t0 = clock();
    bool done = false;

    while (!done && !Verilated::gotFinish()) {
        // ---- inputs for the coming CPU cycle ----
        if (cyc == 8) top->rst_in = 0;
        double ms = cyc / CPU_HZ * 1000.0;
        while (ev_pos < evs.size() && evs[ev_pos].ms <= ms) {
            if (evs[ev_pos].kind == 0) top->pb = evs[ev_pos].v; else top->dip = evs[ev_pos].v;
            ev_pos++;
        }
        if (top->calib && !top->rst_in) {             // UART bit-banging
            if (rx_bit < 0 && !uart_in.empty() && rx_gap == 0) {
                rx_sh = (uint16_t)((1u << 9) | (uart_in.front() << 1));   // start(0), 8 data, stop(1)
                uart_in.pop_front(); uart_bytes_in++;
                rx_bit = 0; rx_cnt = 0;
            }
            if (rx_bit >= 0) {
                top->uart_rxd = (rx_sh >> rx_bit) & 1;
                if (++rx_cnt == UART_DIV) { rx_cnt = 0; if (++rx_bit == 10) { rx_bit = -1; rx_gap = uart_gap; } }
            }
            else { top->uart_rxd = 1; if (rx_gap) rx_gap--; }
        }

        // ---- sample CPU-domain outputs of the cycle that is ending ----
        if (top->tr_valid) {
            commits++;
            if (trace) fprintf(trace, "%u %08x\n", top->tr_rd, top->tr_val);
        }
        if (top->mem_stall) stall_cycles++;
        if (top->oled_write) {
            uint32_t d = top->oled_data;
            if (top->oled_col < 96)
                fb[top->oled_row][top->oled_col] = (uint16_t)((((d >> 19) & 31) << 11) | (((d >> 10) & 63) << 5) | ((d >> 3) & 31));
            if (++oled_writes % 6144 == 0) {
                if (frame_dir && frames % every == 0) {
                    char name[512]; snprintf(name, sizeof name, "%s/frame_%05llu.ppm", frame_dir, (unsigned long long)frames);
                    FILE *f = fopen(name, "wb");
                    if (f) {
                        fprintf(f, "P6\n96 64\n255\n");
                        for (int r = 0; r < 64; r++) for (int c = 0; c < 96; c++) {
                            uint16_t p = fb[r][c];
                            uint8_t rgb[3] = { (uint8_t)((p >> 11) << 3), (uint8_t)(((p >> 5) & 63) << 2), (uint8_t)((p & 31) << 3) };
                            fwrite(rgb, 1, 3, f);
                        }
                        fclose(f);
                    }
                }
                frames++;
                if (frames % 10 == 0)
                    fprintf(stderr, "[tb] frame %llu at cycle %llu (%.0f ms)\n", (unsigned long long)frames, (unsigned long long)cyc, ms);
            }
        }
        // UART TX decode
        {
            int txd = top->uart_txd;
            if (tx_state < 0) { if (!txd) { tx_state = 0; tx_cnt = UART_DIV / 2; tx_bits = 0; tx_sh = 0; } }
            else if (--tx_cnt <= 0) {
                tx_cnt = UART_DIV;
                if (tx_state == 0) tx_state = 1;                       // middle of the start bit
                else if (tx_bits < 8) { tx_sh |= (uint8_t)(txd << tx_bits); tx_bits++; }
                else { if (!quiet) { fputc(tx_sh, stdout); fflush(stdout); } tx_state = -1; }
            }
        }
        if (top->sim_done) { done = true; break; }

        // ---- one CPU cycle = two ui_clk cycles; both clocks rise together ----
        top->clk_cpu = 1; top->clk_ui = 1; top->eval();
        top->clk_ui = 0; top->eval();
        top->clk_cpu = 0; top->clk_ui = 1; top->eval();
        top->clk_ui = 0; top->eval();
        cyc++;
        if (max_cycles && cyc >= max_cycles) break;
    }

    double secs = (double)(clock() - t0) / CLOCKS_PER_SEC;
    fprintf(stderr, "\n[tb] %s: %llu cycles (%.1f ms simulated), %llu reg-write commits, MemStall %.1f%%, "
                    "frames %llu, UART in %llu B, %.1f s host (%.2f MHz), LED %02x 7SEG %08x\n",
            done ? ((top->sim_code >> 1) == 0 ? "EXIT PASS" : "EXIT FAIL") : "STOP",
            (unsigned long long)cyc, cyc / CPU_HZ * 1000.0, (unsigned long long)commits,
            cyc ? 100.0 * stall_cycles / cyc : 0.0, (unsigned long long)frames, (unsigned long long)uart_bytes_in,
            secs, secs > 0 ? cyc / secs / 1e6 : 0.0, top->led, top->sevenseg);
    if (trace) fclose(trace);
    top->final();
    int rc = done ? (int)(top->sim_code >> 1) : 0;
    delete top;
    return rc;
}
