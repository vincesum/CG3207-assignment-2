# Shift test for test_RV_shifter.v. Each result is stored to results[].
.eqv LED 0xFFFF0060
.macro chk(%r)
    sw   %r, 0(s5)
    addi s5, s5, 4
.end_macro
.data
results: .space 160
.text
    la   s5, results
    li   a0, 0xF000000F      # negative value
    li   a1, 0x7000000F      # positive value
    addi a2, x0, 4
    addi a3, x0, 31
    addi a4, x0, 36          # only the low 5 bits count: same as 4
    sll  t0, a0, a2
    chk(t0)
    srl  t0, a0, a2
    chk(t0)
    sra  t0, a0, a2
    chk(t0)
    sra  t0, a1, a2
    chk(t0)
    sll  t0, a0, x0
    chk(t0)
    srl  t0, a0, x0
    chk(t0)
    sra  t0, a0, x0
    chk(t0)
    sll  t0, a0, a3
    chk(t0)
    srl  t0, a0, a3
    chk(t0)
    sra  t0, a0, a3
    chk(t0)
    sra  t0, a1, a3
    chk(t0)
    sll  t0, a0, a4
    chk(t0)
    srl  t0, a0, a4
    chk(t0)
    sra  t0, a0, a4
    chk(t0)
    slli t0, a0, 1
    chk(t0)
    srli t0, a0, 1
    chk(t0)
    srai t0, a0, 1
    chk(t0)
    slli t0, a1, 16
    chk(t0)
    srli t0, a1, 16
    chk(t0)
    srai t0, a1, 16
    chk(t0)
    srai t0, a0, 16
    chk(t0)
    slli t0, a0, 31
    chk(t0)
    srli t0, a0, 31
    chk(t0)
    srai t0, a0, 31
    chk(t0)
    slli t0, a0, 0
    chk(t0)
    srai t0, a0, 0
    chk(t0)
    li   s0, LED
    li   t0, 0xFF
    sw   t0, 0(s0)
spin:
    jal  x0, spin
