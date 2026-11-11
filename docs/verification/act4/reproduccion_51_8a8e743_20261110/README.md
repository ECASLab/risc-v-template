# Reproducción ACT4 — 51 casos RV64I

Campaña de reproducción del 10 de noviembre de 2026.

## Identificación

- Núcleo: `8a8e74382ddc6e65908fdf6134c06bdd0b1c44ed`
- Rama: `fpga/platform-uram`
- ACT4: `d6094ad3ede5268b454197e7bb8eb1cbcbe140d0`
- Casos ejecutados: 51
- PASS: 51
- FAIL: 0
- Diferencias de métricas históricas: 0

## Contenido

- `INFORME_CIERRE_ACT4.md`: informe técnico.
- `resultados_51_actuales.csv`: métricas individuales.
- `resumen.json`: resumen de la auditoría.
- `SHA256SUMS.txt`: hashes de estos documentos.

## Evidencia externa

Los registros completos, imágenes y paquetes de
simulación están conservados en los directorios
`B6_8a8e743` a `B14_8a8e743` dentro de
`tfg_evidencias_locales`.

Las rutas de paquetes en el CSV son relativas a
dicho directorio. Para consultar o volver a verificar
los paquetes es necesario disponer de esas evidencias.

El CSV versionado normaliza las rutas del CSV original;
los datos de resultados y hashes de paquetes se conservan.

## Alcance

Estos resultados corresponden a 51 pruebas ACT4
seleccionadas para RV64I. No constituyen una
certificación completa de conformidad RISC-V.

Las pruebas privilegiadas permanecen desactivadas.
Las limitaciones de UDB, Sail y memoria física
se documentan en el informe técnico.
