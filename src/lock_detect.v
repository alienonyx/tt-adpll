`timescale 1ns / 1ps

// Lock Detector
// Asserts lock when |phase_error| < threshold for LOCK_COUNT consecutive ref cycles.
// Deasserts when |phase_error| >= threshold for UNLOCK_COUNT consecutive cycles.
module lock_detect #(
    parameter ERROR_WIDTH    = 17,
    parameter LOCK_THRESHOLD = 4,
    parameter LOCK_COUNT     = 16,
    parameter UNLOCK_COUNT   = 4,
    parameter COUNTER_WIDTH  = 6
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          enable,
    input  wire                          error_valid,
    input  wire signed [ERROR_WIDTH-1:0] phase_error,
    output reg                           locked
);

    reg [COUNTER_WIDTH-1:0] good_count;
    reg [COUNTER_WIDTH-1:0] bad_count;

    wire [ERROR_WIDTH-2:0] abs_error;
    assign abs_error = phase_error[ERROR_WIDTH-1] ? (~phase_error[ERROR_WIDTH-2:0] + 1)
                                                  : phase_error[ERROR_WIDTH-2:0];

    wire within_threshold;
    assign within_threshold = (abs_error < LOCK_THRESHOLD);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            locked     <= 1'b0;
            good_count <= 0;
            bad_count  <= 0;
        end else if (!enable) begin
            locked     <= 1'b0;
            good_count <= 0;
            bad_count  <= 0;
        end else if (error_valid) begin
            if (within_threshold) begin
                bad_count <= 0;
                if (!locked) begin
                    if (good_count >= LOCK_COUNT - 1)
                        locked <= 1'b1;
                    else
                        good_count <= good_count + 1;
                end
            end else begin
                good_count <= 0;
                if (locked) begin
                    if (bad_count >= UNLOCK_COUNT - 1)
                        locked <= 1'b0;
                    else
                        bad_count <= bad_count + 1;
                end
            end
        end
    end

endmodule
