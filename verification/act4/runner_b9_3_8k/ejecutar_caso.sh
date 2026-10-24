#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# TFG B.9.3.8k: una prueba ACT4 RV64I seleccionada sobre core_top.
# Cada prueba usa resultados aislados; los repositorios y pruebas anteriores no se modifican.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BASE="$HOME/TFG_tools"
ACT4="$BASE/riscv-arch-test"
PREP="$BASE/B9_3_7d_primer_elf"
CORE="${CORE_REPO:-/run/media/saul/Data/Documentos/Linux/TFG_downloads/riscv-core-project/risc-v-template}"
CASE="${ACT4_CASE:?Definir ACT4_CASE a una prueba del lote B.9.3.8k}"
case "$CASE" in
  I-fence-00|I-nop-00) ;;
  *) echo "ERROR: caso no autorizado: $CASE" >&2; exit 2 ;;
esac
OUT="$BASE/B9_3_8k_resultados/casos/$CASE"
PACK="$BASE/B9_3_8k_resultados/paquetes/$CASE.tar.gz"
HEAD="d6094ad3ede5268b454197e7bb8eb1cbcbe140d0"
UDB_SHA="056eecbfcd0973cede1464c4e8c19c89e8bfba3627e6decaa07f67d70461a6c1"
SAIL_SHA="c2000c9c85ffde07517fb581e5af520d8709886ea942e15583c30d6a803772ea"

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ ! -e "$OUT" && ! -e "$PACK" ]] || fail "Ya existen resultados del caso y no se sobrescriben: $OUT o $PACK"
[[ -f "$ACT4/tests/rv64i/I/$CASE.S" ]] || fail "Falta la fuente $CASE.S (ejecutar make tests EXTENSIONS=I si procede)"
[[ -f "$PREP/tests/env/c_test_start.S" && -f "$PREP/tests/env/c_test_support.c" ]] || fail 'Falta tests/env de B.9.3.7d'
[[ -f "$CORE/rtl/core/core_top.sv" && -f "$CORE/Makefile" ]] || fail 'No se encuentra el repositorio del núcleo'
[[ "$(git -C "$ACT4" rev-parse HEAD)" == "$HEAD" ]] || fail 'ACT4 está en otro commit'
[[ -z "$(git -C "$ACT4" status --porcelain)" ]] || fail 'ACT4 tiene modificaciones; revisar antes de proseguir'
for tool in git sha256sum make iverilog vvp python3 tar riscv64-unknown-elf-readelf; do
  command -v "$tool" >/dev/null || fail "Falta herramienta: $tool"
done
[[ -x /usr/bin/clang-22 && -x "$BASE/sail-riscv-0.16/bin/sail_riscv_sim" ]] || fail 'Falta Clang 22 o Sail 0.16'
[[ -x "$BASE/riscv-arch-test/.venv/bin/python" ]] || fail 'Falta entorno Python de ACT4'
for f in test_config.yaml tfg-rv64i.yaml link.ld rvmodel_macros.h sail.json; do
  [[ -f "$PREP/config/$f" ]] || fail "Falta configuración B.9.3.7d: $f"
done
[[ "$(sha256sum "$PREP/config/tfg-rv64i.yaml" | cut -d' ' -f1)" == "$UDB_SHA" ]] || fail 'Cambió la UDB validada'
[[ "$(sha256sum "$PREP/config/sail.json" | cut -d' ' -f1)" == "$SAIL_SHA" ]] || fail 'Cambió sail.json validado'

mkdir -p "$OUT"/{config,tests/rv64i/I,tests/env,work,imagenes,reportes}
finish() {
  rc=$?
  trap - EXIT
  echo "$rc" > "$OUT/estado.txt"
  if (( rc == 0 )); then
    echo "PASS: B.9.3.8k - $CASE ejecutado en core_top (tohost=1)"
  else
    echo "PENDIENTE: B.9.3.8k $CASE fallo (exit=$rc); ver registros. No cambiar RTL aun."
  fi
  # Archivar trazabilidad sin incluir HEX de 1 MiB ni todos los archivos intermedios.
  paths=(contexto.txt estado.txt act.log conversion.log memoria.log compile.log sim.log)
  for file in reporte_elf.txt imagenes/metadata.json reportes/variables.txt; do
    [[ -f "$OUT/$file" ]] && paths+=("$file")
  done
  if [[ -f "$OUT/work/tfg-rv64i-clang22/elfs/rv64i/I/$CASE.elf" ]]; then
    paths+=("work/tfg-rv64i-clang22/elfs/rv64i/I/$CASE.elf")
  fi
  if [[ -f "$OUT/work/tfg-rv64i-clang22/test_list.md" ]]; then
    paths+=("work/tfg-rv64i-clang22/test_list.md")
  fi
  tar -czf "$PACK" -C "$OUT" "${paths[@]}" || true
  printf 'ARCHIVO PARA COMPARTIR: %s\n' "$PACK"
  exit "$rc"
}
trap finish EXIT
: > "$OUT/act.log"; : > "$OUT/conversion.log"; : > "$OUT/memoria.log"
: > "$OUT/compile.log"; : > "$OUT/sim.log"
cp -a "$PREP/config/." "$OUT/config/"
cp -a "$PREP/tests/env/." "$OUT/tests/env/"
cp "$ACT4/tests/rv64i/I/$CASE.S" "$OUT/tests/rv64i/I/$CASE.S"
{
  echo 'TFG B.9.3.8k - Prueba ACT4: $CASE'
  date -Is
  printf 'ACT4 HEAD: %s\n' "$HEAD"
  printf 'CORE HEAD: %s\n' "$(git -C "$CORE" rev-parse HEAD)"
  echo 'CORE status:'
  git -C "$CORE" status --short
  echo 'ACT4 status:'
  git -C "$ACT4" status --short
  echo 'UDB: Sm provisional, include_priv_tests: false'
  echo 'Clang:'; /usr/bin/clang-22 --version | head -n 1
  echo 'Sail:'; "$BASE/sail-riscv-0.16/bin/sail_riscv_sim" --version
  sha256sum "$OUT/config/"{test_config.yaml,tfg-rv64i.yaml,link.ld,rvmodel_macros.h,sail.json}
  sha256sum "$OUT/tests/rv64i/I/$CASE.S"
  printf 'env files: %s\n' "$(find "$OUT/tests/env" -type f | wc -l)"
} > "$OUT/contexto.txt" 2>&1
cat "$OUT/contexto.txt"

