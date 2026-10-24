#!/usr/bin/env bash
# B.9.3.9e-v3: sin strings en testbench, 8 casos aislados, no cambia RTL.
set -Eeuo pipefail
ulimit -c 0 || true
ROOT="$HOME/TFG_tools"
CORE="${TFG_CORE:-/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/B9_3_9e_v3_resultados"
ARCHIVE="$ROOT/B9_3_9e_v3_resultados.tar.gz"
if [[ -e "$OUT" || -e "$ARCHIVE" ]]; then
    echo "ERROR: resultados v3 previos encontrados. Se preservan: $OUT / $ARCHIVE" >&2
    exit 2
fi
mkdir -p "$OUT/logs"
trap 'rc=$?; trap - EXIT; printf "EXIT_CODE=%s\n" "$rc" > "$OUT/resultado.txt"; tar -czf "$ARCHIVE" -C "$ROOT" B9_3_9e_v3_resultados || true; echo "ARCHIVO PARA COMPARTIR: $ARCHIVE"; exit "$rc"' EXIT
if [[ ! -d "$CORE" ]]; then
    echo "ERROR: no existe el directorio del núcleo: $CORE" >&2
    exit 2
fi
for cmd in git python3 iverilog vvp tar; do
    command -v "$cmd" >/dev/null || { echo "ERROR: falta comando $cmd" >&2; exit 2; }
done
printf '=== ENTORNO ===\n'
{
    git -C "$CORE" rev-parse HEAD
    git -C "$CORE" status --short
    iverilog -V 2>&1 | head -n 1
} > "$OUT/entorno.txt"
cat "$OUT/entorno.txt"

printf '\n=== AUDITORÍA ESTÁTICA ===\n'
python3 "$SCRIPT_DIR/auditar_B9_3_9e_v2.py" "$CORE" "$OUT" | tee "$OUT/auditoria.log"

printf '\n=== CONTROL DE COMPATIBILIDAD IVERILOG ===\n'
python3 - "$SCRIPT_DIR/tb_imem_limites.sv" <<'PY_CHECK' | tee "$OUT/control_compatibilidad.log"
from pathlib import Path
import sys
s = Path(sys.argv[1]).read_text()
assert 'integer caso_id;' in s, 'Falta caso_id entero'
assert 'case (caso_id)' in s, 'No se usa case con entero'
assert 'string caso;' not in s, 'Quedó variable string'
assert 'case (caso)' not in s, 'Quedó case string'
assert '$value$plusargs("ID=%d", caso_id)' in s
assert all(f'{i}:' in s for i in range(1,9))
print('PASS: selección ID=1..8 numérica; sin variable string/case(string)')
PY_CHECK

printf '\n=== COMPILACIÓN DEL MODELO IMEM ===\n'
iverilog -g2012 -s tb_imem_limites -o "$OUT/tb_imem_limites.vvp" \
    "$SCRIPT_DIR/tb_imem_limites.sv" "$CORE/tb/models/imem_sync_model.sv" \
    > "$OUT/compilacion.log" 2>&1 || { tail -n 40 "$OUT/compilacion.log"; exit 1; }
echo 'PASS: Icarus compiló testbench sin strings e IMEM original'

printf 'caso,resultado,exit_simulador,razon\n' > "$OUT/resumen.csv"
run_valid() {
    local id="$1" caso="$2" log="$OUT/logs/${2}.log" rc=0
    vvp "$OUT/tb_imem_limites.vvp" "+ID=$id" > "$log" 2>&1 || rc=$?
    if (( rc != 0 )) || ! grep -Fq "PASS_VALIDO: ID=$id " "$log" || grep -Eq '%load/v error|Assertion.*failed' "$log"; then
        echo "ERROR: lectura IMEM válida falló: $caso (rc=$rc)"; cat "$log"; return 1
    fi
    printf '%s,PASS,0,lectura_valida\n' "$caso" >> "$OUT/resumen.csv"
    echo "PASS: $caso: lectura y respuesta verificadas"
}
run_bad() {
    local id="$1" caso="$2" direccion="$3" texto="$4" log="$OUT/logs/${2}.log" rc=0
    vvp "$OUT/tb_imem_limites.vvp" "+ID=$id" > "$log" 2>&1 || rc=$?
    if (( rc == 0 )) || ! grep -Fq "$texto" "$log" || \
       ! grep -Fq "addr=0x$direccion" "$log" || ! grep -Fq 'FATAL:' "$log" || \
       grep -Eq '%load/v error|Assertion.*failed|FAIL: modelo acepto direccion' "$log"; then
        echo "ERROR: fatal IMEM no corresponde al esperado: $caso (rc=$rc)"; cat "$log"; return 1
    fi
    printf '%s,PASS,%s,fatal_esperado_modelo\n' "$caso" "$rc" >> "$OUT/resumen.csv"
    echo 'PASS:' "$caso" 'produjo $fatal esperado de IMEM' "(rc=$rc)"
}

printf '\n=== ENSAYOS IMEM AISLADOS: 16 BYTES ===\n'
run_valid 1 valido_base
run_valid 2 valido_ultima
run_bad 3 invalido_fin 0000000080000010 'IMEM model error:'
run_bad 4 invalido_inferior 000000007ffffffc 'IMEM model error:'
run_bad 5 invalido_mas_2p32 0000000180000000 'IMEM model error:'
run_bad 6 invalido_mas_2p55 0080000080000000 'IMEM model error:'
run_bad 7 invalido_mas_2p56 0100000080000000 'IMEM model error:'
run_bad 8 invalido_desalineada 0000000080000002 'IMEM protocol error: fetch desalineado'
[[ $(($(wc -l < "$OUT/resumen.csv") - 1)) -eq 8 ]] || { echo 'ERROR: faltan casos'; exit 1; }
cat "$OUT/resumen.csv"
cat > "$OUT/conclusion.md" <<'REPORT'
# B.9.3.9e-v3: caracterización aislada del modelo IMEM

- Version v3 evita `string` en selector SV por una incompatibilidad conocida de Icarus 12.0.
- Dos lecturas de memoria válidas y seis condiciones inválidas contrastadas en IMEM de cuatro palabras (16 bytes).
- En las seis condiciones inválidas, PASS indica solamente un `$fatal` previsto del **modelo de memoria**.
- **No implica `instruction access fault` arquitectural ni validación de un trap de `core_top`.**
- `core_top` carece de `imem_error`, por lo que el tratamiento físico de fetch inválido continúa pendiente.
- No se ha determinado `PHYS_ADDR_WIDTH` de la implementación en FPGA.
- La ejecución no modifica fuentes RTL, UDB ni Sail.
REPORT
printf '\nPASS: B.9.3.9e-v3 - 2 lecturas válidas y 6 rechazos esperados del modelo IMEM.\n'
