# Instalación y primeros pasos en Ubuntu

Esta guía permite preparar el entorno local, compilar
software RV64I y ejecutar las pruebas del núcleo y del
acelerador de demostración.

No se necesita una FPGA, Vivado ni acceso a los servidores
del ECASLab para completar este procedimiento.

[Volver al README principal](../README.md).

## 1. Entorno de referencia

Entorno inventariado el 11 de noviembre de 2026:

| Componente | Versión observada |
|---|---|
| Sistema | Ubuntu 26.04.1 LTS, x86_64 |
| Git | 2.53.0 |
| GNU Make | 4.4.1 |
| Python | 3.14.4 |
| Icarus Verilog | 12.0 |
| Verilator | 5.032 |
| RISC-V GCC | 14.2.0 |
| RISC-V Binutils | 2.45.50 |

Estas versiones identifican el entorno inspeccionado.
No constituyen una matriz completa de compatibilidad
ni garantizan resultados binarios idénticos en otros sistemas.

## 2. Instalar las dependencias

En Ubuntu, instalar las herramientas mediante APT:

```bash
sudo apt update

sudo apt install \
  git \
  make \
  python3 \
  iverilog \
  verilator \
  gcc-riscv64-unknown-elf \
  binutils-riscv64-unknown-elf
```

Los paquetes de herramientas electrónicas y RISC-V
pueden requerir que el repositorio `universe` de Ubuntu
esté habilitado.

No es necesario instalar cocotb, ACT4 ni Vivado
para ejecutar las pruebas básicas indicadas aquí.

## 3. Obtener el proyecto

```bash
git clone https://github.com/ECASLab/risc-v-template.git

cd risc-v-template
```

Todos los comandos siguientes se ejecutan desde la
raíz del repositorio, donde se encuentra el Makefile.

Para identificar la versión descargada:

```bash
git rev-parse HEAD
git status --short --branch
```

Se recomienda conservar el identificador del commit
junto con los resultados de las pruebas.

## 4. Comprobar las herramientas

```bash
make check-tools
make check-verilator
make check-riscv-tools
```

Estas comprobaciones confirman que los ejecutables
requeridos pueden localizarse en el entorno.

No ejecutan una regresión funcional.

Para consultar las opciones del proyecto:

```bash
make help
make list-tests
```

## 5. Primera prueba: programa bare-metal

```bash
make baremetal-probe
```

Este procedimiento:

1. Compila un programa RV64I mediante GCC.
2. Convierte el ejecutable ELF en una imagen binaria.
3. Genera las imágenes de memoria necesarias.
4. Compila el testbench SystemVerilog.
5. Ejecuta la simulación mediante Icarus Verilog.

El Makefile comprueba la finalización del simulador
y busca indicadores de error.

El resultado satisfactorio termina con:

```text
PASS: bare-metal probe completado
```

Los archivos generados se almacenan en:

`build/baremetal_probe/`

## 6. Probar el acelerador de demostración

```bash
make baremetal-accelerator
```

El programa utiliza la interfaz de expansión MMIO
para comunicarse con el acelerador.

La prueba comprueba la interacción del procesador
con el periférico de demostración mediante simulación.

El resultado satisfactorio termina con:

```text
PASS: baremetal-accelerator completado
```

Los archivos generados se almacenan en:

`build/baremetal_accelerator/`

## 7. Regresión funcional

```bash
make regression
```

Este objetivo ejecuta las pruebas funcionales
configuradas y la demostración bare-metal del
acelerador.

No es necesario ejecutar otra vez
`make baremetal-accelerator` para completar
la regresión, ya que está incluido como dependencia.

Un resultado satisfactorio exige que todas las
pruebas obligatorias terminen sin fallos.

## 8. Análisis estático

```bash
make lint
```

Ejecuta el análisis del RTL y de los testbenches
configurados mediante Verilator.

El proceso debe terminar sin errores de lint
según las opciones definidas por el Makefile.

## 9. Ejecutar una prueba individual

Para consultar los testbenches disponibles:

```bash
make list-tests
```

Ejemplo de prueba individual:

```bash
make run-one TB=tb_core_hazard_branch
```

Esto permite estudiar y verificar un componente
sin ejecutar toda la regresión.

## 10. Archivos de salida

Las compilaciones y simulaciones locales generan
archivos en `build/`.

Algunos objetivos adicionales permiten guardar
registros de ejecución en `docs/verification/logs/`.

El directorio `build/` contiene resultados
regenerables y no debe confundirse con el
RTL o la documentación fuente.

Para eliminar los resultados del directorio
de construcción:

```bash
make clean
```

Este comando elimina `build/`. Debe utilizarse
solamente cuando ya no se necesiten sus resultados.

## 11. Problemas frecuentes

### Falta iverilog o vvp

Comprobar la instalación de `iverilog`
y que ambos comandos estén disponibles en PATH.

### Falta verilator

Instalar el paquete `verilator` y ejecutar
nuevamente `make check-verilator`.

### Falta riscv64-unknown-elf-gcc

Comprobar la instalación de
`gcc-riscv64-unknown-elf`.

### Falta riscv64-unknown-elf-objcopy

Comprobar la instalación de
`binutils-riscv64-unknown-elf`.

### La simulación falla

Consultar el error original del compilador
o del simulador, y revisar los registros generados.

Un resultado FAIL debe investigarse; no debe
interpretarse como un problema de instalación
sin examinar antes la salida correspondiente.

No modificar el RTL para eliminar errores de
entorno sin identificar primero su causa.

## 12. Verificaciones avanzadas

El flujo local de esta guía es independiente de:

- ACT4, utilizado en la verificación arquitectural.
- Vivado 2024.1, utilizado para implementar la FPGA.
- DFX Manager, utilizado en el despliegue sobre KV260.

Las pruebas ACT4 históricas no están integradas
como un comando general `make act4`.

Consultar:

- [ACT4 y sus limitaciones](../verification/act4/README.md).
- [Plataforma KV260](../fpga/kv260/README.md).
- [Resultados FPGA](verification/fpga/cierre_kv260_20261111/README.md).

La reconstrucción y programación física de la
FPGA requieren procedimientos y verificaciones
adicionales. No deben ejecutarse como parte
de esta instalación básica.

## 13. Reutilización y modificaciones

Antes de modificar el núcleo o incorporar
hardware nuevo, conservar una versión de
referencia mediante Git.

Después de cada modificación significativa,
se recomienda volver a ejecutar las pruebas
funcionales y el análisis estático aplicable.

Para ampliar la plataforma, consultar la
[Guía de la interfaz de expansión](expansion-interface.md).
