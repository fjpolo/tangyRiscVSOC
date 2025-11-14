module tangyRiscVSOC_top #(
    parameter useTangUART = 0,
    parameter instBlitter3DAcceleration = 1,
    parameter instFastFloatingMath = 0,
    parameter instHidUSBHost = 1,
    parameter instI2SAudio = 1
)(
    // Clocks and Reset
    input  logic         extPllClock25,
    input  logic         extPllClock12,
    input  logic         oscClock27,
    input  logic         buttonReset,
    input  logic         buttonUser,

    // LEDs
    output logic [5:0]  leds,
    output logic        rgbLedDout,

    // HDMI Ports
    output logic        O_tmds_clk_p,
    output logic        O_tmds_clk_n,
    output logic [2:0]  O_tmds_data_p,
    output logic [2:0]  O_tmds_data_n,
    inout  logic        dviCEC,
    inout  logic        dviEdidClk,
    inout  logic        dviEdidDat,

    // I2S Audio
    output logic        i2sSDMode,
    output logic        i2sBClk,
    output logic        i2sLRCk,
    output logic        i2sDOut,

    // UART (Tang Nano/External)
    output logic        tangUartTx,
    input  logic        tangUartRx,
    output logic        extUartTx,
    input  logic        extUartRx,

    // Flash SPI
    output logic        tangFlashCSn,
    output logic        tangFlashClk,
    output logic        tangFlashMOSI,
    input  logic        tangFlashMISO,

    // SD Card
    inout  logic [3:0]  sdMciDat,
    output logic        sdMciCmd,
    output logic        sdMciClk,

    // USB Host
    //inout  logic        usbhDP,
    //inout  logic        usbhDM,

    // SDRAM
    output logic        O_sdram_clk,
    output logic        O_sdram_cke,
    output logic        O_sdram_cs_n,
    output logic        O_sdram_cas_n,
    output logic        O_sdram_ras_n,
    output logic        O_sdram_wen_n,
    output logic [3:0]  O_sdram_dqm,
    output logic [10:0] O_sdram_addr,
    output logic [1:0]  O_sdram_ba,
    inout  logic [31:0] IO_sdram_dq,

    // --- NEW SNES Controller Ports ---
    output logic        snesLatch,  // Latch (Output to controller)
    output logic        snesClk,    // Clock (Output to controller)
    input  logic        snesData,   // Data (Input from controller)
    // snes controllers
    output joy1_strb,
    output joy1_clk,
    input  joy1_data
// ,
//    output joy2_strb,
//    output joy2_clk,
//    input  joy2_data
);
wire       usbhDP;
wire        usbhDM;

// ============================================================================
// SIGNAL DECLARATIONS
// ============================================================================

// Domain 1 - pllHDMI (25MHz input clock)
logic clk25;
logic clk125;
logic clk125ps;
logic clk41_66;

// Domain 2 - pllSystem (80MHz system clock derived from 25MHz)
logic clkd2_80;     // 80MHz CPU memory / peripheral clock
logic clkd2_80ps;   // 80MHz phase-shifted (for SDRAM)
logic clkd2_40;     // 40MHz CPU clock
logic clkd2_20;     // 20MHz (unused in current logic, typically)

// Reset
logic reset;
logic resetn;

// HDMI pll
logic pllHDMILocked;

// HDMI encoder
logic dviClock;     // clk125
logic dviVs;
logic dviHs;
logic dviDe;
logic [7:0] dviR;
logic [7:0] dviG;
logic [7:0] dviB;

// SDRAM controller signals
logic sdramClock;   // clkd2_80ps

// Video mux signals
logic [15:0] vmMode;

// Font ROM signals
logic [10:0] fontRomA;
logic [7:0]  fontRomDout;

