`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// doom_soc: RV32IM pipeline + boot ROM + I/D caches + MMIO + MIG bridge.
// Board-independent: the FPGA top (doom_top.v) adds clocks, the MIG and the OLED/7-seg
// drivers; the simulation top (sim/tb_soc.v) adds a MIG model.
//
//   clk     CPU clock (37.5 MHz = ui_clk / 2, phase aligned)
//   ui_clk  MIG user clock (75 MHz)
// -----------------------------------------------------------------------------
module doom_soc #(
    parameter ROM_FILE = "boot.hex",
    parameter IC_IDX   = 9,          // 8 KB I-cache
    parameter DC_IDX   = 9,          // 8 KB D-cache
    parameter UART_DIV = 25          // CPU clock / baud (37.5 MHz / 1.5 Mbaud)
)(
    input              clk,
    input              rst,          // synchronous to clk
    input              ui_clk,
    input              ui_rst,
    // board
    input      [15:0]  dip,
    input      [4:0]   pb,
    output     [7:0]   led,
    output     [31:0]  sevenseg,
    input              uart_rxd,
    output             uart_txd,
    output             audio_bit,
    output             oled_write,
    output     [6:0]   oled_col,
    output     [5:0]   oled_row,
    output     [23:0]  oled_data,
    // MIG native interface (ui_clk)
    output     [26:0]  app_addr,
    output     [2:0]   app_cmd,
    output             app_en,
    input              app_rdy,
    output     [127:0] app_wdf_data,
    output     [15:0]  app_wdf_mask,
    output             app_wdf_wren,
    output             app_wdf_end,
    input              app_wdf_rdy,
    input      [127:0] app_rd_data,
    input              app_rd_data_valid
);
    // ---------------- CPU ----------------
    wire [31:0] PC, Instr, ALUResult, WriteData, ReadData;
    wire [3:0]  MemWrite;
    wire        MemRead, MemStall;

    RV #(.PC_INIT(32'h0040_0000)) cpu (
        .CLK(clk), .RESET(rst),
        .Instr(Instr), .ReadData_in(ReadData),
        .MemRead(MemRead), .MemWrite_out(MemWrite),
        .PC(PC), .ALUResult(ALUResult), .WriteData_out(WriteData),
        .MemStall(MemStall)
    );

    // ---------------- memory system ----------------
    wire         mmio_sel;
    wire [31:0]  mmio_rdata;
    wire         req_tog, req_we, ack_tog;
    wire [22:0]  req_line;
    wire [127:0] req_wdata, ack_rdata;
    wire [15:0]  req_wmask;
    wire         stat_imiss, stat_dmiss, stat_stall;

    memctl #(.IC_IDX(IC_IDX), .DC_IDX(DC_IDX), .ROM_FILE(ROM_FILE)) mem (
        .clk(clk), .rst(rst),
        .pc(PC), .instr(Instr),
        .daddr(ALUResult), .dread(MemRead), .dwrite(MemWrite), .dwdata(WriteData),
        .drdata(ReadData), .mem_stall(MemStall),
        .mmio_sel(mmio_sel), .mmio_rdata(mmio_rdata),
        .req_tog(req_tog), .req_we(req_we), .req_line(req_line), .req_wdata(req_wdata),
        .req_wmask(req_wmask), .ack_tog(ack_tog), .ack_rdata(ack_rdata),
        .stat_imiss(stat_imiss), .stat_dmiss(stat_dmiss), .stat_stall(stat_stall)
    );

    mmio #(.UART_DIV(UART_DIV)) io (
        .clk(clk), .rst(rst), .commit(~MemStall), .sel(mmio_sel),
        .addr(ALUResult[7:0]), .rd(MemRead), .we(MemWrite), .wdata(WriteData), .rdata(mmio_rdata),
        .dip_in(dip), .pb_in(pb), .led(led), .sevenseg(sevenseg),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .audio_bit(audio_bit), .oled_write(oled_write), .oled_col(oled_col), .oled_row(oled_row), .oled_data(oled_data),
        .stat_imiss(stat_imiss), .stat_dmiss(stat_dmiss), .stat_stall(stat_stall)
    );

    mig_bridge bridge (
        .ui_clk(ui_clk), .ui_rst(ui_rst), .cpu_rst(rst),
        .req_tog(req_tog), .req_we(req_we), .req_line(req_line), .req_wdata(req_wdata),
        .req_wmask(req_wmask), .ack_tog(ack_tog), .ack_rdata(ack_rdata),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_mask(app_wdf_mask), .app_wdf_wren(app_wdf_wren),
        .app_wdf_end(app_wdf_end), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid)
    );
endmodule
