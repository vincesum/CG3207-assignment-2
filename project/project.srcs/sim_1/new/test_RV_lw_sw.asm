# Load and store test for test_RV_lw_sw.v. Each result is stored to results[].
.eqv LED 0xFFFF0060
.macro chk(%r)
    sw   %r, 0(s5)
    addi s5, s5, 4
.end_macro
.data
results: .space 128
words:   .word 0x11223344, 0x55667788, 0x99AABBCC, 0xDDEEFF00
scratch: .space 32
.text
    la   s5, results
    la   s1, words
    addi s2, s1, 8           # middle of the table, for negative offsets
    la   s3, scratch
    lw   t0, 0(s1)
    chk(t0)
    lw   t0, 4(s1)
    chk(t0)
    lw   t0, -4(s2)
    chk(t0)
    lw   t0, 4(s2)
    chk(t0)
    li   a0, 0xCAFEBABE
    sw   a0, 0(s3)
    lw   t0, 0(s3)
    chk(t0)
    sw   a0, 28(s3)
    addi t1, s3, 32
    lw   t0, -4(t1)
    chk(t0)
    lui  t0, 0x12345
    chk(t0)
    auipc t0, 1
    chk(t0)
    # Loads of each byte and halfword, signed and unsigned
    lb   t0, 8(s1)           # CC
    chk(t0)
    lbu  t0, 8(s1)
    chk(t0)
    lb   t0, 9(s1)           # BB
    chk(t0)
    lbu  t0, 10(s1)          # AA
    chk(t0)
    lb   t0, 11(s1)          # 99
    chk(t0)
    lb   t0, 0(s1)           # 44, positive
    chk(t0)
    lh   t0, 8(s1)           # BBCC
    chk(t0)
    lhu  t0, 8(s1)
    chk(t0)
    lh   t0, 10(s1)          # 99AA
    chk(t0)
    lhu  t0, 10(s1)
    chk(t0)
    lh   t0, 0(s1)           # 3344, positive
    chk(t0)
    # Stores of each byte and halfword leave the rest of the word alone
    li   a1, 0xA1B2C3D4
    sw   a0, 4(s3)
    sb   a1, 4(s3)
    lw   t0, 4(s3)
    chk(t0)
    sb   a1, 5(s3)
    lw   t0, 4(s3)
    chk(t0)
    sb   a1, 6(s3)
    sb   a1, 7(s3)
    lw   t0, 4(s3)
    chk(t0)
    sw   a0, 8(s3)
    sh   a1, 8(s3)
    lw   t0, 8(s3)
    chk(t0)
    sh   a1, 10(s3)
    lw   t0, 8(s3)
    chk(t0)
    li   s0, LED
    li   t0, 0xFF
    sw   t0, 0(s0)
spin:
    jal  x0, spin
