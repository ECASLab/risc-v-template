#!/usr/bin/env bash
set -euo pipefail
SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="${TFG_REPORT:-$HOME/TFG_tools/B9_3_9b_auditoria}"
mkdir -p "$OUTPUT"
python3 "$SCRIPTS_DIR/auditar_config.py" | tee "$OUTPUT/consola.txt"
ARCHIVO="$HOME/TFG_tools/B9_3_9b_resultados.tar.gz"
tar -czf "$ARCHIVO" -C "$(dirname "$OUTPUT")" "$(basename "$OUTPUT")"
echo "ARCHIVO PARA COMPARTIR: $ARCHIVO"
echo 'NOTA: solo se copiaron fuentes y configuración; no se modificó el RTL.'
