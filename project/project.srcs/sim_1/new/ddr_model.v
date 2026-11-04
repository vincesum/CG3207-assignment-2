`timescale 1ns / 1ps
// Simulation stand-in for the DDR2 controller (MIG), with the same app_* interface as the real
// one. It holds off ready now and then, has a fixed read latency, honours byte masks, and
// handles one command at a time in order. Holds 2**LINE_BITS 16-byte lines; addresses wrap.
module ddr_model #(
    parameter RD_LAT    = 22,       // ui_clk cycles from read command to data
    parameter CAL_CYC   = 200,      // ui_clk cycles before calibration completes
    parameter LINE_BITS = 18        // 4 MB
)(
    input              ui_clk,
    output             calib,
    input      [26:0]  app_addr,
    input      [2:0]   app_cmd,
    input              app_en,
    output reg         app_rdy = 1'b0,
    input      [127:0] app_wdf_data,
    input      [15:0]  app_wdf_mask,
    input              app_wdf_wren,
    input              app_wdf_end,
    output reg         app_wdf_rdy = 1'b0,
    output reg [127:0] app_rd_data = 128'd0,
    output reg         app_rd_data_valid = 1'b0
);
    reg [127:0] mem [0:(1 << LINE_BITS) - 1];
    integer i;
    initial for (i = 0; i < (1 << LINE_BITS); i = i + 1) mem[i] = 128'd0;

    reg [15:0] cal_cnt = 0;
    reg        calib_r = 1'b0;
    assign calib = calib_r;

    reg [15:0]  lfsr = 16'hACE1;
    reg [127:0] wbuf_d = 0;
    reg [15:0]  wbuf_m = 0;
    reg         wbuf_full = 1'b0;           // data that came before its command
    reg         wcmd_pend = 1'b0;           // command that came before its data
    reg [22:0]  wcmd_line = 0;
    integer     rd_timer = -1;
    reg [22:0]  rd_line = 0;
    integer     errors = 0;
    wire        wdata_now = app_wdf_wren && app_wdf_rdy;

    task write_line(input [22:0] line, input [127:0] data, input [15:0] mask);
        integer b;
        reg [127:0] v;
        begin
            v = mem[line[LINE_BITS-1:0]];
            for (b = 0; b < 16; b = b + 1)
                if (!mask[b]) v[8*b +: 8] = data[8*b +: 8];     // mask 1 = keep the byte
            mem[line[LINE_BITS-1:0]] = v;
        end
    endtask

    always @(posedge ui_clk) begin
        if (cal_cnt != CAL_CYC[15:0]) cal_cnt <= cal_cnt + 1'b1;
        else calib_r <= 1'b1;

        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        app_rdy     <= calib_r & (lfsr[3:0] != 4'd0) & (rd_timer < 0) & ~wcmd_pend;
        app_wdf_rdy <= calib_r & (lfsr[7:4] != 4'd0) & ~wbuf_full;
        app_rd_data_valid <= 1'b0;

        if (wdata_now && !app_wdf_end) begin
            $display("DDR MODEL ERROR: wdf_end low");
            errors = errors + 1;
        end
        if (wdata_now && wcmd_pend) begin
            write_line(wcmd_line, app_wdf_data, app_wdf_mask);
            wcmd_pend <= 1'b0;
        end
        else if (wdata_now && !(app_en && app_rdy && app_cmd == 3'b000)) begin
            wbuf_d <= app_wdf_data;
            wbuf_m <= app_wdf_mask;
            wbuf_full <= 1'b1;
        end

        if (app_en && app_rdy) begin
            if (app_addr[2:0] != 3'd0 || app_addr[26]) begin
                $display("DDR MODEL ERROR: bad address %h", app_addr);
                errors = errors + 1;
            end
            if (app_cmd == 3'b000) begin
                if (wbuf_full) begin
                    write_line(app_addr[25:3], wbuf_d, wbuf_m);
                    wbuf_full <= 1'b0;
                end
                else if (wdata_now)
                    write_line(app_addr[25:3], app_wdf_data, app_wdf_mask);
                else begin
                    wcmd_pend <= 1'b1;
                    wcmd_line <= app_addr[25:3];
                end
            end
            else if (app_cmd == 3'b001) begin
                rd_timer <= RD_LAT;
                rd_line  <= app_addr[25:3];
            end
            else begin
                $display("DDR MODEL ERROR: bad command %b", app_cmd);
                errors = errors + 1;
            end
        end
        if (rd_timer == 0) begin
            app_rd_data <= mem[rd_line[LINE_BITS-1:0]];
            app_rd_data_valid <= 1'b1;
        end
        if (rd_timer >= 0) rd_timer <= rd_timer - 1;
    end
endmodule
