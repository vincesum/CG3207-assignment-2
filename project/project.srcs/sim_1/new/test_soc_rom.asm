# Program for test_soc.v. It runs from the 4 KB ROM and tests the whole SoC. It reports each result
# by writing it to the 7-segment display, then writing a new count to the LEDs. The testbench reads
# the result when the LEDs change, and compares it with its table. 0xFF on the LEDs means finished.
.eqv MMIO_BASE 0xFFFF0000
.eqv RX_VALID  0x00
.eqv RX        0x04
.eqv TX_READY  0x08
.eqv TX        0x0C
.eqv OLED_COL  0x20
.eqv OLED_ROW  0x24
.eqv OLED_DATA 0x28
.eqv OLED_CTRL 0x2C
.eqv LED       0x60
.eqv DIP       0x64
.eqv PB        0x68
.eqv SEG       0x80
.eqv CYCLES    0xA0
.eqv IMISS     0xB0
.eqv DMISS     0xB4
.eqv STALLS    0xB8
.macro report(%r)
    sw   %r, SEG(s0)
    addi s7, s7, 1
    sw   s7, LED(s0)
.end_macro
.macro uart_send(%c)
poll:
    lw   t0, TX_READY(s0)
    beq  t0, x0, poll
    addi t0, x0, %c
    sw   t0, TX(s0)
.end_macro
.text
    li   s0, MMIO_BASE
    li   s1, 0x80000000
    addi s7, x0, 0

    # ---- Peripherals ----
    lw   t0, DIP(s0)             # 1: switches
    report(t0)
    lw   t0, PB(s0)              # 2: buttons
    report(t0)
    uart_send(0x48)              # 'H', checked by the testbench
    uart_send(0x49)              # 'I'
rx1:
    lw   t0, RX_VALID(s0)
    beq  t0, x0, rx1
    lw   t1, RX(s0)              # 3: first byte sent by the testbench
    report(t1)
rx2:
    lw   t0, RX_VALID(s0)
    beq  t0, x0, rx2
    lw   t1, RX(s0)              # 4: second byte
    report(t1)
    lw   t0, RX_VALID(s0)        # 5: reading must have removed both
    report(t0)
    addi t0, x0, 0x14            # 16-bit colour, auto-advance along the row
    sw   t0, OLED_CTRL(s0)
    addi t0, x0, 5
    sw   t0, OLED_COL(s0)
    addi t0, x0, 6
    sw   t0, OLED_ROW(s0)
    li   t0, 0xF800
    sw   t0, OLED_DATA(s0)       # pixels checked by the testbench
    li   t0, 0x07E0
    sw   t0, OLED_DATA(s0)
    addi t0, x0, 0x1F
    sw   t0, OLED_DATA(s0)

    # ---- Data cache: a miss fills the line, and later reads hit ----
    li   a0, 0x11111111
    sw   a0, 0x100(s1)
    li   a0, 0x22222222
    sw   a0, 0x104(s1)
    lw   s2, DMISS(s0)
    lw   s3, STALLS(s0)
    lw   a1, 0x100(s1)           # miss
    lw   a2, 0x100(s1)           # hit
    lw   a3, 0x104(s1)           # hit, same line
    lw   t0, DMISS(s0)
    sub  t0, t0, s2              # 6: exactly one miss
    report(t0)
    report(a2)                   # 7
    report(a3)                   # 8
    lw   t0, STALLS(s0)
    sltu t0, s3, t0              # 9: the miss stalled the CPU
    report(t0)

    # ---- Direct mapping: addresses 8 KB apart share a line ----
    li   a0, 0xB0B0B0B0
    sw   a0, 0x300(s1)
    li   s4, 0x80002300
    li   a0, 0xC0C0C0C0
    sw   a0, 0(s4)
    lw   s2, DMISS(s0)
    lw   a1, 0x300(s1)           # miss
    lw   a2, 0(s4)               # miss, evicts the first
    lw   a3, 0x300(s1)           # miss, evicts the second
    lw   t0, DMISS(s0)
    sub  t0, t0, s2              # 10: three misses
    report(t0)
    report(a3)                   # 11
    report(a2)                   # 12

    # ---- Stores: a hit updates the cache, a miss doesn't allocate ----
    li   a0, 0x33333333
    sw   a0, 0x100(s1)           # 0x100 is still cached
    lw   s2, DMISS(s0)
    lw   a1, 0x100(s1)
    lw   t0, DMISS(s0)
    sub  t0, t0, s2              # 13: no miss
    report(t0)
    report(a1)                   # 14
    li   a0, 0x66666666
    sw   a0, 0x500(s1)           # not cached
    lw   s2, DMISS(s0)
    lw   a1, 0x500(s1)
    lw   t0, DMISS(s0)
    sub  t0, t0, s2              # 15: one miss, so the store didn't allocate
    report(t0)
    report(a1)                   # 16

    # ---- Byte and halfword accesses on DDR2 ----
    li   a0, 0x44332211
    sw   a0, 0x600(s1)
    addi a0, x0, 0xAA
    sb   a0, 0x601(s1)
    li   a0, 0xBBCC
    sh   a0, 0x602(s1)
    lw   t0, 0x600(s1)           # 17
    report(t0)
    lb   t0, 0x601(s1)           # 18
    report(t0)
    lbu  t0, 0x601(s1)           # 19
    report(t0)
    lh   t0, 0x602(s1)           # 20
    report(t0)
    lhu  t0, 0x602(s1)           # 21
    report(t0)
    addi a0, x0, 0x55
    sb   a0, 0x600(s1)           # a store hit on a cached line
    lw   t0, 0x600(s1)           # 22
    report(t0)

    # ---- A high address ----
    li   s4, 0x803F0000
    li   a0, 0x5A5AA5A5
    sw   a0, 0(s4)
    lw   t0, 0(s4)               # 23
    report(t0)

    # ---- Instruction cache: copy a routine to DDR2 and run it there, twice ----
    addi a0, x0, 100
    sw   a0, 0x700(s1)
    addi a0, x0, 1000
    sw   a0, 0x740(s1)
    la   a0, routine
    la   a2, routine_end
    li   a3, 0x80001000
