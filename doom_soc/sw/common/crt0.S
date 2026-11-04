# Startup code: set gp and sp, clear .bss, call main, then exit(main's return value).
# .data is not copied: the loader (simulation preload, or the boot loader later) places
# the whole image at its run address.
    .section .text.boot.entry, "ax", @progbits
    .globl _start
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    la      sp, __stack_top

    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:
    li      a0, 0           # argc
    li      a1, 0           # argv
    call    main
    call    exit            # newlib exit (flushes stdio) or bare.c exit
3:  j       3b
