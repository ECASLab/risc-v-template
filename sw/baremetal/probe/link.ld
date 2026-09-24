OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 1M
}

PHDRS
{
    text PT_LOAD FLAGS(5); /* R + X */
    data PT_LOAD FLAGS(6); /* R + W */
}

SECTIONS
{
    . = ORIGIN(RAM);

    .text.init :
    {
        KEEP(*(.text.init))
    } > RAM :text

    .text :
    {
        *(.text)
        *(.text.*)
    } > RAM :text

    .rodata : ALIGN(8)
    {
        *(.rodata)
        *(.rodata.*)
    } > RAM :text

    .data : ALIGN(8)
    {
        *(.data)
        *(.data.*)
    } > RAM :data

    .bss (NOLOAD) : ALIGN(8)
    {
        __bss_start = .;
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
    } > RAM :data

    . = ALIGN(16);

    __image_end = .;
    __stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
