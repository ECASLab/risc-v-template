# Interfaz de expansión para aceleradores

Esta guía describe el contrato MMIO del núcleo RV64I,
el acelerador de demostración implementado y los puntos
de integración para desarrollos posteriores.

[Volver al README principal](../README.md).

## 1. Alcance

El núcleo RV64I dispone de un puerto de expansión
mapeado en memoria, independiente de las interfaces
de memoria de instrucciones y datos.

El contrato está implementado en:

- `rtl/core/core_top.sv`

El periférico de demostración está implementado en:

- `rtl/core/expansion_demo_periph.sv`

La integración FPGA de referencia se encuentra en:

- `rtl/platform/rv64i_platform_top.sv`

No es necesario modificar la ISA ni crear
instrucciones nuevas para acceder al acelerador.
El software utiliza instrucciones de carga y
almacenamiento de RV64I.

## 2. Mapa de direcciones

En la plataforma FPGA de referencia:

| Región | Dirección base | Tamaño |
|---|---|---|
| Expansión MMIO | `0x10000000` | 4 KiB |
| RAM RV64I | `0x80000000` | 1 MiB |
| Supervisor ARM/AXI | `0xA0000000` | 4 KiB |

La región de expansión es accesible desde el RV64I.

El supervisor AXI4-Lite permite al procesador ARM
controlar la ejecución y acceder al mecanismo BOOT
de la plataforma, pero no reemplaza el puerto MMIO
del acelerador.

**Atención a los parámetros del núcleo:**

`core_top.sv` tiene un valor predeterminado histórico
de `EXP_BASE=0x80000000`.

`rv64i_platform_top.sv` sobrescribe explícitamente
este parámetro con `EXP_BASE=0x10000000` y utiliza
`EXP_MASK=0xFFFFFFFFFFFFF000`.

Los nuevos sistemas deben configurar la región de
expansión sin solaparla con la memoria RAM.

Algunos testbenches dirigidos usan otras direcciones
base y las configuran explícitamente para sus ensayos.

## 3. Señales del puerto de expansión

| Señal | Dirección desde core | Función |
|---|---|---|
| `exp_valid` | Salida | Acceso MMIO válido |
| `exp_we` | Salida | 1: escritura, 0: lectura |
| `exp_addr` | Salida, 64 bits | Dirección completa |
| `exp_wdata` | Salida, 64 bits | Datos de escritura |
| `exp_wstrb` | Salida, 8 bits | Habilitación por byte |
| `exp_size` | Salida, 2 bits | Tamaño de acceso |
| `exp_ready` | Entrada | Operación completada |
| `exp_rdata` | Entrada, 64 bits | Datos de lectura |
| `exp_error` | Entrada | Error de acceso |

Codificación de `exp_size`:

| Valor | Tamaño |
|---|---|
| `00` | 8 bits |
| `01` | 16 bits |
| `10` | 32 bits |
| `11` | 64 bits |

Para una escritura de 64 bits alineada,
`exp_wstrb` normalmente contiene `8'hFF`.

El dato de escritura se presenta alineado por
byte lane. Los accesos parciales requieren
respetar las habilitaciones correspondientes.

## 4. Protocolo de comunicación

El núcleo decodifica la dirección en la etapa MEM.

Cuando una carga o almacenamiento válido pertenece
a la región de expansión, activa `exp_valid`.

El periférico recibe dirección, operación,
tamaño y datos correspondientes.

`exp_ready` indica que la transacción ha terminado.
No es una señal de concesión independiente.

Mientras una operación de expansión permanezca
sin completar, el núcleo puede detener el pipeline
mediante su control de espera en MEM.

En una respuesta de lectura completada,
`exp_rdata` contiene el dato correspondiente.

Si el periférico indica `exp_error` junto con
la finalización, el núcleo transforma el fallo
en una excepción de acceso.

Un periférico nuevo con latencia variable debe
evitar ejecutar varias veces una operación mientras
la solicitud permanece presentada.

