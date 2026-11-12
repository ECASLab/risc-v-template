# Plataforma RISC-V RV64I para FPGA

**Trabajo Final de Graduación — Ingeniería Electrónica, TEC / ECASLab**

Plataforma académica basada en un procesador RISC-V RV64I de
64 bits, desarrollado en SystemVerilog, con microarquitectura
pipeline de cinco etapas, interfaz de expansión para
aceleradores y una implementación sobre AMD Kria KV260.

El proyecto proporciona código RTL, programas bare-metal,
testbenches, herramientas de verificación, scripts FPGA
y evidencias técnicas para facilitar su estudio y reutilización.

## ¿Qué permite hacer?

1. **Estudiar el procesador:** analizar las etapas IF, ID,
   EX, MEM y WB, el control del pipeline, las dependencias
   y los mecanismos privilegiados implementados.
2. **Simular y verificar:** ejecutar programas bare-metal,
   pruebas funcionales y análisis estático.
3. **Integrar aceleradores:** utilizar la interfaz de
   expansión MMIO y el acelerador de demostración
   como referencia para nuevos desarrollos.
4. **Trabajar con FPGA:** estudiar y reconstruir la
   integración RV64I + UltraRAM + supervisor AXI4-Lite
   para la Kria KV260.

## Inicio rápido: simulación en Ubuntu

Para preparar el entorno desde cero, consultar la [Guía de instalación y primeros pasos](docs/getting-started.md).

Para las pruebas locales se requieren:

- GNU Make y Python 3.
- Icarus Verilog (`iverilog` y `vvp`).
- Verilator.
- Toolchain bare-metal RISC-V
  (`riscv64-unknown-elf-gcc` y
  `riscv64-unknown-elf-objcopy`).

Clonar el repositorio:

```bash
git clone https://github.com/ECASLab/risc-v-template.git
cd risc-v-template
```

Comprobar las herramientas instaladas:

```bash
make check-tools check-verilator check-riscv-tools
```

Ejecutar las pruebas principales:

```bash
make baremetal-probe
make baremetal-accelerator
make regression
make lint
```

`baremetal-probe` verifica un programa RV64I básico.
`baremetal-accelerator` compila y ejecuta en simulación
un programa que utiliza el acelerador MMIO.

`regression` incluye la batería funcional configurada
y la demostración bare-metal del acelerador.

`lint` ejecuta el análisis estático configurado con
Verilator.

Estas actividades no necesitan acceso a la Kria
ni ejecutar Vivado.

Otros comandos disponibles:

```bash
make help
make list-tests
make run-one TB=tb_core_hazard_branch
```

## Arquitectura

La plataforma incluye:

- Núcleo RV64I de cinco etapas, in-order y single-issue.
- Mecanismos de forwarding, stalls y control de hazards.
- Soporte delimitado de M-mode, CSR y traps.
- Interfaces independientes de memoria de instrucciones
  y datos.
- Región MMIO de expansión para aceleradores.
- Acelerador de demostración.
- Integración FPGA con UltraRAM y supervisor AXI4-Lite.

El diseño no pretende implementar un procesador
Linux de propósito general ni todas las extensiones
de RISC-V.

## Interfaz de expansión

La región MMIO del acelerador de demostración
comienza en `0x10000000`.

El programa de ejemplo está disponible en
`sw/baremetal/accelerator/`.

El acelerador de referencia y sus interfaces están
implementados en `rtl/core/`.

La prueba de integración se encuentra en
`tb/tb_sv/tb_core_baremetal_accelerator.sv`.

Para desarrollar nuevos aceleradores, consultar
la [Guía de la interfaz de expansión](docs/expansion-interface.md).

## Plataforma FPGA: Kria KV260

La implementación utiliza Vivado 2024.1 y el
dispositivo Kria K26.

Componentes principales:

- Núcleo RV64I.
- Memoria implementada mediante UltraRAM.
- Acelerador MMIO.
- Supervisor AXI4-Lite accesible desde el ARM.
- Software ARM para cargar y supervisar la ejecución.

Fuentes y documentación:

- [Guía de utilización y reconstrucción FPGA KV260](docs/fpga-kv260.md).
- [Integración KV260](fpga/kv260/README.md).
- [Despliegue FPGA](fpga/deploy/README.md).
- [Resultados físicos](docs/verification/fpga/cierre_kv260_20261111/README.md).

La implementación validada utiliza un período
de reloj de 17 ns, equivalente aproximadamente
a 58,824 MHz.

El firmware compilado se conserva actualmente
en respaldos verificados y está pendiente de
incorporación a la distribución final.

**No programar la FPGA sin comprobar la
compatibilidad del firmware, la ventilación,
el reloj y el procedimiento de recuperación.**

## Verificación y resultados

El proyecto dispone de evidencias de:

- Regresiones funcionales y lint.
- Ejecución de software bare-metal.
- 51 pruebas arquitecturales ACT4 con resultado PASS
  en la campaña documentada.
- Síntesis e implementación FPGA.
- Dos demostraciones físicas satisfactorias
  del RV64I y el acelerador en la KV260.

La campaña ACT4 está documentada en
[verification/act4/README.md](verification/act4/README.md).

Los 51 PASS corresponden al conjunto auditado
y no representan certificación integral de la ISA.
El ejecutor ACT4 histórico todavía no constituye
un target general `make act4` reproducible
desde cualquier instalación.

La reconstrucción completa del bitstream desde
un clon limpio todavía requiere validación específica.

## Organización del repositorio

| Directorio | Contenido |
|---|---|
| `rtl/core/` | Núcleo RV64I y expansión |
| `rtl/platform/` | Integración de plataforma |
| `tb/` | Modelos y testbenches |
| `sw/baremetal/` | Software RV64I |
| `sw/host/` | Herramientas ARM y host |
| `verification/` | Entorno arquitectural ACT4 |
| `fpga/` | Scripts, integración y despliegue |
| `docs/verification/` | Resultados y evidencias |
| `mk/` y `tools/` | Automatización y utilidades |

## Estado de distribución

El repositorio está en preparación para su entrega
como plataforma académica reutilizable.

Las condiciones de licencia y redistribución
deben confirmarse con los responsables del proyecto
antes de publicar nuevos artefactos compilados.

No debe suponerse autorización para redistribuir
firmware original del laboratorio ni componentes
de terceros.

## Documentación técnica adicional

- [Resumen y limitaciones ACT4](verification/act4/README.md).
- [Cierre de verificación FPGA](docs/verification/fpga/cierre_kv260_20261111/README.md).
- [Reproducibilidad del clon](docs/verification/fpga/cierre_kv260_20261111/REPRODUCIBILIDAD_CLON.md).

Las guías de instalación, extensión y reconstrucción
se consolidarán como parte de la entrega final.

## Estado de entrega

La preparación de la versión reutilizable y sus condiciones de distribución se documentan en [Estado de entrega](docs/release-readiness.md).
