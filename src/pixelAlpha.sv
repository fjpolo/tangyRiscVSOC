module pixelAlpha (
    // Inputs
    input  logic        reset,
    input  logic        clock,
    input  logic [15:0] colorInA,
    input  logic [15:0] colorInB,
    input  logic [4:0]  alpha,
    
    // Output
    output logic [15:0] colorOut
);

    logic [9:0] mulAR, mulAG, mulAB;
    logic [9:0] mulBR, mulBG, mulBB;
    logic [4:0] beta;
    logic [4:0] outR, outG, outB;

    always_ff @(posedge clock) begin
        beta <= ~alpha;
        
        // Multiplications
        mulAR <= colorInA[4:0]   * alpha;
        mulAG <= colorInA[10:6]  * alpha;
        mulAB <= colorInA[15:11] * alpha;
        
        mulBR <= colorInB[4:0]   * beta;
        mulBG <= colorInB[10:6]  * beta;
        mulBB <= colorInB[15:11] * beta;

        // Summation with bit slicing
        outR <= mulAR[9:5] + mulBR[9:5];
        outG <= mulAG[9:5] + mulBG[9:5];
        outB <= mulAB[9:5] + mulBB[9:5];
        
        // Output assignment
        colorOut <= {outB, outG, 1'b0, outR};
    end

endmodule