`timescale 1ns / 1ps

// Time-to-Digital Converter (TDC)
// Counts DCO cycles between consecutive ref_clk rising edges.
// Phase error = TARGET_COUNT - measured_count (positive when DCO too slow)
module tdc #(
    parameter COUNT_WIDTH  = 16,
    parameter TARGET_COUNT = 512
)(
    input  wire                            dco_clk,
    input  wire                            ref_clk,
    input  wire                            rst_n,
    input  wire                            enable,
    output reg  [COUNT_WIDTH-1:0]          count,
    output reg  signed [COUNT_WIDTH:0]     phase_error,
    output reg                             count_valid
);

    // Synchronize ref_clk into dco_clk domain
    reg [2:0] ref_sync;
    wire      ref_rising;

    always @(posedge dco_clk or negedge rst_n) begin
        if (!rst_n)
            ref_sync <= 3'b000;
        else
            ref_sync <= {ref_sync[1:0], ref_clk};
    end

    assign ref_rising = ref_sync[1] & ~ref_sync[2];

    // Free-running counter in dco_clk domain
    reg [COUNT_WIDTH-1:0] cycle_count;

    always @(posedge dco_clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_count <= 0;
            count       <= 0;
            phase_error <= 0;
            count_valid <= 1'b0;
        end else if (!enable) begin
            cycle_count <= 0;
            count_valid <= 1'b0;
        end else if (ref_rising) begin
            // Latch measurement
            count       <= cycle_count;
            phase_error <= $signed(TARGET_COUNT[COUNT_WIDTH:0]) - $signed({1'b0, cycle_count});
            count_valid <= 1'b1;
            // Reset counter for next period
            cycle_count <= 1;
        end else begin
            cycle_count <= cycle_count + 1;
            count_valid <= 1'b0;
        end
    end

endmodule
