module pixelGenTxt #(
    parameter hBackPorch  = 48,
    parameter hActive     = 640,
    parameter hFrontPorch = 16,
    parameter hSyncPulse  = 96,
    parameter vBackPorch  = 33,
    parameter vActive     = 480,
    parameter vFrontPorch = 10,
    parameter vSyncPulse  = 2
)(
    // Inputs
    input  logic        reset,
    input  logic        pgClock,
    
    // Outputs
    output logic        pgVSync,
    output logic        pgHSync,
    output logic        pgDe,
    output logic [7:0]  pgR,
    output logic [7:0]  pgG,
    output logic [7:0]  pgB,
    
    // Font ROM interface
    output logic [10:0] fontRomA,
    input  logic [7:0]  fontRomDout,
    
    // Video RAM interface
    output logic [13:0] videoRamBA,
    input  logic [15:0] videoRamBDout,
    
    // Timing outputs
    output logic [11:0] pgXCount,
    output logic [11:0] pgYCount,
    output logic        pgDeX,
    output logic        pgDeY,
    output logic        pgPreFetchLine,
    output logic        pgFetchEnable,
    
    // Video mode control
    input  logic [1:0]  pgVideoMode
);

    // Internal signals
    logic [13:0] pgDisplayPtr;
    logic [13:0] pgDisplayPtrShadow;
    logic [3:0]  pgLetterYCount;
    logic [7:0]  pgLetterData;
    
    // State machine type
    typedef enum logic [5:0] {
        m0pre0, m0pre1, m0pre2, m0pre3, m0pre4, m0pre5, m0pre6, m0p0, m0p1, m0p2, m0p3, m0p4, m0p5, m0p6, m0p7,
        m0p8, m0p9, m0p10, m0p11, m0p12, m0p13, m0p14, m0p15, m0hblank,
        m1pre0, m1pre1, m1pre2, m1pre3, m1pre4, m1pre5, m1pre6, m1p0, m1p1, m1p2, m1p3, m1p4, m1p5, m1p6, m1p7,
        m1p8, m1p9, m1p10, m1p11, m1p12, m1p13, m1p14, m1p15, m1hblank
    } pgState_T;
    
    pgState_T pgState;
    
    // Color LUT signals
    logic [23:0] pgLutLetterColor;
    logic [23:0] pgLutBackgroundColor;
    logic [23:0] pgLetterColor;
    logic [23:0] pgBackgroundColor;

    // Color LUT process
    always_ff @(posedge pgClock) begin
        // Background color LUT
        case (videoRamBDout[15:12])
            4'h0: pgLutBackgroundColor <= 24'h000000;
            4'h1: pgLutBackgroundColor <= 24'h000080;
            4'h2: pgLutBackgroundColor <= 24'h008000;
            4'h3: pgLutBackgroundColor <= 24'h800000;
            4'h4: pgLutBackgroundColor <= 24'h008080;
            4'h5: pgLutBackgroundColor <= 24'h808000;
            4'h6: pgLutBackgroundColor <= 24'h800080;
            4'h7: pgLutBackgroundColor <= 24'h202020;
            4'h8: pgLutBackgroundColor <= 24'h808080;
            4'h9: pgLutBackgroundColor <= 24'h0000ff;
            4'ha: pgLutBackgroundColor <= 24'h00ff00;
            4'hb: pgLutBackgroundColor <= 24'hff0000;
            4'hc: pgLutBackgroundColor <= 24'h00ffff;
            4'hd: pgLutBackgroundColor <= 24'hffff00;
            4'he: pgLutBackgroundColor <= 24'hff00ff;
            4'hf: pgLutBackgroundColor <= 24'hffffff;
            default: pgLutBackgroundColor <= 24'h000000;
        endcase

        // Letter color LUT
        case (videoRamBDout[11:8])
            4'h0: pgLutLetterColor <= 24'h000000;
            4'h1: pgLutLetterColor <= 24'h000080;
            4'h2: pgLutLetterColor <= 24'h008000;
            4'h3: pgLutLetterColor <= 24'h800000;
            4'h4: pgLutLetterColor <= 24'h008080;
            4'h5: pgLutLetterColor <= 24'h808000;
            4'h6: pgLutLetterColor <= 24'h800080;
            4'h7: pgLutLetterColor <= 24'h404040;
            4'h8: pgLutLetterColor <= 24'h808080;
            4'h9: pgLutLetterColor <= 24'h0000ff;
            4'ha: pgLutLetterColor <= 24'h00ff00;
            4'hb: pgLutLetterColor <= 24'hff0000;
            4'hc: pgLutLetterColor <= 24'h00ffff;
            4'hd: pgLutLetterColor <= 24'hffff00;
            4'he: pgLutLetterColor <= 24'hff00ff;
            4'hf: pgLutLetterColor <= 24'hffffff;
            default: pgLutLetterColor <= 24'h000000;
        endcase
    end

    // Pixel generation process
    always_ff @(posedge pgClock) begin
        logic pgDeX_v;
        logic pgDeY_v;
        
        if (reset) begin
            pgXCount <= '0;
            pgYCount <= '0;
            pgState <= m0pre0;
            pgDisplayPtr <= 14'h6D40;  // 0x6D40
            pgDisplayPtrShadow <= 14'h6D40;
            pgLetterYCount <= '0;
        end else begin
            // Sync generation
            if (pgXCount < (hBackPorch + hActive + hFrontPorch + hSyncPulse - 1)) begin
                pgXCount <= pgXCount + 1;
            end else begin
                // X sync wrap
                pgXCount <= '0;
                if (pgYCount < (vBackPorch + vActive + vFrontPorch + vSyncPulse - 1)) begin
                    pgYCount <= pgYCount + 1;
                end else begin
                    pgYCount <= '0;
                end
            end

            // Generate sync signals
            // Horizontal: bp(48) + active(640) + fp(16) + hs(96)
            pgHSync <= (pgXCount >= (hBackPorch + hActive + hFrontPorch));

            // Vertical: bp(33) + active(480) + fp(10) + vs(2)
            pgVSync <= (pgYCount >= (vBackPorch + vActive + vFrontPorch));

            // Display enable X and Y
            pgDeX_v = (pgXCount >= hBackPorch) && (pgXCount < (hBackPorch + hActive));
            pgDeY_v = (pgYCount >= vBackPorch) && (pgYCount < (vBackPorch + vActive));

            // Pre fetch line, active for 2 pixels, just before end of front v porch
            pgPreFetchLine <= (pgYCount == (vBackPorch - 2)) && (pgXCount[11:2] == '0);

            // Fetch enable: 8 pixels before line start, only when deY is active
            pgFetchEnable <= pgDeY && (pgXCount >= (hBackPorch - 8)) && (pgXCount < (hBackPorch + hActive - 8));

            pgDe <= pgDeX_v && pgDeY_v;
            pgDeX <= pgDeX_v;
            pgDeY <= pgDeY_v;

            // Reset display pointer on VSync
            if (pgVSync) begin
                pgDisplayPtr <= 14'h6D40;
                pgDisplayPtrShadow <= 14'h6D40;
                pgLetterYCount <= '0;
            end

            // State machine
            case (pgState)
                // Mode 0: 40x30 chars - wait for fetch enable
                m0pre0: begin
                    pgR <= '0;
                    pgG <= '0;
                    pgB <= '0;

                    if (pgFetchEnable) begin
                        // Pre-fetch first character and attributes
                        pgDisplayPtrShadow <= pgDisplayPtr;
                        videoRamBA <= pgDisplayPtr;
                        pgState <= m0pre1;
                    end

                    // Switch mode if necessary
                    if (pgVideoMode == 2'b01) begin
                        pgState <= m1pre0;
                    end
                end

                m0pre1: begin
                    pgState <= m0pre2;
                end

                m0pre2: begin
                    // Read char shape
                    fontRomA <= {videoRamBDout[7:0], pgLetterYCount[3:1]};
                    pgState <= m0pre3;
                end

                m0pre3: begin
                    // Latch colors
                    pgLetterColor <= pgLutLetterColor;
                    pgBackgroundColor <= pgLutBackgroundColor;
                    pgState <= m0pre4;
                end

                m0pre4: begin
                    pgDisplayPtr <= pgDisplayPtr + 1;
                    pgLetterData <= fontRomDout;
                    pgState <= m0pre5;
                end

                m0pre5: begin
                    pgState <= m0pre6;
                end

                m0pre6: begin
                    pgState <= m0p0;
                end

                m0p0: begin
                    pgR <= pgLetterData[7] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[7] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[7] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m0p1;
                end

                m0p1: begin
                    pgState <= m0p2;
                end

                m0p2: begin
                    pgR <= pgLetterData[6] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[6] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[6] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m0p3;
                end

                m0p3: begin
                    pgState <= m0p4;
                end

                m0p4: begin
                    pgR <= pgLetterData[5] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[5] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[5] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m0p5;
                end

                m0p5: begin
                    pgState <= m0p6;
                end

                m0p6: begin
                    pgR <= pgLetterData[4] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[4] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[4] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m0p7;
                end

                m0p7: begin
                    pgState <= m0p8;
                end

                m0p8: begin
                    pgR <= pgLetterData[3] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[3] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[3] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m0p9;
                end

                m0p9: begin
                    // Start fetch
                    videoRamBA <= pgDisplayPtr;
                    pgState <= m0p10;
                end

                m0p10: begin
                    pgR <= pgLetterData[2] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[2] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[2] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m0p11;
                end

                m0p11: begin
                    // Read char shape
                    fontRomA <= {videoRamBDout[7:0], pgLetterYCount[3:1]};
                    pgState <= m0p12;
                end

                m0p12: begin
                    pgR <= pgLetterData[1] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[1] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[1] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m0p13;
                end

                m0p13: begin
                    pgState <= m0p14;
                end

                m0p14: begin
                    pgR <= pgLetterData[0] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[0] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[0] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m0p15;
                end

                m0p15: begin
                    if (pgFetchEnable) begin
                        pgDisplayPtr <= pgDisplayPtr + 1;
                    end

                    // Store next character and latch colors
                    pgLetterData <= fontRomDout;
                    pgLetterColor <= pgLutLetterColor;
                    pgBackgroundColor <= pgLutBackgroundColor;

                    if (pgFetchEnable) begin
                        pgState <= m0p0;
                    end else begin
                        pgState <= m0hblank;
                    end
                end

                m0hblank: begin
                    pgR <= '0;
                    pgG <= '0;
                    pgB <= '0;

                    if (pgLetterYCount != 4'hF) begin
                        // If not end of 16 px line (one letter height)
                        // Restore data pointer
                        pgDisplayPtr <= pgDisplayPtrShadow;
                    end

                    pgLetterYCount <= pgLetterYCount + 1;
                    pgState <= m0pre0;
                end

                // Mode 1: 80x30 chars - wait for fetch enable
                m1pre0: begin
                    pgR <= '0;
                    pgG <= '0;
                    pgB <= '0;

                    if (pgFetchEnable) begin
                        // Pre-fetch first character and attributes
                        pgDisplayPtrShadow <= pgDisplayPtr;
                        videoRamBA <= pgDisplayPtr;
                        pgState <= m1pre1;
                    end

                    // Switch mode if necessary
                    if (pgVideoMode == 2'b00) begin
                        pgState <= m0pre0;
                    end
                end

                m1pre1: begin
                    pgState <= m1pre2;
                end

                m1pre2: begin
                    // Read char shape
                    fontRomA <= {videoRamBDout[7:0], pgLetterYCount[3:1]};
                    pgState <= m1pre3;
                end

                m1pre3: begin
                    // Latch colors
                    pgLetterColor <= pgLutLetterColor;
                    pgBackgroundColor <= pgLutBackgroundColor;
                    pgState <= m1pre4;
                end

                m1pre4: begin
                    pgDisplayPtr <= pgDisplayPtr + 1;
                    pgLetterData <= fontRomDout;
                    pgState <= m1pre5;
                end

                m1pre5: begin
                    pgState <= m1pre6;
                end

                m1pre6: begin
                    pgState <= m1p0;
                end

                m1p0: begin
                    pgR <= pgLetterData[7] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[7] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[7] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m1p1;
                end

                m1p1: begin
                    pgR <= pgLetterData[6] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[6] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[6] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m1p2;
                end

                m1p2: begin
                    pgR <= pgLetterData[5] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[5] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[5] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m1p3;
                end

                m1p3: begin
                    pgR <= pgLetterData[4] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[4] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[4] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    // Start fetch
                    videoRamBA <= pgDisplayPtr;
                    pgState <= m1p4;
                end

                m1p4: begin
                    pgR <= pgLetterData[3] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[3] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[3] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m1p5;
                end

                m1p5: begin
                    pgR <= pgLetterData[2] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[2] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[2] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    // Read char shape
                    fontRomA <= {videoRamBDout[7:0], pgLetterYCount[3:1]};
                    pgState <= m1p6;
                end

                m1p6: begin
                    pgR <= pgLetterData[1] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[1] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[1] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];
                    pgState <= m1p7;
                end

                m1p7: begin
                    pgR <= pgLetterData[0] ? pgLetterColor[7:0] : pgBackgroundColor[7:0];
                    pgG <= pgLetterData[0] ? pgLetterColor[15:8] : pgBackgroundColor[15:8];
                    pgB <= pgLetterData[0] ? pgLetterColor[23:16] : pgBackgroundColor[23:16];

                    if (pgFetchEnable) begin
                        pgDisplayPtr <= pgDisplayPtr + 1;
                    end

                    // Store next character and latch colors
                    pgLetterData <= fontRomDout;
                    pgLetterColor <= pgLutLetterColor;
                    pgBackgroundColor <= pgLutBackgroundColor;

                    if (pgFetchEnable) begin
                        pgState <= m1p0;
                    end else begin
                        pgState <= m1hblank;
                    end
                end

                m1hblank: begin
                    pgR <= '0;
                    pgG <= '0;
                    pgB <= '0;

                    if (pgLetterYCount != 4'hF) begin
                        // If not end of 16 px line (one letter height)
                        // Restore data pointer
                        pgDisplayPtr <= pgDisplayPtrShadow;
                    end

                    pgLetterYCount <= pgLetterYCount + 1;
                    pgState <= m1pre0;
                end

                default: begin
                    pgState <= m0pre0;
                end
            endcase
        end
    end

endmodule