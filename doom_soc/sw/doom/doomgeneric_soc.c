// doomgeneric platform layer for doom_soc (CG3207 RV32IM + DDR2 + 96x64 PmodOLEDrgb).
//
// Video:  DOOM renders its normal 320x200 8-bit frame (I_VideoBuffer). DG_DrawFrame maps it
//         through the palette to RGB565 and nearest-neighbour downscales it to 96x64, written
//         straight to the OLED (16-bit colour, row-major auto-advance).
// Time:   CYCLECOUNT (wraps every ~114 s at 37.5 MHz; tracked here as a running ms count).
// Input:  push buttons + DIP switches (see the table below), and optional key events over the
//         UART from host/doom_keys.py: 0xE0 <key> = press, 0xE1 <key> = release.
// HUD:    the 7-segment display shows health (left 3 digits) and ammo (right 3 digits).
#include <stdio.h>
#include <string.h>
#include "doomgeneric.h"
#include "doomkeys.h"
#include "doomtype.h"
#include "i_video.h"
#include "doomstat.h"
#include "d_player.h"
#include "d_items.h"
#include "doom_soc.h"

extern byte *I_VideoBuffer;
extern struct color colors[256];
extern boolean palette_changed;
extern int detailLevel;
extern int screenblocks;

#define SRC_W 320
#define SRC_H 200
#define OLED_W 96
#define OLED_H 64

static uint16_t pal565[256];
static uint16_t xmap[OLED_W];
static uint32_t yoff[OLED_H];
static int      pal_valid;

// ---------------------------------------------------------------- time
static uint32_t ms_count, cyc_rem, cyc_last;
#define CYC_PER_MS (CPU_HZ / 1000u)

uint32_t DG_GetTicksMs(void)
{
    uint32_t now = cycles();
    cyc_rem += now - cyc_last;
    cyc_last = now;
    if (cyc_rem >= CYC_PER_MS) {
        uint32_t n = cyc_rem / CYC_PER_MS;
        ms_count += n;
        cyc_rem -= n * CYC_PER_MS;
    }
    return ms_count;
}

void DG_SleepMs(uint32_t ms)
{
    uint32_t t0 = DG_GetTicksMs();
    while (DG_GetTicksMs() - t0 < ms)
        ;
}

// ---------------------------------------------------------------- video
void DG_Init(void)
{
    for (int x = 0; x < OLED_W; x++)
        xmap[x] = (uint16_t)(((2 * x + 1) * SRC_W) / (2 * OLED_W));     // pixel centres
    for (int y = 0; y < OLED_H; y++)
        yoff[y] = (uint32_t)(((2 * y + 1) * SRC_H) / (2 * OLED_H)) * SRC_W;

    // Defaults for a 96x64 screen: low detail (160-wide columns, still > 96) and the
    // full-screen view without the status bar (health/ammo go to the 7-segment display).
    // There is no config file, so M_LoadDefaults keeps these.
    detailLevel  = 1;
    screenblocks = 11;

    cyc_last = cycles();
    MMIO(LED) = 0x01;
    printf("DG_Init: OLED %dx%d, CPU %u Hz\n", OLED_W, OLED_H, (unsigned)CPU_HZ);
}

static uint32_t bcd3(int v)
{
    if (v < 0) v = 0;
    if (v > 999) v = 999;
    return (uint32_t)(((v / 100) << 8) | (((v / 10) % 10) << 4) | (v % 10));
}

static void update_hud(void)
{
    if (gamestate != GS_LEVEL) { MMIO(SEVENSEG) = 0; return; }
    player_t *p = &players[consoleplayer];
    int ammo = 0;
    ammotype_t at = weaponinfo[p->readyweapon].ammo;
    if (at != am_noammo) ammo = p->ammo[at];
    MMIO(SEVENSEG) = (bcd3(p->health) << 16) | bcd3(ammo);
}

void DG_DrawFrame(void)
{
    if (palette_changed || !pal_valid) {
        for (int i = 0; i < 256; i++)
            pal565[i] = (uint16_t)(((colors[i].r >> 3) << 11) | ((colors[i].g >> 2) << 5) | (colors[i].b >> 3));
        palette_changed = false;
        pal_valid = 1;
    }

    // Re-arm the auto-advance at (0,0) every frame: COL/ROW first, then CTRL
    // (16-bit colour [7:4]=1, row-major auto-advance [3:0]=4).
    MMIO(OLED_COL)  = 0;
    MMIO(OLED_ROW)  = 0;
    MMIO(OLED_CTRL) = 0x14;

    volatile uint32_t *oled = &MMIO(OLED_DATA);
    for (int y = 0; y < OLED_H; y++) {
        const byte *src = I_VideoBuffer + yoff[y];
        for (int x = 0; x < OLED_W; x += 4) {
            *oled = pal565[src[xmap[x]]];
            *oled = pal565[src[xmap[x + 1]]];
            *oled = pal565[src[xmap[x + 2]]];
            *oled = pal565[src[xmap[x + 3]]];
        }
    }
    update_hud();
}

