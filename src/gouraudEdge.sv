module gouraudEdge (
    // Reset
    input  logic                reset,
    input  logic                clock,
    
    // Input coordinates
    input  logic [15:0]         e1_x,
    input  logic [15:0]         e1_y,
    input  logic [15:0]         e2_x,
    input  logic [15:0]         e2_y,
    input  logic [15:0]         p_x,
    input  logic [15:0]         p_y,

    // Output edge value
    output logic [31:0]         o_edge
);

// Internal signals
logic signed [15:0] a_x;
logic signed [15:0] a_y;
logic signed [15:0] b_x;
logic signed [15:0] b_y;
logic signed [31:0] leftMult;
logic signed [31:0] rightMult;

// Main process
always_ff @(posedge clock) begin
    if (reset) begin
        // Reset values
        a_x <= '0;
        a_y <= '0;
        b_x <= '0;
        b_y <= '0;
        leftMult <= '0;
        rightMult <= '0;
        o_edge <= '0;
    end else begin
        // Calculate vectors
        a_x <= signed'(p_x) - signed'(e1_x);
        a_y <= signed'(p_y) - signed'(e1_y);
        
        b_x <= signed'(e2_x) - signed'(e1_x);
        b_y <= signed'(e2_y) - signed'(e1_y);
        
        // Calculate cross product components
        leftMult <= a_x * b_y;
        rightMult <= a_y * b_x;
        
        // Calculate final edge value (cross product)
        o_edge <= leftMult - rightMult;
    end
end

endmodule