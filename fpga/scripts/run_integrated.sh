#!/usr/bin/env bash
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
[[ -f "$REPO/rtl/platform/rv64i_platform_ram.sv" ]] || { echo 'ERROR: falta plataforma'; exit 2; }
for bin in riscv64-unknown-elf-gcc riscv64-unknown-elf-objcopy python3 xvlog xelab xsim vivado; do
    command -v "$bin" >/dev/null || { echo "ERROR: falta $bin"; exit 3; }
done
mkdir -p "$HOME/tfg_fpga_checks"
RUN_DIR="$(mktemp -d "$HOME/tfg_fpga_checks/p2_6_3_repro_XXXXXX")"
export TFG_REPO="$REPO"
cd "$RUN_DIR"
echo "RUN_DIR=$RUN_DIR"
echo '=== PROGRAMA BARE-METAL ==='
riscv64-unknown-elf-gcc -march=rv64i -mabi=lp64 -mcmodel=medany -mstrict-align \
    -nostdlib -nostartfiles -T "$REPO/sw/baremetal/accelerator/link.ld" \
    -Wl,-Map=integration_accelerator.map -o integration_accelerator.elf \
    "$REPO/sw/baremetal/accelerator/start.S"
riscv64-unknown-elf-objcopy -O binary --gap-fill=0x00 \
    integration_accelerator.elf integration_accelerator.bin
python3 "$REPO/tools/bin_to_mem.py" integration_accelerator.bin \
    --imem integration_imem.hex --dmem integration_dmem.hex
WORDS="$(wc -l < integration_dmem.hex)"
(( WORDS > 0 && WORDS <= 256 )) || { echo "ERROR: IMAGE_WORDS=$WORDS"; exit 4; }
printf 'localparam int unsigned IMAGE_WORDS = %s;\n' "$WORDS" > image_words.svh
echo "IMAGE_WORDS=$WORDS"
echo '=== SIMULACION ==='
mapfile -t RTL < <(find "$REPO/rtl/core" -maxdepth 1 -name '*.sv' -type f | sort)
(( ${#RTL[@]} == 18 )) || { echo 'ERROR: archivos RTL inesperados'; exit 5; }
xvlog -sv -i "$RUN_DIR" "${RTL[@]}" \
    "$REPO/rtl/platform/rv64i_platform_ram.sv" \
    "$REPO/rtl/platform/rv64i_platform_top.sv" \
    "$REPO/tb/platform/tb_rv64i_platform_integration.sv" \
    > integration_compile.log 2>&1 || { tail -n 50 integration_compile.log; exit 11; }
xelab -L xpm work.tb_rv64i_platform_integration -s integrated_xsim \
    > integration_elab.log 2>&1 || { tail -n 50 integration_elab.log; exit 12; }
xsim integrated_xsim -runall > integration_sim.log 2>&1 || { tail -n 50 integration_sim.log; exit 13; }
grep -q '^PASS: P2.6.2' integration_sim.log || { tail -n 50 integration_sim.log; exit 14; }
grep -E '^PASS:|result_flag = ' integration_sim.log
echo '=== SINTESIS OOC 1 MiB ==='
if vivado -mode batch -source "$REPO/fpga/scripts/synth_integrated_top.tcl" \
    -log integrated_synth.log -journal integrated_synth.jou \
    > integrated_console.log 2>&1; then
    grep -E '^INTEGRATED_URAM_COUNT=|^INTEGRATED_BRAM_COUNT=|^P2_6_3_SYNTH_PASS$' integrated_console.log
else
    grep -E 'ERROR:|CRITICAL WARNING:|^INTEGRATED_URAM_COUNT=|^INTEGRATED_BRAM_COUNT=' \
        integrated_console.log | tail -n 45 || true
    echo 'SINTESIS_INTEGRADA_FAIL'; exit 22
fi
printf 'GIT_STATUS='
if [[ -z "$(git -C "$REPO" status --porcelain)" ]]; then echo CLEAN; else echo 'CON_CAMBIOS (verificar si estan staged)'; fi
