# Firmware precompilado — Kria KV260

Este directorio documenta los artefactos de referencia
del TFG RV64I para AMD Kria KV260.

[Guía técnica FPGA](../../../docs/fpga-kv260.md).

## Estado de distribución

**Pendiente de autorización institucional.**

Por ahora este directorio contiene solamente
metadatos. No incluye archivos binarios.

Los archivos originales están conservados en
respaldos externos verificados.

## Estructura prevista

```text
kv260/
├── README.md
├── manifest.json
├── firmware/
│   └── tfg-rv64i-kv260/
│       ├── shell.json
│       ├── rv64i_tfg_kv260.bit.bin
│       └── rv64i_tfg_kv260.dtbo
└── software/
    ├── accelerator.bin
    └── rv64i_arm_loader_first_run
```

El directorio firmware contiene el paquete PL_FLAT.
Los programas se mantienen separados del firmware.

## Verificación de integridad

Desde la raíz del repositorio, verificar el manifiesto:

```bash
python3 tools/verify_fpga_prebuilt.py --metadata-only
```

Este modo no requiere los binarios y no acredita su
integridad física.

Para verificar los cinco artefactos de una distribución
completa, ejecutar:

```bash
python3 tools/verify_fpga_prebuilt.py
```

Mientras los archivos estén fuera de Git, puede utilizarse
un directorio externo con la misma estructura:

```bash
python3 tools/verify_fpga_prebuilt.py \
  --artifact-root /ruta/al/paquete
```

Una verificación completa debe terminar con cinco
comprobaciones SHA-256 satisfactorias.

El verificador no instala ni programa el firmware.
Los hashes permiten comprobar integridad respecto
al manifiesto, no sustituyen la autorización de uso.

## Procedencia

Los binarios corresponden a la revisión histórica
8a8e743 y fueron utilizados en la validación FPGA.

El archivo manifest.json conserva sus SHA-256
y tamaños originales.

El commit ce68d46 corresponde a la preparación
del repositorio reutilizable, no a una nueva
compilación de los binarios.

## Reutilización

Las instrucciones de reconstrucción y verificación
se encuentran en la guía técnica FPGA.

No se debe asumir que el bitstream histórico
incorpora modificaciones posteriores del RTL.

## Seguridad

No programar la FPGA sin comprobar el dispositivo,
el reloj, el ventilador, el overlay y los mecanismos
de recuperación.

Esta documentación no autoriza la redistribución,
la instalación ni la programación de la FPGA.