El contrato debe comprobarse con simulaciones
que incluyan esperas y respuestas de error.

## 5. Acelerador de demostración

El periférico de referencia realiza una suma
de dos operandos de 64 bits.

Su mapa de registros utiliza desplazamientos
respecto a la base de expansión:

| Offset | Registro | Función |
|---|---|---|
| `0x00` | ID | Identificación, solo lectura |
| `0x08` | VERSION | Versión, solo lectura |
| `0x10` | CONTROL | Inicio y limpieza |
| `0x18` | STATUS | Estado |
| `0x20` | OPERAND_A | Primer operando |
| `0x28` | OPERAND_B | Segundo operando |
| `0x30` | RESULT | Resultado, solo lectura |

Los registros se organizan como palabras de
64 bits con desplazamientos múltiplos de 8.

`CONTROL[0]` inicia la suma.
`CONTROL[1]` permite limpiar el indicador done.

Los bits de control utilizados para comandos
se autolimpian después de la escritura.

`STATUS[0]` representa busy.
`STATUS[1]` representa done.
`STATUS[2]` está reservado para error.

En esta implementación de demostración,
busy y el bit de estado error permanecen en cero.
La operación de suma se completa sin una fase
de procesamiento de múltiples ciclos.

`STATUS[1]` permite limpieza mediante
escritura de uno (W1C), respetando el byte enable.

Los registros ID, VERSION y RESULT son
de solo lectura.

Los accesos a registros desconocidos y las
escrituras no permitidas reportan `exp_error`.

El periférico de referencia mantiene
`exp_ready=1` y presenta datos de lectura
mediante lógica combinacional.

Esta implementación sirve como ejemplo inicial;
no representa por sí misma un acelerador
multiciclo con gestión de busy.

### Precisión sobre tamaños y alineación

El periférico de demostración agrupa las direcciones
en registros de 64 bits utilizando `exp_addr_i[11:3]`.

Para las escrituras parciales, aplica las habilitaciones
por byte indicadas en `exp_wstrb_i`.

Aunque recibe `exp_size_i`, el periférico de ejemplo
no utiliza esta señal para validar individualmente
el tamaño de la operación.

El núcleo RV64I dispone de lógica para detectar
accesos desalineados. No obstante, un periférico
conectado a otro iniciador deberá contar con las
comprobaciones de acceso que correspondan.

El periférico actual responde sin insertar esperas.
Un acelerador multiciclo debe implementar
correctamente `exp_ready`, conservar la transacción
pendiente y evitar efectos duplicados.

Estas características corresponden al RTL actual,
no a obligaciones universales de todos los
periféricos que puedan conectarse a la interfaz.

## 6. Programa bare-metal de referencia

Archivo:

`sw/baremetal/accelerator/start.S`

La demostración realiza la siguiente secuencia:

1. Escribe el primer operando en `BASE + 0x20`.
2. Escribe el segundo operando en `BASE + 0x28`.
3. Escribe `1` en CONTROL para iniciar la operación.
4. Consulta STATUS hasta observar done.
5. Lee RESULT y lo compara con el valor esperado.
6. Limpia done mediante W1C y verifica STATUS.
7. Escribe una marca de éxito o fallo en RAM.

Los operandos de referencia son:

- A: `0x1122334455667788`
- B: `0x22`

Resultado esperado:

`0x11223344556677AA`

La marca final se escribe en una región de RAM
definida por el programa y su linker script.

El programa utiliza RV64I sin necesidad
de una biblioteca estándar de C.

## 7. Ejecutar las pruebas existentes

Desde la raíz del repositorio:

```bash
make baremetal-accelerator
```

Para ejecutar toda la regresión funcional:

```bash
make regression
```

Para ejecutar el análisis estático:

```bash
make lint
```

La regresión funcional ya incorpora el
ejemplo bare-metal del acelerador.

Testbenches útiles:

