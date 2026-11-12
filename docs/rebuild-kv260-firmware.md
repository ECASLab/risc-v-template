# Reconstrucción del firmware KV260

Esta guía complementa [FPGA KV260](fpga-kv260.md).

## Alcance

La plataforma permite generar firmware PL_FLAT desde un
proyecto Vivado 2024.1 previamente implementado hasta
`route_design`.

La generación del firmware no ejecuta nuevamente síntesis,
routing ni programación física de la tarjeta.

## 1. Generar BIT/BIN

En un entorno con Vivado 2024.1 habilitado, desde la raíz
del repositorio:

```bash
export TFG_XPR="/ruta/al/proyecto/rv64i_kv260_ps_pl.xpr"
export TFG_OUTPUT_DIR="/ruta/externa/bitstream"

mkdir -p "$TFG_OUTPUT_DIR"

vivado -mode batch \
  -source fpga/kv260/generate_firmware.tcl
```

El proyecto debe tener `impl_1` completado hasta routing.
El directorio de salida no debe contener archivos BIT/BIN
anteriores.

## 2. Preparar el paquete PL_FLAT

```bash
python3 fpga/scripts/package_kv260_firmware.py \
  --bin "/ruta/externa/bitstream/rv64i_tfg_kv260.bin" \
  --out "/ruta/externa/paquete-kv260" \
  --design-commit "$(git rev-parse HEAD)"
```

El `--design-commit` debe ser el commit exacto del diseño
con el que se generó el proyecto Vivado. Si el firmware
procede de otra revisión, indicar aquella revisión y no
utilizar automáticamente el HEAD actual.

Requiere Python 3 y `dtc`. Crea bit.bin, DTBO,
shell.json, manifest.json y SHA256SUMS.txt.

## 3. Alcance de la validación

La generación de archivos y la verificación de integridad
no equivalen a una nueva validación física en la KV260.

El paquete histórico validado y el firmware reconstruido
se conservan y documentan por separado.

Los binarios no deben publicarse sin las autorizaciones
de distribución correspondientes.
