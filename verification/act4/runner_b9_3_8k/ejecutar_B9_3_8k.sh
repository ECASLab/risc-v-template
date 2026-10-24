#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# TFG B.9.3.8k: cierre de las dos pruebas RV64I restantes: FENCE y NOP, sin cambios de RTL/ACT4.
set -euo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE="$HOME/TFG_tools"
ACT4="$BASE/riscv-arch-test"
OUT="$BASE/B9_3_8k_resultados"
PACK="$BASE/B9_3_8k_resultados.tar.gz"
CASES=(I-fence-00 I-nop-00)
fail() { echo "ERROR: $*" >&2; exit 1; }
[[ ! -e "$OUT" && ! -e "$PACK" ]] || fail "Ya hay resultados; no se sobrescriben: $OUT o $PACK"
for case_name in "${CASES[@]}"; do
    [[ -f "$ACT4/tests/rv64i/I/$case_name.S" ]] || fail "Falta la prueba: tests/rv64i/I/$case_name.S"
done
for f in ejecutar_caso.sh convertir_elf_act4_generico.py verificar_imagenes_generico.py tb_core_act4_generic.sv act4_runner.mk; do
    [[ -f "$ROOT/$f" ]] || fail "Falta $f"
done
mkdir -p "$OUT"/{casos,paquetes,logs}
python3 "$ROOT/auditar_pendientes.py" "$ACT4" "$OUT"
export ACT4_MAX_CYCLES="${ACT4_MAX_CYCLES:-500000}"
START="$(date -Is)"
cat > "$OUT/manifest.txt" <<EOF
TFG B.9.3.8k - cierre del lote RV64I (FENCE, NOP)
Inicio: $START
ACT4 HEAD: $(git -C "$ACT4" rev-parse HEAD)
CORE PATH: ${CORE_REPO:-/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template}
Ciclos maximos: $ACT4_MAX_CYCLES
NOTA: Sm y parametros de direccion fisica/PMA siguen provisionales; pruebas privilegiadas desactivadas.
EOF
printf 'caso,resultado,ciclos,fetch,dmem,respuestas,tohost,exit_code\n' > "$OUT/resumen.csv"
[[ "${#CASES[@]}" -eq 2 ]] || fail "Se esperaban 2 pruebas"
FAILED=0
for case_name in "${CASES[@]}"; do
    printf '\n=== EJECUTANDO %s ===\n' "$case_name"
    set +e
    ACT4_CASE="$case_name" bash "$ROOT/ejecutar_caso.sh" > "$OUT/logs/$case_name.console.log" 2>&1
    rc=$?
    set -e
    sim="$OUT/casos/$case_name/sim.log"
    details=""
    if [[ -f "$sim" ]]; then
        details="$(grep -E '^[[:space:]]+ciclos=[0-9]+ fetch=[0-9]+ dmem=[0-9]+ respuestas=[0-9]+' "$sim" | tail -n 1 || true)"
    fi
    if [[ "$rc" -eq 0 ]] && grep -Fq "PASS: ACT4 $case_name ejecutado en core_top (tohost=1)" "$sim"; then
        status=PASS
        vals="$(printf '%s\n' "$details" | sed -nE 's/^[[:space:]]*ciclos=([0-9]+) fetch=([0-9]+) dmem=([0-9]+) respuestas=([0-9]+).*$/\1,\2,\3,\4/p')"
        if [[ -z "$vals" ]]; then status=FAIL; rc=1; vals=",,,"; fi
        printf '%s,%s,%s,1,%s\n' "$case_name" "$status" "$vals" "$rc" >> "$OUT/resumen.csv"
    else
        status=FAIL
        [[ "$rc" -ne 0 ]] || rc=1
        printf '%s,FAIL,,,,,,%s\n' "$case_name" "$rc" >> "$OUT/resumen.csv"
    fi
    if [[ "$status" == PASS ]]; then
        grep -F "PASS: ACT4 $case_name ejecutado" "$sim" || true
        echo "$details"
    else
        FAILED=$((FAILED+1))
        echo "FALLO: $case_name (exit=$rc). Ultimas 25 lineas:"
        tail -n 25 "$OUT/logs/$case_name.console.log" || true
    fi
done
printf '\n=== RESUMEN INDIVIDUAL ===\n'
column -s, -t "$OUT/resumen.csv" 2>/dev/null || cat "$OUT/resumen.csv"
printf '%s\n' "$FAILED" > "$OUT/fallos.txt"
# Cada caso ya dispone de su tar de diagnostico; agrupar sin incluir imagenes HEX grandes.
paths=(manifest.txt resumen.csv fallos.txt inventario_51.txt pendientes_antes.txt pendientes_despues.txt)
for case_name in "${CASES[@]}"; do
    paths+=("logs/$case_name.console.log")
    [[ -f "$OUT/paquetes/$case_name.tar.gz" ]] && paths+=("paquetes/$case_name.tar.gz")
done
tar -czf "$PACK" -C "$OUT" "${paths[@]}"
echo "ARCHIVO PARA COMPARTIR: $PACK"
if [[ "$FAILED" -ne 0 ]]; then
    echo "PENDIENTE: $FAILED de ${#CASES[@]} pruebas fallaron. Conservar resultados y compartir paquete."
    exit 1
fi
echo "PASS: B.9.3.8k — ${#CASES[@]} pruebas ACT4 completadas en core_top"
