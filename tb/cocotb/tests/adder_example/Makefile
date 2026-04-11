SIM ?= icarus
TOPLEVEL := adder
VERILOG_SOURCES := $(PWD)/adder.v
COCOTB_TEST_MODULES := test_adder
PYTHON_BIN := $(abspath ../../venv/bin/python)
COCOTB_MAKEFILES := $(shell $(PYTHON_BIN) -m cocotb_tools.config --makefiles)

include $(COCOTB_MAKEFILES)/Makefile.inc
include $(COCOTB_MAKEFILES)/simulators/Makefile.$(SIM)
