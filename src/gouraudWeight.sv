module gouraudWeight (
    // Reset
    input  logic        reset,
    input  logic        clock,
    
    // Input edge and area values
    input  logic [31:0] i_edge,
    input  logic [31:0] area,
    
    // Output weight value
    output logic [31:0] weight
);

// ============================================================================
// COMPONENT INSTANTIATION
// ============================================================================

divider32s divider32sInst (
    .clk(clock),
    .rstn(~reset),
    .dividend({i_edge[23:0], 8'h00}),
    .divisor(area),
    .quotient(weight)
);

endmodule