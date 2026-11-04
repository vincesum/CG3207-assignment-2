`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// tb_soc: Verilator top for doom_soc. Clocks, UART and OLED are handled by the C++
// harness (sim/verilator/tb_main.cpp); DDR2 contents live in C++ (DPI).
//
// MIG model: behavioural app_* interface like ddr2_bringup/sim/tb_ddr_tester.v -
// app_rdy / app_wdf_rdy drop now and then (LFSR), fixed read latency, honours byte
// masks, Strict ordering (one command at a time, in order), calibration delay.
// -----------------------------------------------------------------------------
module tb_soc #(
    parameter ROM_FILE = "boot.hex",
    parameter RD_LAT   = 22,            // ui_clk cycles from read command to data
    parameter CAL_CYC  = 200            // ui_clk cycles before calibration completes
)(
    input         clk_cpu,
    input         clk_ui,
    input         rst_in,               // asynchronous-ish, from the harness (held a few cycles)
    input  [15:0] dip,
    input  [4:0]  pb,
    input         uart_rxd,
    output        uart_txd,
    output [7:0]  led,
    output [31:0] sevenseg,
    output        oled_write,
    output [6:0]  oled_col,
    output [5:0]  oled_row,
    output [23:0] oled_data,
    // trace / status for the harness
    output        tr_valid,             // a register write commits this CPU cycle
    output [4:0]  tr_rd,
    output [31:0] tr_val,
    output        sim_done,
    output [31:0] sim_code,
    output        mem_stall,
    output        calib
);
    import "DPI-C" function void ddr_read(input int line, output bit [127:0] data);
    import "DPI-C" function void ddr_write(input int line, input bit [127:0] data, input bit [15:0] mask);

    // ---------------- reset: CPU held until "calibration" completes ----------------
    reg [15:0] cal_cnt = 0;
    reg        calib_r = 1'b0;
    always @(posedge clk_ui) begin
        if (cal_cnt != CAL_CYC[15:0]) cal_cnt <= cal_cnt + 1'b1;
        else calib_r <= 1'b1;
    end
    assign calib = calib_r;
    wire ui_rst = ~calib_r;

    reg [1:0] rst_sync = 2'b11;
    always @(posedge clk_cpu) rst_sync <= {rst_sync[0], rst_in | ~calib_r};
    wire rst = rst_sync[1];

    // ---------------- DUT ----------------
    wire [26:0]  app_addr;
    wire [2:0]   app_cmd;
    wire         app_en, app_wdf_wren, app_wdf_end;
    wire [127:0] app_wdf_data;
    wire [15:0]  app_wdf_mask;
    reg          app_rdy = 1'b0, app_wdf_rdy = 1'b0;
    reg  [127:0] app_rd_data = 128'd0;
    reg          app_rd_data_valid = 1'b0;

    doom_soc #(.ROM_FILE(ROM_FILE)) soc (
        .clk(clk_cpu), .rst(rst), .ui_clk(clk_ui), .ui_rst(ui_rst),
        .dip(dip), .pb(pb), .led(led), .sevenseg(sevenseg),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .oled_write(oled_write), .oled_col(oled_col), .oled_row(oled_row), .oled_data(oled_data),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_mask(app_wdf_mask), .app_wdf_wren(app_wdf_wren),
        .app_wdf_end(app_wdf_end), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid)
    );

    // ---------------- MIG model ----------------
    reg [15:0]  lfsr = 16'hACE1;
    reg [127:0] wbuf_d;  reg [15:0] wbuf_m;  reg wbuf_full = 1'b0;   // data that came before its command
    reg         wcmd_pend = 1'b0;  reg [22:0] wcmd_line;             // command that came before its data
    integer     rd_timer = -1;
    reg [22:0]  rd_line;
    reg [127:0] rd_tmp;
    integer     model_errors = 0;
    wire        wdata_now = app_wdf_wren && app_wdf_rdy;

    always @(posedge clk_ui) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        app_rdy     <= calib_r & (lfsr[3:0] != 4'd0) & (rd_timer < 0) & ~wcmd_pend;
        app_wdf_rdy <= calib_r & (lfsr[7:4] != 4'd0) & ~wbuf_full;
        app_rd_data_valid <= 1'b0;

        if (wdata_now && !app_wdf_end) begin $display("MIG MODEL ERROR: wdf_end low"); model_errors = model_errors + 1; end
        if (wdata_now && wcmd_pend) begin                 // late data for an accepted write command
            ddr_write({9'd0, wcmd_line}, app_wdf_data, app_wdf_mask);
            wcmd_pend <= 1'b0;
        end
        else if (wdata_now && !(app_en && app_rdy && app_cmd == 3'b000)) begin
            wbuf_d <= app_wdf_data; wbuf_m <= app_wdf_mask; wbuf_full <= 1'b1;
        end

        if (app_en && app_rdy) begin
            if (app_addr[2:0] != 3'd0 || app_addr[26]) begin
                $display("MIG MODEL ERROR: bad app_addr %h", app_addr); model_errors = model_errors + 1;
            end
            if (app_cmd == 3'b000) begin
                if (wbuf_full) begin
                    ddr_write({9'd0, app_addr[25:3]}, wbuf_d, wbuf_m);
                    wbuf_full <= 1'b0;
                end
                else if (wdata_now)
                    ddr_write({9'd0, app_addr[25:3]}, app_wdf_data, app_wdf_mask);
                else begin
                    wcmd_pend <= 1'b1;                    // data follows later
                    wcmd_line <= app_addr[25:3];
                end
            end
            else if (app_cmd == 3'b001) begin
                rd_timer <= RD_LAT;
                rd_line  <= app_addr[25:3];
            end
            else begin $display("MIG MODEL ERROR: bad app_cmd %b", app_cmd); model_errors = model_errors + 1; end
        end
        if (rd_timer == 0) begin
            ddr_read({9'd0, rd_line}, rd_tmp);
            app_rd_data <= rd_tmp;
            app_rd_data_valid <= 1'b1;
        end
        if (rd_timer >= 0) rd_timer <= rd_timer - 1;
    end

    // ---------------- trace: register writes as they commit ----------------
    // A W-stage instruction is new in a cycle if the pipeline advanced at the edge
    // that started the cycle (MemStall was low in the previous cycle).
    reg fresh = 1'b0;
    always @(posedge clk_cpu) fresh <= ~rst & ~soc.MemStall;
    assign tr_valid  = fresh & ~rst & soc.cpu.RegWriteW & (soc.cpu.rdW != 5'd0);
    assign tr_rd     = soc.cpu.rdW;
    assign tr_val    = soc.cpu.WD;
    assign mem_stall = soc.MemStall;

    // ---------------- SIM_CTRL (MMIO 0xFC) ----------------
    reg        done_r = 1'b0;
    reg [31:0] code_r = 32'd0;
    always @(posedge clk_cpu)
        if (!rst && soc.mmio_sel && soc.ALUResult[7:0] == 8'hFC && soc.MemWrite[0] && !soc.MemStall) begin
            done_r <= 1'b1;
            code_r <= soc.WriteData;
        end
    assign sim_done = done_r;
    assign sim_code = code_r;
endmodule
