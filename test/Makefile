# Cocotb test Makefile for TT ADPLL
SIM ?= icarus
TOPLEVEL_LANG ?= verilog

# Testbench
VERILOG_SOURCES += $(PWD)/tb.v

# RTL or gate-level sources
ifneq ($(GATES),yes)
    VERILOG_SOURCES += $(PWD)/../src/tt_um_adpll.v
    VERILOG_SOURCES += $(PWD)/../src/adpll_top.v
    VERILOG_SOURCES += $(PWD)/../src/dco.v
    VERILOG_SOURCES += $(PWD)/../src/tdc.v
    VERILOG_SOURCES += $(PWD)/../src/loop_filter.v
    VERILOG_SOURCES += $(PWD)/../src/divider.v
    VERILOG_SOURCES += $(PWD)/../src/lock_detect.v
else
    VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/primitives.v
    VERILOG_SOURCES += $(PDK_ROOT)/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v
    VERILOG_SOURCES += $(PWD)/gate_level_netlist.v
    COMPILE_ARGS    += -DGL_TEST
    COMPILE_ARGS    += -DSIM
    COMPILE_ARGS    += -DUNIT_DELAY=\#1
endif

TOPLEVEL = tb
MODULE   = test

include $(shell cocotb-config --makefiles)/Makefile.sim
