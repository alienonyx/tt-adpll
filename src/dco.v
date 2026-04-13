// Digitally Controlled Oscillator (DCO)
//
// Two implementations:
//   - Default: Synthesizable ring oscillator (for OpenLane/ASIC flow)
//   - SIM defined: Behavioral delay model (for functional simulation)
//
// In both modes:
//   Higher control_word -> higher output frequency
//

`ifdef SIM
`timescale 1ps / 1ps   // Picosecond resolution for behavioral model tuning
`else
`timescale 1ns / 1ps
`endif

module dco #(
    parameter DCO_WIDTH = 12
)(
    input  wire                  rst_n,
    input  wire                  enable,
    input  wire [DCO_WIDTH-1:0]  control_word,
    output wire                  dco_clk
);

`ifdef SIM

    // ================================================================
    // Behavioral model (simulation only)
    //
    // Maps control_word linearly to oscillation half-period.
    // Uses integer picosecond delays (timescale 1ps/1ps) to avoid
    // real-type issues with cocotb+Icarus.
    //
    // Half-period (ps) = 60000 - control_word * 122 / 10
    //   control_word=0:    60000 ps (60.0 ns) ->  8.33 MHz
    //   control_word=2464: 29941 ps (29.9 ns) -> 16.70 MHz  (loop settles here)
    //   control_word=4095: 10041 ps (10.0 ns) -> 49.8  MHz
    // ================================================================

    reg dco_clk_int;
    assign dco_clk = dco_clk_int;

    localparam integer BASE_HP_PS  = 60000;  // 60.0 ns in ps
    localparam integer STEP_X10    = 122;    // 12.2 ps per LSB (scaled x10)
    localparam integer MIN_HP_PS   = 15000;  // 15.0 ns minimum

    integer hp_ps;

    initial dco_clk_int = 1'b0;

    always begin
        if (!rst_n || !enable) begin
            dco_clk_int = 1'b0;
            @(posedge rst_n or posedge enable);
        end else if (^control_word === 1'bx) begin
            // Unknown control word at startup — use safe default delay
            #(BASE_HP_PS) dco_clk_int = ~dco_clk_int;
        end else begin
            hp_ps = BASE_HP_PS - (control_word * STEP_X10) / 10;
            if (hp_ps < MIN_HP_PS) hp_ps = MIN_HP_PS;
            #(hp_ps) dco_clk_int = ~dco_clk_int;
        end
    end

`else

    // ================================================================
    // Synthesizable ring oscillator
    //
    // Coarse tuning: control_word[11:7] selects ring length
    //   5 bits -> 31 options, ring lengths 3 to 63 (odd, step 2)
    //   Higher value -> shorter ring -> higher frequency
    //
    // Fine tuning: control_word[6:0] controls 7 load buffers
    //   Each bit disables one capacitive load on ring node
    //   Higher value -> fewer loads -> higher frequency
    //
    // Actual oscillation frequency depends on Sky130 process corner,
    // voltage, and temperature. The ADPLL loop compensates for this.
    // ================================================================

    wire en = rst_n & enable;
    wire [4:0] coarse = control_word[11:7];
    wire [6:0] fine   = control_word[6:0];

    // ---- 63-stage inverter chain ----
    localparam NSTG = 63;

    (* dont_touch = "true" *)
    wire [NSTG-1:0] stg;

    // Feedback tap: select ring length (must be even index for odd inversions)
    // tap = 62 - 2*coarse, clamped to minimum 2 (ring length 3)
    wire [5:0] tap;
    assign tap = (coarse >= 5'd31) ? 6'd2 : (6'd62 - {coarse, 1'b0});

    // Feedback from selected tap via MUX
    (* dont_touch = "true" *)
    wire fb;

    // Explicit MUX for feedback tap selection
    reg fb_mux;
    always @(*) begin
        case (tap)
            6'd2:    fb_mux = stg[2];
            6'd4:    fb_mux = stg[4];
            6'd6:    fb_mux = stg[6];
            6'd8:    fb_mux = stg[8];
            6'd10:   fb_mux = stg[10];
            6'd12:   fb_mux = stg[12];
            6'd14:   fb_mux = stg[14];
            6'd16:   fb_mux = stg[16];
            6'd18:   fb_mux = stg[18];
            6'd20:   fb_mux = stg[20];
            6'd22:   fb_mux = stg[22];
            6'd24:   fb_mux = stg[24];
            6'd26:   fb_mux = stg[26];
            6'd28:   fb_mux = stg[28];
            6'd30:   fb_mux = stg[30];
            6'd32:   fb_mux = stg[32];
            6'd34:   fb_mux = stg[34];
            6'd36:   fb_mux = stg[36];
            6'd38:   fb_mux = stg[38];
            6'd40:   fb_mux = stg[40];
            6'd42:   fb_mux = stg[42];
            6'd44:   fb_mux = stg[44];
            6'd46:   fb_mux = stg[46];
            6'd48:   fb_mux = stg[48];
            6'd50:   fb_mux = stg[50];
            6'd52:   fb_mux = stg[52];
            6'd54:   fb_mux = stg[54];
            6'd56:   fb_mux = stg[56];
            6'd58:   fb_mux = stg[58];
            6'd60:   fb_mux = stg[60];
            6'd62:   fb_mux = stg[62];
            default: fb_mux = stg[62];
        endcase
    end
    assign fb = fb_mux;

    // First stage: gated NAND (starts/stops oscillation)
    (* dont_touch = "true" *)
    assign stg[0] = ~(en & fb);

    // Inverter chain: stages 1 through 62
    genvar s;
    generate
        for (s = 1; s < NSTG; s = s + 1) begin : inv
            (* dont_touch = "true" *)
            assign stg[s] = ~stg[s-1];
        end
    endgenerate

    // ---- Fine tuning: switchable capacitive loads ----
    // Each load buffer adds capacitance to stg[1], slowing the ring.
    // fine[i]=1 -> load i disabled (less capacitance, faster)
    // fine[i]=0 -> load i enabled  (more capacitance, slower)
    genvar i;
    generate
        for (i = 0; i < 7; i = i + 1) begin : fine_ld
            (* dont_touch = "true" *)
            wire ld;
            assign ld = (~fine[i]) ? stg[1] : 1'b0;
        end
    endgenerate

    assign dco_clk = fb;

`endif

endmodule
