TFG - SUBPUNTO: PROGRAMA BARE-METAL + ACELERADOR MMIO

Archivos nuevos (no sustituir RTL ni modelos existentes):
  sw/baremetal/accelerator/start.S
  sw/baremetal/accelerator/link.ld
  tb/tb_sv/tb_core_baremetal_accelerator.sv
  mk/baremetal_accelerator.mk

Con el archivo incluido desde el Makefile principal, ejecutar:
  make baremetal-accelerator
  make lint-baremetal-accelerator
  make regression
  make lint

No volver a pasar el archivo mk/baremetal_accelerator.mk con -f si el
Makefile principal ya contiene su directiva include. Es innecesario y
puede duplicar la lectura de reglas.


El programa escribe OPERAND_A/OPERAND_B, inicia la suma, consulta STATUS,
lee RESULT, limpia DONE mediante W1C y guarda PASS=1 (o FAIL=2)
en RAM 0x80000300. Usa la región MMIO 0x10000000.

La prueba usa los modelos síncronos reales ya existentes y NO modifica core_top.
El test no sustituye ACT4 ni prueba aún la FPGA física.
