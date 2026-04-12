`timescale 1ns / 1ps

// ADPLL Top-Level
// 32.768 KHz ref_clk -> 16.777216 MHz dco_clk (x512)
module adpll_top #(
    parameter DCO_WIDTH     = 12,
    parameter COUNT_WIDTH   = 16,
    parameter TARGET_COUNT  = 512,
    parameter ERROR_WIDTH   = 17,
    parameter ACCUM_WIDTH   = 28,
    parameter LOCK_THRESHOLD = 4,
    parameter LOCK_COUNT    = 16
)(
    input  wire         rst_n,
    input  wire         enable,
    input  wire         ref_clk,
    input  wire [2:0]   kp_sel,
    input  wire [2:0]   ki_sel,
    output wire         dco_clk_out,
    output wire         div_clk_out,
    output wire         locked,
    output wire signed [ERROR_WIDTH-1:0] phase_error_out,
    output wire [DCO_WIDTH-1:0]          dco_control_out
);

    // Internal wires
    wire                            dco_clk;
    wire [COUNT_WIDTH-1:0]          tdc_count;
    wire signed [ERROR_WIDTH-1:0]   phase_error;
    wire                            count_valid;
    wire [DCO_WIDTH-1:0]            dco_control;
    wire                            dco_valid;

    // TDC: count DCO cycles per ref_clk period
    tdc #(
        .COUNT_WIDTH  (COUNT_WIDTH),
        .TARGET_COUNT (TARGET_COUNT)
    ) u_tdc (
        .dco_clk     (dco_clk),
        .ref_clk     (ref_clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .count       (tdc_count),
        .phase_error (phase_error),
        .count_valid (count_valid)
    );

    // Digital PI Loop Filter
    loop_filter #(
        .ERROR_WIDTH (ERROR_WIDTH),
        .DCO_WIDTH   (DCO_WIDTH),
        .ACCUM_WIDTH (ACCUM_WIDTH)
    ) u_loop_filter (
        .clk         (dco_clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .error_valid (count_valid),
        .phase_error (phase_error),
        .kp_sel      (kp_sel),
        .ki_sel      (ki_sel),
        .dco_control (dco_control),
        .dco_valid   (dco_valid)
    );

    // DCO: ring oscillator (behavioral model)
    dco #(
        .DCO_WIDTH (DCO_WIDTH)
    ) u_dco (
        .rst_n        (rst_n),
        .enable       (enable),
        .control_word (dco_control),
        .dco_clk      (dco_clk)
    );

    // Divide-by-512 for debug output
    divider #(
        .COUNT_BITS (9)
    ) u_divider (
        .clk_in  (dco_clk),
        .rst_n   (rst_n),
        .enable  (enable),
        .clk_out (div_clk_out)
    );

    // Lock detector
    lock_detect #(
        .ERROR_WIDTH    (ERROR_WIDTH),
        .LOCK_THRESHOLD (LOCK_THRESHOLD),
        .LOCK_COUNT     (LOCK_COUNT)
    ) u_lock_detect (
        .clk         (dco_clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .error_valid (count_valid),
        .phase_error (phase_error),
        .locked      (locked)
    );

    // Output assignments
    assign dco_clk_out     = dco_clk;
    assign phase_error_out = phase_error;
    assign dco_control_out = dco_control;

endmodule
