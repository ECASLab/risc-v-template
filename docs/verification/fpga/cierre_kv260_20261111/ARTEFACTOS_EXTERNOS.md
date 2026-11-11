# Inventario de artefactos externos del TFG

## Propósito

Registrar los artefactos generados utilizados durante
la implementación y validación del RV64I en la KV260.

Los hashes corresponden a las auditorías D.3.2 y D.3.3.
Los respaldos no se incorporan al repositorio Git.

## Paquetes históricos

Archivos conservados en la carpeta local Descargas:

| Paquete | SHA-256 |
|---|---|
| TFG_DIRECTORIOS_COMPLETOS_8a8e743_2026-11-06.tar.gz | 7bc995d174c51b4be1b686cd4c55664f1e5e66324788113675884498b8e8eddf |
| TFG_TRANSFERENCIA_REAL_8a8e743_2026-11-06.zip | ecb55a810de6c9939c5f002624542ddae396543d4210d440afc671e6a223984c |
| TFG_DIRECTORIOS_COMPLETOS_a3c0e5f_2026-11-05.tar.gz | e1ea62bf0615c69a8b4195c33972aae2ce4c88745c549485fc678ba31de47503 |
| TFG_TRANSFERENCIA_REAL_a3c0e5f_2026-11-05.zip | 0f0e878df88537b8f993363f38faa868a6d369c371ce8ba11e6d9e96776ae148 |

## Artefactos de la revisión 8a8e743

| Artefacto | SHA-256 |
|---|---|
| accelerator.bin | 52a2f729e547c67f9b70309a2de964bea3f6f29afe0d4a19257a26cfb31755af |
| rv64i_tfg_kv260.bit.bin | a7d0e3c7990d188fc616a2544030935fd1ed77b999a3243bd984430530c27cd6 |
| rv64i_tfg_kv260.dtbo | 5d04ca5c85dfae7e115c4a4effca8d0ed9dea1d7aec04d53c1f8b31544136046 |
| k26_starter_kits.bit.bin | f9dfe95d14881a2768b2c0e6a36fc363635e8ae7882ecad9725d270490395d3e |
| k26_starter_kits.dtbo | 1e998ffd5d33a05da3746df3603e65603e1628006bc878209a836cc9bd3c4ae1 |
| first_run.log | a14a8f19f4c55dfec4650139fa3c1c80bb51fb647b937b776c08f11ce3ed1119 |

## Cargador ARM64

El ejecutable `rv64i_arm_loader_first_run` preservado
en los paquetes de la revisión 8a8e743 tiene SHA-256:

`2a80bb1db1a228a3d3bcca23f5e5c7c87cf648f0aa9b8bc13cce6138f98bfb80`

Este hash coincide con el ejecutable comprobado
durante la segunda campaña física.

Una referencia histórica anterior menciona otra
huella digital. Su procedencia continúa pendiente
de aclaración. No se considera evidencia de dos
versiones diferentes del ejecutable.

## Evidencias de verificación

En el directorio externo `tfg_evidencias_locales`:

- B6 a B14: campaña ACT4 y auditoría consolidada.
- C6_20261111_directa: segunda ejecución física.
- C6_2_comparacion_20261111: comparación de ejecuciones.
- C7_1_c5f33c3_20261111: auditoría Vivado.
- C7_2_c5f33c3_20261111: informe FPGA inicial.
- D3_3_c5f33c3_20261111: auditoría de paquetes.
- D3_4_c5f33c3_20261111: clon limpio y pruebas.

## Conservación y límites

Los respaldos contienen archivos de firmware y
material procedente del laboratorio. No deben
publicarse automáticamente como anexos en GitHub
sin revisar permisos y contenido.

La auditoría de los paquetes comprobó archivos
seleccionados y hashes de contenedores. No
constituyó una revisión funcional de cada miembro.

La disponibilidad de artefactos no sustituye la
reconstrucción del bitstream mediante Vivado.
