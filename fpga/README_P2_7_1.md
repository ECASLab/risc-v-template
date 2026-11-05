# TFG — P2.7.1 supervisor AXI4-Lite (primera candidata)

## Alcance

Este paquete se prueba **fuera del repositorio**, contra la rama `fpga/platform-uram` y el commit `047aaef`. No cambia el procesador. No crea un block design, no ejecuta place/route, no genera bitstream y no se comunica con la Kria.

Se incluyen:

- `rtl/platform/rv64i_axi_supervisor.sv`: esclavo AXI4-Lite de 32 bits; AW y W independientes, BRESP retenido hasta BREADY y RDATA hasta RREADY. Cada comando boot responde cuando terminó la operación nativa.
- `rtl/platform/rv64i_platform_top.sv`: mismo top P2.6.3, con monitor **pasivo** del resultado del programa de demostración sobre DMEM en `0x80000300`, sin modificar `core_top.sv` ni RAM.
- `rtl/platform/rv64i_soc_axi_top.sv`: integra supervisor y plataforma con un único reloj.
- `rtl/platform/rv64i_soc_axi_bd_wrapper.v`: envoltura **Verilog-2001** para posterior Module Reference en Vivado IP Integrator 2024.1.
- `tb/platform/tb_rv64i_axi_integration.sv`: un test de integración, ejecuta el programa bare-metal existente usando accesos AXI4-Lite y la RAM XPM real de 64 KiB en simulación.
- `fpga/scripts/synth_axi_soc.tcl`: síntesis OOC del sistema completo con RAM de 1 MiB y 32 UltraRAM previstas.

## Registro de control (offsets respecto a la futura base AXI configurada en IP Integrator)

| Offset | Nombre | Operación |
| --- | --- | --- |
| `0x00` | `CONTROL` | R/W. Bit 0: `run`. 0 = RV64I detenido/reset, habilita puerto boot; 1 = ejecutar. |
| `0x04` | `STATUS` | R. Bit 0 = run; bits 9:8 = `result_code` (0 aún no marcado, 1 PASS, 2 FAIL). |
| `0x08` | `BOOT_ADDR_LO` | R/W. Mitad baja de dirección **absoluta** de RAM. |
| `0x0C` | `BOOT_ADDR_HI` | R/W. Mitad alta de dirección de RAM. |
| `0x10` | `BOOT_WDATA_LO` | R/W. Mitad baja de los 64 bits a escribir. |
| `0x14` | `BOOT_WDATA_HI` | R/W. Mitad alta de los 64 bits a escribir. |
| `0x18` | `BOOT_WSTRB` | R/W. Máscara 8-bit, un bit por byte. Predeterminado `0xff`. |
| `0x1C` | `BOOT_CMD` | W. Valor `1` escritura, `2` lectura. Solo cuando `run=0`. BRESP esperado al finalizar el acceso a RAM. |
| `0x20` | `BOOT_RDATA_LO` | R. Mitad baja de la última lectura boot exitosa. |
| `0x24` | `BOOT_RDATA_HI` | R. Mitad alta de la última lectura boot exitosa. |
| `0x28` | `BOOT_STATUS` | R. Bit 0 operación terminada; bit 1 error de la última operación. |

- Escrituras de registros de datos/dirección respetan `WSTRB` de AXI. Las escrituras de 64 bits se realizan en **dos accesos de 32 bits**; el comando ejecuta una sola operación 64-bit de UltraRAM.
- `BOOT_CMD` tiene una transacción AXI con respuesta tardía, por diseño. Mientras se ejecuta, no se aceptan nuevas escrituras AXI (AW/W). El canal de lectura sí puede usarse.
- Los accesos a offsets inválidos, `BOOT_CMD` durante `run=1`, comandos inválidos y direcciones desalineadas de registro generan `SLVERR` (2'b10). Los errores de rango/alineación RAM retornan `SLVERR` en el comando.
- La memoria nativa requiere dirección de palabra de **8 bytes alineados**. La CPU utiliza IMEM/DMEM normalmente durante `run=1`; en ese estado no se permite una operación de boot.
- El monitor `STATUS[9:8]` es específico del programa de demostración actual, que guarda 1 (PASS) o 2 (FAIL) en `0x80000300`. Detecta una escritura DMEM confirmada sin error. **No es una interfaz arquitectural estándar RISC-V ni una prueba de rendimiento.** El valor se borra cuando `run=0`.
- El puerto `s_axi_aresetn` debe ser un reset síncrono adecuado al mismo `s_axi_aclk` proporcionado a CPU y AXI; si se cambia el dominio reloj, hará falta diseñar un CDC formal. No conectar directamente un reloj ajeno.
- La base AXI del **ARM** se asignará posteriormente en Vivado; no se confunde con `0x10000000`, que es la base MMIO vista por el RV64I.

## Ejecutar en `xrt-france`

```bash
cd ~/tfg_fpga_checks
python3 -m zipfile -e P2_7_1_axi_supervisor.zip .
cd P2_7_1_axi_supervisor
amd_202401_enable
bash run_p2_7_1.sh
```

El runner verifica la rama y HEAD limpios; crea un directorio propio `~/tfg_fpga_checks/p2_7_1_axi_run_*`; recompila el programa bare-metal actual; simula el SoC; sintetiza OOC con capacidad 1 MiB; comprueba 32 UltraRAM, cero BRAM y la ausencia de critical warnings; no toca Git.

**Criterios de aceptación:**

```text
PASS: P2.7.1 AXI4-Lite + RV64I + UltraRAM + MMIO
AXI_SOC_URAM_COUNT=32
AXI_SOC_BRAM_COUNT=0
P2_7_1_SYNTH_PASS
GIT_STATUS=CLEAN
```

Si el runner falla, enviar solo la salida del error y el directorio RUN_DIR generado. No repetir ni modificar la Kria.

## Limitaciones deliberadas

1. La simulación prueba protocolo, memoria y programa existentes, pero no sustituye una verificación AXI completa con VIP ni una certificación.
2. Solo se permite un boot pendiente y una respuesta de escritura AXI pendiente; esto es válido porque AXI4-Lite permite aplicar backpressure.
3. La temporización del reloj, las restricciones de interfaz AXI y la integración PS/PL se comprobarán después. Un OOC exitoso **no valida** timing o bitstream.
4. No se ha probado todavía en Vivado 2024.1 de `xrt-france`; es un **candidato**. No incorporar al repositorio antes de un PASS real.
