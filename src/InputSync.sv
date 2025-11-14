module inputSync #(
    parameter inputWidth = 1
)(
    input  logic                      clock,
    input  logic [inputWidth-1:0]     signalInput,
    output logic [inputWidth-1:0]     signalOutput
);

    // Local parameter for signal width
    localparam signalWidth = inputWidth - 1;

    // Synchronization registers
    logic [signalWidth:0] stage1Reg;
    logic [signalWidth:0] stage2Reg;
    logic [signalWidth:0] stage3Reg;

    // Output assignment
    assign signalOutput = stage3Reg;

    // Three-stage synchronization process
    always_ff @(posedge clock) begin
        stage1Reg <= signalInput;
        stage2Reg <= stage1Reg;
        stage3Reg <= stage2Reg;
    end

endmodule