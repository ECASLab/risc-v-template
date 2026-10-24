# B.9.3.9g — Matriz CSR y traps

## Objetivo
Consolidar evidencia de CSR/traps ya obtenida en la regresión histórica B.9.3.9a y delimitar qué NO demuestra B.9.3.9f. NO implementa nuevas funciones, no cambia RTL, no modifica Git, no repite simulaciones.

## Dependencias
- Núcleo original en la ruta habitual; opcional `CORE_ROOT=/ruta/real`.
- `~/TFG_tools/B9_3_9a_resultados.tar.gz` (archivo de evidencia histórica).
- Python 3 y Git.

## Ejecución
```bash
bash -n "$HOME/TFG_tools/B9_3_9g_matriz_csr_traps/ejecutar_B9_3_9g.sh"
bash "$HOME/TFG_tools/B9_3_9g_matriz_csr_traps/ejecutar_B9_3_9g.sh"
```

## Salidas
- `~/TFG_tools/B9_3_9g_resultados.tar.gz` (enviar al chat).
- `informe.md`, `matriz_trazabilidad.csv`, `auditoria.json`, `ejecucion.log`, `resultado.txt`.

El script falla explícitamente si detecta otro commit/fuentes distintas o si el log no contiene los 35 resultados esperados. No sobrescribe resultados existentes. Los PASS históricos no equivalen a conformidad completa con Sm o Zicsr.