export PATH="$HOME/.local/bin:$PATH"
cd "$ACT4"
eval "$(mise activate bash)"
echo 'FASE 1/4: ACT4 construyendo ELF autocontenido...'
if ! mise exec -- uv run act "$OUT/config/test_config.yaml" \
  --test-dir "$OUT/tests" --workdir "$OUT/work" \
  --extensions I --jobs 1 --debug > "$OUT/act.log" 2>&1; then
  tail -n 80 "$OUT/act.log"
  fail 'ACT4 no pudo generar el ELF'
fi
tail -n 12 "$OUT/act.log"
mapfile -d '' ELFS < <(find "$OUT/work" -type f -path '*/elfs/*.elf' -print0 | sort -z)
[[ "${#ELFS[@]}" -eq 1 ]] || fail "ACT4 produjo ${#ELFS[@]} ELF finales; se requiere exactamente uno"
ELF="${ELFS[0]}"
[[ "$(basename "$ELF")" == "$CASE.elf" ]] || fail "ELF inesperado: $ELF"
echo "PASS: ACT4 genero exactamente $CASE.elf"
{
  riscv64-unknown-elf-readelf -hW "$ELF"
  riscv64-unknown-elf-readelf -lW "$ELF"
  riscv64-unknown-elf-readelf -AW "$ELF"
  riscv64-unknown-elf-readelf -sW "$ELF" | grep -E 'rvtest_entry_point|tohost|begin_signature|end_signature' || true
} > "$OUT/reporte_elf.txt" 2>&1

printf 'FASE 2/4: convertir ELF a IMEM/DMEM de 1 MiB...\n'
python3 "$ROOT/convertir_elf_act4_generico.py" \
  --elf "$ELF" --out "$OUT/imagenes" --base 0x80000000 --ram-size 0x100000 \
  > "$OUT/conversion.log" 2>&1 || { cat "$OUT/conversion.log"; fail 'Conversion fallida'; }
cat "$OUT/conversion.log"

printf 'FASE 3/4: verificar integridad y compilar testbench...\n'
python3 "$ROOT/verificar_imagenes_generico.py" "$OUT/imagenes" "$OUT/reportes/variables.txt" \
  > "$OUT/memoria.log" 2>&1 || { cat "$OUT/memoria.log"; fail 'Imagenes invalidas'; }
cat "$OUT/memoria.log"
# Archivo generado solo por el verificador con nombres de variables fijos.
# shellcheck source=/dev/null
source "$OUT/reportes/variables.txt"
[[ "$CASE_NAME" == "$CASE" ]] || fail "Caso de metadata no coincide: $CASE_NAME"
VVP_FILE="$OUT/reportes/tb_core_act4_generic.vvp"
if ! make -C "$CORE" --no-print-directory \
  -f Makefile -f "$ROOT/act4_runner.mk" \
  ACT4_VVP="$VVP_FILE" ACT4_TB="$ROOT/tb_core_act4_generic.sv" \
  act4-runner-build > "$OUT/compile.log" 2>&1; then
  tail -n 60 "$OUT/compile.log"
  fail 'Error de compilacion Icarus'
fi
echo 'PASS: testbench genérico compilado'

printf 'FASE 4/4: ejecutar ELF en core_top...\n'
MAX_CYCLES="${ACT4_MAX_CYCLES:-500000}"
set +e
vvp "$VVP_FILE" \
  "+IMEM_HEX=$IMEM_FILE" "+DMEM_HEX=$DMEM_FILE" \
  "+CASE_NAME=$CASE_NAME" "+ENTRY_HEX=$ENTRY_HEX" \
  "+HIGH_TEXT_HEX=$HIGH_TEXT_HEX" "+TOHOST_HEX=$TOHOST_HEX" \
  "+MAX_CYCLES=$MAX_CYCLES" > "$OUT/sim.log" 2>&1
SIM_RC=$?
set -e
tail -n 35 "$OUT/sim.log"
[[ "$SIM_RC" -eq 0 ]] || fail "La simulacion fallo (exit=$SIM_RC)"
grep -Fq "PASS: ACT4 $CASE ejecutado en core_top (tohost=1)" "$OUT/sim.log" \
  || fail 'La simulacion no confirmo tohost=1'
echo "PASS: escritura de tohost verificada para $CASE"
