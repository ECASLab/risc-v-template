# Núcleo RISC-V RV64I — TFG

Diseño y verificación de un núcleo RV64I de cinco etapas, in-order y single-issue,
con interfaces IMEM/DMEM síncronas y puerto MMIO de expansión para aceleradores.

## Organización

- `rtl/core/`: núcleo SystemVerilog e interfaces de expansión.
- `tb/models/`, `tb/tb_sv/`: modelos y pruebas funcionales.
- `sw/baremetal/probe/`: programa mínimo RV64I con LD/SD y su linker **propio**.
- `verification/act4/`: configuración auditada de ACT4 y fuentes históricas.
- `docs/verification/act4/`: evidencias seleccionadas de pruebas arquitecturales.
- `TFG_HANDOFF.txt`: estado técnico y copia reproducible de fuentes relevantes.

## Pruebas del núcleo

```bash
make baremetal-probe
make regression
make lint
```

Las 51 pruebas ACT4 ya fueron ejecutadas históricamente mediante un runner
externo. Los scripts copiados se mantienen como fuentes de referencia hasta
su integración y validación dentro de este repositorio. No equivalen a un
nuevo `make act4` funcionando aquí.

Ver [ACT4 y limitaciones](verification/act4/README.md).
