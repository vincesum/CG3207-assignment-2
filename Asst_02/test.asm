.eqv MMIO_BASE      0xFFFF0000
.eqv DIP_OFF        0x64
.eqv LED_OFF        0x60

.data
    # Data memory section initialized with test variables
    test_word: .word 0xDEADBEEF 
    save_word: .word 0x00000000
    delay_val: .word 4          # Delay constant for the LED loop
    # Operand pairs (a, b) for the branch tests in section 7
    branch_ops: .word 5, 5      # a == b
                .word -1, 1     # a < b signed,  a > b unsigned
                .word 1, -1     # a > b signed,  a < b unsigned

.text
.globl main
main:
    # --------------------------------------------------------
    # 1. UPPER IMMEDIATE INSTRUCTIONS
    # --------------------------------------------------------
    lui x1, 0x12345           # x1 = 0x12345000
    auipc x2, 0               # x2 = Current PC 

    # --------------------------------------------------------
    # 2. IMMEDIATE DATA PROCESSING (DP)
    # --------------------------------------------------------
    addi x3, x0, 10           # x3 = 10 
    addi x4, x0, -5           # x4 = -5 
    andi x5, x3, 15           # x5 = 10 & 15 = 10
    ori  x6, x3, 4            # x6 = 10 | 4  = 14
    xori x7, x3, 15           # x7 = 10 ^ 15 = 5	
    slti x8, x4, 0            # x8 = (-5 < 0) ? 1 : 0 = 1
    sltiu x9, x4, 10          # x9 = (unsigned -5 < 10) ? 1 : 0 = 0

    # --------------------------------------------------------
    # 3. IMMEDIATE SHIFTS
    # --------------------------------------------------------
    slli x10, x3, 2           # x10 = 10 << 2 = 40 
    srli x11, x4, 1           # x11 = 0xFFFFFFFB >>> 1 = 0x7FFFFFFD (zero fill; compare srai below)
    srai x12, x4, 1           # x12 = -5 >> 1 = -3 = 0xFFFFFFFD (sign fill)

    # --------------------------------------------------------
    # 4. REGISTER DATA PROCESSING (DP)
    # --------------------------------------------------------
    add  x13, x3, x3          # x13 = 10 + 10 = 20
    sub  x14, x3, x4          # x14 = 10 - (-5) = 15
    and  x15, x3, x6          # x15 = 10 & 14 = 10
    or   x16, x3, x6          # x16 = 10 | 14 = 14
    xor  x17, x3, x6          # x17 = 10 ^ 14 = 4
    slt  x18, x4, x3          # x18 = (-5 < 10) ? 1 : 0 = 1
    sltu x19, x4, x3          # x19 = (unsigned -5 < 10) ? 1 : 0 = 0

    # --------------------------------------------------------
    # 5. REGISTER SHIFTS
    # --------------------------------------------------------
    addi x20, x0, 2           # x20 = 2 (Shift amount)
    sll  x21, x3, x20         # x21 = 10 << 2 = 40
    srl  x22, x4, x20         # x22 = 0xFFFFFFFB >>> 2 = 0x3FFFFFFE (zero fill; compare sra below)
    sra  x23, x4, x20         # x23 = -5 >> 2 = -2 = 0xFFFFFFFE (sign fill)

    # --------------------------------------------------------
    # 6. MEMORY INSTRUCTIONS (LW / SW)
    # --------------------------------------------------------
    lui  x24, %hi(test_word) # pseudo instruction for la
    addi x24, x24, %lo(test_word)
    
    lw   x25, 0(x24)          # x25 = 0xDEADBEEF
    addi x26, x0, 0x77        # x26 = 0x00000077
    sw   x26, 4(x24)          # Store 0x77 into save_word 

