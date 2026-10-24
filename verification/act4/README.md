# ACT4 y pruebas complementarias del TFG

**Referencias históricas, no certificación oficial.**

- Núcleo verificado: `cf78be1cc7206879744f7587ab9806a508113b24`.
- ACT4 verificado: `d6094ad3ede5268b454197e7bb8eb1cbcbe140d0`.
- Se conservan **51 PASS / 0 FAIL** de ACT4 RV64I y regresión RTL histórica.
- Las fuentes ACT4 se instalaron a partir de `~/TFG_tools` sin modificar el origen.

## Directorios

- `config/`: instantánea **auditada** de UDB, linker, macros, Sail y cabeceras.
- `runner_b9_3_8k/`: ejecutor **histórico** del lote FENCE/NOP; no es un runner
  general ya integrado en Makefile. Contiene rutas a `~/TFG_tools`, comprobaciones
  de hashes de la configuración original y protección contra sobrescribir evidencias.
- `auditorias_historicas/`: scripts y TB originales de B.9.3.9a–h, preservados
  para trazabilidad. Sus rutas absolutas no se han adaptado y **no debe suponerse
  que se ejecutan directamente tras copiarse**.
- `../../docs/verification/act4/`: CSV, informes y resultados seleccionados.

## Advertencias arquitecturales

- `include_priv_tests: false`, con `Sm` provisional en UDB. No es conformidad
  completa de modo máquina ni de Zicsr.
- UDB `PHYS_ADDR_WIDTH=56`; Sail del caso auditado declara 32 bits. Pendiente
  de decisión y conciliación.
- `PMA_GRANULARITY=3` es hipótesis pendiente de justificar.
- El modelo IMEM termina en `$fatal` ante direcciones inválidas ensayadas;
  `core_top` no implementa `imem_error` como trap de instruction access fault.
- La prueba FENCE/MMIO solo acredita el sistema serializado observado.
- La memoria modelada de 1 MiB y las simulaciones no acreditan síntesis/BRAM FPGA.

## Regla de mantenimiento

No actualizar ACT4, sobrescribir evidencias previas, modificar RTL o asumir que
el linker del probe bare-metal es el linker ACT4 sin una prueba que lo requiera.
Antes de migrar un ejecutor al flujo principal, hacerlo configurable y verificar
que use exactamente las mismas fuentes, direcciones y criterios PASS/FAIL.

## Fuente pública

<https://github.com/riscv/riscv-arch-test/blob/act4/README.md>
