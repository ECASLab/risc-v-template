/*
 * TFG: demostracion bare-metal de la suma MMIO RV64I.
 * No necesita runtime C, pila ni biblioteca estandar.
 * Contrato: EXP_BASE=0x10000000; resultado en RAM 0x80000300.
 */
    .option norvc
    .section .text.init,"ax",@progbits
    .globl _start
    .type _start, @function

_start:
    /* MMIO: periférico de expansión. */
    li   s0, 0x10000000

    /* 64 bits: operand_a = 0x1122334455667788. */
    li   t0, 0x1122334455667788
    sd   t0, 0x20(s0)

    /* operand_b = 0x22. */
    li   t0, 0x22
    sd   t0, 0x28(s0)

    /* CONTROL[0] = start. */
    li   t0, 1
    sd   t0, 0x10(s0)

poll_done:
    ld   t1, 0x18(s0)       /* STATUS[1] = done */
    andi t2, t1, 2
    beq  t2, zero, poll_done

    ld   t3, 0x30(s0)       /* RESULT */
    li   t4, 0x11223344556677aa
    bne  t3, t4, fail

    /* W1C de STATUS[1]: escribir 1 en dicho bit. */
    li   t0, 2
    sd   t0, 0x18(s0)
    ld   t1, 0x18(s0)
    bne  t1, zero, fail

    /* Marca PASS=1 en RAM, visible para el testbench. */
    lla  t0, result_flag
    li   t1, 1
    sd   t1, 0(t0)
pass_loop:
    jal  zero, pass_loop

fail:
    /* Marca FAIL=2 en RAM. */
    lla  t0, result_flag
    li   t1, 2
    sd   t1, 0(t0)
fail_loop:
    jal  zero, fail_loop

    .size _start, .-_start

    .section .result_flag,"aw",@progbits
    .balign 8
    .globl result_flag
result_flag:
    .dword 0
