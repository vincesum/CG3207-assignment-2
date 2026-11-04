/* Unified memory map: program (code + data + heap + stack) in RAM at 0x80000000.
   doom_soc: stack top 0x86FF0000 (below the WAD header at 0x86FFFFF0 and the WAD at 0x87000000).
   Override the stack top with -Wl,--defsym=__ram_size=<bytes>. */
OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

SECTIONS
{
    .text : {
        KEEP(*(.text.boot.entry))
        KEEP(*(.text.init))
        *(.text .text.*)
    } > RAM

    ASSERT(_start == ORIGIN(RAM), "Startup must be at RAM base: serial loader jumps to 0x80000000")

    .rodata : ALIGN(4) {
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
    } > RAM

    .init_array : ALIGN(4) {
        PROVIDE_HIDDEN(__init_array_start = .);
        KEEP(*(SORT(.init_array.*)))
        KEEP(*(.init_array))
        PROVIDE_HIDDEN(__init_array_end = .);
    } > RAM
    .fini_array : ALIGN(4) {
        PROVIDE_HIDDEN(__fini_array_start = .);
        KEEP(*(SORT(.fini_array.*)))
        KEEP(*(.fini_array))
        PROVIDE_HIDDEN(__fini_array_end = .);
    } > RAM

    .data : ALIGN(4) {
        __data_start = .;
        *(.data .data.*)
    } > RAM

    .sdata : ALIGN(4) {
        __sdata_start = .;
        *(.sdata .sdata.* .sdata2 .sdata2.*)
    } > RAM
    __global_pointer$ = __sdata_start + 0x800;

    .sbss (NOLOAD) : ALIGN(4) {
        __bss_start = .;
        *(.sbss .sbss.*)
        *(.scommon)
    } > RAM
    .bss (NOLOAD) : ALIGN(4) {
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM

    . = ALIGN(16);
    _end = .;
    PROVIDE(end = .);
    __heap_start = .;

    __ram_size = DEFINED(__ram_size) ? __ram_size : 0x06FF0000;
    __stack_top = ORIGIN(RAM) + __ram_size;

    /DISCARD/ : { *(.eh_frame) *(.comment) *(.note .note.*) }
}
