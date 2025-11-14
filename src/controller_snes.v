// snes_gamepad_controller.sv
// SystemVerilog Module for interfacing a SNES Gamepad with the TangyRiscVSOC bus.
//
// This module implements the serial protocol to read 16 bits of button data
// from a standard SNES controller and provides that data via a simple
// memory-mapped register (MMIO) interface for the RISC-V core.
//
// The core clock (clk) is assumed to be 80MHz (12.5ns period).

module snes_gamepad_controller #(
    parameter CLK_FREQ_HZ = 80_000_000, // Assuming 80 MHz Register Clock
    parameter ADDR_WIDTH  = 32,          // RISC-V Bus Address Width
    parameter DATA_WIDTH  = 32           // RISC-V Bus Data Width
) (
    // System Clock and Reset
    input  logic                   clk,
    input  logic                   rst,

    // RISC-V Bus Interface (APB/Wishbone Lite-style Read)
    input  logic                   i_bus_read_en,  // Read Enable (CS & RD)
    input  logic [ADDR_WIDTH-1:0]  i_bus_addr,     // Address from CPU
    output logic [DATA_WIDTH-1:0]  o_bus_rdata,    // Data to CPU
    output logic                   o_bus_rdy,      // Ready signal for synchronous bus

    // SNES Controller Physical Interface
    output logic                   o_snes_latch,   // Latch (Output to controller)
    output logic                   o_snes_clk,     // Clock (Output to controller)
    input  logic                   i_snes_data     // Data (Input from controller)
);

    // --- Local Parameters for SNES Timing (Based on 80MHz clock) ---
    // 80MHz clock period = 12.5ns.
    // Latch/Clock pulse width: 12us -> 960 cycles.
    // Half clock period: 6us -> 480 cycles.
    localparam SNES_LATCH_PULSE_CYCLES = 960; // 12 us @ 80MHz
    localparam SNES_HALF_PERIOD_CYCLES = 480;  // 6 us @ 80MHz
    localparam SNES_READ_DELAY_CYCLES  = 40;   // 0.5 us @ 80MHz

    // --- FSM State Definition ---
    typedef enum logic [3:0] {
        IDLE,             // Waiting for a read command
        LATCH_HIGH,       // Sending 12us LATCH pulse
        LATCH_LOW,        // Waiting for the first clock cycle
        CLK_HIGH,         // Clock high period (wait for read)
        CLK_LOW,          // Clock low period (advance to next bit)
        READ_DONE         // All 16 bits read, data ready
    } state_t;

    state_t current_state, next_state;

    // --- Internal Signals ---
    logic [15:0] snes_button_status_reg; // Stores the 16 bits of button data
    logic [15:0] bit_counter;            // Counts the 16 bits read
    logic [11:0] timer_counter;          // Generic timer for microsecond delays
    logic        start_read;             // Control signal to trigger a read cycle

    // --- LATCH/CLOCK Signal Outputs ---
    assign o_snes_latch = (current_state == LATCH_HIGH) ? 1'b1 : 1'b0;
    assign o_snes_clk   = (current_state == CLK_HIGH)   ? 1'b1 : 1'b0;

    // --- Register Access (MMIO) ---
    // This is the read-only register used by the RISC-V CPU.
    localparam SNES_REG_ADDR = 32'h0; // Arbitrary offset 0 for this module

    // Read Data Multiplexer
    assign o_bus_rdata = (i_bus_addr[1:0] == SNES_REG_ADDR[1:0]) ?
                         {{16{1'b0}}, snes_button_status_reg} : 32'hDEADBEEF; // 16 MSBs are unused, LSBs hold button status

    // Bus Ready Signal (Read operation is combinational/instantaneous)
    // The FSM runs constantly, so the data is assumed to be available.
    assign o_bus_rdy = 1'b1;

    // Trigger read cycle on any bus read attempt to the controller's address
    assign start_read = (i_bus_read_en && (i_bus_addr[1:0] == SNES_REG_ADDR[1:0]) && (current_state == IDLE));


    // --- State & Timer Logic ---
    always @(posedge clk) begin
        if (rst) begin
            current_state <= IDLE;
            timer_counter <= 12'd0;
            bit_counter   <= 16'd0;
        end else begin
            // State Update
            current_state <= next_state;

            // Timer Update
            if (timer_counter != 12'd0) begin
                timer_counter <= timer_counter - 1'b1;
            end

            // Main State Machine Logic
            case (current_state)
                IDLE: begin
                    if (start_read) begin
                        timer_counter <= SNES_LATCH_PULSE_CYCLES;
                        bit_counter   <= 16'd0;
                    end
                end

                LATCH_HIGH: begin
                    if (timer_counter == 12'd0) begin
                        timer_counter <= SNES_READ_DELAY_CYCLES; // Small delay after latch release
                        // Store the first bit (B button) immediately after LATCH high finishes.
                        snes_button_status_reg[0] <= i_snes_data;
                    end
                end

                LATCH_LOW: begin
                    if (timer_counter == 12'd0) begin
                        timer_counter <= SNES_HALF_PERIOD_CYCLES;
                    end
                end

                CLK_HIGH: begin
                    if (timer_counter == 12'd0) begin
                        // CLK falling edge: Read the next data bit (except for the first read)
                        if (bit_counter < 15) begin
                            snes_button_status_reg[bit_counter + 1] <= i_snes_data;
                            bit_counter <= bit_counter + 1;
                        end
                        timer_counter <= SNES_HALF_PERIOD_CYCLES;
                    end
                end

                CLK_LOW: begin
                    if (timer_counter == 12'd0) begin
                        timer_counter <= SNES_HALF_PERIOD_CYCLES;
                    end
                end

                READ_DONE: begin
                    // Hold here until the next read trigger, or simply reset to IDLE
                    // We immediately go back to IDLE in the combinatorial block
                end
            endcase
        end
    end

    // --- Next State Logic (Combinational) ---
    always_comb begin
        next_state = current_state; // Default is to stay in the current state

        case (current_state)
            IDLE: begin
                if (start_read) next_state = LATCH_HIGH;
            end
            LATCH_HIGH: begin
                if (timer_counter == 12'd0) next_state = LATCH_LOW;
            end
            LATCH_LOW: begin
                if (timer_counter == 12'd0) next_state = CLK_HIGH;
            end
            CLK_HIGH: begin
                if (timer_counter == 12'd0) next_state = CLK_LOW;
            end
            CLK_LOW: begin
                if (timer_counter == 12'd0) begin
                    if (bit_counter < 15) next_state = CLK_HIGH; // Loop for the next bit
                    else next_state = READ_DONE; // Finished reading all 16 bits
                end
            end
            READ_DONE: begin
                next_state = IDLE; // Immediately ready for the next read
            end
        endcase
    end

    // --- Button Mapping (For reference in your C code) ---
    // snes_button_status_reg[15:0] mapping (Active High):
    // [0]  : B
    // [1]  : Y
    // [2]  : SELECT
    // [3]  : START
    // [4]  : UP
    // [5]  : DOWN
    // [6]  : LEFT
    // [7]  : RIGHT
    // [8]  : A
    // [9]  : X
    // [10] : L
    // [11] : R
    // [12-15] : Unused (read as 0 by this module)

endmodule