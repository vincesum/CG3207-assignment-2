# Data processing test for test_RV_dp.v. Each result is stored to results[].
.eqv LED 0xFFFF0060
.macro chk(%r)
    sw   %r, 0(s5)
    addi s5, s5, 4
.end_macro
.data
results: .space 160
.text
    la   s5, results
    li   a0, 0x12345678
    li   a1, 0xF0F0F0F0
    li   a2, 0x7FFFFFFF
    li   a3, 0x80000000
    li   a4, -1
    add  t0, a0, a1
    chk(t0)
    add  t0, a2, a2      # overflow wraps
    chk(t0)
    sub  t0, a0, a1
    chk(t0)
    sub  t0, a3, a4
    chk(t0)
    and  t0, a0, a1
    chk(t0)
    or   t0, a0, a1
    chk(t0)
    xor  t0, a0, a1
    chk(t0)
    slt  t0, a3, a2      # signed: min < max
    chk(t0)
    slt  t0, a2, a3
    chk(t0)
    sltu t0, a3, a2      # unsigned: opposite answer
    chk(t0)
    sltu t0, a2, a3
    chk(t0)
    slt  t0, a4, x0
    chk(t0)
    sltu t0, a4, x0
    chk(t0)
    addi t0, a0, -1
    chk(t0)
    addi t0, a0, 2047
    chk(t0)
    addi t0, a0, -2048
    chk(t0)
    andi t0, a1, 0x7F0
    chk(t0)
    andi t0, a1, -16     # immediate is sign extended
    chk(t0)
    ori  t0, a0, 0x0F0
    chk(t0)
    ori  t0, x0, -1
    chk(t0)
    xori t0, a0, -1
    chk(t0)
    xori t0, a0, 0x555
    chk(t0)
    slti t0, a4, 0
    chk(t0)
    slti t0, a0, 1
    chk(t0)
    sltiu t0, a0, -1     # -1 is the largest unsigned value
    chk(t0)
    sltiu t0, x0, 1
    chk(t0)
    lui  t0, 0xABCDE
    chk(t0)
    lui  t0, 0xFFFFF
    addi t0, t0, -1
    chk(t0)
    auipc t0, 0
    chk(t0)
    auipc t0, 0x10
    chk(t0)
    add  x0, a0, a1      # x0 stays zero
    chk(x0)
    addi x0, x0, 5
    chk(x0)
    li   s0, LED
    li   t0, 0xFF
    sw   t0, 0(s0)
spin:
    jal  x0, spin
