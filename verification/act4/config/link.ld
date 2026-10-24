/* ACT4 / TFG RV64I: linker inicial de validacion del mapa de memoria.
 * Basado en el layout de ACT4 (commit d6094ad), ajustado al contrato
 * del procesador; aun NO supone que ACT4 ya pueda generar pruebas.
 */
RAM_ORIGIN = 0x80000000;
RAM_LENGTH = 0x00100000;  /* 1 MiB */
TEST_BASE  = RAM_ORIGIN;
NUM_HARTS  = 1;
STACK_SIZE = 0x00020000;  /* 128 KiB, como en la referencia ACT4 */

OUTPUT_ARCH(riscv)
ENTRY(rvtest_entry_point)

MEMORY
{
    ram (rwx) : ORIGIN = RAM_ORIGIN, LENGTH = RAM_LENGTH
}

PROVIDE(__stack_size = STACK_SIZE);
PROVIDE(__num_harts  = NUM_HARTS);

SECTIONS
{
    ASSERT(TEST_BASE >= ORIGIN(ram) &&
           TEST_BASE < ORIGIN(ram) + LENGTH(ram),
           "TEST_BASE esta fuera de RAM")

    .text.init TEST_BASE : { KEEP(*(.text.init)) } > ram
    .text.rvtest . : { *(.text.rvtest) *(.text.rvtest.*) } > ram

    . = ALIGN(0x4000);
    .rodata ALIGN(0x4000) : {
        *(.rodata) *(.rodata.*) *(.srodata) *(.srodata.*)
    } > ram

    .data . : {
        *(.data) *(.data.*) *(.sdata) *(.sdata.*)
    } > ram

    /* RVMODEL_DATA_SECTION publica tohost/fromhost en .tohost.
       El testbench observara las escrituras a la direccion de 'tohost'. */
    .tohost ALIGN(8) : {
        . = ALIGN(8);
        KEEP(*(.tohost))
    } > ram

    . = ALIGN(16);
    .bss (NOLOAD) : {
        __bss_start = .;
        *(.sbss) *(.sbss.*) *(.bss) *(.bss.*) *(COMMON)
        . = ALIGN(16);
        __bss_end = .;
    } > ram

    . = ALIGN(16);
    .stack (NOLOAD) : {
        __stack_bottom = .;
        . += __stack_size * __num_harts;
        __stack_top = .;
    } > ram

    /* ACT4 exige mantener .text.rvmodel despues de .data. */
    . = ALIGN(0x1000);
    .text.rvmodel ALIGN(0x1000) : {
        *(.text.rvmodel) *(.text.rvmodel.*) *(.text) *(.text.*)
    } > ram

    . = ALIGN(0x1000);
    _end = .;

    ASSERT(_end <= ORIGIN(ram) + LENGTH(ram),
           "ELF supera la region de RAM de 1 MiB")
}
