module fpAlu (
    input  logic                reset,
    input  logic                clock,
    input  logic [15:0]         a,
    input  logic [31:0]         din,
    output logic [31:0]         dout,
    
    input  logic                ce,
    input  logic                wr,
    input  logic [3:0]          dataMask,
    
    output logic                ready
);

// ============================================================================
// COMPONENT INSTANTIATIONS
// ============================================================================

fpMult fpMultInst (
    .clk(clock),
    .rstn(~reset),
    .data_a(fpA),
    .data_b(fpB),
    .result(fpMulResult)
);

fpAdd fpAddInst (
    .clk(clock),
    .rstn(~reset),
    .data_a(fpA),
    .data_b(fpB),
    .result(fpAddResult)
);

fpSub fpSubInst (
    .clk(clock),
    .rstn(~reset),
    .data_a(fpA),
    .data_b(fpB),
    .result(fpSubResult)
);

fpDiv fpDivInst (
    .clk(clock),
    .rstn(~reset),
    .data_a(fpA),
    .data_b(fpB),
    .result(fpDivResult)
);

// ============================================================================
// SIGNAL DECLARATIONS
// ============================================================================

typedef enum logic {
    farsWaitForRegAccess,
    farsWaitForBusCycleEnd
} fpAluRegState_T;

fpAluRegState_T state;
logic [31:0] fpA;
logic [31:0] fpB;
logic [31:0] fpAddResult;
logic [31:0] fpSubResult;
logic [31:0] fpMulResult;
logic [31:0] fpDivResult;

// ============================================================================
// MAIN PROCESS
// ============================================================================

always_ff @(posedge clock) begin
    if (reset) begin
        ready <= '0;
        state <= farsWaitForRegAccess;
    end else begin
        case (state)
            farsWaitForRegAccess: begin
                if (ce) begin
                    // CPU wants to access registers
                    ready <= '0;
                    
                    case (a[7:0])
                        // 0x00 rw fpA
                        8'h00: begin
                            dout <= fpA;
                            if (wr) begin
                                fpA <= din;
                            end
                            ready <= '1;
                        end
                        
                        // 0x04 rw fpB
                        8'h01: begin
                            dout <= fpB;
                            if (wr) begin
                                fpB <= din;
                            end
                            ready <= '1;
                        end
                        
                        // 0x08 r- fpAddResult
                        8'h02: begin
                            dout <= fpAddResult;
                            ready <= '1;
                        end
                        
                        // 0x0c r- fpSubResult
                        8'h03: begin
                            dout <= fpSubResult;
                            ready <= '1;
                        end
                        
                        // 0x10 r- fpMulResult
                        8'h04: begin
                            dout <= fpMulResult;
                            ready <= '1;
                        end
                        
                        // 0x14 r- fpDivResult
                        8'h05: begin
                            dout <= fpDivResult;
                            ready <= '1;
                        end
                        
                        default: begin
                            dout <= '0;
                            ready <= '1;
                        end
                    endcase
                    
                    state <= farsWaitForBusCycleEnd;
                end
            end
            
            farsWaitForBusCycleEnd: begin
                // Wait for bus cycle to end
                if (~ce) begin
                    state <= farsWaitForRegAccess;
                    ready <= '0;
                end
            end
            
            default: begin
                state <= farsWaitForRegAccess;
            end
        endcase
    end
end

endmodule