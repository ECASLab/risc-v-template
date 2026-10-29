/* La región de datos del programa queda en RAM + 0x300. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 1M
}

PHDRS
{
    text PT_LOAD FLAGS(5); /* RX */
    data PT_LOAD FLAGS(6); /* RW */
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
        *(.rodata)
        *(.rodata.*)
    } > RAM :text

    /* El programa guarda la prueba en esta dirección fija. */
    .result_flag ORIGIN(RAM) + 0x300 :
    {
        KEEP(*(.result_flag))
    } > RAM :data

    /DISCARD/ :
    {
        *(.comment)
        *(.note*)
    }
}
