#!/usr/bin/env bash
# B.9.3.9h: ensayo dirigido de orden observable MMIO y contraste FENCE/NOP.
# Sin cambios RTL, ni modificacion de configuraciones UDB/Sail.
set -Eeuo pipefail
ulimit -c 0 || true
ROOT="$HOME/TFG_tools"
CORE="${TFG_CORE:-/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
OUT="$ROOT/B9_3_9h_resultados"
ARCHIVE="$ROOT/B9_3_9h_resultados.tar.gz"
if [[ -e "$OUT" || -e "$ARCHIVE" ]]; then
  echo "ERROR: existe evidencia previa; no se sobrescribe: $OUT / $ARCHIVE" >&2
  exit 2
fi
mkdir -p "$OUT/logs"
trap 'rc=$?; trap - EXIT; printf "EXIT_CODE=%s\n" "$rc" > "$OUT/resultado.txt"; tar -czf "$ARCHIVE" -C "$ROOT" B9_3_9h_resultados || true; echo "ARCHIVO PARA COMPARTIR: $ARCHIVE"; exit "$rc"' EXIT
for cmd in git make iverilog vvp python3 tar grep sed; do
  command -v "$cmd" >/dev/null || { echo "ERROR: falta $cmd" >&2; exit 2; }
done
[[ -f "$CORE/Makefile" && -f "$CORE/rtl/core/core_top.sv" && -f "$CORE/tb/models/imem_sync_model.sv" ]] || {
  echo "ERROR: no se encuentra Makefile/core_top/IMEM en CORE=$CORE" >&2; exit 2;
}
{
  git -C "$CORE" rev-parse HEAD
  git -C "$CORE" status --short
} > "$OUT/entorno_antes.txt"
iverilog -V > "$OUT/iverilog_version_completa.log" 2>&1
sed -n '1p' "$OUT/iverilog_version_completa.log" >> "$OUT/entorno_antes.txt"
cat "$OUT/entorno_antes.txt"
[[ "$(git -C "$CORE" rev-parse HEAD)" == 'cf78be1cc7206879744f7587ab9806a508113b24' ]] || {
  echo 'ERROR: commit distinto del baseline; no se ejecuta' >&2; exit 2;
}
python3 - "$CORE" "$OUT" <<'PY'
from pathlib import Path
import hashlib,json,sys
core,out=map(Path,sys.argv[1:])
expected={
 'rtl/core/core_top.sv':'cdc92a0bcd5841a14a0e63fb4a5a9eca140c395b1dd853359663277671d491f7',
 'rtl/core/decoder.sv':'c7a43aa86b9b69ed0d334fb0b225b68d7541f03bc121ef3f9b2a455e8290353f',
 'tb/models/imem_sync_model.sv':'9d4a22ab33992d93abce7727cd6ced2ef9914f20404eac807cc40ca5ef818446',
}
result={}
for file,digest in expected.items():
    actual=hashlib.sha256((core/file).read_bytes()).hexdigest()
    result[file]={'sha256':actual,'expected':digest,'ok':actual==digest}
(out/'fuentes.json').write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8')
if not all(item['ok'] for item in result.values()):
    raise SystemExit('ERROR: fuente diferente al baseline')
print('PASS: tres fuentes originales idénticas por SHA-256')
PY
printf 'caso,resultado,exit_simulador,operaciones_mmio,observacion\n' > "$OUT/resumen.csv"
run_case() {
  local id="$1"
  local name="$2"
  local vvpfile="$OUT/logs/${name}.vvp"
  local log="$OUT/logs/${name}.log"
  local compilelog="$OUT/logs/${name}.compile.log"
  local rc=0
  if ! make -C "$CORE" --no-print-directory -f Makefile -f "$SCRIPT_DIR/runner.mk" \
      B9H_CASE_ID="$id" B9H_VVP="$vvpfile" B9H_TB="$SCRIPT_DIR/tb_b9h_fence_mmio.sv" \
      b9h-fence-mmio-build > "$compilelog" 2>&1; then
    echo "ERROR: compilacion SystemVerilog en $name" >&2
    tail -n 60 "$compilelog"; return 1
  fi
  vvp "$vvpfile" > "$log" 2>&1 || rc=$?
  if (( rc != 0 )) || ! grep -Fq "PASS_B9H_MMIO: case=$id completed=3" "$log" || \
     [[ "$(grep -c 'TB_B9H_COMPLETE:' "$log")" != 3 ]] || \
     grep -Eq 'FATAL:|FAIL_|Assertion.*failed|%load/v error' "$log"; then
    echo "ERROR: simulacion $name no cumplio criterios (rc=$rc)" >&2
    cat "$log"; printf '%s,FAIL,%s,0,consultar_log\n' "$name" "$rc" >> "$OUT/resumen.csv"
    return 1
  fi
  printf '%s,PASS,0,3,orden_observable_y_esperas\n' "$name" >> "$OUT/resumen.csv"
  echo "PASS: $name - 3 accesos MMIO observados en orden y esperas respetadas"
}
run_case 1 con_fence
run_case 2 sin_fence
cat "$OUT/resumen.csv"
[[ $(($(wc -l < "$OUT/resumen.csv") - 1)) -eq 2 ]] || {
  echo 'ERROR: resumen incompleto' >&2; exit 1;
}
git -C "$CORE" rev-parse HEAD > "$OUT/core_head_despues.txt"
git -C "$CORE" status --short > "$OUT/git_status_despues.txt"
cat > "$OUT/conclusion.md" <<'MD'
# B.9.3.9h: limite del ensayo FENCE y MMIO

Dos variantes de la secuencia SW → (FENCE o NOP) → LW → (FENCE o NOP) → SW
se ejecutan en core_top con 3 operaciones MMIO de distinta latencia. Se verifica
el orden visible en la salida exp_valid/exp_ready y la estabilidad durante
los wait-states; la segunda escritura usa el dato que devolvió el load anterior.

**Alcance:** solo esta secuencia de un hart en el camino de MMIO de un
sistema serializado. Que ambas variantes pasen indicaría que el orden ensayado
proviene de la disciplina de ejecución/handshake del diseño y NO demostraría
que FENCE implementa ordenamiento general ni la conformidad RVWMO con varios
observadores, DMA u otros interconectores/outstanding concurrentes.

No cambia RTL, ni redefine el soporte de Zicsr/Sm/PA.
MD
printf '\nPASS: B.9.3.9h - 2 escenarios FENCE/NOP, 3 accesos MMIO ordenados cada uno.\n'
