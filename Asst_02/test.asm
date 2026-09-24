.eqv MMIO_BASE      0xFFFF0000
.eqv DIP_OFF        0x64
.eqv LED_OFF        0x60

.data
    # Data memory section initialized with test variables
    test_word: .word 0xDEADBEEF 
    save_word: .word 0x00000000
    delay_val: .word 4          # Delay constant for the LED loop

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
    srli x11, x3, 1           # x11 = 10 >> 1 = 5
    srai x12, x4, 1           # x12 = -5 >> 1 = -3 

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
    srl  x22, x3, x20         # x22 = 10 >> 2 = 2 
    sra  x23, x4, x20         # x23 = -5 >> 2 = -2 

    # --------------------------------------------------------
    # 6. MEMORY INSTRUCTIONS (LW / SW)
    # --------------------------------------------------------
    lui  x24, %hi(test_word) # pseudo instruction for la
    addi x24, x24, %lo(test_word)
    
    lw   x25, 0(x24)          # x25 = 0xDEADBEEF
    addi x26, x0, 0x77        # x26 = 0x00000077
    sw   x26, 4(x24)          # Store 0x77 into save_word 

# --------------------------------------------------------
    # 7. BRANCH INSTRUCTIONS
    # --------------------------------------------------------
    addi x27, x0, 5
    addi x28, x0, 5
    beq  x27, x28, test_bne   
    li   x30, 0x01             # Error Code 1: BEQ failed
    jal  x0, fail_trap         

test_bne:
    addi x28, x0, 6
    bne  x27, x28, test_blt   
    li   x30, 0x02             # Error Code 2: BNE failed
    jal  x0, fail_trap         

test_blt:
    blt  x27, x28, test_bge   
    li   x30, 0x03             # Error Code 3: BLT failed
    jal  x0, fail_trap         

test_bge:
    bge  x28, x27, test_bltu  
    li   x30, 0x04             # Error Code 4: BGE failed
    jal  x0, fail_trap         

test_bltu:
    bltu x27, x28, test_bgeu  
    li   x30, 0x05             # Error Code 5: BLTU failed
    jal  x0, fail_trap         

test_bgeu:
    bgeu x28, x27, test_jal   
    li   x30, 0x06             # Error Code 6: BGEU failed
    jal  x0, fail_trap
    
    # --------------------------------------------------------
    # 8. JUMP AND LINK (JAL / JALR)
    # --------------------------------------------------------
test_jal:
    jal  x29, test_jalr       
    li x30, 0xBAD      

test_jalr:
    lui  x31, %hi(end_program)
    addi x31, x31, %lo(end_program)
    jalr x29, 0(x31)          
    li x30, 0xBAD    

    # --------------------------------------------------------
    # 9. END OF TEST & MMIO LED LOOP
    # --------------------------------------------------------
end_program:
    li x30, 0x999     # Success code

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
# HARDWARE ERROR TRAP
# --------------------------------------------------------
fail_trap:
    # Set up MMIO base address
    lui x8, 0xFFFF0           
    
    # Write the error code (stored in x30) to the LEDs (offset 0x60)
    sw x30, 0x60(x8)          

trap_loop:
    # Infinite loop to freeze the processor in the error state
    jal x0, trap_loop