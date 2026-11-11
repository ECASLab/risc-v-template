# Informe técnico de cierre ACT4 — RV64I

## 1. Identificación

- Fecha de auditoría: 2026-11-10T15:30:16.659197-06:00
- Núcleo: `8a8e74382ddc6e65908fdf6134c06bdd0b1c44ed`
- ACT4: `d6094ad3ede5268b454197e7bb8eb1cbcbe140d0`
- Rama: `fpga/platform-uram`
- Compilador ACT4: Clang 22.1.2
- Modelo de referencia: Sail RISC-V 0.16
- Simulador RTL: Icarus Verilog 12.0

## 2. Objetivo y alcance

Reproducir los 51 casos arquitecturales RV64I del conjunto histórico seleccionado, ejecutando los ELF autocontenidos generados mediante ACT4 sobre el núcleo `core_top` en simulación RTL.

La campaña no representa una certificación oficial ni una verificación exhaustiva de RISC-V.

## 3. Metodología

1. Fijar los commits del núcleo y ACT4.
2. Verificar las configuraciones UDB, Sail, linker y macros del DUT.
3. Generar un ELF por caso con ACT4.
4. Convertir el ELF en imágenes IMEM y DMEM.
5. Verificar integridad y ejecutar en `core_top`.
6. Comprobar `tohost=1`, salida cero y solicitudes/respuestas DMEM equilibradas.
7. Contrastar métricas con la campaña histórica.

## 4. Resultados globales

| Indicador | Resultado |
|---|---:|
| Casos únicos | 51 |
| PASS | 51 |
| FAIL | 0 |
| Paquetes verificados | 51 |
| Diferencias de métricas históricas | 0 |

Los 51 casos reprodujeron las métricas históricas de ciclos, solicitudes de instrucciones y transacciones/respuestas de memoria.

Los ciclos corresponden a programas completos de prueba y no constituyen mediciones de latencia individual ni de CPI del núcleo.

## 5. Limitaciones y pendientes

- `include_priv_tests: false`: no se ejecutaron pruebas privilegiadas.
- La extensión `Sm` figura provisionalmente en la configuración UDB.
- `PHYS_ADDR_WIDTH=56` en UDB y 32 bits declarados en la configuración Sail histórica: conciliación pendiente.
- `PMA_GRANULARITY=3`: hipótesis pendiente de justificación.
- No se acreditó completamente el trap de `instruction access fault` en `core_top`.
- La prueba FENCE acredita el comportamiento observado en el sistema serializado ensayado.
- La memoria modelada de 1 MiB no acredita por sí sola recursos ni comportamiento temporal de memorias FPGA.

Estas limitaciones se describen en `verification/act4/README.md` del commit auditado.

## 6. Evidencia y trazabilidad

- Resultados actuales: `B14_8a8e743/resultados_51_actuales.csv`
- Resumen: `B14_8a8e743/resumen.json`
- Auditoría: `B14_8a8e743/auditoria.log`
- Manifiesto: `B14_8a8e743/SHA256SUMS.txt`
- Lotes originales: B6 a B13, conservados fuera del repositorio.

SHA-256 del CSV consolidado: `f2449e25d7ac507d8dc3d16560aa0a5abff2f1f1387fa20c887bdf4c40b7bf07`

## 7. Anexo — Resultados individuales

