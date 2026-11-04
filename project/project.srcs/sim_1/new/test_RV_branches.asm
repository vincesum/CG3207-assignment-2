# Branch and jump test for test_RV_branches.v. Each test adds its own bit to s6 on the correct
# path and sets a bit in s7 on a wrong path, so results[] shows exactly which ones misbehaved.
.eqv LED 0xFFFF0060
.data
results: .space 64
.text
    la   s5, results
    addi s6, x0, 0
    addi s7, x0, 0
    li   a0, 5
    li   a1, 5
    li   a2, 6
    li   a3, -1
    li   a4, 1
    # Taken
    beq  a0, a1, tkt1
    ori  s7, s7, 1
tkt1: ori  s6, s6, 1
    bne  a0, a2, tkt2
    ori  s7, s7, 2
tkt2: ori  s6, s6, 2
    blt  a3, a4, tkt3          # signed: -1 < 1
    ori  s7, s7, 4
tkt3: ori  s6, s6, 4
    bge  a4, a3, tkt4          # signed: 1 >= -1
    ori  s7, s7, 8
tkt4: ori  s6, s6, 8
    bltu a4, a3, tkt5          # unsigned: 1 < 0xFFFFFFFF
    ori  s7, s7, 16
tkt5: ori  s6, s6, 16
    bgeu a3, a4, tkt6
    ori  s7, s7, 32
tkt6: ori  s6, s6, 32
    bge  a0, a1, tkt7          # equal counts as >=
    ori  s7, s7, 64
tkt7: ori  s6, s6, 64
    bgeu a0, a1, tkt8
    ori  s7, s7, 128
tkt8: ori  s6, s6, 128
    sw   s6, 0(s5)
    sw   s7, 4(s5)
    # Not taken: the bit is set only if the branch wrongly jumps over nothing else
    addi s6, x0, 0
    addi s7, x0, 0
    beq  a0, a2, w1
    ori  s6, s6, 1
    jal  x0, n1
w1: ori  s7, s7, 1
n1: bne  a0, a1, w2
    ori  s6, s6, 2
    jal  x0, n2
w2: ori  s7, s7, 2
n2: blt  a4, a3, w3
    ori  s6, s6, 4
    jal  x0, n3
w3: ori  s7, s7, 4
n3: bge  a3, a4, w4
    ori  s6, s6, 8
    jal  x0, n4
w4: ori  s7, s7, 8
n4: bltu a3, a4, w5
    ori  s6, s6, 16
    jal  x0, n5
w5: ori  s7, s7, 16
n5: bgeu a4, a3, w6
    ori  s6, s6, 32
    jal  x0, n6
w6: ori  s7, s7, 32
n6: sw   s6, 8(s5)
    sw   s7, 12(s5)
    # Backward branch: count down a loop
    addi t0, x0, 10
    addi t1, x0, 0
loop:
    addi t1, t1, 3
    addi t0, t0, -1
    bne  t0, x0, loop
    sw   t1, 16(s5)
    # jal: link value, then jump over wrong-path code
    jal  ra, j1
    addi t2, x0, 99
    jal  x0, j2
j1: sw   ra, 20(s5)
    jalr t3, ra, 0           # return, keeping a link in t3
j2: sw   t2, 24(s5)
    sw   t3, 28(s5)
    # jalr with a positive offset, and with rd = rs1
    la   t4, j3
    addi t4, t4, -8
    jalr t5, t4, 8
    addi s7, x0, 0x7FF
j3: sw   t5, 32(s5)
    sw   s7, 36(s5)
    la   t6, j4
    jalr t6, t6, 0           # the link must not disturb the jump target
    addi s7, x0, 0x555
j4: sw   t6, 40(s5)
    sw   s7, 44(s5)
    li   s0, LED
    li   t0, 0xFF
    sw   t0, 0(s0)
spin:
    jal  x0, spin
