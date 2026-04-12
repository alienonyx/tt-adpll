`timescale 1ns / 1ps

// Tiny Tapeout Wrapper for ADPLL
//
// Pin Mapping:
//   ui_in[0]     = ref_clk (32.768 KHz external crystal)
//   ui_in[3:1]   = kp_sel[2:0]
//   ui_in[6:4]   = ki_sel[2:0]
//   ui_in[7]     = loop_enable
//
//   uo_out[0]    = dco_clk_out
//   uo_out[1]    = div_clk_out (should match ref_clk when locked)
//   uo_out[2]    = locked
//   uo_out[3]    = phase_error sign
//   uo_out[7:4]  = |phase_error|[3:0] (lower 4 bits of absolute error)
//
//   uio_out[7:0] = dco_control[11:4] (upper 8 bits of DCO word)
//   uio_oe       = 8'hFF (all outputs)

module tt_um_adpll (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // Input mapping
    wire        ref_clk     = ui_in[0];
    wire [2:0]  kp_sel      = ui_in[3:1];
    wire [2:0]  ki_sel      = ui_in[6:4];
    wire        loop_enable = ui_in[7] & ena;

    // ADPLL outputs
    wire        dco_clk_out;
    wire        div_clk_out;
    wire        locked;
    wire signed [16:0] phase_error;
    wire [11:0] dco_control;

    // ADPLL core
    adpll_top #(
        .DCO_WIDTH     (12),
        .COUNT_WIDTH   (16),
        .TARGET_COUNT  (512),
        .ERROR_WIDTH   (17),
        .ACCUM_WIDTH   (28),
        .LOCK_THRESHOLD(4),
        .LOCK_COUNT    (16)
    ) u_adpll (
        .rst_n           (rst_n),
        .enable          (loop_enable),
        .ref_clk         (ref_clk),
        .kp_sel          (kp_sel),
        .ki_sel          (ki_sel),
        .dco_clk_out     (dco_clk_out),
        .div_clk_out     (div_clk_out),
        .locked          (locked),
        .phase_error_out (phase_error),
        .dco_control_out (dco_control)
    );

    // Absolute value of phase error for output
    wire [15:0] abs_error;
    assign abs_error = phase_error[16] ? (~phase_error[15:0] + 1) : phase_error[15:0];

    // Output mapping
    assign uo_out[0]   = dco_clk_out;
    assign uo_out[1]   = div_clk_out;
    assign uo_out[2]   = locked;
    assign uo_out[3]   = phase_error[16]; // sign bit
    assign uo_out[7:4] = abs_error[3:0];  // lower 4 bits of |error|

    // Bidirectional pins: upper 8 bits of DCO control word
    assign uio_out = dco_control[11:4];
    assign uio_oe  = 8'hFF; // all outputs

endmodule
