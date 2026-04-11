SIM ?= icarus
TOPLEVEL_LANG ?= verilog
VERILOG_SOURCES := $(PWD)/or_gate.v
or:
		$(MAKE) sim	MODULE=or_gate_test TOPLEVEL=or_gate
include $(shell cocotb-config --makefiles)/Makefile.sim