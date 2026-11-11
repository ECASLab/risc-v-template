# Revisión de restricciones temporales — KV260

## Identificación

- Vivado 2024.1.
- Diseño: `system_wrapper`.
- Dispositivo: `xck26-sfvc784`.
- Estado: `Routed`.
- Fuente: `docs/verification/fpga/p2_8_5/final_timing.rpt`.

## Resultados temporales

| Indicador | Resultado |
|---|---:|
| Período clk_pl_0 | 17,000 ns |
| Frecuencia clk_pl_0 | 58,824 MHz |
| WNS | +1,245 ns |
| TNS | 0,000 ns |
| WHS | +0,012 ns |
| THS | 0,000 ns |
| WPWS | +7,000 ns |
| TPWS | 0,000 ns |

## Comprobaciones de restricciones

El reporte se generó utilizando
`report_timing_summary -report_unconstrained`.

Las doce categorías de `check_timing` presentan
cero incidencias:

- no_clock
- constant_clock
- pulse_width_clock
- unconstrained_internal_endpoints
- no_input_delay
- no_output_delay
- multiple_clock
- generated_clocks
- loops
- partial_input_delay
- partial_output_delay
- latch_loops

La sección `Unconstrained Path Table` no presenta
entradas.

El reporte contiene una sección de rutas ignoradas
por el usuario, diferente de la sección de rutas
sin restricciones.

## Alcance y limitaciones

Los resultados respaldan el cumplimiento de las
restricciones temporales evaluadas para el diseño
implementado y completamente enrutado.

Se conserva un informe independiente de
`report_methodology`, generado con Vivado 2024.1
sobre `system_wrapper` en estado `Fully Routed`.
El resultado registra **cero violaciones**.

Fuente: `docs/verification/fpga/p2_8_5/impl_methodology.rpt`.

El resumen de metodología de `final_timing.rpt`
indica que no había un informe metodológico
previo disponible para ese resumen. Esto no
contradice la existencia del reporte independiente.
No se acredita que ambos reportes procedan
del mismo checkpoint exacto.

La frecuencia del reloj no representa una medición
experimental de Fmax ni del rendimiento del RV64I.

## Referencias

- AMD Vivado UG906, versión 2024.1.
- AMD Vivado UG949, versión 2024.1.
- AMD Vivado UG835, versión 2024.1.