// Text pixel gen signals
logic pgClock;      // clk25
logic pgVSync;
logic pgHSync;
logic pgDe;
logic [7:0] pgR;
logic [7:0] pgG;
logic [7:0] pgB;
logic [11:0] pgXCount;
logic [11:0] pgYCount;
logic pgDeX;
logic pgDeY;
logic pgPreFetchLine;
logic pgFetchEnable;
logic [15:0] videoRamBDout;
logic [13:0] videoRamBA;

// VSync signal synchronized to CPU clock domain
logic pgVSyncClkD2;

// GFX pixel gen signals
logic pgEnabled;
logic [7:0] pggR;
logic [7:0] pggG;
logic [7:0] pggB;
logic [1:0] pggDMARequest;
logic [1:0] pggDMARequestClkD2;

// System RAM signals
logic fpgaCpuMemoryClock;
logic systemRAMCE;
logic systemRamReady;
logic [31:0] systemRamDoutForCPU;
logic [31:0] systemRamDoutForPixelGen;
logic [31:0] systemRamDataIn;
logic systemRamWr;

typedef enum logic [2:0] {
    srasIdle,
    srasRead0,
    srasReadModifyWrite0,
    srasReadModifyWrite1,
    srasReadModifyWrite2
} systemRamAccessState_T;

systemRamAccessState_T systemRamAccessState;

// CPU signals
logic cpuClock;     // clkd2_40
logic cpuResetn;
logic [29:0] cpuAOut;
logic [31:0] cpuDOut;
logic cpuMemValid;
logic cpuMemInstr;
logic cpuMemReady;
logic [31:0] cpuAOutFull;
logic [3:0] cpuWrStrobe;
logic [31:0] cpuDin;
logic cpuWr;
logic [3:0] cpuDataMask;

// CPU reset generation
logic [15:0] cpuResetGenCounter;

// GPO signals (General Purpose Output - often used for registers/video mode)
logic [31:0] gpoRegister;

// Registers signals (MMIO 0xF00)
logic registersClock;
// Existing register state machine (not used in current logic, keeping for structure)
typedef enum logic {
    rsWaitForRegAccess,
    rsWaitForBusCycleEnd
} regState_T;
regState_T registerState;
logic registersCE;
logic [31:0] registersDoutForCPU;

// Tick timer signals (MMIO 0xF00)
logic tickTimerClock;
logic tickTimerReset;
logic [31:0] tickTimerPrescalerCounter;
logic [31:0] tickTimerCounter;
localparam tickTimerPrescalerValue = 40000 - 1; // 1ms tick timer @40MHz

// Frame timer signals (MMIO 0xF00)
logic frameTimerClock;
logic frameTimerReset;
logic frameTimerPgPrvVSync;
logic [31:0] frameTimerValue;

// DMA signals
logic sdramDmaClock;

// DMA ch0 buffer RAM signals (for GFX pixel gen)
logic [31:0] gfxBufRamDOut;
logic [8:0]  gfxBufRamRdA;
logic [20:0] dmaDisplayPointerStart;

// DMA ch1 signals (audio)
logic dmaCh1Request;
logic [20:0] dmaCh1A;
logic [31:0] dmaCh1Dout;
logic dmaCh1Ready;

// DMA ch2 signals (blitter)
logic dmaCh2Request;
logic dmaCh2Ready;
logic dmaCh2RWn;
logic [31:0] dmaCh2Din;
logic [31:0] dmaCh2Dout;
logic [21:0] dmaCh2A;
logic dmaCh2TransferSize;
logic [1:0] dmaCh2TransferMask;

// DMA ch3 signals (CPU - MMIO 0x20)
logic dmaMemoryCE;
logic cpuDmaReady;
logic [31:0] dmaDoutForCPU;

// UART signals (MMIO 0xF04)
logic uartClock;
logic uartCE;
logic [31:0] uartDoutForCPU;
logic uartReady;
logic uartTxd;
logic uartRxd;

// SPI signals (SD Card - MMIO 0xF05)
logic spiClock;
logic spiCE;
logic [31:0] spiDoutForCPU;
logic spiReady;
logic spiSClk;
logic spiMOSI;
logic spiMISO;

