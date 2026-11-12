# Plataforma FPGA — AMD Kria KV260

Esta guía describe la integración del núcleo RV64I en la
Kria KV260, los archivos disponibles, el flujo de Vivado
y las precauciones para una futura utilización física.

[Volver al README principal](../README.md).

## 1. Arquitectura de la plataforma

La implementación integra:

- Núcleo RISC-V RV64I de cinco etapas.
- Memoria de 1 MiB implementada mediante UltraRAM.
- Interfaz MMIO de expansión y acelerador de demostración.
- Supervisor AXI4-Lite para comunicación desde ARM.
- Procesador Zynq UltraScale+ del módulo Kria K26.
- Conexión de control del ventilador mediante TTC0/EMIO.

El ARM controla la carga y ejecución del programa RV64I.
El programa RV64I se ejecuta en el núcleo RTL implementado
en la lógica programable y utiliza su acelerador MMIO.

El software ARM no sustituye la ejecución del RV64I.

## 2. Hardware y herramientas de referencia

| Elemento | Configuración verificada |
|---|---|
| Tarjeta | AMD Kria KV260 |
| Dispositivo | `xck26-sfvc784-2LV-c` |
| Vivado | 2024.1 |
| Board part | `xilinx.com:kv260_som:part0:1.4` |
| Reloj implementado | 17 ns |
| Frecuencia correspondiente | 58,824 MHz |
| Firmware de referencia | `tfg-rv64i-kv260` |
| Gestor en la Kria histórica | DFX Manager 2023.1 |

Las versiones y referencias anteriores corresponden
a la plataforma estudiada y validada.

No debe suponerse compatibilidad con otras tarjetas,
revisiones, versiones de Vivado o imágenes Linux.

## 3. Mapa de memoria

| Región | Dirección base | Tamaño |
|---|---|---|
| RAM del RV64I | `0x80000000` | 1 MiB |
| Expansión MMIO del RV64I | `0x10000000` | 4 KiB |
| Supervisor AXI visto por ARM | `0xA0000000` | 4 KiB |

La interfaz del supervisor ARM es distinta del
contrato MMIO interno del núcleo.

Consultar la
[guía de expansión](expansion-interface.md).

## 4. Organización de archivos

| Archivo | Función |
|---|---|
| `fpga/kv260/build_ps_pl_bd.tcl` | Construcción PS/PL |
| `fpga/kv260/run_p2_8_1.sh` | Ejecuta y valida el diseño de bloques |
| `fpga/kv260/run_implementation.tcl` | Síntesis e implementación hasta routing |
| `fpga/kv260/verify_fan.tcl` | Revisión del ventilador, timing y DRC |
| `fpga/kv260/kv260_fan.xdc` | Restricciones del ventilador |
| `fpga/kv260/source_wrapper.sha256` | Integridad del wrapper |
| `fpga/deploy/rv64i_tfg_kv260.dts` | Fuente del Device Tree Overlay |
| `fpga/deploy/shell.json` | Descriptor PL_FLAT |
| `sw/host/rv64i_arm_loader.c` | Aplicación de control ARM |
| `sw/baremetal/accelerator/start.S` | Programa ejecutado por RV64I |

Las rutas de esta tabla son relativas a la raíz
del repositorio.

Los scripts `run_integrated.sh` y `run_axi_soc.sh`
permiten realizar comprobaciones adicionales
de simulación y síntesis fuera de contexto.

## 5. Desarrollo sin utilizar la FPGA física

El trabajo con Vivado debe realizarse en un equipo
con las herramientas AMD y los archivos de placa
compatibles.

El servidor de referencia del TFG utilizó Vivado
2024.1. Las regresiones locales independientes
se realizaron en Ubuntu.

El primer paso de integración disponible es:

`fpga/kv260/run_p2_8_1.sh`

Este script comprueba la integridad del repositorio,
la ascendencia del commit de referencia, el wrapper
y la disponibilidad de Vivado.

Después crea un proyecto aislado y valida el
diseño de bloques mediante `build_ps_pl_bd.tcl`.

El resultado esperado incluye:

- `P2_8_1_BD_VALIDATED`
- `P2_8_1_NO_BITSTREAM`
- Un directorio de proyecto Vivado.
- Un archivo `bd_summary.txt`.

El script exige un árbol Git limpio. No debe
ejecutarse desde una rama con modificaciones
pendientes.

El directorio de ejecuciones puede configurarse
mediante la variable `TFG_FPGA_RUNS_DIR`.

La adaptación de portabilidad fue validada en
Vivado 2024.1 desde un clon independiente en la
campaña D.6.8 (12 de noviembre de 2026).
La reconstrucción alcanzó síntesis y routing,
con WNS de +1,245 ns, WHS de +0,012 ns,
cero violaciones DRC y cero de metodología.
No se generó un nuevo bitstream ni se realizó
otra prueba física.

Consultar las [evidencias de reconstrucción](verification/fpga/reconstruccion_kv260_20261112_86a15be/README.md).

## 6. Síntesis e implementación

El repositorio contiene:

`fpga/kv260/run_implementation.tcl`

Este script necesita la variable de entorno
`TFG_XPR`, que identifica el proyecto Vivado
creado previamente.

El procedimiento:

1. Abre el proyecto Vivado.
2. Genera el wrapper del diseño de bloques.
3. Ejecuta síntesis.
4. Ejecuta implementación hasta routing.
5. Genera reportes de utilización, temporización,
   DRC, enrutamiento y metodología.

El Tcl termina sin ejecutar `write_bitstream`.

Por tanto, este script NO genera automáticamente
el bitstream de distribución.