- `tb/tb_sv/tb_expansion_demo_periph.sv`
- `tb/tb_sv/tb_core_expansion_mmio.sv`
- `tb/tb_sv/tb_core_baremetal_accelerator.sv`
- `tb/tb_sv/tb_core_expansion_priv_wait.sv`
- `tb/tb_sv/tb_core_expansion_fault_trap.sv`

No todos estos bancos utilizan el mismo mapa
de direcciones ni el mismo entorno de memoria.
Consultar los parámetros de cada testbench.

## 8. Incorporar un acelerador nuevo

El procedimiento recomendado consiste en
conservar inicialmente el contrato `exp_*`
y sustituir la lógica del periférico de ejemplo.

### Paso A: definir la función

Documentar:

- Operación realizada.
- Registros de control y datos.
- Direcciones y tamaños soportados.
- Latencia de ejecución.
- Condiciones de busy, done y error.
- Comportamiento ante reset.

### Paso B: implementar el módulo RTL

Crear un módulo nuevo en `rtl/core/`
que presente las señales compatibles con el
puerto de expansión.

No es necesario modificar `core_top.sv`
si se conserva el contrato existente.

Los periféricos multiciclo requieren controlar
la finalización de transacciones, los estados
internos y los efectos únicos de las escrituras.

### Paso C: crear pruebas dirigidas

Agregar un testbench que verifique, al menos:

- Reset y valores iniciales.
- Lecturas y escrituras válidas.
- Escrituras parciales cuando correspondan.
- Registros no implementados.
- Errores y operaciones no permitidas.
- Esperas y finalización.
- Ausencia de operaciones duplicadas.

### Paso D: integrar con el núcleo

Utilizar como referencia:

`tb/tb_sv/tb_core_baremetal_accelerator.sv`

Actualizar la instanciación del periférico
y cualquier archivo de compilación necesario.

Verificar que las direcciones del programa y
del hardware coincidan.

### Paso E: adaptar el software

Modificar o crear el programa bare-metal
de demostración y sus comprobaciones de resultado.

Revisar la imagen de memoria y el linker script
si cambia la distribución del software.

### Paso F: validar la integración

Ejecutar las pruebas específicas y, después,
la regresión completa y el análisis estático.

Si se modifica la plataforma FPGA,
actualizar la lista de fuentes y los scripts
de implementación pertinentes.

Una modificación del acelerador requiere
generar y verificar una implementación nueva.
El bitstream histórico no incluye automáticamente
los cambios realizados al RTL.

## 9. Relación con AXI4-Lite

El repositorio incluye también:

- `rtl/core/exp_axi4lite_master_bridge.sv`
- `rtl/core/axi4lite_expansion_demo_periph.sv`

Estos módulos permiten estudiar una adaptación
entre el contrato de expansión y AXI4-Lite.

No deben confundirse con el supervisor AXI4-Lite
del procesador ARM en la plataforma FPGA.

La integración FPGA aprobada utiliza
`expansion_demo_periph` directamente.

La utilización de otro acelerador AXI4-Lite
requiere comprobar y verificar la integración
con el puente correspondiente.

## 10. Límites de reutilización

La interfaz de expansión es un contrato propio
de este proyecto, no una interfaz RISC-V
estandarizada por la ISA.

El periférico actual no demuestra el comportamiento
de todos los aceleradores posibles.

Los resultados históricos de verificación
corresponden a la configuración evaluada.
Modificar la lógica de expansión requiere
nuevas pruebas de integración.

Las operaciones sobre una FPGA física requieren
además comprobar temporización, recursos,
firmware y condiciones de seguridad.

## 11. Referencias técnicas

- RISC-V Unprivileged ISA:
  https://docs.riscv.org/
- Vivado IP Integrator UG994, versión 2024.1:
  https://docs.amd.com/r/2024.1-English/ug994-vivado-ip-subsystems

La descripción del contrato concreto del TFG
procede del RTL versionado en este repositorio.
