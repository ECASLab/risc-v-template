#!/usr/bin/env bash
# B.9.3.9a: consolidacion reproducible ACT4 y regresion del nucleo
set -uo pipefail

BASE="${HOME}/TFG_tools"
PACK="${BASE}/B9_3_9a_cierre"
CORE="${CORE_ROOT:-/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template}"
OUT="${BASE}/B9_3_9a_resultados"
ARCHIVE="${BASE}/B9_3_9a_resultados.tar.gz"

if [[ ! -f "${CORE}/Makefile" || ! -f "${CORE}/rtl/core/core_top.sv" ]]; then
    echo "ERROR: no se encontro el repositorio CORE en: ${CORE}" >&2
    echo "Defina CORE_ROOT con la ruta correcta antes de reintentar." >&2
    exit 2
fi
if [[ ! -f "${PACK}/auditar_51_ACT4.py" ]]; then
    echo "ERROR: falta ${PACK}/auditar_51_ACT4.py" >&2
    exit 2
fi
if [[ -e "$OUT" || -e "$ARCHIVE" ]]; then
    echo "ERROR: ya existe un resultado B9_3_9a. No se sobrescribe evidencia." >&2
    echo "Directorios/archivo: $OUT $ARCHIVE" >&2
    exit 2
fi
mkdir -p "$OUT"
FAIL=0
{
    echo "B.9.3.9a - Auditoria de cierre ACT4 y prueba de no regresion"
    date -Is
    echo "CORE=$CORE"
    echo "CORE HEAD=$(git -C "$CORE" rev-parse HEAD 2>/dev/null || echo NO_GIT)"
    echo "ACT4 HEAD=$(git -C "$BASE/riscv-arch-test" rev-parse HEAD 2>/dev/null || echo NO_GIT)"
    printf '\nVERSIONES HERRAMIENTAS\n'
    (iverilog -V 2>/dev/null | head -n 1) || true
    (riscv64-unknown-elf-gcc --version 2>/dev/null | head -n 1) || true
    (clang-22 --version 2>/dev/null | head -n 1) || true
    echo "CORE STATUS INICIAL:"
    git -C "$CORE" status --short 2>/dev/null || true
    echo "ACT4 STATUS:"
    git -C "$BASE/riscv-arch-test" status --short 2>/dev/null || true
} > "$OUT/entorno_git.txt"

printf '=== Auditoria retrospectiva de 51 casos ACT4 ===\n'
if python3 "$PACK/auditar_51_ACT4.py" --archivos "$BASE" --salida "$OUT/consolidado" > "$OUT/auditoria.log" 2>&1; then
    cat "$OUT/auditoria.log"
else
    echo "FAIL: auditoria 51 ACT4; ver auditoria.log"
    FAIL=1
fi

: > "$OUT/resultados_regresion.csv"
printf 'objetivo,estado,codigo_salida\n' > "$OUT/resultados_regresion.csv"
for GOAL in baremetal-probe regression lint; do
    printf '\n=== make %s ===\n' "$GOAL"
    if (cd "$CORE" && make "$GOAL") > "$OUT/make_${GOAL}.log" 2>&1; then
        echo "PASS: make $GOAL"
        printf '%s,PASS,0\n' "$GOAL" >> "$OUT/resultados_regresion.csv"
    else
        RC=$?
        echo "FAIL: make $GOAL (exit=$RC); ver make_${GOAL}.log"
        printf '%s,FAIL,%s\n' "$GOAL" "$RC" >> "$OUT/resultados_regresion.csv"
        FAIL=1
    fi
    tail -n 8 "$OUT/make_${GOAL}.log" || true
done

{
    echo "CORE HEAD FINAL:"
    git -C "$CORE" rev-parse HEAD || true
    echo "CORE STATUS FINAL:"
    git -C "$CORE" status --short || true
    echo "ACT4 STATUS FINAL:"
    git -C "$BASE/riscv-arch-test" status --short || true
} > "$OUT/git_final.txt" 2>&1

printf 'B9_3_9a exit=%s\n' "$FAIL" > "$OUT/estado.txt"
# create archive regardless of failure to allow diagnosis
if tar -czf "$ARCHIVE" -C "$BASE" "$(basename "$OUT")"; then
    echo "ARCHIVO PARA COMPARTIR: $ARCHIVE"
else
    echo "ERROR: no se pudo empaquetar $OUT" >&2
    exit 2
fi
if [[ $FAIL -eq 0 ]]; then
    echo "PASS: B.9.3.9a - auditoria 51/51 y las tres pruebas base del nucleo"
else
    echo "PENDIENTE: B.9.3.9a presenta una incidencia; consulte los logs"
fi
exit "$FAIL"