La creación del bitstream, exportación XSA,
conversión a `.bit.bin` y compilación del DTBO
requieren documentar y validar el flujo integral
antes de anunciar una reconstrucción completa
desde un clon limpio.

Los resultados históricos y reportes originales
se conservan para trazabilidad.

## 7. Resultados históricos de implementación

La implementación aprobada registró:

| Indicador | Resultado |
|---|---:|
| Período | 17,000 ns |
| Frecuencia | 58,824 MHz |
| WNS | +1,245 ns |
| TNS | 0 ns |
| LUT de CLB | 7246 |
| Registros de CLB | 4784 |
| UltraRAM | 32 |
| BRAM | 0 |
| DSP | 0 |
| Errores finales de routing | 0 |
| Violaciones DRC | 0 |

Los recursos representan el sistema FPGA
integrado, no únicamente el procesador.

Estos valores corresponden a la implementación
histórica aprobada. No representan una medición
experimental de Fmax ni una nueva construcción
desde el commit de entrega.

Consultar el
[informe técnico FPGA](verification/fpga/cierre_kv260_20261111/INFORME_CIERRE_FPGA.md).

## 8. Firmware de referencia PL_FLAT

El paquete de firmware utiliza tres componentes:

- `rv64i_tfg_kv260.bit.bin`
- `rv64i_tfg_kv260.dtbo`
- `shell.json`

DFX Manager puede reconocer diseños estáticos
PL_FLAT a partir de estos archivos.

El software RV64I `accelerator.bin` y el cargador
ARM64 se distribuyen separadamente de los tres
archivos requeridos por el gestor.

Los binarios fueron localizados y comprobados
mediante SHA-256 en los respaldos históricos.

Su incorporación al repositorio de distribución
está pendiente de preparación y autorización.

Consultar el
[inventario de artefactos](verification/fpga/cierre_kv260_20261111/ARTEFACTOS_EXTERNOS.md).

No se debe reconstruir el firmware original
del laboratorio a partir de archivos no autorizados
ni publicarlo automáticamente.

## 9. Precauciones para utilizar la Kria

La programación física requiere una revisión
independiente y autorización para usar la tarjeta.

Antes de cargar un diseño, verificar:

1. Modelo y dispositivo FPGA exactos.
2. Compatibilidad de bitstream y Device Tree.
3. SHA-256 de los archivos de firmware.
4. Disponibilidad y estado de DFX Manager.
5. Estado del firmware actualmente cargado.
6. Reloj PL0 y su configuración.
7. Control del ventilador, sensores y temperatura.
8. Procedimiento de recuperación del diseño original.
9. Disponibilidad de los mecanismos de acceso y
   recuperación autorizados por el laboratorio.

El ventilador de la KV260 depende de una
conexión a través de la lógica programable.

El diseño validado conserva la ruta TTC0/EMIO
hasta `fan_en_b`, asignada al pin A12 con
estándar LVCMOS33.

No se obtuvo una medición independiente de RPM.

Un nuevo bitstream debe volver a verificar esta
ruta y sus restricciones antes de programarse.

**Esta guía no autoriza programar la FPGA.**

No modificar QSPI, U-Boot, firmware de arranque,
configuraciones persistentes o `default_firmware`
como parte de las pruebas ordinarias.

## 10. Aplicación ARM64

El código fuente se encuentra en:

`sw/host/rv64i_arm_loader.c`

La aplicación permite comprobar una imagen
bare-metal sin acceder al hardware y dispone
de un modo de ejecución física protegido
mediante confirmaciones explícitas.

La ejecución real utiliza accesos privilegiados
a registros AXI y memoria.

No ejecutar el modo `--execute` sin confirmar
previamente todos los requisitos de hardware,
seguridad y recuperación.

Una transacción hacia un esclavo AXI ausente
o sin reloj podría bloquear el proceso.

Consultar la
[documentación del cargador](../sw/host/README_P2_9_3.md).

## 11. Evidencias de validación física

Se registraron dos ejecuciones satisfactorias
del programa de demostración sobre la KV260.

En ambas:

- `RESULT_FLAG=1`
- `POLLS=1`
- Resultado PASS

La segunda campaña verificó adicionalmente
la restauración de `k26-starter-kits`.

Esto respalda la operación del núcleo RV64I y
su interacción con el acelerador seleccionado.

No demuestra una validación exhaustiva de todos
los aceleradores, del rendimiento del procesador
ni de todas las configuraciones de la FPGA.

Consultar el
[cierre de validación física](verification/fpga/cierre_kv260_20261111/README.md).

## 12. Ampliación de la plataforma

Para integrar un acelerador nuevo:

1. Mantener inicialmente el contrato MMIO `exp_*`.
2. Implementar un nuevo periférico RTL.
3. Adaptar el software bare-metal.
4. Crear pruebas dirigidas y ejecutar regresiones.
5. Actualizar las fuentes de integración FPGA.
6. Reconstruir el diseño y verificar timing,
   recursos, DRC y ventilación.
7. Generar y auditar un nuevo paquete de firmware.
8. Programar la FPGA solo mediante el
   procedimiento autorizado.

El bitstream histórico no incorpora cambios
posteriores del RTL.

## 13. Referencias externas

- AMD DFX Manager:
  https://github.com/Xilinx/dfx-mgr
- AMD Vivado UG835, versión 2024.1:
  https://docs.amd.com/r/2024.1-English/ug835-vivado-tcl-commands
- AMD Kria KV260, UG1089:
  https://docs.amd.com/r/en-US/ug1089-kv260-starter-kit

Las condiciones específicas y los resultados
numéricos de este TFG proceden del repositorio
y las evidencias históricas del proyecto.
