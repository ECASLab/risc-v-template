# ============================================================
# Makefile - RISC-V Core Project
# Ubicación esperada:
#   risc-v-template/Makefile
#
# Uso principal:
#   make
#   make regression
#   make lint
#   make clean
#
# Ejecutar una prueba específica:
#   make tb_core_system_trap
#   make run-one TB=tb_core_illegal_trap
# ============================================================

SHELL := /bin/bash

# Permite usar ">" en lugar de tab en las recetas.
.RECIPEPREFIX := >

# ------------------------------------------------------------
# Herramientas
# ------------------------------------------------------------

IVERILOG  ?= iverilog
VVP       ?= vvp
VERILATOR ?= verilator

# ------------------------------------------------------------
# Directorios
# ------------------------------------------------------------

BUILD_DIR := build
TB_DIR    := tb/tb_sv
TB_MODEL_DIR := tb/models
RTL_DIR   := rtl/core

EVID_DIR := docs/verification
LOG_DIR  := $(EVID_DIR)/logs
DATE_STR ?= $(shell date +%F_%H-%M-%S)

# ------------------------------------------------------------
# Flags
# ------------------------------------------------------------

IVERILOG_FLAGS := -g2012 -Wall
# ------------------------------------------------------------
# Verilator
#
# RTL:
#   Lint estricto. El código sintetizable debe permanecer
#   libre de warnings.
#
# Testbenches:
#   Conservamos -Wall, pero filtramos únicamente warnings
#   de estilo deliberados y repetitivos propios del entorno
#   de simulación.
# ------------------------------------------------------------
VERILATOR_RTL_FLAGS := --lint-only -Wall

VERILATOR_TB_FLAGS := --lint-only --timing -Wall \
	-Wno-PINCONNECTEMPTY \
	-Wno-UNUSEDSIGNAL \
	-Wno-UNUSEDPARAM \
	-Wno-BLKSEQ

# ------------------------------------------------------------
# RTL del núcleo
# ------------------------------------------------------------

RTL_FILES := \
	$(RTL_DIR)/alu.sv \
	$(RTL_DIR)/branch_unit.sv \
	$(RTL_DIR)/csr_file.sv \
	$(RTL_DIR)/decoder.sv \
	$(RTL_DIR)/ex_mem_reg.sv \
	$(RTL_DIR)/hazard_unit.sv \
	$(RTL_DIR)/id_ex_reg.sv \
	$(RTL_DIR)/if_id_reg.sv \
	$(RTL_DIR)/imm_gen.sv \
	$(RTL_DIR)/mem_wb_reg.sv \
	$(RTL_DIR)/regfile.sv \
	$(RTL_DIR)/expansion_demo_periph.sv \
	$(RTL_DIR)/axi4lite_expansion_demo_periph.sv \
	$(RTL_DIR)/exp_axi4lite_master_bridge.sv \
	$(RTL_DIR)/dmem_handshake_ctrl.sv \
	$(RTL_DIR)/imem_handshake_ctrl.sv \
	$(RTL_DIR)/dmem_legacy_compat.sv \
	$(RTL_DIR)/core_top.sv


# ------------------------------------------------------------
# Modelos de verificación
# ------------------------------------------------------------

DMEM_SYNC_MODEL := $(TB_MODEL_DIR)/dmem_sync_model.sv
IMEM_SYNC_MODEL := $(TB_MODEL_DIR)/imem_sync_model.sv

# Tests que necesitan el modelo DMEM síncrono real.
DMEM_SYNC_TESTS := \
	tb_core_dmem_sync \
	tb_core_dmem_sync_fault \
	tb_core_dmem_sync_subword \
	tb_core_smoke \
	tb_core_hazards \
	tb_core_hazard_branch \
	tb_core_mem_misaligned_trap

# ------------------------------------------------------------
# Tests que necesitan el modelo IMEM síncrono
# ------------------------------------------------------------

IMEM_SYNC_TESTS := \
	tb_imem_sync_model \
	tb_core_imem_sync

# ------------------------------------------------------------
# Testbenches SystemVerilog
# El nombre debe coincidir con:
#   tb/tb_sv/<nombre>.sv
# y con el módulo top:
#   module <nombre>;
# ------------------------------------------------------------

TESTS := \
	tb_alu_w \
	tb_decoder_w \
	tb_dmem_handshake_ctrl \
	tb_imem_handshake_ctrl \
	tb_dmem_legacy_compat \
	$(DMEM_SYNC_TESTS) \
	$(IMEM_SYNC_TESTS) \
	tb_core_jump \
	tb_core_mtval \
	tb_core_system_trap \
	tb_core_csr_ops \
	tb_core_ebreak_trap \
	tb_core_branch_misaligned_trap \
	tb_core_jal_misaligned_trap \
	tb_core_illegal_trap \
	tb_core_jalr_misaligned_trap \
	tb_core_directed \
	tb_expansion_demo_periph \
	tb_core_expansion_mmio \
	tb_core_expansion_fault_trap \
	tb_core_expansion_store_fault_trap \
	tb_axi4lite_expansion_demo_periph \
	tb_exp_axi4lite_master_bridge \
	tb_core_expansion_axi4lite_wait \
	tb_core_expansion_priv_wait \
	tb_core_expansion_axi4lite_load_fault \
	tb_core_expansion_axi4lite_store_fault

