# KV260 – diseño aprobado con ventilador

Estado: verificado por usuario el 2026-11-05 para Vivado 2024.1 y K26
`xck26-sfvc784-2LV-c`. Rama base `fpga/platform-uram`, commit
`0ba9c8a`. Esta carpeta incluye el **Tcl final de construcción PS/PL**,
la copia del wrapper compatible con IP Integrator, su comprobación SHA256,
la restricción XDC del ventilador, el script de implementación y reportes.

- Procesador RV64I + UltraRAM 1 MiB + MMIO + supervisor AXI4-Lite.
- Supervisor desde ARM: `0xA0000000`, ventana 4 KiB.
- Programa bare metal RV64I: RAM desde `0x80000000`.
- Ventilador KV260: TTC0/EMIO bit 2 -> `fan_en_b` -> A12/LVCMOS33.
- Reloj implementado `clk_pl_0`: 17 ns (58,824 MHz), WNS +1,245 ns.
- DRC 0 y routing completo; **bitstream corregido** en respaldos de firmware.

El proyecto Vivado debe reconstruirse en un directorio independiente.
No cargar ni programar placa hasta verificar DFX Manager, DTBO, reloj y
recuperación del overlay anterior.

El script `run_p2_8_1.sh` actualizado obtiene la raíz del repositorio
desde su propia ubicación, sin exigir el nombre de la rama histórica.
Admite `TFG_FPGA_RUNS_DIR` para configurar la ubicación de resultados.
Conserva las comprobaciones de ascendencia Git, árbol limpio e integridad
del wrapper. El board part de referencia es
`xilinx.com:kv260_som:part0:1.4`.

Para la utilización actual, consultar la
[guía de la plataforma KV260](../../docs/fpga-kv260.md).
La ejecución del script actualizado con Vivado sigue pendiente
de validación específica.
