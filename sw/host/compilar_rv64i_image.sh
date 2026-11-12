#!/usr/bin/env bash
# Ejecutar SOLO en xrt-france, no modifica el repositorio ni la Kria.
set -euo pipefail
REPO="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
test -s "$REPO/sw/baremetal/accelerator/start.S"
command -v riscv64-unknown-elf-gcc >/dev/null || { echo 'ERROR: habilita amd_202401_enable'; exit 2; }
command -v riscv64-unknown-elf-objcopy >/dev/null || { echo 'ERROR: falta objcopy RISC-V'; exit 2; }
OUT="${1:-$PWD}"
mkdir -p "$OUT"
OUT="$(realpath "$OUT")"
riscv64-unknown-elf-gcc -march=rv64i -mabi=lp64 -mcmodel=medany -mstrict-align \
  -nostdlib -nostartfiles -T "$REPO/sw/baremetal/accelerator/link.ld" \
  -Wl,-Map="$OUT/accelerator.map" -o "$OUT/accelerator.elf" \
  "$REPO/sw/baremetal/accelerator/start.S"
riscv64-unknown-elf-objcopy -O binary --gap-fill=0x00 \
  "$OUT/accelerator.elf" "$OUT/accelerator.bin"
SIZE=$(stat -c %s "$OUT/accelerator.bin")
test "$SIZE" -eq 776 || { echo "ERROR: tamaño inesperado: $SIZE"; exit 3; }
echo "IMAGE_READY=$OUT/accelerator.bin"
sha256sum "$OUT/accelerator.bin"