# ------------------------------------------------------------
# Testbenches legacy
#
# Se conservan para trazabilidad y ejecución manual, pero no
# forman parte de la regresión funcional obligatoria.
#
# tb_core_mem_sizes fue reemplazado funcionalmente por
# tb_core_dmem_sync_subword, que además verifica el handshake
# DMEM síncrono, wait-states, offsets, wstrb y wdata.
# ------------------------------------------------------------

LEGACY_TESTS := \
	tb_core_mem_sizes

# Solo estos TB necesitan compilar el modelo de DMEM síncrona.
$(DMEM_SYNC_TESTS): EXTRA_TB_SRCS := $(DMEM_SYNC_MODEL)
$(addprefix lint_,$(DMEM_SYNC_TESTS)): EXTRA_TB_SRCS := $(DMEM_SYNC_MODEL)

$(IMEM_SYNC_TESTS): EXTRA_TB_SRCS := $(IMEM_SYNC_MODEL)
$(addprefix lint_,$(IMEM_SYNC_TESTS)): EXTRA_TB_SRCS := $(IMEM_SYNC_MODEL)

# tb_core_hazard_branch utiliza simultáneamente DMEM e IMEM
# síncronas reales.
tb_core_hazard_branch: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_hazard_branch: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_jump: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_jump: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_system_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_system_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_ebreak_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_ebreak_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_illegal_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_illegal_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_branch_misaligned_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_branch_misaligned_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_jal_misaligned_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_jal_misaligned_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_jalr_misaligned_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_jalr_misaligned_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_mtval: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_mtval: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_csr_ops: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_csr_ops: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_mem_misaligned_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_mem_misaligned_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_smoke: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_smoke: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_hazards: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_hazards: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_dmem_sync: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_dmem_sync: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_dmem_sync_fault: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_dmem_sync_fault: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_dmem_sync_subword: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_dmem_sync_subword: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_directed: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_directed: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_expansion_mmio: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_expansion_mmio: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_expansion_fault_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_expansion_fault_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_expansion_store_fault_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_expansion_store_fault_trap: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_expansion_axi4lite_wait: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_expansion_axi4lite_wait: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_expansion_axi4lite_load_fault: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_expansion_axi4lite_load_fault: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_expansion_axi4lite_store_fault: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_expansion_axi4lite_store_fault: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_expansion_priv_wait: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_expansion_priv_wait: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

tb_core_mem_sizes: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)
lint_tb_core_mem_sizes: EXTRA_TB_SRCS += $(IMEM_SYNC_MODEL)

ALL_TESTS  := $(TESTS) $(LEGACY_TESTS)
LINT_TESTS := $(addprefix lint_,$(ALL_TESTS))

# ------------------------------------------------------------
# Targets phony
# ------------------------------------------------------------

.PHONY: all help \
	check-tools check-verilator \
	sim regression regress lint lint-rtl lint-log \
	run-one list-tests \
	evidence_dirs regress-log \
	clean clean-vcd \
	$(ALL_TESTS) $(LINT_TESTS)

# ------------------------------------------------------------
# Target por defecto
# ------------------------------------------------------------

all: regression

help:
> @echo "Targets disponibles:"
> @echo "  make                         Ejecuta regression"
> @echo "  make regression              Ejecuta todas las simulaciones con Icarus"
> @echo "  make regress                 Ejecuta simulación + lint"
> @echo "  make lint                    Ejecuta lint con Verilator"
> @echo "  make list-tests              Lista los testbenches configurados"
> @echo "  make run-one TB=<test>       Ejecuta un test específico"
> @echo "  make regress-log             Guarda log de regresión en docs/verification/logs"
> @echo "  make clean                   Limpia build"
> @echo "  make tb_core_expansion_store_fault_trap"
> @echo ""
> @echo "Ejemplos:"
> @echo "  make tb_core_system_trap"
> @echo "  make tb_expansion_demo_periph"
> @echo "  make tb_core_expansion_fault_trap"
> @echo "  make tb_core_expansion_mmio"
> @echo "  make run-one TB=tb_core_illegal_trap"
> @echo "  make run-one TB=tb_core_expansion_mmio"
> @echo "  make run-one TB=tb_core_expansion_fault_trap"
> @echo "  make regress-log"

# ------------------------------------------------------------
# Directorios
# ------------------------------------------------------------

$(BUILD_DIR):
> @mkdir -p $(BUILD_DIR)

$(LOG_DIR):
> @mkdir -p $(LOG_DIR)

evidence_dirs: $(LOG_DIR)

# ------------------------------------------------------------
# Revisión de herramientas
# ------------------------------------------------------------