copy:
    lw   t0, 0(a0)
    sw   t0, 0(a3)
    addi a0, a0, 4
    addi a3, a3, 4
    bne  a0, a2, copy
    li   s4, 0x80001000
    addi a1, s1, 0x700
    lw   s2, IMISS(s0)
    jalr ra, s4, 0
    report(a0)                   # 24: the routine's result
    lw   t0, IMISS(s0)
    sltu t0, s2, t0              # 25: fetching it missed
    report(t0)
    lw   s2, IMISS(s0)
    jalr ra, s4, 0
    report(a0)                   # 26: same result
    lw   t0, IMISS(s0)
    sub  t0, t0, s2              # 27: second run hits
    report(t0)

    # ---- Hazards on a real cache miss ----
    li   s4, 0x80000900
    li   a0, 0x1234
    sw   a0, 0(s4)
    lw   t0, 0(s4)               # miss
    addi t1, t0, 1               # 28: load-use
    report(t1)
    addi a0, x0, 7
    sw   a0, 0x40(s4)
    addi t2, x0, 0
    addi t1, x0, 7
    lw   t0, 0x40(s4)            # miss
    beq  t0, t1, taken           # load-use into a branch
    addi t2, x0, 0x55            # wrong path
    addi t2, x0, 0x55
taken:
    report(t2)                   # 29

    # ---- M extension ----
    addi a0, x0, -2
    addi a1, x0, 3
    mulhsu t0, a0, a1            # 30
    report(t0)
    addi a0, x0, 5
    div  t0, a0, x0              # 31: divide by zero
    report(t0)
    rem  t0, a0, x0              # 32
    report(t0)

    # ---- Cycle counter ----
    lw   a0, CYCLES(s0)
    lw   a1, CYCLES(s0)
    sltu t0, a0, a1              # 33
    report(t0)

    addi t0, x0, 0xFF
    sw   t0, LED(s0)
spin:
    jal  x0, spin

# Copied to 0x8000_1000. It only uses relative addressing, so it can run anywhere.
# a1 points at test data: 0(a1) = 100 and 0x40(a1) = 1000. The result is 574.
routine:
    lw   t0, 0(a1)
    addi t1, t0, 1               # load-use: 101
    sw   t1, 4(a1)               # store data forwarded
    lw   t2, 4(a1)
    sw   t2, 8(a1)               # mem-mem copy
    lw   t3, 8(a1)
    addi t4, x0, 3
    mul  t5, t3, t4              # 303
    addi t4, x0, 7
    lw   t0, 0x40(a1)            # a load miss just before a divide
    div  t6, t0, t4              # 1000 / 7 = 142
    div  s5, t5, t4              # 303 / 7 = 43
    rem  s6, t5, t4              # 2
    addi s8, x0, 0x7E0
    sw   s8, OLED_DATA(s0)       # OLED writes while fetches miss: each must happen once
    sw   s8, OLED_DATA(s0)
    sw   s8, OLED_DATA(s0)
    sw   s8, OLED_DATA(s0)
    sw   s8, OLED_DATA(s0)
    sw   s8, OLED_DATA(s0)
    addi t4, x0, 10
    mul  s5, s5, t4              # 430
    add  a0, s5, s6              # 432
    add  a0, a0, t6              # 574
    jalr x0, ra, 0
routine_end:
