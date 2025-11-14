module textureShader (
    // Inputs
    input  logic        reset,
    input  logic        clock,
    input  logic [15:0] colorIn,
    input  logic [4:0]  lightIn,
    
    // Output
    output logic [15:0] colorOut
);

    logic [9:0] mulr, mulg, mulb;

    always_ff @(posedge clock) begin
        mulr <= colorIn[4:0]   * lightIn;
        mulg <= colorIn[10:6]  * lightIn;
        mulb <= colorIn[15:11] * lightIn;
        
        colorOut <= {mulb[9:5], mulg[9:5], 1'b0, mulr[9:5]};
    end

endmodule