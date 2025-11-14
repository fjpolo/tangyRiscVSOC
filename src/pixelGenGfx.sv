module pixelGenGfx (
    // Inputs
    input  logic        reset,
    input  logic        pggClock,
    
    // Outputs
    output logic [7:0]  pggR,
    output logic [7:0]  pggG,
    output logic [7:0]  pggB,
    
    // GFX buffer RAM interface
    input  logic [31:0] gfxBufRamDOut,
    output logic [8:0]  gfxBufRamRdA,
    
    // DMA requests
    output logic [1:0]  pggDMARequest,
    
    // Sync generator inputs
    input  logic        pgVSync,
    input  logic        pgHSync,
    input  logic        pgDe,
    input  logic [11:0] pgXCount,
    input  logic [11:0] pgYCount,
    input  logic        pgDeX,
    input  logic        pgDeY,
    input  logic        pgPreFetchLine,
    input  logic        pgFetchEnable,
    
    // Video mode control
    input  logic [1:0]  pgVideoMode,
    input  logic        pgEnabled
);

    // State machine type definition
    typedef enum logic [4:0] {
        mDisabled,
        m1pre0, m1pre1, m1pre2, m1pre3, m1pre4, m1pre5, m1pre6, m1p0, m1p1, m1p2, m1p3, m1post0, m1post1, m1post2, m1post3, m1hblank,
        m2pre0, m2pre1, m2pre2, m2pre3, m2pre4, m2pre5, m2pre6, m2p0, m2p1, m2hblank
    } pggState_T;

    // Internal signals
    pggState_T pggState;
    logic [8:0] pggGfxBufAddressCounter;
    logic [1:0] pggLineCounter;
    logic [31:0] pggPixelData;

    always_ff @(posedge pggClock) begin
        if (reset) begin
            pggState <= m1pre0;
            pggGfxBufAddressCounter <= '0;
            pggLineCounter <= '0;
            pggPixelData <= '0;
            pggDMARequest <= '0;
        end else begin
            case (pggState)
                // Pixel gen gfx is disabled, no DMA requests
                mDisabled: begin
                    pggR <= '0;
                    pggG <= '0;
                    pggB <= '0;
                    pggDMARequest <= '0;

                    if (pgEnabled) begin
                        // Pixel gen gfx has been enabled
                        // Select state according to gfx mode selected
                        if (pgVideoMode == 2'b01) begin
                            pggState <= m2pre0;
                        end else begin
                            pggState <= m1pre0;
                        end
                    end
                end

                // Mode 1: 320x240x16 - wait for fetch enable
                // 7 prefetch states to match 8 clock cycles between fetch enable and display enable
                m1pre0: begin
                    pggR <= '0;
                    pggG <= '0;
                    pggB <= '0;

                    // Pass DMA request for first displayed line
                    if (pgPreFetchLine) begin
                        // Fill lower line
                        pggDMARequest <= 2'b01;
                        // Clear line counter for doubling lo-res lines
                        pggLineCounter <= '0;
                    end else begin
                        pggDMARequest <= '0;
                    end

                    if (pgFetchEnable) begin
                        // Pre-fetch first data
                        // Reset line buf address counter
                        pggGfxBufAddressCounter <= '0;
                        pggState <= m1pre1;
                    end

                    // Switch mode if necessary
                    if (pgVideoMode == 2'b01) begin
                        pggState <= m2pre0;
                    end

                    // Check if not disabled
                    if (!pgEnabled) begin
                        pggState <= mDisabled;
                    end
                end

                m1pre1: begin
                    gfxBufRamRdA <= {pggLineCounter[1], pggGfxBufAddressCounter[7:0]};
                    pggState <= m1pre2;
                end

                m1pre2: begin
                    // DMA requests
                    if (!pggLineCounter[0]) begin
                        if (!pggLineCounter[1]) begin
                            // Display lower buffer half, fill upper
                            pggDMARequest <= 2'b10;
                        end else begin
                            // Display upper buffer half, fill lower
                            pggDMARequest <= 2'b01;
                        end
                    end
                    pggState <= m1pre3;
                end

                m1pre3: begin
                    pggPixelData <= gfxBufRamDOut;
                    pggGfxBufAddressCounter <= pggGfxBufAddressCounter + 1;
                    pggState <= m1pre4;
                end

                m1pre4: begin
                    // Clear DMA request
                    pggDMARequest <= '0;
                    pggState <= m1pre5;
                end

                m1pre5: begin
                    pggState <= m1pre6;
                end

                m1pre6: begin
                    pggState <= m1p0;
                end

                m1p0: begin
                    pggR <= {pggPixelData[15:11], 3'b000};
                    pggG <= {pggPixelData[10:5],  2'b00};
                    pggB <= {pggPixelData[4:0],   3'b000};
                    
                    gfxBufRamRdA <= {pggLineCounter[1], pggGfxBufAddressCounter[7:0]};
                    pggState <= m1p1;
                end

                m1p1: begin
                    pggGfxBufAddressCounter <= pggGfxBufAddressCounter + 1;
                    pggState <= m1p2;
                end

                m1p2: begin
                    pggR <= {pggPixelData[31:27], 3'b000};
                    pggG <= {pggPixelData[26:21], 2'b00};
                    pggB <= {pggPixelData[20:16], 3'b000};
                    pggState <= m1p3;
                end

                m1p3: begin
                    pggPixelData <= gfxBufRamDOut;
                    if (pgFetchEnable) begin
                        pggState <= m1p0;
                    end else begin
                        pggState <= m1post0;
                    end
                end

                m1post0: begin
                    pggR <= {pggPixelData[15:11], 3'b000};
                    pggG <= {pggPixelData[10:5],  2'b00};
                    pggB <= {pggPixelData[4:0],   3'b000};
                    pggState <= m1post1;
                end

                m1post1: begin
                    pggState <= m1post2;
                end

                m1post2: begin
                    pggR <= {pggPixelData[31:27], 3'b000};
                    pggG <= {pggPixelData[26:21], 2'b00};
                    pggB <= {pggPixelData[20:16], 3'b000};
                    pggState <= m1post3;
                end

                m1post3: begin
                    pggState <= m1hblank;
                end

                m1hblank: begin
                    // Increment line counter
                    pggLineCounter <= pggLineCounter + 1;
                    pggR <= '0;
                    pggG <= '0;
                    pggB <= '0;
                    pggState <= m1pre0;
                end

                // Mode 2: 640x480x16
                // Wait for fetch enable
                // 7 prefetch states to match 8 clock cycles between fetch enable and display enable
                m2pre0: begin
                    pggR <= '0;
                    pggG <= '0;
                    pggB <= '0;

                    // Pass DMA request for first displayed line
                    if (pgPreFetchLine) begin
                        // Fill lower line
                        pggDMARequest <= 2'b01;
                    end else begin
                        pggDMARequest <= '0;
                    end

                    // Reset line buf address counter
                    pggGfxBufAddressCounter <= '0;

                    if (pgFetchEnable) begin
                        // Pre-fetch first data
                        pggState <= m2pre1;
                    end

                    // Switch mode if necessary
                    if (pgVideoMode == 2'b00) begin
                        pggState <= m1pre0;
                    end

                    // Check if not disabled
                    if (!pgEnabled) begin
                        pggState <= mDisabled;
                    end
                end

                m2pre1: begin
                    gfxBufRamRdA <= pggGfxBufAddressCounter;
                    pggGfxBufAddressCounter <= pggGfxBufAddressCounter + 1;
                    pggState <= m2pre2;
                end

                m2pre2: begin
                    // DMA requests
                    // Display lower buffer half, fill upper
                    pggDMARequest <= 2'b10;
                    pggState <= m2pre3;
                end

                m2pre3: begin
                    pggPixelData <= gfxBufRamDOut;
                    gfxBufRamRdA <= pggGfxBufAddressCounter;
                    pggState <= m2pre4;
                end

                m2pre4: begin
                    // Clear DMA request
                    pggDMARequest <= '0;
                    pggState <= m2pre5;
                end

                m2pre5: begin
                    pggState <= m2pre6;
                end

                m2pre6: begin
                    pggState <= m2p0;
                end

                m2p0: begin
                    // RISCV
                    pggR <= {pggPixelData[15:11], 3'b000};
                    pggG <= {pggPixelData[10:5],  2'b00};
                    pggB <= {pggPixelData[4:0],   3'b000};

                    // Display higher buffer half, fill lower
                    // Middle screen is 48 + 640 / 2 = 368 - 1 px
                    // Adjust this when video timings changed 
                    if (pgXCount[11:1] == 10'b0001011011) begin
                        // Fetch lower buffer part
                        pggDMARequest <= 2'b01;
                        // Switch data fetch address to higher buffer part
                        pggGfxBufAddressCounter <= 9'b100000001;
                        gfxBufRamRdA <= 9'b100000000;
                    end else begin
                        gfxBufRamRdA <= pggGfxBufAddressCounter;
                        pggGfxBufAddressCounter <= pggGfxBufAddressCounter + 1;
                        pggDMARequest <= '0;
                    end
                    pggState <= m2p1;
                end

                m2p1: begin
                    pggR <= {pggPixelData[31:27], 3'b000};
                    pggG <= {pggPixelData[26:21], 2'b00};
                    pggB <= {pggPixelData[20:16], 3'b000};
                    pggPixelData <= gfxBufRamDOut;
                    
                    if (pgDeX) begin
                        pggState <= m2p0;
                    end else begin
                        pggState <= m2hblank;
                    end
                end

                m2hblank: begin
                    pggR <= '0;
                    pggG <= '0;
                    pggB <= '0;
                    pggState <= m2pre0;
                end

                default: begin
                    pggState <= m1pre0;
                end
            endcase
        end
    end

endmodule