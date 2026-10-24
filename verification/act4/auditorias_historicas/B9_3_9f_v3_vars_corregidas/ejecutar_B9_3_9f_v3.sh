#!/usr/bin/env bash
# B.9.3.9f-v3: core_top integrado con modelo IMEM: no cambia RTL, no reemplaza fuentes.
set -Eeuo pipefail
ulimit -c 0 || true
ROOT="$HOME/TFG_tools"
CORE="${TFG_CORE:-/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/B9_3_9f_v3_resultados"
ARCHIVE="$ROOT/B9_3_9f_v3_resultados.tar.gz"
if [[ -e "$OUT" || -e "$ARCHIVE" ]]; then
  echo "ERROR: resultados existentes. Se preservan: $OUT / $ARCHIVE" >&2
  exit 2
fi
mkdir -p "$OUT/logs"
trap 'rc=$?; trap - EXIT; printf "EXIT_CODE=%s\n" "$rc" > "$OUT/resultado.txt"; tar -czf "$ARCHIVE" -C "$ROOT" B9_3_9f_v3_resultados || true; echo "ARCHIVO PARA COMPARTIR: $ARCHIVE"; exit "$rc"' EXIT
for cmd in git python3 make iverilog vvp sha256sum tar grep sed; do
  command -v "$cmd" >/dev/null || { echo "ERROR: falta $cmd" >&2; exit 2; }
done
[[ -f "$CORE/Makefile" && -f "$CORE/rtl/core/core_top.sv" && -f "$CORE/tb/models/imem_sync_model.sv" ]] || {
  echo "ERROR: faltan Makefile o fuentes en $CORE" >&2; exit 2;
}
{
  git -C "$CORE" rev-parse HEAD
  git -C "$CORE" status --short
} > "$OUT/entorno_antes.txt"
# Guardar la salida COMPLETA antes de mostrar la primera línea.
# Sin pipe a head: con pipefail, el SIGPIPE de iverilog provocaba EXIT_CODE=141.
iverilog -V > "$OUT/iverilog_version_completa.log" 2>&1
sed -n '1p' "$OUT/iverilog_version_completa.log" >> "$OUT/entorno_antes.txt"
cat "$OUT/entorno_antes.txt"
[[ "$(git -C "$CORE" rev-parse HEAD)" == 'cf78be1cc7206879744f7587ab9806a508113b24' ]] || {
  echo 'ERROR: commit diferente al baseline auditado. No se ejecutan pruebas'; exit 2;
}
python3 - "$CORE" "$OUT" <<'PY'
from pathlib import Path
import hashlib,json,sys
core,out=map(Path,sys.argv[1:])
wanted={
  'rtl/core/core_top.sv':'cdc92a0bcd5841a14a0e63fb4a5a9eca140c395b1dd853359663277671d491f7',
  'tb/models/imem_sync_model.sv':'9d4a22ab33992d93abce7727cd6ced2ef9914f20404eac807cc40ca5ef818446',
}
audit={}
for p,digest in wanted.items():
  got=hashlib.sha256((core/p).read_bytes()).hexdigest()
  audit[p]={'actual':got,'esperado':digest,'coincide':got==digest}
(out/'auditoria_fuentes.json').write_text(json.dumps(audit,indent=2)+'\n')
if not all(x['coincide'] for x in audit.values()):
  raise SystemExit('ERROR: fuentes diferentes al baseline. Se preserva evidencia y no se ejecuta')
print('PASS: core_top y modelo IMEM idénticos a baseline B.9.3.9b/e (SHA256)')
PY
printf 'caso,resultado,exit_simulador,causa\n' > "$OUT/resumen.csv"
run_case() {
  # Cada asignacion local se evalua de forma independiente: con set -u,
  # expandir $name dentro del mismo comando local que la declara causa error.
  local id="$1"
  local name="$2"
  local target="$3"
  local vvpfile="$OUT/logs/${name}.vvp"
  local log="$OUT/logs/${name}.log"
  local compilelog="$OUT/logs/${name}.compile.log"
  local rc=0
  if ! make -C "$CORE" --no-print-directory \
    -f Makefile -f "$SCRIPT_DIR/runner.mk" \
    B9F_CASE_ID="$id" B9F_VVP="$vvpfile" B9F_TB="$SCRIPT_DIR/tb_core_imem_integracion.sv" \
    b9f-core-imem-build > "$compilelog" 2>&1; then
    echo "ERROR: compilacion caso $name"; tail -n 50 "$compilelog"; return 1
  fi
  vvp "$vvpfile" > "$log" 2>&1 || rc=$?
  if [[ "$id" == 1 ]]; then
    if (( rc != 0 )) || ! grep -Fq 'PASS_CORE_VALID_FETCH: addr=0x0000000080000000 data=0x0000006f' "$log" || \
       ! grep -Fq 'TB_CORE_REQUEST: addr=0x0000000080000000' "$log" || \
       grep -Eq 'FATAL:|FAIL_|Assertion.*failed|%load/v error' "$log"; then
      echo "ERROR: caso valido fallo: $name (rc=$rc)"; cat "$log"; return 1
    fi
    printf '%s,PASS,0,fetch_valido_core_integrado\n' "$name" >> "$OUT/resumen.csv"
    echo "PASS: $name: fetch valido confirmado en core_top"
  else
    if (( rc == 0 )) || ! grep -Fq "TB_CORE_REQUEST: addr=0x$target" "$log" || \
       ! grep -Fq "IMEM model error: dirección fuera de rango addr=0x$target" "$log" || \
       ! grep -Fq 'FATAL:' "$log" || \
       grep -Eq 'FAIL_|Assertion.*failed|%load/v error' "$log"; then
      echo "ERROR: caso negativo no fallo por causa prevista: $name (rc=$rc)"; cat "$log"; return 1
    fi
    printf '%s,PASS,%s,fatal_esperado_modelo_IMEM\n' "$name" "$rc" >> "$OUT/resumen.csv"
    echo "PASS: $name: core solicitó PC fuera de rango y modelo IMEM produjo fatal esperado (rc=$rc)"
  fi
}
run_case 1 valido_base 0000000080000000
run_case 2 invalido_fin 0000000080000100
run_case 3 invalido_inferior 000000007ffffffc
run_case 4 invalido_mas_2p32 0000000180000000
run_case 5 invalido_mas_2p56 0100000080000000
cat "$OUT/resumen.csv"
[[ $(($(wc -l < "$OUT/resumen.csv") - 1)) -eq 5 ]] || { echo 'ERROR: resumen incompleto'; exit 1; }
git -C "$CORE" rev-parse HEAD > "$OUT/core_head_despues.txt"
git -C "$CORE" status --short > "$OUT/git_status_despues.txt"
cat > "$OUT/conclusion.md" <<'MD'
# B.9.3.9f-v3: integración core_top + IMEM original

La prueba válida comprueba la primera respuesta de instrucción consumible por el frontend.
Los cuatro casos negativos parten desde un RESET_PC fuera del rango de un modelo IMEM de 256 bytes.
En ellos, PASS indica **que el núcleo emite un fetch inválido y el modelo de simulación se detiene mediante $fatal**.
No se acredita un trap arquitectural ni el soporte de `instruction access fault` por `core_top`.
La ausencia de entrada `imem_error` sigue pendiente; no se altera RTL ni configuración ACT4.
Esta prueba no fija PHYS_ADDR_WIDTH ni sustituye una futura verificación en FPGA.
MD
printf '\nPASS: B.9.3.9f-v3 - 1 fetch valido y 4 rechazos de IMEM integrados con core_top.\n'
