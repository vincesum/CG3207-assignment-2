/* doom_soc boot ROM: 4 KB at 0x0040_0000, read-only (no .data / .bss allowed). */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x00400000, LENGTH = 4K
}

SECTIONS
{
    .text : {
        KEEP(*(.text.init))
        *(.text .text.*)
        *(.rodata .rodata.* .srodata .srodata.*)
    } > ROM

    .data : {
        *(.data .data.* .sdata .sdata.* .bss .bss.* .sbss .sbss.* COMMON)
    } > ROM

    ASSERT(SIZEOF(.data) == 0, "boot ROM code must not use writable globals")

    /DISCARD/ : { *(.eh_frame) *(.comment) *(.note .note.*) *(.riscv.attributes) }
}
