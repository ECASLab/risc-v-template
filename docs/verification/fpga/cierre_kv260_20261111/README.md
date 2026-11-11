# Cierre de implementación FPGA — Kria KV260

## Identificación

- Fecha de segunda campaña: 11 de noviembre de 2026.
- Diseño RTL: commit `8a8e743`.
- Referencia documental previa: commit `c5f33c3`.
- Plataforma: Kria KV260.
- Firmware del TFG: `tfg-rv64i-kv260`.
- Firmware original: `k26-starter-kits`.

## Resultados

Se registraron dos demostraciones físicas
satisfactorias del programa seleccionado:

- Primera ejecución: `RESULT_FLAG=1`.
- Segunda ejecución: `RESULT_FLAG=1`.
- Ambas registraron `POLLS=1`.
- La segunda verificó `CONTROL=0` al finalizar.
- El firmware original fue restaurado al slot 0.
- Los servicios DFX y fancontrol se verificaron
  activos después de la restauración.

El diseño implementado presentó WNS=+1,245 ns,
TNS=0 ns y cero errores finales de enrutamiento
y violaciones DRC reportadas.

## Archivos

- `INFORME_CIERRE_FPGA.md`: informe técnico.
- `matriz_criterios_I4.csv`: trazabilidad.
- `resumen_fpga.json`: métricas de implementación.
- `comparacion_ejecuciones.csv`: dos demostraciones.
- `diferencias_logs.txt`: diferencias textuales.
- `REVISION_TEMPORAL.md`: análisis de restricciones.
- `SHA256SUMS.txt`: integridad documental.

## Evidencias originales

Los reportes de Vivado se encuentran en
`docs/verification/fpga/p2_8_5/`.

Las evidencias físicas completas se conservan
externamente en:

- `C6_20261111_directa`
- `C6_2_comparacion_20261111`
- `C7_1_c5f33c3_20261111`
- `C7_2_c5f33c3_20261111`

Los paquetes y bitstreams completos no se
incorporan al repositorio.

## Limitaciones

- Dos demostraciones físicas de un programa.
- No se midió CPI ni Fmax experimental.
- `report_methodology` se ejecutó por separado
  sobre el diseño enrutado: cero violaciones.
  No se acreditó identidad exacta de checkpoint
  con el resumen final de temporización.
- No se midieron RPM de manera independiente.
- No se acreditó una prueba funcional exhaustiva
  del overlay del firmware original.
- El conjunto ACT4 seleccionado se documenta
  por separado.

Este cierre no constituye una certificación
arquitectural integral.

## Reproducibilidad y artefactos externos

- `ARTEFACTOS_EXTERNOS.md`: inventario de respaldos, firmware, hashes y límites de entrega.
- `REPRODUCIBILIDAD_CLON.md`: reconstrucción local comprobada desde GitHub.
