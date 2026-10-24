#!/usr/bin/env bash
# B.9.3.9c: compare UDB and Sail address-bit candidates (non-destructive).
set -Eeuo pipefail
ROOT="$HOME/TFG_tools"
ACT4="$ROOT/riscv-arch-test"
SRC="$ROOT/B9_3_7d_primer_elf/config"
OUT="$ROOT/B9_3_9c_resultados"
ARCHIVE="$ROOT/B9_3_9c_resultados.tar.gz"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MISE="$HOME/.local/bin/mise"
SAIL="$ROOT/sail-riscv-0.16/bin/sail_riscv_sim"
if [[ ! -x "$MISE" || ! -x "$SAIL" || ! -d "$ACT4/framework/src/act/data" ]]; then
    echo 'ERROR: falta mise, Sail o el directorio de ACT4' >&2; exit 1
fi
[[ -f "$SRC/tfg-rv64i.yaml" && -f "$SRC/sail.json" ]] || { echo 'ERROR: no estan las configuraciones originales' >&2; exit 1; }
python3 "$SCRIPT_DIR/preparar_candidatas.py"
{
    echo '=== REFERENCIAS DE VERSION ==='
    "$SAIL" --version
    git -C "$ACT4" rev-parse HEAD
    echo '=== ESTADO GIT ACT4 ==='
    git -C "$ACT4" status --short
} > "$OUT/entorno.txt" 2>&1

FAILS=0
for bits in 32 56; do
    echo "=== CANDIDATA ${bits}/${bits} ==="
    udb="$OUT/pa_$bits/tfg-rv64i.yaml"
    sail="$OUT/pa_$bits/sail.json"
    set +e
    "$SAIL" --config "$sail" --validate-config > "$OUT/pa_$bits/sail_validacion.log" 2>&1
    sail_rc=$?
    (
        cd "$ACT4/framework/src/act/data" || exit 1
        "$MISE" exec -- bundle exec udb validate cfg "$udb"
    ) > "$OUT/pa_$bits/udb_validacion.log" 2>&1
    udb_rc=$?
    set -e
    printf 'SAIL_EXIT=%s\nUDB_EXIT=%s\n' "$sail_rc" "$udb_rc" | tee "$OUT/pa_$bits/resultado.txt"
    if [[ "$sail_rc" -eq 0 ]]; then echo "PASS: Sail acepta candidato $bits"; else
        echo "REVISAR: Sail rechazo $bits (ver sail_validacion.log)"; FAILS=$((FAILS+1));
        tail -n 8 "$OUT/pa_$bits/sail_validacion.log" || true
    fi
    if [[ "$udb_rc" -eq 0 ]]; then echo "PASS: UDB acepta candidato $bits"; else
        echo "REVISAR: UDB rechazo $bits (ver udb_validacion.log)"; FAILS=$((FAILS+1));
        tail -n 12 "$OUT/pa_$bits/udb_validacion.log" || true
    fi
done

sha256sum "$SRC/tfg-rv64i.yaml" "$SRC/sail.json" > "$OUT/huellas_originales_despues.txt"
python3 - "$OUT/manifiesto.json" "$OUT/huellas_originales_despues.txt" <<'PY'
import json, sys
from pathlib import Path
j=json.loads(Path(sys.argv[1]).read_text())
t=Path(sys.argv[2]).read_text().splitlines()
a={x.split()[1]:x.split()[0] for x in t}
assert a[j['fuente_udb']] == j['sha256_udb_original'], 'UDB original cambio'
assert a[j['fuente_sail']] == j['sha256_sail_original'], 'Sail original cambio'
print('PASS: UDB y Sail originales sin modificaciones')
PY
printf '\nADVERTENCIA: Ambas validaciones solo prueban aceptacion de configuracion, no ancho PA del RTL.\n' | tee "$OUT/interpretacion.txt"
tar -czf "$ARCHIVE" -C "$ROOT" B9_3_9c_resultados
printf 'ARCHIVO PARA COMPARTIR: %s\n' "$ARCHIVE"
if [[ "$FAILS" -eq 0 ]]; then
    echo 'PASS: B.9.3.9c completado. Pendiente decidir PA efectivo con evidencia de la plataforma.'
else
    echo "PENDIENTE: $FAILS validaciones fallaron; revisar logs antes de cambios"; exit 1
fi
