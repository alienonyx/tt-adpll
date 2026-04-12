`timescale 1ns / 1ps

// Digital PI Loop Filter
// Proportional + Integral controller for ADPLL
// Kp and Ki implemented as arithmetic right-shifts (no multipliers)
//
// Convention: positive phase_error means DCO is too slow -> increase control word
//
// Architecture:
//   proportional = error >>> kp_sel
//   integrator  += error  (full precision accumulation)
//   output       = DCO_MID + proportional + (integrator >>> ki_sel)
//
// Accumulating full error ensures small residual errors still integrate over time.
module loop_filter #(
    parameter ERROR_WIDTH = 17,
    parameter DCO_WIDTH   = 12,
    parameter ACCUM_WIDTH = 32
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          enable,
    input  wire                          error_valid,
    input  wire signed [ERROR_WIDTH-1:0] phase_error,
    input  wire [2:0]                    kp_sel,  // Kp = 1 >> kp_sel
    input  wire [2:0]                    ki_sel,  // Ki = 1 >> ki_sel (applied on output)
    output reg  [DCO_WIDTH-1:0]          dco_control,
    output reg                           dco_valid
);

    localparam signed [DCO_WIDTH:0] DCO_MID = 2048;
    localparam signed [DCO_WIDTH:0] DCO_MAX = 4095;

    reg signed [ACCUM_WIDTH-1:0] integrator;

    // Anti-windup limits: prevent integrator from accumulating beyond
    // what could produce a useful output change
    localparam signed [ACCUM_WIDTH-1:0] INTEG_MAX =  (4096 <<< 7); // 4096 * 128
    localparam signed [ACCUM_WIDTH-1:0] INTEG_MIN = -(4096 <<< 7);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            integrator  <= 0;
            dco_control <= DCO_MID[DCO_WIDTH-1:0];
            dco_valid   <= 1'b0;
        end else if (!enable) begin
            integrator  <= 0;
            dco_control <= DCO_MID[DCO_WIDTH-1:0];
            dco_valid   <= 1'b0;
        end else if (error_valid) begin : pi_update
            reg signed [ACCUM_WIDTH-1:0] integ_new;
            reg signed [ACCUM_WIDTH-1:0] prop;
            reg signed [ACCUM_WIDTH-1:0] integ_scaled;
            reg signed [ACCUM_WIDTH-1:0] output_raw;

            // Proportional path: scale error by Kp
            prop = phase_error >>> kp_sel;

            // Integral path: accumulate full-precision error
            integ_new = integrator + phase_error;

            // Anti-windup clamp
            if (integ_new > INTEG_MAX)
                integ_new = INTEG_MAX;
            else if (integ_new < INTEG_MIN)
                integ_new = INTEG_MIN;

            integrator <= integ_new;

            // Scale integrator on output
            integ_scaled = integ_new >>> ki_sel;

            // Compute output: midpoint + proportional + scaled integrator
            output_raw = DCO_MID + prop + integ_scaled;

            // Clamp to valid DCO range [0, 4095]
            if (output_raw > DCO_MAX)
                dco_control <= {DCO_WIDTH{1'b1}};
            else if (output_raw < 0)
                dco_control <= 0;
            else
                dco_control <= output_raw[DCO_WIDTH-1:0];

            dco_valid <= 1'b1;
        end else begin
            dco_valid <= 1'b0;
        end
    end

endmodule
