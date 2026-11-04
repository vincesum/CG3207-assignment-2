// doom_soc memory map and MMIO registers (must match rtl/soc/mmio.v and iss/rv32sim.c).
#ifndef DOOM_SOC_H
#define DOOM_SOC_H
#include <stdint.h>

#define CPU_HZ           37500000u      // CPU clock (ui_clk / 2)

#define ROM_BASE         0x00400000u    // boot ROM
#define DDR_BASE         0x80000000u    // DDR2, 128 MB, cached
#define DDR_SIZE         0x08000000u
#define WAD_HDR_ADDR     0x86FFFFF0u    // written by the boot loader: magic, length, data address
#define WAD_DATA_ADDR    0x87000000u    // WAD contents (up to 16 MB)
#define WAD_MAGIC        0x31444157u    // "WAD1"

#define MMIO_BASE        0xFFFF0000u
#define UART_RX_VALID    0x00u   // RO, bit 0: RX FIFO not empty
#define UART_RX          0x04u   // RO, reading pops one byte from the RX FIFO
#define UART_TX_READY    0x08u   // RO, bit 0
#define UART_TX          0x0Cu   // WO, low byte
#define OLED_COL         0x20u   // WO
#define OLED_ROW         0x24u   // WO
#define OLED_DATA        0x28u   // WO
#define OLED_CTRL        0x2Cu   // WO (writing it also re-arms auto-advance: next data write goes to COL/ROW)
#define ACCEL_DATA       0x40u   // RO (not fitted in doom_soc: 0)
#define ACCEL_DREADY     0x44u   // RO
#define LED              0x60u   // WO, 8 bits
#define DIP              0x64u   // RO, 16 bits
#define PB               0x68u   // RO, [4:0] = {BTND, BTNU, BTNL, BTNC, BTNR}
#define SEVENSEG         0x80u   // WO, 32 bits (8 hex digits)
#define CYCLECOUNT       0xA0u   // RO, CPU cycles since reset (wraps)
#define SIM_CTRL         0xFCu   // WO, simulation only: (code << 1) | 1 ends the run

#define PB_BTNR 0x01u
#define PB_BTNC 0x02u
#define PB_BTNL 0x04u
#define PB_BTNU 0x08u
#define PB_BTND 0x10u

#define MMIO(off) (*(volatile uint32_t *)(MMIO_BASE + (off)))

static inline uint32_t cycles(void) { return MMIO(CYCLECOUNT); }

#endif
