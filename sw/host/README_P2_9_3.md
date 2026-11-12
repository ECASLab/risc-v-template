# Estado actualizado — P2.9.4 (2026-11-06)

> **Nota de vigencia (11 de noviembre de 2026):** después de esta
> etapa se completó una segunda ejecución física satisfactoria
> y se verificó la restauración de `k26-starter-kits`.
> Las indicaciones inferiores sobre actividades pendientes
> reflejan el estado histórico del 6 de noviembre.
> Consultar la [guía FPGA](../../docs/fpga-kv260.md) y el
> [informe de cierre](../../docs/verification/fpga/cierre_kv260_20261111/README.md).

Se probó `rv64i_arm_loader.c` en la KV260 ARM64 y se completó **una** ejecución
física satisfactoria (`RESULT_FLAG=1`, código de salida 0). Se corrigió la
comprobación del overlay de `rv64i_tfg` a `tfg-rv64i-kv260_image_`.

El commit de referencia anterior a la integración es `a3c0e5f`. Los scripts
de pruebas se conservaron en `sw/host/p2_9_4_tests/`. La documentación de
resultados está en `docs/verification/fpga/kria_p2_9_4/`.

Para comprobación offline, sin hardware:

```bash
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
    -o /tmp/rv64i_arm_loader rv64i_arm_loader.c
/tmp/rv64i_arm_loader --image /ruta/accelerator.bin --check-image
```

**No iniciar el core por defecto.** `--execute --confirm-hardware` opera
sobre `/dev/mem` y requiere verificar antes firmware, reloj, ventilación
y procedimiento ECASLab de recuperación. Repetibilidad y restauración
aún pendientes. El texto siguiente corresponde a la fase histórica P2.9.3.

---

# P2.9.3 — Aplicación ARM para supervisar RV64I (candidata)

Esta versión se deriva de **`rtl/platform/rv64i_axi_supervisor.sv`** y del testbench P2.7.1. No configura ni programa la FPGA; solo comunica con el hardware **después** de que otro procedimiento seguro haya aplicado el firmware correcto.

## Fase actual: compilación y validación sin acceso físico

En el **servidor `xrt-france`**, después de extraer el ZIP:

```bash
amd_202401_enable
cd ~/tfg_fpga_checks/P2_9_3_aplicacion_arm
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror -o rv64i_arm_loader rv64i_arm_loader.c
bash compilar_rv64i_image.sh "$PWD"
./rv64i_arm_loader --image accelerator.bin --check-image
```

**Esperado:** `IMAGE_READY=.../accelerator.bin`, `IMAGE_VALID: 776 bytes, 97 palabras` y `DRY_RUN_OK`. Los archivos se generan solo en el directorio de pruebas, fuera de Git.

Para compilar para **ARM64 en la Kria**, cuando corresponda y todavía sin hardware:

```bash
gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror -o rv64i_arm_loader rv64i_arm_loader.c
./rv64i_arm_loader --image accelerator.bin --check-image
```

También puede usarse un compilador cruzado `aarch64-linux-gnu-gcc` en otro host, si está disponible. El programa no usa bibliotecas externas.

## Contrato de registros (AXI base física 0xA0000000)

| Offset | Registro | Uso |
|---|---|---|
| 0x00 | CONTROL | bit0 = run |
| 0x04 | STATUS | bits 9:8 = resultado (0 pendiente, 1 PASS, 2 FAIL) |
| 0x08 / 0x0C | BOOT_ADDR_LO/HI | Dirección absoluta de memoria RV64I |
| 0x10 / 0x14 | BOOT_WDATA_LO/HI | Palabra de 64 bits |
| 0x18 | BOOT_WSTRB | Byte enables; 0xFF |
| 0x1C | BOOT_CMD | 1 = write, 2 = read; solo cuando run=0 |
| 0x20 / 0x24 | BOOT_RDATA_LO/HI | Resultado de lectura |
| 0x28 | BOOT_STATUS | bit0 done; bit1 error |

- Memoria: 1 MiB desde `0x80000000`; palabra nativa de 8 bytes, little endian.
- Programa bare-metal: `sw/baremetal/accelerator/start.S`, con linker `link.ld`. El binario de demostración histórico ocupa 776 bytes (97 palabras).
- Marcador de resultado: 64 bits en `0x80000300`, valor 1 si PASS, 2 si FAIL.
- La aplicación escribe todas las palabras, valida la primera, última y marcador inicial, inicia RV64I, espera `STATUS[9:8]`, lo detiene y verifica el marcador vía boot.

## Seguridad: no ejecutar contra la FPGA todavía

El modo predeterminado **no abre `/dev/mem`**. El modo `--execute` está reservado para una etapa posterior, con dos condiciones explícitas: `--confirm-hardware` y `root`. Adicionalmente verifica que haya un overlay aplicado cuyo nombre contenga `rv64i_tfg`, que no siga aplicado el overlay `k26-starter-kits`, que el Device Tree tenga el nodo exacto con ventana de 4 KiB y que FPGA Manager indique `operating`.

**Estas verificaciones no bastan por sí solas para autorizar la carga.** Antes de usar el modo real deben confirmarse en la Kria `.90`: la versión de `dfx-mgr`, la carga y rollback seguros, el ventilador y la temperatura, el reloj real de PL0 compatible con 17 ns, y la coherencia entre bitstream y DTBO.

**Riesgo conocido**: una lectura o escritura MMIO hacia un AXI sin reloj o sin esclavo puede bloquear el proceso incluso aunque la aplicación tenga un timeout para el programa RV64I. No ejecutar si existe alguna duda del overlay o del reloj. No alterar QSPI, U-Boot ni aplicaciones FPGA activas en esta fase.

## Limitaciones

- El software utiliza `/dev/mem` y `mmap` en la ruta de ejecución real; es un acceso privilegiado y no reemplaza a un driver Linux.
- La validación offline revisa el tamaño del binario y el marcador inicial; no comprueba que toda instrucción RISC-V sea correcta. La integración funcional se verificó previamente mediante XSIM.
- Si cambia el programa bare-metal, su marcador, dimensiones o mapa de registro, deberá actualizarse la herramienta.
- Ni el ejecutable compilado ni el éxito del modo de prueba offline demuestran funcionamiento en FPGA física.
