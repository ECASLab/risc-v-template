# Reconstrucción local desde un clon limpio

## Campaña D.3.4

Fecha: 11 de noviembre de 2026.

- Repositorio: ECASLab/risc-v-template.
- Rama probada: fpga/platform-uram.
- Commit: c5f33c37b35120982f0b5015ab1ce437f7aff525.
- Sistema: Ubuntu Linux x86_64.
- Entorno: herramientas locales previamente instaladas.

## Procedimiento

Desde un directorio de pruebas independiente:

```bash
git clone --branch fpga/platform-uram --single-branch \
  https://github.com/ECASLab/risc-v-template.git
cd risc-v-template
git checkout c5f33c37b35120982f0b5015ab1ce437f7aff525

make check-tools check-verilator check-riscv-tools
make baremetal-probe
make regression
make lint
```

## Resultados

| Comprobación | Resultado |
|---|---|
| Clonación e identidad del commit | PASS |
| Dependencias del proyecto | PASS |
| Bare-metal probe | PASS |
| Regresión local | PASS |
| Lint Verilator | PASS |
| Árbol de fuentes Git sin modificaciones | PASS |

El programa `accelerator.bin` se reconstruyó con
776 bytes y SHA-256:

`52a2f729e547c67f9b70309a2de964bea3f6f29afe0d4a19257a26cfb31755af`

Esta huella coincide exactamente con el programa
empleado durante la demostración física.

## Alcance

La campaña acredita la reconstrucción local y
verificación mediante simulación del código
versionado, en el entorno de herramientas probado.

No incluye una reconstrucción completa del
bitstream en Vivado 2024.1 ni una nueva ejecución
de las 51 pruebas ACT4 desde este clon.

La validación física sobre KV260 y la campaña ACT4
se documentan por separado.

## Evidencias

Los registros de D.3.4 y sus hashes se conservan en
`tfg_evidencias_locales/D3_4_c5f33c3_20261111/`.

No se modificó el repositorio de trabajo original.
