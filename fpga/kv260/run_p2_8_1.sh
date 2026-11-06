#!/usr/bin/env bash
set -euo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$HOME/tfg_rv64i"
EXPECTED="0ba9c8a"
[[ -d "$REPO/.git" ]] || { echo "ERROR: falta repositorio"; exit 2; }
[[ "$(git -C "$REPO" branch --show-current)" == "fpga/platform-uram" ]] || { echo 'ERROR: rama distinta'; exit 3; }
git -C "$REPO" merge-base --is-ancestor "$EXPECTED" HEAD || { echo 'ERROR: falta commit base validado'; exit 4; }
[[ -z "$(git -C "$REPO" status --porcelain)" ]] || { echo 'ERROR: repositorio no limpio'; exit 5; }
(cd "$REPO" && sha256sum -c "$PKG/source_wrapper.sha256")
command -v vivado >/dev/null || { echo 'ERROR: Vivado no habilitado'; exit 6; }
mkdir -p "$HOME/tfg_fpga_checks"
RUN_DIR="$(mktemp -d "$HOME/tfg_fpga_checks/p2_8_1_bd_XXXXXX")"
echo "RUN_DIR=$RUN_DIR"
export TFG_REPO="$REPO" P28_PKG="$PKG"
cd "$RUN_DIR"
echo '=== VIVADO IP INTEGRATOR: KV260 PS + RV64I ==='
if vivado -mode batch -source "$PKG/build_ps_pl_bd.tcl" -log vivado_bd.log -journal vivado_bd.jou > vivado_console.log 2>&1; then
  grep -E '^P2_8_1_|^PROJECT_DIR=' vivado_console.log || true
else
  echo 'P2_8_1_BD_FAIL'
  grep -E '^ERROR:|^CRITICAL WARNING:|^SOC_|^ERROR ' vivado_console.log | tail -n 30 || true
  tail -n 35 vivado_console.log
  exit 10
fi
if grep -q '^CRITICAL WARNING:' vivado_console.log; then
  echo 'P2_8_1_CRITICAL_WARNINGS_REVIEW_REQUIRED'
  grep '^CRITICAL WARNING:' vivado_console.log | tail -n 15
  exit 11
fi
[[ -s bd_summary.txt ]] || { echo 'ERROR: sin resumen BD'; exit 12; }
echo '=== RESUMEN DEL DISEÑO ==='
cat bd_summary.txt
echo '=== GIT STATUS ==='
if [[ -z "$(git -C "$REPO" status --porcelain)" ]]; then echo GIT_STATUS=CLEAN; else echo GIT_STATUS=DIRTY; exit 13; fi
