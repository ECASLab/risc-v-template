#!/usr/bin/env bash
set -Eeuo pipefail
BASE="${HOME}/TFG_tools"
CORE="${CORE_ROOT:-/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$BASE/B9_3_9g_resultados"
TAR="$BASE/B9_3_9g_resultados.tar.gz"
REG="$BASE/B9_3_9a_resultados.tar.gz"
if [[ -e "$OUT" || -e "$TAR" ]]; then
 echo "ERROR: existen resultados B9_3_9g; conservamos evidencia previa. No se sobrescribe." >&2
 exit 2
fi
mkdir -p "$OUT"
status=0
{
 printf '=== ENTORNO ===\n'
 printf 'CORE_ROOT=%s\n' "$CORE"
 git -C "$CORE" rev-parse HEAD
 git -C "$CORE" status --short
 python3 --version
 printf '\n=== MATRIZ DE TRAZABILIDAD CSR/TRAPS ===\n'
 python3 "$SCRIPT_DIR/auditar_B9_3_9g.py" --core "$CORE" --baseline-tar "$REG" --out "$OUT"
} > "$OUT/ejecucion.log" 2>&1 || status=$?
cat "$OUT/ejecucion.log"
printf 'EXIT_CODE=%s\n' "$status" > "$OUT/resultado.txt"
tar -czf "$TAR" -C "$BASE" B9_3_9g_resultados
printf 'ARCHIVO PARA COMPARTIR: %s\n' "$TAR"
exit "$status"
