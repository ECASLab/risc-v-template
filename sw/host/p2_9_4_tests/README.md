# Pruebas dirigidas P2.9.4 ejecutadas en Kria KV260

Estas siete fuentes se recuperaron del snapshot de la Kria `kria_p2_9_4_snapshot_20261106.tar.gz` (SHA-256 `12b042556e69f9e2202d45e93b7edb9ba85a512fa31bcc739613e1fbc22c5932`).
Única adaptación respecto a las fuentes de la Kria: la ruta del `#include` ahora es `../rv64i_arm_loader.c`, porque aquí se almacenan en un subdirectorio. No se han modificado los algoritmos de prueba.

Los programas **incluyen el código C original** redefiniendo `main` y llaman funciones internas `static`; son pruebas dirigidas del prototipo, no una API pública del loader. Deben compilarse para ARM64 en la Kria al utilizar el hardware. Compilación de referencia sin acceder al hardware desde el directorio raíz del repositorio:

```bash
mkdir -p /tmp/tfg_p2_9_4_bin
for f in sw/host/p2_9_4_tests/*.c; do
    gcc -std=c11 -O2 -Wall -Wextra -Wpedantic -Werror \
      -o "/tmp/tfg_p2_9_4_bin/$(basename "${f%.c}")" "$f"
done
```

**No ejecutar las pruebas MMIO por defecto.** Requieren el paquete FPGA correcto, permisos de root, acceso Tapo para recuperación y revisión del estado térmico y de PL0. Una transacción AXI bloqueada puede dejar Linux sin respuesta, y `timeout` no siempre puede cancelarla.

| Fuente | Propósito | Resultado histórico en Kria |
|---|---|---|
| `p2_9_4_overlay_preflight.c` | Comprueba overlay y nodo Device Tree; sin MMIO | PASS |
| `p2_9_4_axi_read_probe.c` | CONTROL +0x00, lectura AXI | PASS (`0x00000000`) |
| `p2_9_4_status_probe.c` | STATUS +0x04, lectura AXI | PASS (`0x00000000`) |
| `p2_9_4_boot_regs_probe.c` | BOOT_STATUS/BOOT_WSTRB | PASS (`0` / `0xff`) |
| `p2_9_4_addr_shadow_probe.c` | Escritura/lectura/restore de BOOT_ADDR_LO | PASS |
| `p2_9_4_boot_word_probe.c` | Escritura y lectura de 64 bits en UltraRAM con RUN=0 | PASS (`0x1122334455667788`) |
| `p2_9_4_full_image_stage.c` | Carga y verifica 97 palabras, RUN=0; modo por defecto offline | PASS (97/97) |

Los ejecutables ARM64 compilados en la Kria, los reportes finales y los respaldos del firmware de referencia están en el paquete de transferencia, no en Git. Las salidas de usuario registradas durante el proyecto aportan la evidencia histórica; no se han repetido pruebas físicas al reconstruir estas fuentes.
