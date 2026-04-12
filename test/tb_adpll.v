`timescale 1ns / 1ps

module tb_adpll;

    // Tiny Tapeout interface signals
    reg  [7:0] ui_in;
    wire [7:0] uo_out;
    reg  [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;
    reg        ena;
    reg        clk;
    reg        rst_n;

    // DUT
    tt_um_adpll dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    // Decode outputs for readability
    wire        dco_clk_out = uo_out[0];
    wire        div_clk_out = uo_out[1];
    wire        locked      = uo_out[2];
    wire        error_sign  = uo_out[3];
    wire [3:0]  error_low   = uo_out[7:4];
    wire [7:0]  dco_hi      = uio_out;

    // Reference clock generation: 32.768 KHz
    // Period = 30517.578125 ns, half-period = 15258.789 ns
    reg ref_clk;
    localparam real REF_HALF_PERIOD = 15258.789;

    initial ref_clk = 1'b0;
    always #(REF_HALF_PERIOD) ref_clk = ~ref_clk;

    // TT system clock: 10 MHz (not critical, just for completeness)
    initial clk = 1'b0;
    always #50 clk = ~clk;

    // Wire ref_clk to ui_in[0]
    always @(*) ui_in[0] = ref_clk;

    // Monitor DCO frequency by counting edges
    integer dco_edge_count;
    real    last_ref_time;
    real    measured_freq;
    integer ref_cycle_num;

    initial begin
        dco_edge_count = 0;
        last_ref_time  = 0;
        ref_cycle_num  = 0;
    end

    always @(posedge dco_clk_out) begin
        dco_edge_count = dco_edge_count + 1;
    end

    always @(posedge ref_clk) begin
        if (last_ref_time > 0) begin
            measured_freq = dco_edge_count / (($realtime - last_ref_time) / 1e9);
            ref_cycle_num = ref_cycle_num + 1;

            if (ref_cycle_num % 10 == 0 || locked) begin
                $display("T=%0t ref_cycle=%0d dco_edges=%0d freq=%.3f MHz locked=%b dco_ctrl=0x%03x err_sign=%b err_low=%04b",
                    $realtime, ref_cycle_num, dco_edge_count,
                    measured_freq / 1e6, locked, {dco_hi, 4'b0000}, error_sign, error_low);
            end
        end
        dco_edge_count = 0;
        last_ref_time  = $realtime;
    end

    // Test sequence
    initial begin
        $dumpfile("adpll.vcd");
        $dumpvars(0, tb_adpll);

        // Initial state
        ena    = 1'b0;
        rst_n  = 1'b0;
        uio_in = 8'h00;
        ui_in  = 8'h00;

        // Hold reset for a few ref_clk cycles
        #(REF_HALF_PERIOD * 6);
        rst_n = 1'b1;
        #(REF_HALF_PERIOD * 4);

        // Configure: kp_sel=2 (Kp=1/4), ki_sel=4 (Ki=1/16), enable
        //   ui_in[3:1] = kp_sel = 3'b010
        //   ui_in[6:4] = ki_sel = 3'b100
        //   ui_in[7]   = loop_enable = 1
        ena = 1'b1;
        ui_in[7]   = 1'b1;  // enable
        ui_in[3:1] = 3'b010; // kp_sel = 2
        ui_in[6:4] = 3'b100; // ki_sel = 4

        $display("=== ADPLL Enabled: kp_sel=2, ki_sel=4 ===");
        $display("=== Target: 32.768 KHz x 512 = 16.777216 MHz ===");

        // Wait for lock (up to 300 ref cycles = ~9.2 ms)
        repeat (300) @(posedge ref_clk);

        if (locked) begin
            $display("=== LOCKED after %0d ref cycles ===", ref_cycle_num);
        end else begin
            $display("=== WARNING: Not locked after %0d ref cycles ===", ref_cycle_num);
        end

        // Run for 50 more cycles in locked state
        repeat (50) @(posedge ref_clk);

        $display("=== Test Complete ===");
        $finish;
    end

    // Watchdog timer: 20 ms
    initial begin
        #20_000_000;
        $display("=== TIMEOUT: Simulation exceeded 20 ms ===");
        $finish;
    end

endmodule
