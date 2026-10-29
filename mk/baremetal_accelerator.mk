# TFG: programa bare-metal que opera el acelerador MMIO.
# Se incluye al final del Makefile principal.
ACC_DIR := sw/baremetal/accelerator
ACC_BUILD := $(BUILD_DIR)/baremetal_accelerator
ACC_ELF := $(ACC_BUILD)/accelerator.elf
ACC_BIN := $(ACC_BUILD)/accelerator.bin
ACC_IMEM := $(ACC_BUILD)/accelerator_imem.hex
ACC_DMEM := $(ACC_BUILD)/accelerator_dmem.hex
ACC_TB := tb_core_baremetal_accelerator
ACC_VVP := $(ACC_BUILD)/$(ACC_TB).vvp
ACC_LOG := $(ACC_BUILD)/$(ACC_TB).log

.PHONY: baremetal-accelerator
baremetal-accelerator: check-tools check-riscv-tools $(BUILD_DIR)
> @mkdir -p $(ACC_BUILD)
> @$(RISCV_GCC) -march=rv64i -mabi=lp64 -mcmodel=medany \
>     -mstrict-align -nostdlib -nostartfiles \
>     -T $(ACC_DIR)/link.ld -Wl,-Map=$(ACC_BUILD)/accelerator.map \
>     -o $(ACC_ELF) $(ACC_DIR)/start.S
> @$(RISCV_OBJCOPY) -O binary --gap-fill=0x00 $(ACC_ELF) $(ACC_BIN)
> @$(PYTHON) tools/bin_to_mem.py $(ACC_BIN) --imem $(ACC_IMEM) --dmem $(ACC_DMEM)
> @$(IVERILOG) $(IVERILOG_FLAGS) -s $(ACC_TB) -o $(ACC_VVP) \
>     $(RTL_FILES) $(IMEM_SYNC_MODEL) $(DMEM_SYNC_MODEL) \
>     $(TB_DIR)/$(ACC_TB).sv
> @set -o pipefail; \
> image_bytes=$$(wc -c < $(ACC_BIN)); \
> $(VVP) $(ACC_VVP) \
>     +IMEM_HEX=$(abspath $(ACC_IMEM)) \
>     +DMEM_HEX=$(abspath $(ACC_DMEM)) \
>     +IMAGE_BYTES=$$image_bytes | tee $(ACC_LOG); \
> sim_status=$${PIPESTATUS[0]}; \
> if [ $$sim_status -ne 0 ]; then exit $$sim_status; fi; \
> if ! grep -q '^PASS: bare-metal accelerator MMIO' $(ACC_LOG); then \
>     echo '[FAIL] Falta indicador PASS del testbench'; exit 1; fi
> @echo 'PASS: baremetal-accelerator completado'

# ------------------------------------------------------------
# P1.2: integrar la prueba real en la regresion y en el lint.
# No se agrega a TESTS: requiere generar ELF e imagenes de
# memoria y suministrarlas al TB mediante plusargs.
# GNU make agrega estas dependencias a las reglas existentes.
# ------------------------------------------------------------
.PHONY: lint-baremetal-accelerator

lint-baremetal-accelerator: check-verilator
> @echo "============================================================"
> @echo "LINT: bare-metal accelerator"
> @echo "============================================================"
> @$(VERILATOR) $(VERILATOR_TB_FLAGS) \
>     --top-module $(ACC_TB) \
>     $(RTL_FILES) \
>     $(IMEM_SYNC_MODEL) $(DMEM_SYNC_MODEL) \
>     $(TB_DIR)/$(ACC_TB).sv
> @echo "PASS: lint bare-metal accelerator completado"

# Dependencias adicionales sin reemplazar las recetas originales.
regression: baremetal-accelerator
regress: baremetal-accelerator
lint: lint-baremetal-accelerator