void DG_SetWindowTitle(const char *title) { (void)title; }

// ---------------------------------------------------------------- input
// Buttons (held):  BTNU = forward (up arrow), BTND = back (down arrow),
//                  BTNL / BTNR = turn left / right (strafe when SW1 is on),
//                  BTNC = fire + enter (use + enter when SW0 is on).
// Switches (held): SW0 = BTNC uses instead of fires, SW1 = strafe mode, SW2 = run.
// Switches (tap, any flip sends press+release): SW15 = Esc (menu), SW14 = 'y',
//                  SW13 = Tab (automap), SW3..SW9 = weapons 1..7.
#define NKEYS 16
static unsigned char held[NKEYS];          // keys currently reported as down
static int           n_held;

#define QLEN 64
static struct { unsigned char pressed, key; } q[QLEN];
static unsigned qh, qt;
static uint32_t last_dip;
static int      rx_state;                  // 0 idle, 1 got 0xE0, 2 got 0xE1

static void push(int pressed, unsigned char key)
{
    if (qt - qh < QLEN) { q[qt % QLEN].pressed = (unsigned char)pressed; q[qt % QLEN].key = key; qt++; }
}

static int is_held(unsigned char k) { for (int i = 0; i < n_held; i++) if (held[i] == k) return 1; return 0; }

static void poll_inputs(void)
{
    uint32_t pb = MMIO(PB), dip = MMIO(DIP);
    unsigned char want[NKEYS]; int n = 0;
    int strafe = dip & 2, usemode = dip & 1;

    if (pb & PB_BTNU) want[n++] = KEY_UPARROW;
    if (pb & PB_BTND) want[n++] = KEY_DOWNARROW;
    if (pb & PB_BTNL) want[n++] = strafe ? KEY_STRAFE_L : KEY_LEFTARROW;
    if (pb & PB_BTNR) want[n++] = strafe ? KEY_STRAFE_R : KEY_RIGHTARROW;
    if (pb & PB_BTNC) { want[n++] = usemode ? KEY_USE : KEY_FIRE; want[n++] = KEY_ENTER; }
    if (dip & 4)      want[n++] = KEY_RSHIFT;

    for (int i = 0; i < n_held; i++) {                   // releases
        int still = 0;
        for (int j = 0; j < n; j++) if (want[j] == held[i]) still = 1;
        if (!still) push(0, held[i]);
    }
    for (int j = 0; j < n; j++)                          // presses
        if (!is_held(want[j])) push(1, want[j]);
    memcpy(held, want, (size_t)n);
    n_held = n;

    uint32_t flip = (dip ^ last_dip) & 0xE3F8u;           // tap switches: 15, 14, 13, 9..3
    last_dip = dip;
    static const unsigned char tapkey[16] = { 0, 0, 0, '1', '2', '3', '4', '5', '6', '7', 0, 0, 0, KEY_TAB, 'y', KEY_ESCAPE };
    for (int b = 3; b < 16; b++)
        if ((flip >> b) & 1) { push(1, tapkey[b]); push(0, tapkey[b]); }

    while (MMIO(UART_RX_VALID) & 1) {                    // host key events
        unsigned char c = (unsigned char)MMIO(UART_RX);
        if (rx_state == 0) rx_state = c == 0xE0 ? 1 : c == 0xE1 ? 2 : 0;
        else { push(rx_state == 1, c); rx_state = 0; }
    }
}

int DG_GetKey(int *pressed, unsigned char *key)
{
    if (qh == qt) poll_inputs();
    if (qh == qt) return 0;
    *pressed = q[qh % QLEN].pressed;
    *key = q[qh % QLEN].key;
    qh++;
    return 1;
}

// ---------------------------------------------------------------- main
int main(void)
{
    static char *argv[] = { "doom", "-iwad", "doom1.wad", NULL };
    printf("\nDOOM on the CG3207 RV32IM SoC\n");
    last_dip = MMIO(DIP);
    doomgeneric_Create(3, argv);
    for (;;)
        doomgeneric_Tick();
    return 0;
}
