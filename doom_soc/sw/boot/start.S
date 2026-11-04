# doom_soc boot ROM entry (reset vector 0x0040_0000). Stack at the top of DDR2.
    .section .text.init, "ax", @progbits
    .globl _start
_start:
    li      sp, 0x88000000
    call    boot_main
1:  j       1b
