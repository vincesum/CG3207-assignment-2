// doom_soc boot ROM: UART loader (runs from the 4 KB ROM at 0x0040_0000, stack in DDR2).
// No writable globals here: the ROM is read-only and nothing is copied to RAM.
//
// Protocol (host -> board, little-endian; host/load.py implements it):
//   'P'                         ping            -> 'K'
//   'L' addr len data[len] s1 s2  load bytes    -> 'K' if the checksum matches, else 'E'
//   'C' addr len                checksum mem    -> s1 s2 (read back through the D-cache)
//   'J' addr                    jump            -> 'K', then jump (never returns)
// Checksum over the bytes b: s1 += b; s2 += s1 (both 32-bit, start at 0).
// LEDs: 0x80 waiting, 0x40 loading, 0x20 checksum error seen. 7-seg: last address loaded.
#include <stdint.h>
#include "doom_soc.h"

static inline uint32_t getb(void)
{
    while (!(MMIO(UART_RX_VALID) & 1))
        ;
    return MMIO(UART_RX) & 0xFF;
}

static uint32_t get32(void)
{
    uint32_t v = getb();
    v |= getb() << 8;
    v |= getb() << 16;
    v |= getb() << 24;
    return v;
}

static void putb(uint32_t c)
{
    while (!(MMIO(UART_TX_READY) & 1))
        ;
    MMIO(UART_TX) = c;
}

static void put32(uint32_t v)
{
    for (int i = 0; i < 4; i++) { putb(v & 0xFF); v >>= 8; }
}

static void puts_(const char *s)
{
    while (*s) putb((uint8_t)*s++);
}

void boot_main(void)
{
    uint32_t leds = 0x80;
    MMIO(LED) = leds;
    MMIO(SEVENSEG) = 0;
    puts_("\r\nCG3207 doom_soc boot ROM v1 - waiting for host/load.py\r\n");

    for (;;) {
        uint32_t c = getb();
        if (c == 'P') {
            putb('K');
        }
        else if (c == 'L') {
            uint32_t a = get32(), n = get32(), s1 = 0, s2 = 0, i = 0;
            MMIO(LED) = leds | 0x40;
            if ((a & 3) == 0) {
                volatile uint32_t *w = (volatile uint32_t *)a;
                for (; i + 4 <= n; i += 4) {
                    uint32_t b0 = getb(); s1 += b0; s2 += s1;
                    uint32_t b1 = getb(); s1 += b1; s2 += s1;
                    uint32_t b2 = getb(); s1 += b2; s2 += s1;
                    uint32_t b3 = getb(); s1 += b3; s2 += s1;
                    *w++ = b0 | (b1 << 8) | (b2 << 16) | (b3 << 24);
                }
            }
            for (; i < n; i++) {
                uint32_t b = getb(); s1 += b; s2 += s1;
                *(volatile uint8_t *)(a + i) = (uint8_t)b;
            }
            uint32_t h1 = get32(), h2 = get32();
            int ok = (h1 == s1) && (h2 == s2);
            if (!ok) leds |= 0x20;
            MMIO(LED) = leds;
            MMIO(SEVENSEG) = a + n;
            putb(ok ? 'K' : 'E');
        }
        else if (c == 'C') {
            uint32_t a = get32(), n = get32(), s1 = 0, s2 = 0;
            for (uint32_t i = 0; i < n; i++) { s1 += *(volatile uint8_t *)(a + i); s2 += s1; }
            put32(s1);
            put32(s2);
        }
        else if (c == 'J') {
            uint32_t a = get32();
            putb('K');
            while (!(MMIO(UART_TX_READY) & 1))
                ;
            MMIO(LED) = 0;
            ((void (*)(void))a)();
        }
    }
}