// Tang flash SPI signals (MMIO 0xF07)
logic flashSpiClock;
logic flashSpiCE;
logic [31:0] flashSpiDoutForCPU;
logic flashSpiReady;
logic flashSpiSClk;
logic flashSpiMOSI;
logic flashSpiMISO;

// USB host signals (MMIO 0xF03)
logic usbHostClock;
logic usbHostCE;
logic usbHostReady;
logic [31:0] usbHostDoutForCPU;

// USB phy clock (12 MHz)
logic usbHClk;

// Blitter signals (MMIO 0xF02)
logic blitterClock;
logic blitterCE;
logic blitterReady;
logic [31:0] blitterDoutForCPU;

// FPALU signals (MMIO 0xF01)
logic fpAluClock;
logic fpAluCE;
logic [31:0] fpAluDoutForCPU;
logic fpAluReady;

// I2S controller signals (MMIO 0xF06)
logic i2sControllerClock;
logic i2sCE;
logic [31:0] i2sDoutForCPU;
logic i2sReady;

// --- NEW SNES Controller Signals (MMIO 0xF08) ---
logic snesControllerCE;
logic snesControllerReady;
logic [31:0] snesControllerDoutForCPU;

// ============================================================================
// COMPONENT INSTANTIATIONS
// ============================================================================

// PLL for HDMI
pllHDMI pllHDMIInst (
    .clkout(clk125),
    .lock(pllHDMILocked),
    .clkoutp(clk125ps),
    .clkoutd3(clk41_66),
    .reset(buttonReset),
    .clkin(extPllClock25)
);

// Clock divider
clkdiv5 clkdiv5Inst (
    .clkout(clk25),
    .hclkin(clk125),
    .resetn(resetn)
);

// System PLL
pllSystem pllSystemInst (
    .clkout(clkd2_80),
    .clkoutp(clkd2_80ps),
    .clkoutd(clkd2_40),
    .reset(buttonReset),
    .clkin(extPllClock25)
);

// HDMI transmitter
DVI_TX_Top DVI_TX_TopInst (
    .I_rst_n(resetn),
    .I_serial_clk(dviClock),
    .I_rgb_clk(pgClock),
    .I_rgb_vs(dviVs),
    .I_rgb_hs(dviHs),
    .I_rgb_de(dviDe),
    .I_rgb_r(dviR),
    .I_rgb_g(dviG),
    .I_rgb_b(dviB),
    .O_tmds_clk_p(O_tmds_clk_p),
    .O_tmds_clk_n(O_tmds_clk_n),
    .O_tmds_data_p(O_tmds_data_p),
    .O_tmds_data_n(O_tmds_data_n)
);

