# Especificación técnica de la plataforma RISC-V RV64I

**Proyecto:** Desarrollo y verificación de un núcleo RISC-V RV64I con interfaz de expansión para aceleradores en FPGA\
**Institución:** Tecnológico de Costa Rica — Escuela de Ingeniería Electrónica / ECASLab\
**Fecha de consolidación:** 21 de noviembre de 2026\
**Línea base técnica consultada:** `main`, commit `ba29e036df4416f0cb99acfe3701b95fbb02dc18`\
**Publicación previa del proyecto:** [`v1.0.0`](https://github.com/ECASLab/risc-v-template/releases/tag/v1.0.0), commit `73694be98c44cbf6d6e4db182fc52521cb0218e2`

> **Naturaleza del documento.** Esta especificación consolida los requerimientos, contratos y criterios que figuran en el Capítulo 3 del informe final y en los archivos de la plataforma. No sustituye esas fuentes ni afirma haber existido antes de las campañas de verificación. La revisión documental 0.1 no es una nueva versión del RTL, del bitstream ni de la publicación GitHub.

## 1. Propósito, destinatarios y fuentes de verdad

La plataforma proporciona una base académica para estudiar un núcleo RV64I segmentado, ejecutar software *bare-metal* y conectar aceleradores mediante entrada/salida mapeada en memoria (MMIO). Está orientada a estudiantes e investigadores que deseen inspeccionar el RTL, reproducir los procedimientos documentados o desarrollar periféricos compatibles.

Ante discrepancias, debe distinguirse entre: (a) el comportamiento de la revisión RTL consultada, (b) las condiciones de cada campaña histórica y (c) los resultados que efectivamente se midieron. El informe final es la referencia académica de alcance y objetivos; el RTL y los scripts versionados constituyen la referencia técnica de la implementación; los logs, manifiestos y reportes originales sustentan las afirmaciones de verificación.

Documentación complementaria:

- [Inicio e instalación](getting-started.md).
- [Contrato de expansión y guía para nuevos aceleradores](expansion-interface.md).
- [Integración y utilización en FPGA KV260](fpga-kv260.md).
- [Reconstrucción y empaquetado FPGA](rebuild-kv260-firmware.md).
- [Evidencias ACT4 y advertencias](../verification/act4/README.md).
- [Cierre de demostraciones físicas](verification/fpga/cierre_kv260_20261111/README.md).
- [Notas de publicación](release-notes.md) y [condiciones de distribución](release-readiness.md).

## 2. Delimitación del sistema

| Elemento | Configuración documentada |
|---|---|
| ISA objetivo | RISC-V RV64I (XLEN=64), instrucciones base de 32 bits |
| Núcleo | Pipeline IF–ID–EX–MEM–WB, en orden, emisión máxima de una instrucción por ciclo |
| Privilegios | Subconjunto de M-mode, CSR y traps necesario para el alcance *bare-metal* |
| Memoria | Puertos IMEM y DMEM independientes, con solicitud, aceptación y respuesta |
| Expansión | Puerto propio MMIO `exp_*` para cargas y almacenamientos |
| Ejemplo | Acelerador de suma de dos operandos de 64 bits |
| Plataforma física | AMD Kria KV260/K26; ARM de supervisión, UltraRAM y RV64I en lógica programable |
| Herramienta de implementación de referencia | AMD Vivado 2024.1 |

**Fuera del alcance obligatorio:** extensiones M, A y C; MMU y memoria virtual; cachés complejas; ejecución fuera de orden o especulativa; sistema operativo de propósito general; flujo ASIC; certificación integral de conformidad RISC-V. El adaptador de expansión a AXI4-Lite es complementario: no redefine el contrato `exp_*` ni debe confundirse con el supervisor AXI4-Lite utilizado desde ARM.

## 3. Requerimientos técnicos de referencia

Los identificadores `REQ-*` se introducen **solo para trazabilidad documental**. No designan nuevas funcionalidades, nuevos criterios ni pruebas adicionales. El criterio de aceptación de cada grupo se detalla en la sección 7.

| ID | Requerimiento consolidado | Elemento de implementación / referencia |
|---|---|---|
| REQ-ISA-01 | Ejecutar las instrucciones incluidas en la base RV64I declarada para el proyecto y preservar el estado arquitectural observable por el software. | [`core_top.sv`](../rtl/core/core_top.sv), [`decoder.sv`](../rtl/core/decoder.sv) |
| REQ-MIC-01 | Utilizar un pipeline de cinco etapas IF, ID, EX, MEM y WB, con ejecución en orden y emisión máxima de una instrucción por ciclo. | [`core_top.sv`](../rtl/core/core_top.sv), registros de pipeline en `rtl/core/` |
| REQ-MIC-02 | Resolver dependencias y redirecciones mediante forwarding, stalls, burbujas y flush cuando corresponda; preservar el orden de los efectos arquitecturales. | [`hazard_unit.sv`](../rtl/core/hazard_unit.sv), `core_top.sv` |
| REQ-PRV-01 | Incorporar el subconjunto requerido de M-mode, CSR y manejo de traps, con estado preciso incluso ante esperas de memoria. | [`csr_file.sv`](../rtl/core/csr_file.sv), `core_top.sv` |
| REQ-MEM-01 | Ofrecer IMEM con solicitud, aceptación y respuesta separadas; permitir latencia y un máximo de una solicitud pendiente de respuesta. | [`imem_handshake_ctrl.sv`](../rtl/core/imem_handshake_ctrl.sv) |
| REQ-MEM-02 | Ofrecer DMEM para cargas y almacenamientos, con byte enables, tamaño, espera, respuesta y señalización de error; un máximo de una transacción pendiente. | [`dmem_handshake_ctrl.sv`](../rtl/core/dmem_handshake_ctrl.sv) |
| REQ-EXP-01 | Direccionar una ventana MMIO independiente de RAM y permitir lecturas, escrituras, esperas y errores mediante `exp_*`, sin ampliar la ISA. | [`core_top.sv`](../rtl/core/core_top.sv), [contrato](expansion-interface.md) |
| REQ-ACC-01 | Integrar un periférico de demostración controlable mediante software *bare-metal* y capaz de devolver un resultado verificable. | [`expansion_demo_periph.sv`](../rtl/core/expansion_demo_periph.sv), [`sw/baremetal/accelerator/`](../sw/baremetal/accelerator/) |
| REQ-VER-01 | Mantener pruebas dirigidas, regresión automatizada, lint, ejecución *bare-metal*, pruebas arquitecturales aplicables y trazabilidad de resultados por revisión. | [`Makefile`](../Makefile), [`tb/`](../tb/), [`verification/act4/`](../verification/act4/) |
| REQ-FPG-01 | Sintetizar e implementar la plataforma en una FPGA, generar bitstream y reportes de recursos y temporización, y demostrar el núcleo y acelerador en placa. | [`fpga/kv260/`](../fpga/kv260/), [documentación KV260](fpga-kv260.md) |

## 4. Mapa de direcciones y arranque

| Recurso | Dirección base | Límite superior | Tamaño / significado |
|---|---|---|---|
| Expansión MMIO RV64I | `0x10000000` | `0x10000FFF` | Ventana de 4 KiB |
| Programa y datos RV64I | `0x80000000` | `0x800FFFFF` | Región lógica de 1 MiB |
| Reset PC | `0x80000000` | — | Primera dirección de búsqueda en la configuración de plataforma |
| Vector inicial de traps | `0x80000100` | — | Dirección situada dentro de la región de RAM |
| Supervisor AXI4-Lite visto desde ARM | `0xA0000000` | `0xA0000FFF` | Ventana de 4 KiB en la integración FPGA |

Las interfaces de instrucciones y datos están separadas físicamente, pero no definen espacios de direcciones independientes para el software. El flujo *bare-metal* enlaza una imagen para la región de RAM y la transforma en las representaciones requeridas por sus memorias.

**Advertencia de parametrización:** el parámetro predeterminado histórico `EXP_BASE` en `rtl/core/core_top.sv` es `0x80000000`. La integración de referencia en [`rv64i_platform_top.sv`](../rtl/platform/rv64i_platform_top.sv) lo sobrescribe explícitamente con `0x10000000` y usa `EXP_MASK=0xFFFFFFFFFFFFF000`. Una integración nueva debe definir expresamente su mapa sin solapamientos.

El núcleo presenta accesos de datos no MMIO al subsistema DMEM; la validación del intervalo implementado y la comunicación de errores dependen del dispositivo de memoria conectado. El intervalo de 1 MiB no es una RAM interna del núcleo.

## 5. Contratos de comunicación

### 5.1 Memoria de instrucciones (IMEM)

- Solicitud: `imem_req`, `imem_addr[63:0]`; aceptación cuando `imem_req && imem_gnt`.
- Respuesta posterior: `imem_rvalid`, `imem_rdata[31:0]`.
- Máximo una transacción pendiente de respuesta. La solicitud/dirección se conservan hasta aceptación.
- **Limitación confirmada:** el puerto IMEM no tiene `imem_error`; un error externo de búsqueda de instrucciones no se transforma mediante este puerto en un trap de *instruction access fault*. No confundirlo con la detección interna de destinos desalineados.

### 5.2 Memoria de datos (DMEM)

- Solicitud y aceptación: `dmem_req`, `dmem_gnt`, `dmem_addr[63:0]`, `dmem_we`, `dmem_wdata[63:0]`, `dmem_wstrb[7:0]`, `dmem_size[1:0]`.
- Respuesta posterior requerida **tanto para loads como stores**: `dmem_rvalid`; `dmem_rdata[63:0]` es significativo para cargas correctas; `dmem_error` es significativo al afirmar `dmem_rvalid`.
- Máximo una transacción pendiente; no se permite completar la respuesta en el mismo ciclo de aceptación. Se admiten esperas y errores reportados por la memoria externa.

### 5.3 Puerto de expansión (`exp_*`)

- Salidas: `exp_valid`, `exp_we`, `exp_addr[63:0]`, `exp_wdata[63:0]`, `exp_wstrb[7:0]`, `exp_size[1:0]`.
- Entradas: `exp_ready`, `exp_rdata[63:0]`, `exp_error`.
- `exp_ready` señala **finalización de la operación**, no una concesión independiente como `imem_gnt` o `dmem_gnt`. Un periférico puede introducir espera manteniendo la operación pendiente.
- `exp_size`: `00`=8 bits, `01`=16 bits, `10`=32 bits, `11`=64 bits; `exp_wstrb` identifica los bytes habilitados.
- Un `exp_error` al finalizar un acceso se propaga como fallo de acceso de carga o almacenamiento, según la operación. Un periférico nuevo debe evitar efectos repetidos mientras se mantiene presentada una solicitud.

El detalle de registro, temporización y sustitución del periférico se encuentra en la [guía de expansión](expansion-interface.md). Este protocolo es propio del proyecto, no un estándar de la ISA RISC-V ni una interfaz AXI4-Lite nativa.

## 6. Acelerador y plataforma FPGA de referencia

### 6.1 Periférico de demostración

El periférico suma dos operandos de 64 bits. Los desplazamientos de sus registros, relativos a `0x10000000`, son:

| Offset | Registro | Descripción |
|---|---|---|
| `0x00` | `ID` | Identificación, solo lectura |
| `0x08` | `VERSION` | Versión, solo lectura |
| `0x10` | `CONTROL` | Inicio (`bit 0`) y limpieza de `done` (`bit 1`) |
| `0x18` | `STATUS` | `busy` (`bit 0`), `done` (`bit 1`, limpieza W1C), `error` (`bit 2`) |
| `0x20` | `OPERAND_A` | Primer operando |
| `0x28` | `OPERAND_B` | Segundo operando |
| `0x30` | `RESULT` | Resultado, solo lectura |

La implementación de demostración responde con `exp_ready=1`, completa la suma sin un procesamiento multiciclo y mantiene `busy` y `error` en cero; **no acredita** la operación de un acelerador multiciclo arbitrario. La demostración *bare-metal* espera `0x11223344556677AA`; el resultado es una comprobación funcional, no un benchmark de rendimiento.

### 6.2 Integración KV260

La implementación de referencia conecta el ARM del sistema de procesamiento (PS) a un **supervisor AXI4-Lite** en la lógica programable (PL). El supervisor carga y controla la memoria UltraRAM de 1 MiB y el arranque del RV64I; el programa ejecutado por el RV64I accede al acelerador por el puerto MMIO `exp_*`. El supervisor AXI4-Lite del ARM **no** es el adaptador opcional AXI4-Lite de la interfaz de expansión.

La referencia física utiliza Kria KV260, dispositivo `xck26-sfvc784-2LV-c` y Vivado 2024.1. Se documentó una implementación enrutada con período de 17 ns (58,824 MHz), WNS de setup `+1,245 ns` y 32 bloques UltraRAM; dichos valores corresponden a la plataforma integrada y no son mediciones de Fmáx, CPI o latencia del acelerador. La carga física exige revisar el ventilador, el árbol de dispositivos y el procedimiento de recuperación. Véase la [guía FPGA](fpga-kv260.md).

## 7. Criterios de aceptación y trazabilidad histórica

La siguiente matriz **referencia resultados ya documentados**. No ordena ejecutar nuevas pruebas ni traslada sus resultados automáticamente a otro commit.

| Objetivo / criterio del anteproyecto | Criterio consolidado | Evidencia histórica identificada |
|---|---|---|
| OE1 / I1-1 | Requerimientos, microarquitectura, modo máquina, interfaces, mapa, criterios y FPGA documentados. | Capítulo 3 del informe final; este documento los consolida retrospectivamente y enlaza al RTL. |
| OE2 / I2-1, I2-2, I2-3 | Núcleo, mecanismos privilegiados, puerto de expansión y acelerador de ejemplo implementados. | Fuentes `rtl/core/` y `rtl/platform/`; pruebas dirigidas y programa *bare-metal* descritos en el informe. |
| OE3 / I3-1 | Regresión funcional obligatoria sin pruebas fallidas y análisis estático. | Campaña documentada de 35/35 pruebas dirigidas PASS y resultados de lint del informe final; no se afirma una ejecución nueva. |
| OE3 / I3-2 | Conjunto arquitectural RV64I seleccionado sin FAIL. | [ACT4 histórico](../verification/act4/README.md): 51/51 PASS; repetición documentada sobre `8a8e743` en [evidencias ACT4](verification/act4/reproduccion_51_8a8e743_20261110/README.md). |
| OE3 / I3-3 | Resultados relacionables con revisión, configuración y logs. | Auditorías ACT4, reportes de regresión y documentación de campañas identificadas por commit. |
| OE4 / I4-1, I4-2 | Síntesis, implementación, bitstream e informes; para la configuración evaluada, WNS mayor o igual que cero. | [Cierre FPGA](verification/fpga/cierre_kv260_20261111/README.md): 17 ns, WNS `+1,245 ns`, Vivado 2024.1. |
| OE4 / I4-3 | Ejecución del RV64I y uso del acelerador en la FPGA. | Dos demostraciones físicas PASS del firmware histórico, según [cierre KV260](verification/fpga/cierre_kv260_20261111/README.md). |
| IG-1, IG-2, IG-3 | Evaluación global de funcionalidad, arquitectura seleccionada y reproducción de implementación. | Conjunto de evidencias precedentes, interpretadas según sus alcances y limitaciones. |

**Historial de referencias importantes:** campaña ACT4 histórica `cf78be1`; repetición ACT4 y demostraciones físicas `8a8e743`; comprobaciones *bare-metal* desde clon `c5f33c3`; reconstrucción del diseño FPGA hasta reportes `86a15be`; publicación `v1.0.0` en `73694be`; limpieza posterior `ba29e03`. Un identificador de campaña describe **la revisión que se evaluó**; no identifica automáticamente la revisión más reciente del repositorio.

En la Release `v1.0.0` se distinguen el firmware histórico utilizado en las demostraciones físicas y el firmware reconstruido y empaquetado posteriormente. **El firmware reconstruido no recibió una nueva prueba en la placa.** Sus hashes y los del firmware histórico no son idénticos.

## 8. Limitaciones y reglas de reutilización

1. Los 51 casos ACT4 seleccionados no constituyen una certificación oficial ni cobertura completa del ISA o de toda la arquitectura privilegiada. El ejecutor ACT4 histórico no es un target universal `make act4` listo para cualquier instalación; la configuración ACT4 conserva advertencias propias documentadas en su README.
2. No existe señal externa `imem_error`; los ensayos de dirección inválida en el modelo de instrucciones no acreditan un trap de *instruction access fault* originado externamente.
3. El periférico de suma no modela un acelerador de latencia variable y no permite afirmar rendimiento, CPI ni Fmáx medidos en placa.
4. Cambios futuros en RTL, mapa de direcciones, periférico, firmware o condiciones físicas requieren evaluación propia; las evidencias históricas no certifican automáticamente nuevas variantes.
5. La publicación pública no sustituye una decisión institucional sobre titularidad, licencia y permisos de redistribución, incluidos componentes de terceros y firmware. Consulte [estado de distribución](release-readiness.md).

## 9. Guía de mantenimiento documental

Cuando se modifique el diseño, actualizar en el mismo cambio: requerimiento afectado, contratos y direcciones, rutas de implementación, prueba o evidencia aplicable y limitaciones. No alterar ni atribuir retroactivamente resultados a commits distintos de aquellos que aparecen en los registros originales. Una nueva revisión de esta especificación no debe modificar la etiqueta Git `v1.0.0` existente.

## 10. Referencias normativas y de proyecto

- RISC-V International, [RV64I Base Integer Instruction Set, versión 2.1](https://docs.riscv.org/reference/isa/unpriv/rv64.html). La conformidad exigible se limita a la configuración y pruebas declaradas para este proyecto.
- RISC-V International, [documentación general de las especificaciones ISA y privilegiada](https://docs.riscv.org/).
- TEC, *Informe de TFG*, Capítulo 3: metodología, requerimientos, mapa de memoria, interfaces y criterios; capítulos 4–7: implementación y resultados; Apéndice A: trazabilidad histórica.
- TEC, *Anteproyecto actualizado*, sección 3.1.8: criterios IG e I1–I4.
- Fuentes y evidencias versionadas enlazadas en las secciones precedentes.
