# Candidato de entrega — Plataforma RISC-V RV64I

Fecha de preparación: 12 de noviembre de 2026.

Proyecto: Desarrollo y verificación de un núcleo RISC-V
RV64I con interfaz de expansión para aceleradores en FPGA.

Estado: candidato local de entrega, pendiente de integración
en la rama principal y publicación de la versión.

## 1. Componentes de la plataforma

- Núcleo RISC-V RV64I de cinco etapas.
- Interfaces de memoria de instrucciones y datos.
- Interfaz MMIO de expansión para aceleradores.
- Periférico de demostración y pruebas de integración.
- Adaptación AXI4-Lite e integración SoC.
- Programas y herramientas bare-metal.
- Regresiones funcionales y evidencias arquitecturales.
- Diseño FPGA para AMD Kria KV260.
- Herramientas de reconstrucción y empaquetado PL_FLAT.

## 2. Primer uso

Consultar:

- [README principal](../README.md).
- [Instalación](getting-started.md).
- [Interfaz de expansión](expansion-interface.md).
- [Plataforma KV260](fpga-kv260.md).
- [Reconstrucción del firmware](rebuild-kv260-firmware.md).

Comandos principales disponibles:

```bash
make help
make regression
make lint
make baremetal-probe
make baremetal-accelerator
make list-tests
```

## 3. Verificación

Las campañas funcionales y de FPGA se realizaron
conforme al alcance documentado del TFG.

La campaña D.6.8 reconstruyó la implementación KV260
desde un repositorio independiente en Vivado 2024.1.

Resultados después de routing:

- WNS setup: +1,245 ns.
- WHS hold: +0,012 ns.
- TNS y THS: 0 ns.
- DRC: cero violaciones.
- Metodología: cero violaciones.
- UltraRAM: 32.
- Ventilador: A12, LVCMOS33.

Consultar las
[evidencias de reconstrucción](verification/fpga/reconstruccion_kv260_20261112_86a15be/README.md).

Las pruebas ACT4 disponen de evidencias históricas.
No se presenta el runner externo histórico como una
integración nueva de `make act4`.

## 4. Firmware KV260

Se distinguen dos variantes:

### Firmware histórico

Validado previamente mediante las campañas físicas
documentadas del proyecto.

SHA-256 del bitstream histórico:

`a7d0e3c7990d188fc616a2544030935fd1ed77b999a3243bd984430530c27cd6`

### Firmware reconstruido

Generado desde la implementación de D.6.8 y ensamblado
satisfactoriamente durante D.6.9.

SHA-256 del bitstream reconstruido:

`bd143fa4778b8a75130ad5d70c191289e280d7e3a997ae3fca18a1ccdf061c4d`

Ambos tienen tamaño de 7797692 bytes, pero no son
binariamente idénticos.

El DTBO reconstruido coincide con el histórico.

El firmware reconstruido no fue probado nuevamente
en hardware y no sustituye la validación física histórica.

Consultar [artefactos precompilados](../fpga/prebuilt/kv260/README.md).

## 5. Limitaciones y distribución

- Vivado y las IP AMD requieren el entorno compatible.
- No se incluye una nueva campaña física del firmware reconstruido.
- Los archivos precompilados se mantienen diferenciados
  de las fuentes y evidencias de implementación.
- La distribución de binarios debe ajustarse a las
  condiciones aplicables al repositorio académico.
- La versión final requiere revisión e integración
  con el repositorio administrado por el tutor.

Consultar [estado de entrega](release-readiness.md).

## 6. Versión

Estas notas describen el candidato de entrega local.

La etiqueta definitiva de versión y la GitHub Release
se establecerán al integrar la revisión aprobada
en la rama principal.
