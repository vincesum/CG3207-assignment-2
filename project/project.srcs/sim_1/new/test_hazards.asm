.eqv MMIO_BASE      0xFFFF0000
.eqv LED_OFF        0x60
.eqv DIP_OFF        0x64
.eqv SEVENSEG_OFF   0x80

# Pipeline hazard test program.
#
# Each test is written with no NOP padding, so it only passes if the hazard unit handles it.
# Results are saved to results[], then compared against expected[] without branches, so a
# missing branch flush cannot fake a pass. Test 0 ends up in bit 7 of the pass mask.
#   LEDs      : pass mask. Expected 0xFF (all 8 tests pass).
#   7-segment : results[DIP[2:0]], so each result can be inspected on the board.
#
#   idx | hazard                                         | expected
#   ----+------------------------------------------------+-----------
#    0  | RAW, forward from M and W into E               | 0x0000000B
#    1  | RAW, RegFile written and read in the same cycle| 0x0000000A
#    2  | RAW, M has priority over W                     | 0x00000004
#    3  | store data forwarding, then load-use           | 0x00000056
#    4  | mem-mem copy (lw then sw of the loaded reg)    | 0x1234ABCD
#    5  | load-use on the sw address (must stall)        | 0x00000077
#    6  | control: branch/jal/jalr flushes, not-taken    | 0x00000007
#    7  | MCycle with forwarded operands and result      | 0x00000054

.data
    expected:   .word 0x0000000B, 0x0000000A, 0x00000004, 0x00000056
                .word 0x1234ABCD, 0x00000077, 0x00000007, 0x00000054
    results:    .space 32       # 8 words, one per test
    # Test data, accessed as offsets from s1
    scratch:    .word 0         # 0(s1)
    src:        .word 0x1234ABCD # 4(s1)
    dst:        .word 0         # 8(s1)
    ptr:        .word dst2      # 12(s1)
    dst2:       .word 0         # 16(s1)
    jaddr:      .word t6_r1     # 20(s1)

.text
.globl main
main:
    lui  s5, %hi(results)
    addi s5, s5, %lo(results) # s5 = results base
    lui  s1, %hi(scratch)
    addi s1, s1, %lo(scratch) # s1 = test data base

    # --------------------------------------------------------
    # 0. RAW: forward from M and W into E
    # --------------------------------------------------------
    addi t0, x0, 5
    addi t1, t0, 1            # t0 from M: 6
    add  t2, t0, t1           # t0 from W, t1 from M: 11
    sw   t2, 0(s5)

    # --------------------------------------------------------
    # 1. RAW: RegFile written and read in the same cycle
    # --------------------------------------------------------
    addi t0, x0, 9
    nop
    nop
    addi t1, t0, 1            # t0 is in W while this is in D: 10
    sw   t1, 4(s5)

    # --------------------------------------------------------
    # 2. RAW: M has priority over W
    # --------------------------------------------------------
    addi t0, x0, 1
    addi t0, x0, 2
    add  t1, t0, t0           # must use the newer t0 (M): 4, not 2
    sw   t1, 8(s5)

    # --------------------------------------------------------
    # 3. Store data forwarding, then load-use
    # --------------------------------------------------------
    addi t0, x0, 0x55
    sw   t0, 0(s1)            # store data from M
    lw   t1, 0(s1)
    addi t2, t1, 1            # load-use: stall, then from W: 0x56
    sw   t2, 12(s5)

    # --------------------------------------------------------
    # 4. Mem-mem copy
    # --------------------------------------------------------
    lw   t0, 4(s1)            # t0 = src
    sw   t0, 8(s1)            # dst = t0, forwarded from W into M (no stall)
    lw   t1, 8(s1)
    sw   t1, 16(s5)

    # --------------------------------------------------------
    # 5. Load-use on the sw address
    # --------------------------------------------------------
    addi t0, x0, 0x77
    lw   t1, 12(s1)           # t1 = &dst2
    sw   t0, 0(t1)            # address needs the load result: must stall
    lw   t2, 16(s1)
    sw   t2, 20(s5)

    # --------------------------------------------------------
    # 6. Control: wrong-path instructions add 0x100, correct path adds 1
    # --------------------------------------------------------
    addi t5, x0, 0
    addi t0, x0, 1
    beq  t0, t0, t6_b         # taken, compare forwarded from M
    addi t5, t5, 0x100
    addi t5, t5, 0x100
t6_b:
    addi t5, t5, 1
    bne  t0, t0, t6_nt        # not taken: the next two must still execute
    addi t5, t5, 1
    addi t5, t5, 1
t6_nt:
    jal  ra, t6_j             # jal
    addi t5, t5, 0x100
    addi t5, t5, 0x100
t6_j:
    addi t5, t5, 1
    lw   t1, 20(s1)           # t1 = &t6_r1
    jalr x0, 0(t1)            # load-use into the jalr base
    addi t5, t5, 0x100
    addi t5, t5, 0x100
t6_r1:
    addi t5, t5, 1
    lui  t1, %hi(t6_r2)
    addi t1, t1, %lo(t6_r2)
    jalr x0, 0(t1)            # jalr base forwarded from M
    addi t5, t5, 0x100
    addi t5, t5, 0x100
t6_r2:
    addi t5, t5, 1
    addi t3, x0, 0x55
    lw   t2, 0(s1)            # t2 = 0x55
    beq  t2, t3, t6_l         # load-use into the branch compare: taken
    addi t5, t5, 0x100
    addi t5, t5, 0x100
t6_l:
    addi t5, t5, 1            # 1 + 2 + 1 + 1 + 1 + 1 = 7
    sw   t5, 24(s5)

    # --------------------------------------------------------
    # 7. MCycle with forwarded operands and result
    # --------------------------------------------------------
    addi a0, x0, 6
    addi a1, x0, 7
    mul  a2, a0, a1           # a1 from M, a0 from W: 42
    add  a3, a2, a2           # mul result from M: 84
    sw   a3, 28(s5)

    # --------------------------------------------------------
    # COMPARE results[] with expected[], branch free
    # --------------------------------------------------------
    lui  t0, %hi(expected)
    addi t0, t0, %lo(expected)
    addi t4, s5, 0            # t4 = pointer into results
    addi t3, x0, 8            # t3 = tests remaining
    addi s6, x0, 0            # s6 = pass mask

cmp_loop:
    lw   t1, 0(t4)
    lw   t2, 0(t0)
    xor  t1, t1, t2
    sltiu t1, t1, 1           # t1 = 1 if equal
    slli s6, s6, 1
    or   s6, s6, t1
    addi t0, t0, 4
    addi t4, t4, 4
    addi t3, t3, -1
    bne  t3, x0, cmp_loop

    # --------------------------------------------------------
    # DISPLAY
    # --------------------------------------------------------
    li   s0, MMIO_BASE
    sw   s6, LED_OFF(s0)      # LEDs = pass mask (expect 0xFF)

display_loop:
    lw   t1, DIP_OFF(s0)      # read DIP switches
    andi t1, t1, 7            # index = DIP[2:0]
    slli t1, t1, 2            # word offset
    add  t1, s5, t1
    lw   t2, 0(t1)            # t2 = results[index]
    sw   t2, SEVENSEG_OFF(s0) # show it on the 7-segment display
    jal  zero, display_loop
