.section .text.init
.globl _start
.type _start, @function

_start:
    # Dirección PC-relative del dato en RAM.
    lla  t2, probe_data

    # Load real desde la memoria de datos.
    ld   t3, 0(t2)

    # Efectos arquitecturales sencillos adicionales.
    addi t0, zero, 1
    addi t1, t0, 2

    # Store real hacia probe_result.
    sd   t3, 8(t2)

1:
    jal  zero, 1b

    .size _start, .-_start


.section .data
.align 3

.globl probe_data
probe_data:
    .dword 0x1122334455667788

.globl probe_result
probe_result:
    .dword 0x0000000000000000
