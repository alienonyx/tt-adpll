SRC = src/dco.v src/tdc.v src/loop_filter.v src/divider.v src/lock_detect.v src/adpll_top.v src/tt_um_adpll.v
TB  = test/tb_adpll.v
OUT = adpll_tb

.PHONY: sim wave clean

sim: $(SRC) $(TB)
	iverilog -o $(OUT) -g2012 $(TB) $(SRC)
	vvp $(OUT)

wave: sim
	gtkwave adpll.vcd &

clean:
	rm -f $(OUT) adpll.vcd
