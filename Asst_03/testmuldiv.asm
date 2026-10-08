.eqv MMIO_BASE      0xFFFF0000
.eqv LED_OFF        0x60
.eqv DIP_OFF        0x64
.eqv SEVENSEG_OFF   0x80

# Assignment 3 test program for mul and divu (MCycle unit).
#
# Runs 8 tests and keeps one pass bit per test in s6 (test 0 ends up in bit 7).
#   LEDs      : pass mask. Expected 0xFF (all 8 tests pass).
#   7-segment : results[DIP[2:0]], so each result can be inspected on the board.
#
#   idx | test                          | expected
#   ----+-------------------------------+-----------
#    0  | mul  7 * 6                    | 0x0000002A
#    1  | mul  -3 * 5                   | 0xFFFFFFF1 (low word is the same signed or unsigned)
#    2  | mul  100000 * 100000          | 0x540BE400 (true product 0x2_540BE400, upper word discarded)
#    3  | mul  0xFFFFFFFF * 0xFFFFFFFF  | 0x00000001 (-1 * -1, also low word of the unsigned product)
#    4  | divu 100 / 7                  | 0x0000000E (remainder discarded)
#    5  | divu 0xFFFFFFF0 / 16          | 0x0FFFFFFF (signed division would give 0xFFFFFFFF)
#    6  | divu 5 / 9                    | 0x00000000 (dividend < divisor)
#    7  | mul then divu back to back,   | 0x0000007B (123 * 456 = 56088, 56088 / 456 = 123)
#       | divu uses the mul result      |

.data
    # Operand triples (a, b, expected)
    mul_tests:  .word 7, 6, 0x0000002A
                .word -3, 5, 0xFFFFFFF1
                .word 100000, 100000, 0x540BE400
                .word 0xFFFFFFFF, 0xFFFFFFFF, 0x00000001
    div_tests:  .word 100, 7, 0x0000000E
                .word 0xFFFFFFF0, 16, 0x0FFFFFFF
                .word 5, 9, 0x00000000
    results:    .space 32       # 8 words, one per test

.text
.globl main
main:
    lui  s5, %hi(results)
    addi s5, s5, %lo(results) # s5 = pointer into results
    addi s6, x0, 0            # s6 = pass mask

    # --------------------------------------------------------
    # 1. MUL (tests 0-3)
    # --------------------------------------------------------
    lui  t0, %hi(mul_tests)
    addi t0, t0, %lo(mul_tests)
    addi t3, x0, 4            # t3 = tests remaining

mul_loop:
    lw   a0, 0(t0)            # a0 = a
    lw   a1, 4(t0)            # a1 = b
    lw   a2, 8(t0)            # a2 = expected
    mul  a3, a0, a1
    sw   a3, 0(s5)            # save result for the 7-segment display
    slli s6, s6, 1
    bne  a3, a2, mul_next     # uses the mul result in the very next instruction
    ori  s6, s6, 1            # pass
mul_next:
    addi t0, t0, 12
    addi s5, s5, 4
    addi t3, t3, -1
    bne  t3, x0, mul_loop

    # --------------------------------------------------------
    # 2. DIVU (tests 4-6)
    # --------------------------------------------------------
    lui  t0, %hi(div_tests)
    addi t0, t0, %lo(div_tests)
    addi t3, x0, 3            # t3 = tests remaining

div_loop:
    lw   a0, 0(t0)            # a0 = dividend
    lw   a1, 4(t0)            # a1 = divisor
    lw   a2, 8(t0)            # a2 = expected quotient
    divu a3, a0, a1
    sw   a3, 0(s5)
    slli s6, s6, 1
    bne  a3, a2, div_next
    ori  s6, s6, 1            # pass
div_next:
    addi t0, t0, 12
    addi s5, s5, 4
    addi t3, t3, -1
    bne  t3, x0, div_loop

    # --------------------------------------------------------
    # 3. BACK TO BACK (test 7)
    # --------------------------------------------------------
    # Two MCycle instructions in a row, the second depending on the first.
    addi a0, x0, 123
    addi a1, x0, 456
    mul  a2, a0, a1           # a2 = 56088
    divu a3, a2, a1           # a3 = 56088 / 456 = 123
    sw   a3, 0(s5)
    slli s6, s6, 1
    bne  a3, a0, chain_done
    ori  s6, s6, 1            # pass
chain_done:

    # --------------------------------------------------------
    # 4. DISPLAY
    # --------------------------------------------------------
    li   s0, MMIO_BASE
    sw   s6, LED_OFF(s0)      # LEDs = pass mask (expect 0xFF)
    lui  s5, %hi(results)
    addi s5, s5, %lo(results)

display_loop:
    lw   t1, DIP_OFF(s0)      # read DIP switches
    andi t1, t1, 7            # index = DIP[2:0]
    slli t1, t1, 2            # word offset
    add  t1, s5, t1
    lw   t2, 0(t1)            # t2 = results[index]
    sw   t2, SEVENSEG_OFF(s0) # show it on the 7-segment display
    jal  zero, display_loop
