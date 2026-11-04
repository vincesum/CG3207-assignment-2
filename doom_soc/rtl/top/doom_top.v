`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// doom_top: Nexys 4 DDR top level for doom_soc.
//
// Clocks
//   CLK100MHZ -> MMCM -> 200 MHz -> MIG sys_clk_i (also its reference clock)
//   MIG ui_clk 75 MHz  -> MMCM -> clk_cpu 37.5 MHz (phase aligned with ui_clk, so the
//   CPU <-> MIG bridge paths are ordinary timed paths, no CDC)
//   CPU, caches, UART, OLED controller, 7-seg all run on clk_cpu.
//
// Reset
//   CPU_RESETN (red button) resets the CPU only (DDR2 contents survive, so after a
//   reset the boot ROM can reload or the host can just jump again). The MIG is reset
//   only at power-up / configuration (its calibration writes training data to DDR2).
//
// Buttons: BTNR, BTNC, BTNL, BTNU, BTND -> PB[4:0] = {BTND, BTNU, BTNL, BTNC, BTNR}
//
// LEDs
//   LED[7:0]  software (MMIO 0x60)
//   LED8      heartbeat (clk_cpu running)
//   LED13     CPU in reset
//   LED14     CPU clock MMCM locked
//   LED15     DDR2 calibration complete
// -----------------------------------------------------------------------------
module doom_top #(
    parameter ROM_FILE = "boot.hex"   // set to an absolute path by vivado/build.tcl
)(
    input         CLK100MHZ,
    input         CPU_RESETN,
    input         BTNC, BTNU, BTNL, BTNR, BTND,
    input  [15:0] SW,
    output [15:0] LED,
    output AUD_PWM, AUD_SD,
    output [6:0]  SEG,              // CA..CG, active low
    output        DP,
    output [7:0]  AN,               // active low
    input         UART_TXD_IN,      // from the FTDI chip (board receives)
    output        UART_RXD_OUT,     // to the FTDI chip (board transmits)
    // PmodOLEDrgb on JB
    output        PMOD_CS, PMOD_MOSI, PMOD_SCK, PMOD_DC, PMOD_RES, PMOD_VCCEN, PMOD_EN,
    // DDR2 (names must match the MIG-generated constraints)
    inout  [15:0] ddr2_dq,
    inout  [1:0]  ddr2_dqs_n,
    inout  [1:0]  ddr2_dqs_p,
    output [12:0] ddr2_addr,
    output [2:0]  ddr2_ba,
    output        ddr2_ras_n,
    output        ddr2_cas_n,
    output        ddr2_we_n,
    output [0:0]  ddr2_ck_p,
    output [0:0]  ddr2_ck_n,
    output [0:0]  ddr2_cke,
    output [0:0]  ddr2_cs_n,
    output [1:0]  ddr2_dm,
    output [0:0]  ddr2_odt
);
    localparam CPU_HZ = 37_500_000;

    // ---------------- 100 MHz -> 200 MHz (MIG system/reference clock) ----------------
    wire clk_fb0, clk200_unbuf, clk200, locked0;
    MMCME2_BASE #(
        .CLKIN1_PERIOD   (10.0),
        .DIVCLK_DIVIDE   (1),
        .CLKFBOUT_MULT_F (10.0),    // VCO 1000 MHz
        .CLKOUT0_DIVIDE_F(5.0)      // 200 MHz
    ) mmcm_sys (
        .CLKIN1(CLK100MHZ), .CLKFBIN(clk_fb0), .CLKFBOUT(clk_fb0),
        .CLKOUT0(clk200_unbuf), .LOCKED(locked0), .RST(1'b0), .PWRDWN(1'b0),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
    );
    BUFG bufg200 (.I(clk200_unbuf), .O(clk200));

    // ---------------- MIG ----------------
    wire         ui_clk, ui_rst, calib_done;
    wire [26:0]  app_addr;
    wire [2:0]   app_cmd;
    wire         app_en, app_rdy;
    wire [127:0] app_wdf_data, app_rd_data;
    wire [15:0]  app_wdf_mask;
    wire         app_wdf_wren, app_wdf_end, app_wdf_rdy;
    wire         app_rd_data_valid, app_rd_data_end;

    ddr u_ddr (
        .ddr2_addr(ddr2_addr), .ddr2_ba(ddr2_ba), .ddr2_cas_n(ddr2_cas_n),
        .ddr2_ck_n(ddr2_ck_n), .ddr2_ck_p(ddr2_ck_p), .ddr2_cke(ddr2_cke),
        .ddr2_ras_n(ddr2_ras_n), .ddr2_we_n(ddr2_we_n), .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n), .ddr2_dqs_p(ddr2_dqs_p), .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm), .ddr2_odt(ddr2_odt),
        .init_calib_complete(calib_done),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en),
        .app_wdf_data(app_wdf_data), .app_wdf_end(app_wdf_end), .app_wdf_wren(app_wdf_wren),
        .app_wdf_mask(app_wdf_mask),
        .app_rd_data(app_rd_data), .app_rd_data_end(app_rd_data_end),
        .app_rd_data_valid(app_rd_data_valid), .app_rdy(app_rdy), .app_wdf_rdy(app_wdf_rdy),
        .app_sr_req(1'b0), .app_ref_req(1'b0), .app_zq_req(1'b0),
        .app_sr_active(), .app_ref_ack(), .app_zq_ack(),
        .ui_clk(ui_clk), .ui_clk_sync_rst(ui_rst),
        .sys_clk_i(clk200),
        .device_temp_i(12'h9F1),    // XADC disabled in mig.prj: constant ~40 C
        .sys_rst(locked0)           // ACTIVE LOW: held until the 200 MHz clock is stable
    );

    // ---------------- ui_clk 75 MHz -> clk_cpu 37.5 MHz ----------------
    wire clk_fb1, clk_fb1_buf, clk_cpu_unbuf, clk_cpu, locked1;
    MMCME2_BASE #(
        .CLKIN1_PERIOD   (13.333),
        .DIVCLK_DIVIDE   (1),
        .CLKFBOUT_MULT_F (12.0),    // VCO 900 MHz
        .CLKOUT0_DIVIDE_F(24.0)     // 37.5 MHz
    ) mmcm_cpu (
        .CLKIN1(ui_clk), .CLKFBIN(clk_fb1_buf), .CLKFBOUT(clk_fb1),
        .CLKOUT0(clk_cpu_unbuf), .LOCKED(locked1), .RST(ui_rst), .PWRDWN(1'b0),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(), .CLKOUT3(), .CLKOUT3B(),
        .CLKOUT4(), .CLKOUT5(), .CLKOUT6(), .CLKFBOUTB()
    );
    BUFG bufg_fb1 (.I(clk_fb1), .O(clk_fb1_buf));      // feedback through a BUFG: deskewed with ui_clk
    BUFG bufg_cpu (.I(clk_cpu_unbuf), .O(clk_cpu));

    // ---------------- CPU reset ----------------
    // Asserted asynchronously, released synchronously to clk_cpu.
    wire rst_req = ~CPU_RESETN | ~calib_done | ~locked1 | ui_rst;
    (* ASYNC_REG = "TRUE" *) reg [3:0] rst_sync = 4'hF;
    always @(posedge clk_cpu or posedge rst_req)
        if (rst_req) rst_sync <= 4'hF;
        else         rst_sync <= {rst_sync[2:0], 1'b0};
    wire rst_cpu = rst_sync[3];

    // ---------------- SoC ----------------
    wire [7:0]  led_sw;
    wire [31:0] sevenseg;
    wire audio_bit;
    // The board requires open-drain audio, never push-pull logic 1.
    assign AUD_PWM = audio_bit ? 1'bz : 1'b0;
    assign AUD_SD = ~rst_cpu;
    wire        oled_write;
    wire [6:0]  oled_col;
    wire [5:0]  oled_row;
    wire [23:0] oled_data;

    doom_soc #(.ROM_FILE(ROM_FILE), .UART_DIV(CPU_HZ / 1_500_000)) soc (
        .clk(clk_cpu), .rst(rst_cpu), .ui_clk(ui_clk), .ui_rst(ui_rst),
        .dip(SW), .pb({BTND, BTNU, BTNL, BTNC, BTNR}),
        .led(led_sw), .sevenseg(sevenseg),
        .uart_rxd(UART_TXD_IN), .uart_txd(UART_RXD_OUT),
        .audio_bit(audio_bit),
        .oled_write(oled_write), .oled_col(oled_col), .oled_row(oled_row), .oled_data(oled_data),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_mask(app_wdf_mask), .app_wdf_wren(app_wdf_wren),
        .app_wdf_end(app_wdf_end), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid)
    );

    // ---------------- OLED ----------------
    PmodOLEDrgb_bitmap #(
        .CLK_FREQ_HZ(CPU_HZ), .BPP(16)        // GREYSCALE / LEFT_SIDE keep their defaults (false)
    ) oled (
        .clk(clk_cpu), .reset(rst_cpu),
        .pix_write(oled_write), .pix_col(oled_col), .pix_row(oled_row),
        .pix_data_in({oled_data[23:19], oled_data[15:10], oled_data[7:3]}),
        .pix_data_out(),
        .PMOD_CS(PMOD_CS), .PMOD_MOSI(PMOD_MOSI), .PMOD_SCK(PMOD_SCK), .PMOD_DC(PMOD_DC),
        .PMOD_RES(PMOD_RES), .PMOD_VCCEN(PMOD_VCCEN), .PMOD_EN(PMOD_EN)
    );

    // ---------------- 7-segment display (8 hex digits) ----------------
    reg [16:0] seg_cnt = 0;
    always @(posedge clk_cpu) seg_cnt <= seg_cnt + 1'b1;     // ~0.9 ms per digit
    wire [2:0] digit = seg_cnt[16:14];
    wire [3:0] nib   = sevenseg[{digit, 2'b00} +: 4];
    reg  [6:0] seg_n;
    always @(*) begin
        case (nib)                    // gfedcba, active high here
            4'h0: seg_n = 7'b0111111; 4'h1: seg_n = 7'b0000110; 4'h2: seg_n = 7'b1011011; 4'h3: seg_n = 7'b1001111;
            4'h4: seg_n = 7'b1100110; 4'h5: seg_n = 7'b1101101; 4'h6: seg_n = 7'b1111101; 4'h7: seg_n = 7'b0000111;
            4'h8: seg_n = 7'b1111111; 4'h9: seg_n = 7'b1101111; 4'hA: seg_n = 7'b1110111; 4'hB: seg_n = 7'b1111100;
            4'hC: seg_n = 7'b0111001; 4'hD: seg_n = 7'b1011110; 4'hE: seg_n = 7'b1111001; default: seg_n = 7'b1110001;
        endcase
    end
    reg [6:0] seg_r = 7'h7F;
    reg [7:0] an_r  = 8'hFF;
    always @(posedge clk_cpu) begin
        seg_r <= ~seg_n;
        an_r  <= ~(8'd1 << digit);
    end
    assign SEG = seg_r;
    assign DP  = 1'b1;
    assign AN  = an_r;

    // ---------------- LEDs ----------------
    reg [24:0] hb = 0;
    always @(posedge clk_cpu) hb <= hb + 1'b1;
    assign LED[7:0]   = led_sw;
    assign LED[8]     = hb[24];
    assign LED[12:9]  = 4'd0;
    assign LED[13]    = rst_cpu;
    assign LED[14]    = locked1;
    assign LED[15]    = calib_done;
endmodule
