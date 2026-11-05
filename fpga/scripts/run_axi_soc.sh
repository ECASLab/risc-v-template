#!/usr/bin/env bash
set -euo pipefail
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
REPO="$HOME/tfg_rv64i"
[[ -d "$REPO/.git" ]] || { echo 'ERROR: no existe repositorio'; exit 2; }
[[ "$(git -C "$REPO" branch --show-current)" == 'fpga/platform-uram' ]] || { echo 'ERROR: rama Git inesperada'; exit 3; }
git -C "$REPO" merge-base --is-ancestor 047aaef HEAD || { echo 'ERROR: falta commit base 047aaef'; exit 4; }
[[ -z "$(git -C "$REPO" status --porcelain)" ]] || { echo 'ERROR: repositorio modificado'; exit 5; }
for b in riscv64-unknown-elf-gcc riscv64-unknown-elf-objcopy python3 xvlog xelab xsim vivado; do
  command -v "$b" >/dev/null || { echo "ERROR: falta $b"; exit 6; }
done
RUN_DIR="$(mktemp -d "$HOME/tfg_fpga_checks/p2_7_1_axi_run_XXXXXX")"
export TFG_REPO="$REPO" P27_PKG="$PKG"
cd "$RUN_DIR"
echo "RUN_DIR=$RUN_DIR"
echo '=== BUILD bare-metal RV64I existente ==='
riscv64-unknown-elf-gcc -march=rv64i -mabi=lp64 -mcmodel=medany -mstrict-align \
    -nostdlib -nostartfiles -T "$REPO/sw/baremetal/accelerator/link.ld" \
    -Wl,-Map=integration_accelerator.map -o integration_accelerator.elf \
    "$REPO/sw/baremetal/accelerator/start.S"
riscv64-unknown-elf-objcopy -O binary --gap-fill=0x00 \
    integration_accelerator.elf integration_accelerator.bin
python3 "$REPO/tools/bin_to_mem.py" integration_accelerator.bin \
    --imem integration_imem.hex --dmem integration_dmem.hex
WORDS="$(wc -l < integration_dmem.hex)"
(( WORDS > 0 && WORDS <= 256 )) || { echo "ERROR: IMAGE_WORDS=$WORDS"; exit 7; }
printf 'localparam int unsigned IMAGE_WORDS = %s;\n' "$WORDS" > image_words.svh
echo "IMAGE_WORDS=$WORDS"
echo '=== XSIM: AXI4-Lite -> RAM boot -> RV64I -> MMIO -> marcador ==='
mapfile -t RTL < <(find "$REPO/rtl/core" -maxdepth 1 -type f -name '*.sv' | sort)
(( ${#RTL[@]} == 18 )) || { echo 'ERROR: archivos RTL incompletos'; exit 8; }
if ! xvlog -sv -i "$RUN_DIR" "${RTL[@]}" \
    "$REPO/rtl/platform/rv64i_platform_ram.sv" \
    "$PKG/rtl/platform/rv64i_platform_top.sv" \
    "$PKG/rtl/platform/rv64i_axi_supervisor.sv" \
    "$PKG/rtl/platform/rv64i_soc_axi_top.sv" \
    "$PKG/tb/platform/tb_rv64i_axi_integration.sv" \
    > p27_compile.log 2>&1; then tail -n 65 p27_compile.log; exit 11; fi
if ! xelab -L xpm work.tb_rv64i_axi_integration -s p27_axi_sim \
    > p27_elab.log 2>&1; then tail -n 65 p27_elab.log; exit 12; fi
if ! xsim p27_axi_sim -runall > p27_sim.log 2>&1; then tail -n 65 p27_sim.log; exit 13; fi
grep -q '^PASS: P2.7.1' p27_sim.log || { tail -n 65 p27_sim.log; exit 14; }
grep -E '^PASS:|result_flag=' p27_sim.log
echo '=== SINTESIS OOC: SoC con RAM de 1 MiB ==='
if vivado -mode batch -source "$PKG/fpga/scripts/synth_axi_soc.tcl" \
    -log p27_synth.log -journal p27_synth.jou > p27_console.log 2>&1; then
    grep -E '^AXI_SOC_URAM_COUNT=|^AXI_SOC_BRAM_COUNT=|^P2_7_1_SYNTH_PASS$' p27_console.log
else
    grep -E 'ERROR:|CRITICAL WARNING:|^AXI_SOC_URAM_COUNT=|^AXI_SOC_BRAM_COUNT=' p27_console.log | tail -n 40 || true
    echo 'P2_7_1_SYNTH_FAIL'; exit 22
fi
if grep -q '^CRITICAL WARNING:' p27_console.log; then
    echo 'ERROR: Vivado tiene critical warnings';
    grep '^CRITICAL WARNING:' p27_console.log | tail -n 20
    exit 23
fi
printf 'GIT_STATUS='
if [[ -z "$(git -C "$REPO" status --porcelain)" ]]; then echo CLEAN; else echo DIRTY; exit 24; fi
