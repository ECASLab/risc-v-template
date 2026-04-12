EVID_DIR := docs/verification
LOG_DIR  := $(EVID_DIR)/logs
DATE_STR ?= $(shell date +%F)

IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR ?= verilator

BUILD_DIR := build
TB_DIR    := tb/tb_sv
RTL_DIR   := rtl/core

IVERILOG_FLAGS := -g2012 -Wall
VERILATOR_FLAGS := --lint-only --timing

TESTS := \
	tb_core_smoke \
	tb_core_hazard_branch \
	tb_core_jump \
	tb_core_mem_sizes

.PHONY: all sim lint regress clean \
        tb_core_smoke tb_core_hazard_branch tb_core_jump tb_core_mem_sizes \
        lint_tb_core_smoke lint_tb_core_hazard_branch lint_tb_core_jump lint_tb_core_mem_sizes

all: regress

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

# -------------------------
# Simulación
# -------------------------

tb_core_smoke: $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s tb_core_smoke -o $(BUILD_DIR)/tb_core_smoke.vvp -c $(TB_DIR)/core_smoke.f
	$(VVP) $(BUILD_DIR)/tb_core_smoke.vvp

tb_core_hazard_branch: $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s tb_core_hazard_branch -o $(BUILD_DIR)/tb_core_hazard_branch.vvp -c $(TB_DIR)/core_hazard_branch.f
	$(VVP) $(BUILD_DIR)/tb_core_hazard_branch.vvp

tb_core_jump: $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s tb_core_jump -o $(BUILD_DIR)/tb_core_jump.vvp -c $(TB_DIR)/core_jump.f
	$(VVP) $(BUILD_DIR)/tb_core_jump.vvp

tb_core_mem_sizes: $(BUILD_DIR)
	$(IVERILOG) $(IVERILOG_FLAGS) -s tb_core_mem_sizes -o $(BUILD_DIR)/tb_core_mem_sizes.vvp -c $(TB_DIR)/core_mem_sizes.f
	$(VVP) $(BUILD_DIR)/tb_core_mem_sizes.vvp

sim: tb_core_smoke tb_core_hazard_branch tb_core_jump tb_core_mem_sizes

# -------------------------
# Lint
# -------------------------

lint_tb_core_smoke:
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module tb_core_smoke \
		$(TB_DIR)/tb_core_smoke.sv \
		$(RTL_DIR)/alu.sv \
		$(RTL_DIR)/branch_unit.sv \
		$(RTL_DIR)/decoder.sv \
		$(RTL_DIR)/ex_mem_reg.sv \
		$(RTL_DIR)/hazard_unit.sv \
		$(RTL_DIR)/id_ex_reg.sv \
		$(RTL_DIR)/if_id_reg.sv \
		$(RTL_DIR)/imm_gen.sv \
		$(RTL_DIR)/mem_wb_reg.sv \
		$(RTL_DIR)/regfile.sv \
		$(RTL_DIR)/core_top.sv

lint_tb_core_hazard_branch:
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module tb_core_hazard_branch \
		$(TB_DIR)/tb_core_hazard_branch.sv \
		$(RTL_DIR)/alu.sv \
		$(RTL_DIR)/branch_unit.sv \
		$(RTL_DIR)/decoder.sv \
		$(RTL_DIR)/ex_mem_reg.sv \
		$(RTL_DIR)/hazard_unit.sv \
		$(RTL_DIR)/id_ex_reg.sv \
		$(RTL_DIR)/if_id_reg.sv \
		$(RTL_DIR)/imm_gen.sv \
		$(RTL_DIR)/mem_wb_reg.sv \
		$(RTL_DIR)/regfile.sv \
		$(RTL_DIR)/core_top.sv

lint_tb_core_jump:
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module tb_core_jump \
		$(TB_DIR)/tb_core_jump.sv \
		$(RTL_DIR)/alu.sv \
		$(RTL_DIR)/branch_unit.sv \
		$(RTL_DIR)/decoder.sv \
		$(RTL_DIR)/ex_mem_reg.sv \
		$(RTL_DIR)/hazard_unit.sv \
		$(RTL_DIR)/id_ex_reg.sv \
		$(RTL_DIR)/if_id_reg.sv \
		$(RTL_DIR)/imm_gen.sv \
		$(RTL_DIR)/mem_wb_reg.sv \
		$(RTL_DIR)/regfile.sv \
		$(RTL_DIR)/core_top.sv

lint_tb_core_mem_sizes:
	$(VERILATOR) $(VERILATOR_FLAGS) --top-module tb_core_mem_sizes \
		$(TB_DIR)/tb_core_mem_sizes.sv \
		$(RTL_DIR)/alu.sv \
		$(RTL_DIR)/branch_unit.sv \
		$(RTL_DIR)/decoder.sv \
		$(RTL_DIR)/ex_mem_reg.sv \
		$(RTL_DIR)/hazard_unit.sv \
		$(RTL_DIR)/id_ex_reg.sv \
		$(RTL_DIR)/if_id_reg.sv \
		$(RTL_DIR)/imm_gen.sv \
		$(RTL_DIR)/mem_wb_reg.sv \
		$(RTL_DIR)/regfile.sv \
		$(RTL_DIR)/core_top.sv

lint: lint_tb_core_smoke lint_tb_core_hazard_branch lint_tb_core_jump lint_tb_core_mem_sizes

# -------------------------
# Regresión completa
# -------------------------

regress: sim lint
	@echo "PASS: regresion local completa OK"

clean:
	rm -rf $(BUILD_DIR)

.PHONY: evidence_dirs regress-log

evidence_dirs:
	mkdir -p $(LOG_DIR)

regress-log: evidence_dirs
	$(MAKE) regress 2>&1 | tee $(LOG_DIR)/$(DATE_STR)_regress_local.log
