module gouraudIterator (
    // Reset
    input  logic        reset,
    input  logic        clock,
    
    // Input weights and values
    input  logic [15:0] weightCB,
    input  logic [15:0] weightAC,
    input  logic [15:0] weightBA,
    input  logic [7:0]  valA,
    input  logic [7:0]  valB,
    input  logic [7:0]  valC,

    // Output interpolated value
    output logic [7:0]  valOut
);

// ============================================================================
// SIGNAL DECLARATIONS
// ============================================================================

logic [23:0] mul1;
logic [23:0] mul2;
logic [23:0] mul3;
logic [23:0] sum;

// ============================================================================
// MAIN PROCESS
// ============================================================================
assign sum = mul1 + mul2 + mul3;
always_ff @(posedge clock) begin
    if (reset) begin
        mul1 <= '0;
        mul2 <= '0;
        mul3 <= '0;
        valOut <= '0;
    end else begin
        // Perform multiplications
        mul1 <= weightCB * valA;
        mul2 <= weightAC * valB;
        mul3 <= weightBA * valC;
        
        // Sum the results        
        // Take the middle 8 bits
        valOut <= sum[15:8];
    end
end

endmodule