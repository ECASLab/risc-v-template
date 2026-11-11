# Informe técnico de cierre FPGA — Kria KV260

## 1. Identificación

- Proyecto: núcleo RISC-V RV64I con interfaz de expansión para aceleradores.
- FPGA: `xck26-sfvc784`.
- Herramienta: Vivado 2024.1.
- Commit del diseño: `8a8e74382ddc6e65908fdf6134c06bdd0b1c44ed`.
- Commit documental: `c5f33c37b35120982f0b5015ab1ce437f7aff525`.

## 2. Objetivo

Consolidar la evidencia de implementación FPGA, cumplimiento temporal y dos demostraciones funcionales sobre hardware.

## 3. Implementación y temporización

| Parámetro | Resultado |
|---|---:|
| Período del reloj | 17.000 ns |
| Frecuencia correspondiente | 58.824 MHz |
| WNS | +1.245 ns |
| TNS | 0.000 ns |
| Errores de enrutamiento | 0 |
| Violaciones DRC | 0 |

La temporización reportada corresponde al diseño implementado y enrutado. El WNS positivo satisface el criterio de setup evaluado en la campaña.

No se presenta la frecuencia del reloj como Fmax experimental ni se afirma una caracterización exhaustiva de todas las condiciones de operación.

### Revisión metodológica de Vivado

El informe independiente `impl_methodology.rpt`
registra la ejecución de `report_methodology`
en Vivado 2024.1 sobre `system_wrapper`, en
estado `Fully Routed`, con **cero violaciones**.

Este resultado es independiente del resumen
metodológico de `final_timing.rpt`. No se ha
demostrado que ambos se produjeran a partir
del mismo checkpoint exacto.

## 4. Utilización de recursos

| Recurso | Utilización |
|---|---:|
| LUT de CLB | 7246 |
| Registros de CLB | 4784 |
| UltraRAM | 32 |
| BRAM tiles | 0 |
| DSP | 0 |

La utilización incluye el sistema FPGA implementado. No debe atribuirse toda esta utilización exclusivamente al núcleo.

## 5. Ejecuciones físicas

| Indicador | Primera | Segunda |
|---|---|---|
| Tamano programa | 776 | 776 |
| Palabras del programa | 97 | 97 |
| Direccion RAM | 0x80000000 | 0x80000000 |
| Palabras cargadas | 97 | 97 |
| RESULT_FLAG | 1 | 1 |
| POLLS | 1 | 1 |
| Resultado | PASS | PASS |

Las dos demostraciones produjeron `RESULT_FLAG=1` y `POLLS=1`.

La segunda ejecución comprobó adicionalmente que CONTROL permaneció en cero al finalizar y que `k26-starter-kits` volvió a quedar activo.

Los registros contienen diferencias textuales; estas no alteran los indicadores funcionales comparados. Las diferencias se conservan en `diferencias_logs.txt`.

## 6. Trazabilidad de criterios

| Criterio | Evidencia | Evaluación |
|---|---|---|
| I4-1 | Bitstream implementado; carga efectiva del firmware RV64I en la KV260 | EVIDENCIA_FAVORABLE |
| I4-2 | WNS=1.245 ns; TNS=0 ns; enrutamiento y DRC sin errores | EVIDENCIA_FAVORABLE |
| I4-3 | Dos demostraciones fisicas PASS; RESULT_FLAG=1; restauracion verificada | EVIDENCIA_FAVORABLE |

La matriz CSV contiene también las limitaciones individuales para su revisión académica.

## 7. Limitaciones

- Solo se realizaron dos demostraciones físicas del programa seleccionado.
- No se midió CPI, rendimiento sostenido ni Fmax experimental.
- La observación térmica se basó en mediciones puntuales.
- No se obtuvo una medición independiente de RPM del ventilador.
- El cierre temporal se interpreta dentro de las restricciones evaluadas por Vivado.
- Las pruebas ACT4 seleccionadas se documentan por separado y no representan certificación arquitectural integral.

## 8. Evidencias primarias

- `docs/verification/fpga/p2_8_5/`: reportes de implementación versionados.
- `C6_20261111_directa/`: registros físicos y auditoría de restauración.
- `C6_2_comparacion_20261111/`: comparación de ambas ejecuciones.
- `C7_1_c5f33c3_20261111/`: auditoría consolidada de los reportes.

## 9. Referencias técnicas

- AMD Vivado UG904, versión 2024.1.
- AMD Vivado UG906, versión 2024.1.
- AMD Kria KV260, documentación de administración de aplicaciones FPGA.
