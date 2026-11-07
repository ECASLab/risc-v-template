# P2.9.4 — Validación física de RV64I en Kria KV260 (primera ejecución)

## Identificación de la plataforma y del firmware

- Placa observada: `ZynqMP KV260 revB`, Ubuntu 22.04.4 LTS, kernel `5.15.0-1027-xilinx-zynqmp`, arquitectura `aarch64`.
- DFX Manager instalado: `2023.1+5918fb3-0ubuntu0xlnx2`; firmware original `k26-starter-kits` (`XRT_FLAT`).
- Firmware de prueba: `tfg-rv64i-kv260`, tipo `PL_FLAT`. DFX reportó su carga en slot 0 y el overlay `tfg-rv64i-kv260_image_1` como `applied`.
- Ventana de supervisor en Device Tree: `0xA0000000` de tamaño `0x1000`; `compatible = tfg,rv64i-axi-supervisor-1.0`.
- `pl0_ref` de `/sys/kernel/debug/clk/clk_summary`: **58 823 529 Hz**, habilitado. Es información reportada por Linux, no medición con instrumento.
- Ventilación: servicio `fancontrol` activo; las muestras térmicas observadas alrededor de 30–34 °C no evidenciaron problemas. No hubo telemetría independiente de RPM.

## Evidencia física secuencial (resultados de usuario)

| Subpunto | Evidencia positiva | Alcance y limitación |
|---|---|---|
| f.1 | `tfg-rv64i-kv260: loaded to slot 0`, overlay aplicado | Carga FPGA/Device Tree, no ejecución |
| f.2.a | `pl0_ref=58823529`, `hardware enable=Y` | Configuración de reloj reportada por kernel |
| f.4 | `AXI_CONTROL_READ_PASS`, `CONTROL=0` | Primera lectura MMIO física |
| f.5 | `AXI_STATUS_READ_PASS`, `STATUS=0` | Segunda lectura MMIO física |
| f.6 | `BOOT_STATUS=0`, `BOOT_WSTRB=0xff` | Lectura de registros BOOT |
| f.7 | `BOOT_ADDR_LO=0x80000000` con readback y restauración a 0 | Camino físico de escritura AXI |
| f.8 | `BOOT_URAM_WORD_PASS`, patrón `0x1122334455667788` | Escritura/lectura BOOT de palabra UltraRAM |
| f.9.b | `FULL_IMAGE_STAGE_PASS`, `VERIFIED_WORDS=97/97` | Carga y comprobación de imagen manteniendo RUN=0 |
| f.10.a | `LOADER_STATIC_AUDIT_PASS`, `EXECUTION_GUARD_PASS` | Comprobaciones estáticas/offline |
| f.10.b | `PASS: ARM -> AXI4-Lite -> UltraRAM -> RV64I -> MMIO`, `RESULT_FLAG=1 POLLS=1` | **Primera ejecución real, positiva** |
| f.11–f.12 | Respaldo local y copia externa con `SHA256SUMS.txt` verificado | Integridad de evidencia |

La aplicación ARM de prueba descargó 97 palabras (776 bytes) en UltraRAM, inició la ejecución RV64I, comprobó la señalización de resultado de la demostración MMIO y verificó el marcador `result_flag` igual a 1. `POLLS=1` es el número de consultas realizadas por ARM; **no es una medición de ciclos o latencia del núcleo**.

## Fuentes de prueba y hashes conservados

- Commit previo a la integración: `a3c0e5fd0ca9243d00e63ce85b498f52c1f805c0` en `fpga/platform-uram`.
- Snapshot de Kria: `12b042556e69f9e2202d45e93b7edb9ba85a512fa31bcc739613e1fbc22c5932`.
- `accelerator.bin`: `52a2f729e547c67f9b70309a2de964bea3f6f29afe0d4a19257a26cfb31755af`.
- Loader ARM64 corregido: `a1a0c355f0f08c0825f896413ab4978586fd01630f0599fb6ec1b871f8942dce`.
- Registro original `first_run.log`: `a14a8f19f4c55dfec4650139fa3c1c80bb51fb647b937b776c08f11ce3ed1119`.
- Firmware `.bit.bin`: `a7d0e3c7990d188fc616a2544030935fd1ed77b999a3243bd984430530c27cd6`.
- DTBO: `5d04ca5c85dfae7e115c4a4effca8d0ed9dea1d7aec04d53c1f8b31544136046`.

El `first_run.log` íntegro, el binario ARM64 y la captura del estado posterior se conservan en los dos paquetes de transferencia y en `~/ecaslab/tfg_rv64i/evidencias/p2_9_4_f_10_b_first_run/` en la Kria. El respaldo externo fue verificado en Ubuntu local.

## Verificaciones pendientes

- Segunda ejecución y verificación independiente de RUN=0 después de la ejecución (P2.9.4.f.13).
- Restauración real de `k26-starter-kits`, validación posterior del overlay de referencia y del control térmico.
- Consolidación de la evidencia y revisión final del alcance; la ejecución del demo no certifica todas las instrucciones RV64I.

No reprogramar ni realizar accesos AXI sin las verificaciones térmicas y de recuperación descritas en el procedimiento de laboratorio. No incluir contraseñas, tokens o claves privadas en respaldos.
