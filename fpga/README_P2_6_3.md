# P2.6.3 — Plataforma RV64I integrada y reproducible

## Fuentes
- `rtl/platform/rv64i_platform_ram.sv`: memoria de 1 MiB XPM UltraRAM (32 primitivas en la síntesis de P2.6.2).
- `rtl/platform/rv64i_platform_top.sv`: integra `core_top`, RAM y `expansion_demo_periph`; supervisor nativo `boot_*` sin AXI.
- `tb/platform/tb_rv64i_platform_integration.sv`: ejecuta el programa `sw/baremetal/accelerator/start.S`.
- `fpga/scripts/run_integrated.sh`: flujo reproducible XSIM + síntesis OOC Vivado 2024.1.
- `fpga/scripts/synth_integrated_top.tcl`: script de síntesis independiente de directorios temporales.

## Resultado histórico P2.6.2 (no reejecutado durante la preparación de este paquete)
XSIM PASS; result_flag=1; MMIO=7; DMEM=1/1; 42 ciclos; síntesis K26: 32 UltraRAM, 0 BRAM.

## Para repetirlo desde el repositorio

En `xrt-france`: `amd_202401_enable`, después `bash fpga/scripts/run_integrated.sh`. Los artefactos se guardan solo fuera de Git, bajo `~/tfg_fpga_checks/p2_6_3_repro_XXXXXX`.

## Advertencias de alcance
- La simulación reduce RAM_BYTES a 64 KiB; la síntesis usa 1 MiB.
- No hay aún puente AXI4-Lite, supervisor ARM, reloj/reset de plataforma, XDC ni validación física.
- Los fetches fuera de rango devuelven una instrucción ilegal, no un error de instrucción arquitectural.
- No hay prueba de timing ni bitstream. No conectar ni programar la Kria todavía.
- No mezclar los archivos del repositorio con un proyecto Vivado existente. Usar una copia separada para el flujo de implementación futura.

Fuentes: AMD UG974 (XPM_MEMORY_TDPRAM), UG901 (síntesis), UG994 (integración RTL/IP). Ver versión 2024.1.
