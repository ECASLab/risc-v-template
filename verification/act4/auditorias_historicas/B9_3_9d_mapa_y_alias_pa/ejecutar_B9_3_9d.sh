#!/usr/bin/env bash
# B.9.3.9d: caracterizar mapa y comportamiento de DMEM frente a bits altos.
# No modifica RTL, YAML, JSON, ACT4 ni Git.
set -Eeuo pipefail
ROOT="$HOME/TFG_tools"
CORE="${TFG_CORE:-/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template}"
SCRIPTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/B9_3_9d_resultados"
ARCHIVE="$ROOT/B9_3_9d_resultados.tar.gz"
if [[ -e "$OUT" || -e "$ARCHIVE" ]]; then
    echo "ERROR: ya hay resultados anteriores. No se sobrescriben: $OUT o $ARCHIVE" >&2
    exit 2
fi
mkdir -p "$OUT"
trap 'rc=$?; trap - EXIT; printf "EXIT_CODE=%s\n" "$rc" > "$OUT/resultado.txt"; tar -czf "$ARCHIVE" -C "$ROOT" B9_3_9d_resultados || true; echo "ARCHIVO PARA COMPARTIR: $ARCHIVE"; exit "$rc"' EXIT
printf '=== VERSIÓN DEL NÚCLEO Y ENTORNO ===\n' | tee "$OUT/entorno.txt"
{
  git -C "$CORE" rev-parse HEAD
  git -C "$CORE" status --short
  iverilog -V 2>&1
  vvp -V 2>&1
} >> "$OUT/entorno.txt" 2>&1
printf '\n=== AUDITORÍA ESTÁTICA DE MAPA Y FUENTES ===\n'
python3 "$SCRIPTS_DIR/auditar_mapa_pa.py" "$OUT" | tee "$OUT/auditoria.log"
printf '\n=== TESTBENCH DIRIGIDO: DMEM Y BITS ALTOS ===\n'
iverilog -g2012 -s tb_pa_dmem -o "$OUT/tb_pa_dmem.vvp" \
   "$SCRIPTS_DIR/tb_pa_dmem.sv" \
   "$CORE/tb/models/dmem_sync_model.sv" \
   > "$OUT/compilacion.log" 2>&1 || { tail -n 35 "$OUT/compilacion.log"; exit 1; }
vvp "$OUT/tb_pa_dmem.vvp" | tee "$OUT/simulacion.log"
grep -Fq 'PASS: B.9.3.9d DMEM: 9 transacciones dirigidas verificadas' "$OUT/simulacion.log"
echo 'PASS: B.9.3.9d — fuentes y pruebas DMEM, sin declarar PA global.'