check-tools:
> @command -v $(IVERILOG) >/dev/null 2>&1 || { echo "ERROR: no se encontró $(IVERILOG)"; exit 1; }
> @command -v $(VVP) >/dev/null 2>&1 || { echo "ERROR: no se encontró $(VVP)"; exit 1; }

check-verilator:
> @command -v $(VERILATOR) >/dev/null 2>&1 || { echo "ERROR: no se encontró $(VERILATOR)"; exit 1; }

# ------------------------------------------------------------
# Lista de pruebas
# ------------------------------------------------------------

list-tests:
> @echo "Testbenches configurados:"
> @for t in $(TESTS); do echo "  $$t"; done

# ------------------------------------------------------------
# Simulación individual
# ------------------------------------------------------------

$(ALL_TESTS): check-tools $(BUILD_DIR)
> @echo "============================================================"
> @echo "TEST: $@"
> @echo "============================================================"
> @if [ ! -f "$(TB_DIR)/$@.sv" ]; then \
> 	echo "ERROR: no existe $(TB_DIR)/$@.sv"; \
> 	exit 1; \
> fi
> @$(IVERILOG) $(IVERILOG_FLAGS) \
> 	-s $@ \
> 	-o $(BUILD_DIR)/$@.vvp \
> 	$(RTL_FILES) \
> 	$(EXTRA_TB_SRCS) \
> 	$(TB_DIR)/$@.sv
> @set -o pipefail; \
> $(VVP) $(BUILD_DIR)/$@.vvp | tee $(BUILD_DIR)/$@.log; \
> sim_status=$${PIPESTATUS[0]}; \
> if [ $$sim_status -ne 0 ]; then \
> 	echo "[FAIL] $@ -- vvp retornó error"; \
> 	exit $$sim_status; \
> fi; \
> if grep -Eq "(^|[[:space:]])FAIL:|(^|[[:space:]])ERROR:" $(BUILD_DIR)/$@.log; then \
> 	echo "[FAIL] $@ -- el log contiene FAIL o ERROR"; \
> 	exit 1; \
> fi
> @echo "[PASS] $@"

# ------------------------------------------------------------
# Simulación completa
# ------------------------------------------------------------

sim: $(TESTS)

regression: sim
> @echo "============================================================"
> @echo "PASS: regresión local con Icarus completada"
> @echo "============================================================"

# Mantengo regress como alias más estricto:
# simulación + lint.
regress: sim lint
> @echo "============================================================"
> @echo "PASS: regresión completa con simulación + lint completada"
> @echo "============================================================"

# ------------------------------------------------------------
# Ejecutar un test específico por variable
# ------------------------------------------------------------

run-one:
> @if [ -z "$(TB)" ]; then \
> 	echo "ERROR: usa make run-one TB=nombre_del_test"; \
> 	echo "Ejemplo: make run-one TB=tb_core_system_trap"; \
> 	exit 1; \
> fi
> @$(MAKE) $(TB)

# ------------------------------------------------------------
# Lint con Verilator
# ------------------------------------------------------------

lint-rtl: check-verilator
> @echo "============================================================"
> @echo "LINT RTL: core_top + módulos del núcleo"
> @echo "============================================================"
> @$(VERILATOR) $(VERILATOR_RTL_FLAGS) \
> 	--top-module core_top \
> 	$(RTL_FILES)
> @echo "============================================================"
> @echo "PASS: lint RTL completado"
> @echo "============================================================"

lint-log: evidence_dirs
> @set -o pipefail; \
> $(MAKE) lint-rtl 2>&1 | tee $(LOG_DIR)/$(DATE_STR)_lint_rtl.log

$(LINT_TESTS): lint_%: check-verilator
> @echo "============================================================"
> @echo "LINT: $*"
> @echo "============================================================"
> @if [ ! -f "$(TB_DIR)/$*.sv" ]; then \
> 	echo "ERROR: no existe $(TB_DIR)/$*.sv"; \
> 	exit 1; \
> fi
>@$(VERILATOR) $(VERILATOR_TB_FLAGS) \
> 	--top-module $* \
> 	$(RTL_FILES) \
> 	$(EXTRA_TB_SRCS) \
> 	$(TB_DIR)/$*.sv
> @echo "============================================================"
> @echo "PASS: lint $* completado"
> @echo "============================================================"

lint: lint-rtl $(LINT_TESTS)
> @echo "============================================================"
> @echo "PASS: lint completado"
> @echo "============================================================"

# ------------------------------------------------------------
# Regresión con log de evidencia
# ------------------------------------------------------------

regress-log: evidence_dirs
> @set -o pipefail; \
> $(MAKE) regression 2>&1 | tee $(LOG_DIR)/$(DATE_STR)_regression_local.log

# ------------------------------------------------------------
# Limpieza
# ------------------------------------------------------------

clean:
> @rm -rf $(BUILD_DIR)

clean-vcd:
> @rm -f *.vcd
> @rm -f tb/*.vcd
> @rm -f tb/tb_sv/*.vcd
> @rm -f $(BUILD_DIR)/*.vcd