# --------------------------------------------------------
    # 7. CONDITIONAL BRANCHES (each one taken AND not taken)
    # --------------------------------------------------------
    # All six branches run once per operand pair in branch_ops. Across the
    # three pairs, every branch is taken at least once and not taken at least once.
    # x29 records one bit per branch: shift left, then set to 1 only if NOT taken.
    #
    #   pair (a, b) | beq  bne  blt  bge  bltu bgeu | bits (1 = not taken)
    #   ------------+-------------------------------+---------------------
    #   ( 5,  5)    |  T    NT   NT   T    NT   T   | 0 1 1 0 1 0
    #   (-1,  1)    |  NT   T    T    NT   NT   T   | 1 0 0 1 1 0
    #   ( 1, -1)    |  NT   T    NT   T    T    NT  | 1 0 1 0 0 1
    #
    #   (-1, 1): blt taken (signed -1 < 1), bltu not taken (unsigned 0xFFFFFFFF > 1)
    #   ( 1,-1): blt not taken (signed 1 > -1), bltu taken (unsigned 1 < 0xFFFFFFFF)
    #
    # Expected x29 = 011010_100110_101001 = 0x1A9A9
    lui  x24, %hi(branch_ops)
    addi x24, x24, %lo(branch_ops)
    addi x26, x0, 3           # x26 = passes remaining
    addi x29, x0, 0           # x29 = branch signature

branch_pass:
    lw   x27, 0(x24)          # x27 = a
    lw   x28, 4(x24)          # x28 = b

    slli x29, x29, 1
    beq  x27, x28, beq_done
    ori  x29, x29, 1          # beq not taken
beq_done:
    slli x29, x29, 1
    bne  x27, x28, bne_done
    ori  x29, x29, 1          # bne not taken
bne_done:
    slli x29, x29, 1
    blt  x27, x28, blt_done
    ori  x29, x29, 1          # blt not taken
blt_done:
    slli x29, x29, 1
    bge  x27, x28, bge_done
    ori  x29, x29, 1          # bge not taken
bge_done:
    slli x29, x29, 1
    bltu x27, x28, bltu_done
    ori  x29, x29, 1          # bltu not taken
bltu_done:
    slli x29, x29, 1
    bgeu x27, x28, bgeu_done
    ori  x29, x29, 1          # bgeu not taken
bgeu_done:
    addi x24, x24, 8          # next operand pair
    addi x26, x26, -1
    bne  x26, x0, branch_pass # taken after passes 1-2, not taken after pass 3

    # --------------------------------------------------------
    # 8. JUMP AND LINK (JAL / JALR)
    # --------------------------------------------------------
    # count_call adds 1 to x30 and returns with jalr x0, 0(x1). It is called
    # once with jal and once with jalr; each must link x1 = PC + 4 for the
    # program to return here. Expected x30 = 2.
    addi x30, x0, 0           # x30 = call count
    jal  x1, count_call       # call 1: jal links x1 = PC + 4
    lui  x31, %hi(count_call)
    addi x31, x31, %lo(count_call)
    jalr x1, 0(x31)           # call 2: jalr links x1 = PC + 4

    # --------------------------------------------------------
    # 9. MMIO LED LOOP
    # --------------------------------------------------------
    # Setup memory-mapped I/O addresses
    li s0, MMIO_BASE          # Base address: 0xFFFF0000
    addi s1, s0, LED_OFF      # LED address
    li  s2, DIP_OFF           
    add s2, s0, s2            # DIP switch address

mmio_loop:
    lw s3, delay_val          # Load loop counter
    lw s4, 0(s2)              # Read current state of DIP switches
    sw s4, 0(s1)              # Write DIP switch state directly to LEDs

wait:
    addi s3, s3, -1           # Decrement delay counter
    beq s3, zero, mmio_loop   # Once delay hits 0, refresh LEDs with new DIP states
    jal zero, wait            # Otherwise, keep decrementing delay

# --------------------------------------------------------
# SUBROUTINE: count_call (called from section 8)
# --------------------------------------------------------
count_call:
    addi x30, x30, 1          # x30 += 1
    jalr x0, 0(x1)            # return to caller
