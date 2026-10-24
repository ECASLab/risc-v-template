/* TFG RV64I / ACT4 d6094ad
 * Contrato bare-metal: tohost es RAM normal, observada por el testbench.
 * Solo las macros necesarias para pruebas no privilegiadas.
 */
#ifndef TFG_RVMODEL_MACROS_H
#define TFG_RVMODEL_MACROS_H

/* No declarar STANDARD_SM_SUPPORTED: subconjunto M-mode no certificado. */
#define RVMODEL_DATA_SECTION                                      \
  .pushsection .tohost,"aw",@progbits;                            \
  .balign 8; .globl tohost; tohost: .dword 0;                     \
  .balign 8; .globl fromhost; fromhost: .dword 0;                 \
  .popsection

/* Un único store alineado de 64 bits: valor 1=PASS, 3=FAIL.
 * No utilizar CSR, instrucciones C, M ni A. */
#define RVMODEL_HALT_PASS                                          \
  li t1, 1;                                                       \
  la t0, tohost;                                                  \
  sd t1, 0(t0);                                                   \
  1: jal x0, 1b

#define RVMODEL_HALT_FAIL                                          \
  li t1, 3;                                                       \
  la t0, tohost;                                                  \
  sd t1, 0(t0);                                                   \
  1: jal x0, 1b

/* No existe UART en esta integración de simulación. */
#define RVMODEL_IO_INIT(_R1, _R2, _R3)
#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)

#endif