| Caso | Lote | Ciclos | Fetch | DMEM | Respuestas | Estado |
|---|---|---:|---:|---:|---:|---|
| `I-add-00` | B7 | 23949 | 5548 | 1756 | 1756 | PASS |
| `I-addi-00` | B6 | 15857 | 3716 | 992 | 992 | PASS |
| `I-addiw-00` | B8 | 15825 | 3708 | 992 | 992 | PASS |
| `I-addw-00` | B9 | 23949 | 5548 | 1756 | 1756 | PASS |
| `I-and-00` | B8 | 23917 | 5540 | 1756 | 1756 | PASS |
| `I-andi-00` | B9 | 15857 | 3716 | 992 | 992 | PASS |
| `I-auipc-00` | B9 | 2240 | 544 | 63 | 63 | PASS |
| `I-beq-00` | B7 | 29581 | 7018 | 1508 | 1508 | PASS |
| `I-bge-00` | B9 | 31429 | 7480 | 1508 | 1508 | PASS |
| `I-bgeu-00` | B10 | 31429 | 7480 | 1508 | 1508 | PASS |
| `I-blt-00` | B9 | 31213 | 7426 | 1508 | 1508 | PASS |
| `I-bltu-00` | B10 | 31213 | 7426 | 1508 | 1508 | PASS |
| `I-bne-00` | B8 | 33049 | 7885 | 1508 | 1508 | PASS |
| `I-fence-00` | B9 | 2152 | 536 | 7 | 7 | PASS |
| `I-jal-00` | B10 | 65151 | 16259 | 114 | 114 | PASS |
| `I-jalr-00` | B8 | 13410 | 3262 | 361 | 361 | PASS |
| `I-lb-00` | B9 | 5450 | 1256 | 282 | 282 | PASS |
| `I-lbu-00` | B10 | 5450 | 1256 | 282 | 282 | PASS |
| `I-ld-00` | B7 | 4714 | 1088 | 242 | 242 | PASS |
| `I-lh-00` | B10 | 5098 | 1176 | 262 | 262 | PASS |
| `I-lhu-00` | B10 | 5066 | 1168 | 262 | 262 | PASS |
| `I-lui-00` | B10 | 2208 | 536 | 63 | 63 | PASS |
| `I-lw-00` | B10 | 4890 | 1128 | 252 | 252 | PASS |
| `I-lwu-00` | B8 | 4890 | 1128 | 252 | 252 | PASS |
| `I-nop-00` | B11 | 949 | 236 | 4 | 4 | PASS |
| `I-or-00` | B9 | 23917 | 5540 | 1756 | 1756 | PASS |
| `I-ori-00` | B11 | 15857 | 3716 | 992 | 992 | PASS |
| `I-sb-00` | B11 | 13680 | 3224 | 658 | 658 | PASS |
| `I-sd-00` | B8 | 12936 | 3056 | 610 | 610 | PASS |
| `I-sh-00` | B11 | 13324 | 3144 | 634 | 634 | PASS |
| `I-sll-00` | B11 | 23917 | 5540 | 1756 | 1756 | PASS |
| `I-slli-00` | B11 | 11709 | 2748 | 716 | 716 | PASS |
| `I-slliw-00` | B11 | 8041 | 1892 | 472 | 472 | PASS |
| `I-sllw-00` | B11 | 23917 | 5540 | 1756 | 1756 | PASS |
| `I-slt-00` | B12 | 23809 | 5516 | 1744 | 1744 | PASS |
| `I-slti-00` | B12 | 15789 | 3700 | 988 | 988 | PASS |
| `I-sltiu-00` | B12 | 15789 | 3700 | 988 | 988 | PASS |
| `I-sltu-00` | B12 | 23777 | 5508 | 1744 | 1744 | PASS |
| `I-sra-00` | B12 | 23917 | 5540 | 1756 | 1756 | PASS |
| `I-srai-00` | B12 | 11709 | 2748 | 716 | 716 | PASS |
| `I-sraiw-00` | B8 | 8073 | 1900 | 472 | 472 | PASS |
| `I-sraw-00` | B12 | 23917 | 5540 | 1756 | 1756 | PASS |
| `I-srl-00` | B12 | 23949 | 5548 | 1756 | 1756 | PASS |
| `I-srli-00` | B13 | 11709 | 2748 | 716 | 716 | PASS |
| `I-srliw-00` | B13 | 8073 | 1900 | 472 | 472 | PASS |
| `I-srlw-00` | B13 | 23917 | 5540 | 1756 | 1756 | PASS |
| `I-sub-00` | B13 | 23949 | 5548 | 1756 | 1756 | PASS |
| `I-subw-00` | B13 | 23949 | 5548 | 1756 | 1756 | PASS |
| `I-sw-00` | B13 | 13146 | 3104 | 622 | 622 | PASS |
| `I-xor-00` | B8 | 23917 | 5540 | 1756 | 1756 | PASS |
| `I-xori-00` | B13 | 15857 | 3716 | 992 | 992 | PASS |

## 8. Referencias técnicas

- RISC-V ACT4: https://github.com/riscv/riscv-arch-test
- Certification Test Plan: https://riscv.github.io/riscv-arch-test/ctp.html
- Configuración histórica del TFG: `verification/act4/README.md`