// Font ROM
fontProm fontPromInst (
    .dout(fontRomDout),
    .clk(pgClock),
    .oce(1'b1),
    .ce(1'b1),
    .reset(reset),
    .ad(fontRomA)
);

// Text pixel generator
pixelGenTxt pixelGenInst (
    .reset(reset),
    .pgClock(pgClock),
    .pgVSync(pgVSync),
    .pgHSync(pgHSync),
    .pgDe(pgDe),
    .pgR(pgR),
    .pgG(pgG),
    .pgB(pgB),
    .fontRomA(fontRomA),
    .fontRomDout(fontRomDout),
    .videoRamBA(videoRamBA),
    .videoRamBDout(videoRamBDout),
    .pgXCount(pgXCount),
    .pgYCount(pgYCount),
    .pgDeX(pgDeX),
    .pgDeY(pgDeY),
    .pgPreFetchLine(pgPreFetchLine),
    .pgFetchEnable(pgFetchEnable),
    .pgVideoMode(vmMode[3:2])
);

// GFX pixel generator
pixelGenGfx pixelGenGfxInst (
    .reset(reset),
    .pggClock(pgClock),
    .pggR(pggR),
    .pggG(pggG),
    .pggB(pggB),
    .gfxBufRamDOut(gfxBufRamDOut),
    .gfxBufRamRdA(gfxBufRamRdA),
    .pggDMARequest(pggDMARequest),
    .pgVSync(pgVSync),
    .pgHSync(pgHs),
    .pgDe(pgDe),
    .pgXCount(pgXCount),
    .pgYCount(pgYCount),
    .pgDeX(pgDeX),
    .pgDeY(pgDeY),
    .pgPreFetchLine(pgPreFetchLine),
    .pgFetchEnable(pgFetchEnable),
    .pgVideoMode(vmMode[5:4]),
    .pgEnabled(pgEnabled)
);

// System RAM
systemRam systemRamInst (
    .clka(fpgaCpuMemoryClock),
    .reseta(reset),
    .ada(cpuAOut[12:0]),
    .cea(systemRAMCE),
    .ocea(1'b1),
    .wrea(systemRamWr),
    .dina(systemRamDataIn),
    .douta(systemRamDoutForCPU),
    .clkb(pgClock),
    .resetb(reset),
    .adb(videoRamBA[13:1]),
    .ceb(1'b1),
    .oceb(1'b1),
    .wreb(1'b0),
    .dinb(32'h0),
    .doutb(systemRamDoutForPixelGen)
);

// RISC-V CPU
picorv32 picorv32Inst (
    .clk(cpuClock),
    .resetn(cpuResetn),
    .mem_valid(cpuMemValid),
    .mem_instr(cpuMemInstr),
    .mem_ready(cpuMemReady),
    .mem_addr(cpuAOutFull),
    .mem_wdata(cpuDOut),
    .mem_wstrb(cpuWrStrobe),
    .mem_rdata(cpuDin),
    .pcpi_wr(1'b0),
    .pcpi_rd(32'h0),
    .pcpi_wait(1'b0),
    .pcpi_ready(1'b0),
    .irq(32'h0)
);

// UART
UART UARTInst (
    .reset(reset),
    .clock(uartClock),
    .a(cpuAOut[15:0]),
    .din(cpuDOut),
    .dout(uartDoutForCPU),
    .ce(uartCE),
    .wr(cpuWr),
    .dataMask(cpuDataMask),
    .ready(uartReady),
    .uartTXD(uartTxd),
    .uartRXD(uartRxd)
);

// SPI for SD card
SPI SPIInst (
    .reset(reset),
    .clock(spiClock),
    .a(cpuAOut[15:0]),
    .din(cpuDOut),
    .dout(spiDoutForCPU),
    .ce(spiCE),
    .wr(cpuWr),
    .dataMask(cpuDataMask),
    .ready(spiReady),
    .sclk(spiSClk),
    .mosi(spiMOSI),
    .miso(spiMISO)
);

// SPI for flash
SPI flashSPIInst (
    .reset(reset),
    .clock(flashSpiClock),
    .a(cpuAOut[15:0]),
    .din(cpuDOut),
    .dout(flashSpiDoutForCPU),
    .ce(flashSpiCE),
    .wr(cpuWr),
    .dataMask(cpuDataMask),
    .ready(flashSpiReady),
    .sclk(flashSpiSClk),
    .mosi(flashSpiMOSI),
    .miso(flashSpiMISO)
);

// SDRAM Controller
sdramController sdramControllerInst (
    .reset(reset),
    .clock(sdramDmaClock),
    .clockSdram(sdramClock),
    .ch0DmaRequest(pggDMARequestClkD2),
    .ch0DmaPointerStart(dmaDisplayPointerStart),
    .ch0DmaPointerReset(pgVSyncClkD2),
    .ch0BufClk(~pgClock),
    .ch0BufDout(gfxBufRamDOut),
    .ch0BufA(gfxBufRamRdA),
    .ch1DmaRequest(dmaCh1Request),
    .ch1A(dmaCh1A),
    .ch1Dout(dmaCh1Dout),
    .ch1Ready(dmaCh1Ready),
    .ch2DmaRequest(dmaCh2Request),
    .ch2A(dmaCh2A),
    .ch2Din(dmaCh2Din),
    .ch2Dout(dmaCh2Dout),
    .ch2RWn(dmaCh2RWn),
    .ch2WordSize(dmaCh2TransferSize),
    .ch2DataMask(dmaCh2TransferMask),
    .ch2Ready(dmaCh2Ready),
    .a(cpuAOut[20:0]),
    .din(cpuDOut),
    .dout(dmaDoutForCPU),
    .ce(dmaMemoryCE),
    .wr(cpuWr),
    .dataMask(cpuDataMask),
    .instrCycle(cpuMemInstr),
    .ready(cpuDmaReady),
    .O_sdram_clk(O_sdram_clk),
    .O_sdram_cke(O_sdram_cke),
    .O_sdram_cs_n(O_sdram_cs_n),
    .O_sdram_cas_n(O_sdram_cas_n),
    .O_sdram_ras_n(O_sdram_ras_n),
    .O_sdram_wen_n(O_sdram_wen_n),
    .O_sdram_dqm(O_sdram_dqm),
    .O_sdram_addr(O_sdram_addr),
    .O_sdram_ba(O_sdram_ba),
    .IO_sdram_dq(IO_sdram_dq)
);

// Blitter
blitter #(
    .inst3DAcceleration(instBlitter3DAcceleration)
) blitterInst (
    .reset(reset),
    .clock(blitterClock),
    .a(cpuAOut[15:0]),
    .din(cpuDOut),
    .dout(blitterDoutForCPU),
    .ce(blitterCE),
    .wr(cpuWr),
    .dataMask(cpuDataMask),
    .ready(blitterReady),
    .dmaDin(dmaCh2Dout),
    .dmaDout(dmaCh2Din),
    .dmaA(dmaCh2A),
    .dmaRWn(dmaCh2RWn),
    .dmaRequest(dmaCh2Request),
    .dmaTransferSize(dmaCh2TransferSize),
    .dmaTransferMask(dmaCh2TransferMask),
    .dmaReady(dmaCh2Ready)
);

// Input synchronizers
inputSync #(.inputWidth(1)) pgVsyncInputSyncInst (
    .clock(clkd2_80),
    .signalInput(pgVSync),
    .signalOutput(pgVSyncClkD2)
);

inputSync #(.inputWidth(2)) pggDmaRequestInputSyncInst (
    .clock(clkd2_80),
    .signalInput(pggDMARequest),
    .signalOutput(pggDMARequestClkD2)
);

//
// SNES GAMEPAD
//
wor [11:0] joy1_btns, joy2_btns; 
wire [7:0] joy_rx[0:1], joy_rx2[0:1];     // 6 RX bytes for all button/axis state
wire [7:0] usb_btn, usb_btn2;
wire usb_btn_x, usb_btn_y, usb_btn_x2, usb_btn_y2;
wire usb_conerr, usb_conerr2;
wire auto_a, auto_b, auto_a2, auto_b2;
wire [2:0] joypad_out;
wire joypad_strobe = joypad_out[0];
wire [1:0] joypad_clock;
wire [4:0] joypad1_data, joypad2_data;
reg [7:0] joypad_bits, joypad_bits2;
reg [1:0] last_joypad_clock;
controller_snes joy1_snes (
    .clk(clk), .resetn(sys_resetn), .buttons(joy1_btns),
    .joy_strb(joy1_strb), .joy_clk(joy1_clk), .joy_data(joy1_data)
);
//controller_snes joy2_snes (
//    .clk(clk), .resetn(sys_resetn), .buttons(joy2_btns),
//    .joy_strb(joy2_strb), .joy_clk(joy2_clk), .joy_data(joy2_data)
//);
// Autofire for NES A (right) and B (left) buttons
Autofire af_a (.clk(clk), .resetn(sys_resetn), .btn(joy1_btns[8]), .out(auto_a));
Autofire af_b (.clk(clk), .resetn(sys_resetn), .btn(joy1_btns[9]), .out(auto_b));
//Autofire af_a2 (.clk(clk), .resetn(sys_resetn), .btn(joy2_btns[8]), .out(auto_a2));
//Autofire af_b2 (.clk(clk), .resetn(sys_resetn), .btn(joy2_btns[9]), .out(auto_b2));
// Joypad handling
always @(posedge clk) begin
    if (joypad_strobe) begin
        joypad_bits <= {joy1_btns[7:2], joy1_btns[1] | auto_b, joy1_btns[0] | auto_a};;
        joypad_bits2 <= {joy2_btns[7:2], joy2_btns[1] | auto_b2, joy2_btns[0] | auto_a2};
    end
    if (!joypad_clock[0] && last_joypad_clock[0])
        joypad_bits <= {1'b1, joypad_bits[7:1]};
    if (!joypad_clock[1] && last_joypad_clock[1])
        joypad_bits2 <= {1'b1, joypad_bits2[7:1]};
    last_joypad_clock <= joypad_clock;
end
assign joypad1_data[0] = joypad_bits[0];
assign joypad2_data[0] = joypad_bits2[0];

// ============================================================================
// CONDITIONAL IP INSTANTIATIONS
// ============================================================================

generate
    if (instHidUSBHost) begin : instHidUSBHostGen
        usbHost usbHostInst (
            .reset(reset),
            .clock(usbHostClock),
            .a(cpuAOut[15:0]),
            .din(cpuDOut),
            .dout(usbHostDoutForCPU),
            .ce(usbHostCE),
            .wr(cpuWr),
            .dataMask(cpuDataMask),
            .ready(usbHostReady),
            .usbHClk(usbHClk),
            .usbH0Dp(usbhDP),
            .usbH0Dm(usbhDM)
        );
    end else begin
        assign usbHostDoutForCPU = 32'h0;
        assign usbHostReady = 1'b1;
    end
endgenerate

generate
    if (instFastFloatingMath) begin : instFastFloatingMathGen
        fpAlu fpAluInst (
            .reset(reset),
            .clock(fpAluClock),
            .a(cpuAOut[15:0]),
            .din(cpuDOut),
            .dout(fpAluDoutForCPU),
            .ce(fpAluCE),
            .wr(cpuWr),
            .dataMask(cpuDataMask),
            .ready(fpAluReady)
        );
    end else begin
        assign fpAluDoutForCPU = 32'h0;
        assign fpAluReady = 1'b1;
    end
endgenerate

generate
    if (instI2SAudio) begin : instI2SAudioGen
        i2sController i2sControllerInst (
            .reset(reset),
            .clock(i2sControllerClock),
            .a(cpuAOut[15:0]),
            .din(cpuDOut),
            .dout(i2sDoutForCPU),
            .ce(i2sCE),
            .wr(cpuWr),
            .dataMask(cpuDataMask),
            .ready(i2sReady),
            .dmaRequest(dmaCh1Request),
            .dmaA(dmaCh1A),
            .dmaDin(dmaCh1Dout),
            .dmaReady(dmaCh1Ready),
            .i2sBClk(i2sBClk),
            .i2sLRCk(i2sLRCk),
            .i2sDOut(i2sDOut)
        );
        assign i2sSDMode = 1'b1;
    end else begin
        assign i2sSDMode = 1'b0;
        assign i2sDoutForCPU = 32'h0;
        assign i2sReady = 1'b1;
        assign dmaCh1Request = 1'b0;
        assign dmaCh1A = 21'h0;
        assign i2sBClk = 1'b0;
        assign i2sLRCk = 1'b0;
        assign i2sDOut = 1'b0;
    end
endgenerate

// ============================================================================
// COMBINATIONAL LOGIC
// ============================================================================

// Reset logic based on PLL lock
assign reset = ~pllHDMILocked;
assign resetn = ~reset;

// Clock configuration
assign pgClock = clk25;
assign dviClock = clk125;
assign cpuClock = clkd2_40;
assign fpgaCpuMemoryClock = clkd2_80;
assign registersClock = clkd2_80;
assign tickTimerClock = clkd2_40;
assign frameTimerClock = clkd2_80;
assign uartClock = clkd2_80;
assign spiClock = clkd2_40;
assign flashSpiClock = clkd2_40;
assign sdramDmaClock = clkd2_80;
assign sdramClock = clkd2_80ps;
assign usbHostClock = clkd2_80;
assign usbHClk = extPllClock12;
assign blitterClock = clkd2_80;
assign fpAluClock = clkd2_80;
assign i2sControllerClock = clkd2_80;

// LEDs
assign leds = gpoRegister[7:2];

// Bus signals
assign cpuAOut = cpuAOutFull[31:2];
assign cpuWr = |cpuWrStrobe;
assign cpuDataMask = cpuWr ? cpuWrStrobe : 4'b1111;

// Chip selects (MMIO Decoding based on cpuAOutFull[31:20])
assign systemRAMCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'h000));
assign dmaMemoryCE = (cpuMemValid && (cpuAOutFull[31:24] == 8'h20)); // Base 0x20000000
assign registersCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf00));
assign fpAluCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf01));
assign blitterCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf02));
assign usbHostCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf03));
assign uartCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf04));
assign spiCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf05));
assign i2sCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf06));
assign flashSpiCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf07));
assign snesControllerCE = (cpuMemValid && (cpuAOutFull[31:20] == 12'hf08)); // SNES at 0xF0800000

// Bus slaves ready signals mux
assign cpuMemReady =
    systemRAMCE ? systemRamReady :
    uartCE ? uartReady :
    spiCE ? spiReady :
    usbHostCE ? usbHostReady :
    registersCE ? 1'b1 : // Assuming registers are always ready
    dmaMemoryCE ? cpuDmaReady :
    blitterCE ? blitterReady :
    fpAluCE ? fpAluReady :
    i2sCE ? i2sReady :
    flashSpiCE ? flashSpiReady :
    snesControllerCE ? snesControllerReady :
    1'b1; // Default ready

// Bus slaves data outputs mux
always_comb begin
    case (cpuAOutFull[31:20])
        12'h000: cpuDin = systemRamDoutForCPU;
        12'hf04: cpuDin = uartDoutForCPU;
        12'hf05: cpuDin = spiDoutForCPU;
        12'hf03: cpuDin = usbHostDoutForCPU;
        12'hf00: cpuDin = registersDoutForCPU;
        12'h020: cpuDin = dmaDoutForCPU;  // 8'h20 range (DRAM)
        12'hf02: cpuDin = blitterDoutForCPU;
        12'hf01: cpuDin = fpAluDoutForCPU;
        12'hf06: cpuDin = i2sDoutForCPU;
        12'hf07: cpuDin = flashSpiDoutForCPU;
        12'hf08: cpuDin = snesControllerDoutForCPU; // SNES Controller
        default: cpuDin = 32'h00000000;
    endcase
end

// Conditional UART connections
generate
    if (useTangUART) begin : useTangUARTGen
        assign tangUartTx = uartTxd;
        assign uartRxd = tangUartRx;
        assign extUartTx = 1'bZ; // Tristate external Tx
    end else begin
        assign extUartTx = uartTxd;
        assign uartRxd = extUartRx;
        assign tangUartTx = 1'bZ; // Tristate Tang Nano Tx
    end
endgenerate

// SD card SPI connections
assign sdMciClk = spiSClk;
assign sdMciDat[3] = gpoRegister[0];  // CS pin controlled by GPO (0x00)
assign sdMciCmd = spiMOSI;
assign spiMISO = sdMciDat[0];
assign sdMciDat[2:0] = 3'bzzz; // Dat[2:0] are unused in SPI mode

// Tang flash SPI connections
assign tangFlashCSn = gpoRegister[8];
assign tangFlashClk = flashSpiSClk;
assign tangFlashMOSI = flashSpiMOSI;
assign flashSpiMISO = tangFlashMISO;

// GFX pixel gen enable
assign pgEnabled = (vmMode[1:0] != 2'b00);

// Video RAM data output (Selects the 16-bit word from the 32-bit word line based on LSB of address)
assign videoRamBDout = videoRamBA[0] ? systemRamDoutForPixelGen[31:16] :
                                       systemRamDoutForPixelGen[15:0];

// ============================================================================
// SEQUENTIAL LOGIC PROCESSES
// ============================================================================

// System RAM access process (Handles R/W, 32-bit Write, and Read-Modify-Write)
always_ff @(posedge fpgaCpuMemoryClock) begin
    if (reset) begin
        systemRamAccessState <= srasIdle;
        systemRamDataIn <= 32'h0;
        systemRamWr <= 1'b0;
        systemRamReady <= 1'b0;
    end else begin
        case (systemRamAccessState)
            srasIdle: begin
                systemRamReady <= 1'b0;
                systemRamWr <= 1'b0;

                if (systemRAMCE) begin
                    if (~cpuWr) begin
                        // Read (always 32 bit)
                        systemRamReady <= 1'b1;
                        systemRamAccessState <= srasRead0;
                    end else begin
                        if (cpuDataMask == 4'b1111) begin
                            // 32-bit write
                            systemRamReady <= 1'b1;
                            systemRamDataIn <= cpuDOut;
                            systemRamWr <= 1'b1;
                            systemRamAccessState <= srasReadModifyWrite2;
                        end else begin
                            // Read-modify-write (8 or 16 bit)
                            systemRamAccessState <= srasReadModifyWrite0;
                        end
                    end
                end
            end

            srasRead0: begin
                systemRamReady <= 1'b1;
                if (~systemRAMCE) begin
                    systemRamReady <= 1'b0;
                    systemRamAccessState <= srasIdle;
                end
            end

            srasReadModifyWrite0: begin
                // Read wait state
                systemRamAccessState <= srasReadModifyWrite1;
            end

            srasReadModifyWrite1: begin
                // Modify and write
                systemRamDataIn[7:0]   = cpuDataMask[0] ? cpuDOut[7:0]   : systemRamDoutForCPU[7:0];
                systemRamDataIn[15:8]  = cpuDataMask[1] ? cpuDOut[15:8]  : systemRamDoutForCPU[15:8];
                systemRamDataIn[23:16] = cpuDataMask[2] ? cpuDOut[23:16] : systemRamDoutForCPU[23:16];
                systemRamDataIn[31:24] = cpuDataMask[3] ? cpuDOut[31:24] : systemRamDoutForCPU[31:24];
                systemRamWr <= 1'b1;
                systemRamAccessState <= srasReadModifyWrite2;
            end

            srasReadModifyWrite2: begin
                systemRamReady <= 1'b1;
                if (~systemRAMCE) begin
                    systemRamWr <= 1'b0;
                    systemRamReady <= 1'b0;
                    systemRamAccessState <= srasIdle;
                end
            end

            default: begin
                systemRamAccessState <= srasIdle;
            end
        endcase
    end
end

// CPU reset generation process
always_ff @(posedge cpuClock) begin
    if (reset) begin
        cpuResetn <= 1'b0;
        cpuResetGenCounter <= 16'hffff;
    end else begin
        if (cpuResetGenCounter != 16'h0000) begin
            cpuResetn <= 1'b0;
            cpuResetGenCounter <= cpuResetGenCounter - 1'b1;
        end else begin
            cpuResetn <= ~buttonUser; // Release reset when counter is 0, unless button is held
        end
    end
end

endmodule