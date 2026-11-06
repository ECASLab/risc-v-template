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
recuperación del overlay anterior. El script `run_p2_8_1.sh` presupone
ruta `$HOME/tfg_rv64i` y board part `xilinx.com:kv260_som:part0:1.4`.
Si se cambia el árbol de archivos, revisar las rutas antes de ejecutar.
