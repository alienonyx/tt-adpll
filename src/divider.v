`timescale 1ns / 1ps

// Divide-by-512 frequency divider
// Since 512 = 2^9, uses a 9-bit counter with MSB as output
module divider #(
    parameter COUNT_BITS = 9
)(
    input  wire  clk_in,
    input  wire  rst_n,
    input  wire  enable,
    output wire  clk_out
);

    reg [COUNT_BITS-1:0] counter;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n)
            counter <= 0;
        else if (enable)
            counter <= counter + 1;
        else
            counter <= 0;
    end

    assign clk_out = counter[COUNT_BITS-1];

endmodule
