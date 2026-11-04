`timescale 1ns / 1ps
// Behavioural model of the MIG native interface + testbench for ddr_tester.
// The model ignores the top app_addr bit, like the real single-rank MIG (rank bit).
//   (no define)  default LAST_ADDR -> expect 3 clean passes
//   -DFAULT      corrupt one read  -> expect err_data at that address
//   -DOVERRANGE  LAST_ADDR covers the rank bit (the hardware bug) -> expect err_data
//   -DMASKBUG    model ignores byte masks -> expect err_mask only
module tb_ddr_tester;
    localparam AW = 9;                         // 8 address bits + rank bit; default LAST_ADDR = 0x0F8 -> 32 bursts
    localparam LAT = 22;                       // read latency in ui_clk cycles

    reg clk = 0, rst = 1, calib = 0;
    always #6.667 clk = ~clk;                  // ~75 MHz

    wire [AW-1:0] app_addr; wire [2:0] app_cmd; wire app_en;
    wire [127:0] app_wdf_data; wire [15:0] app_wdf_mask; wire app_wdf_wren, app_wdf_end;
    reg  app_rdy = 0, app_wdf_rdy = 0;
    reg  [127:0] app_rd_data = 0; reg app_rd_data_valid = 0;
    wire error, err_data, err_mask, reading, writing; wire [7:0] passes; wire [AW-1:0] fail_addr;

`ifdef OVERRANGE
    ddr_tester #(.AW(AW), .LAST_ADDR(9'h1F8)) dut (
`else
    ddr_tester #(.AW(AW)) dut (                // DEFAULT LAST_ADDR
`endif
        .clk(clk), .rst(rst), .calib_done(calib),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_mask(app_wdf_mask), .app_wdf_wren(app_wdf_wren),
        .app_wdf_end(app_wdf_end), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid),
        .error(error), .err_data(err_data), .err_mask(err_mask), .passes(passes), .reading(reading), .writing(writing), .fail_addr(fail_addr));

    // ---------------- MIG model ----------------
    reg [127:0] mem [0:31];                    // 32 bursts; app_addr[8] (rank) ignored
    reg [127:0] wfifo_d [0:7]; reg [15:0] wfifo_m [0:7];
    reg [2:0] wr_ptr = 0, rd_ptr = 0; reg [3:0] wcount = 0;
    reg [15:0] lfsr = 16'hACE1;
    integer rd_timer = -1; reg [AW-1:0] rd_addr; integer i, b, model_errors = 0;

    always @(posedge clk) begin
        lfsr <= {lfsr[14:0], lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10]};
        app_rdy     <= calib & (lfsr[3:0] != 0) & (rd_timer < 0);   // busy now and then
        app_wdf_rdy <= calib & (lfsr[7:4] != 0) & (wcount < 8);
        app_rd_data_valid <= 1'b0;

        // write data port
        if (app_wdf_wren && app_wdf_rdy) begin
            if (!app_wdf_end) begin $display("MODEL ERROR: wdf_end low"); model_errors = model_errors + 1; end
            wfifo_d[wr_ptr] <= app_wdf_data; wfifo_m[wr_ptr] <= app_wdf_mask; wr_ptr <= wr_ptr + 1;
        end
        // command port
        if (app_en && app_rdy) begin
            if (app_addr[2:0] != 0) begin $display("MODEL ERROR: unaligned addr %h", app_addr); model_errors = model_errors + 1; end
            if (app_cmd == 3'b000) begin
                if (wcount == 0 && !(app_wdf_wren && app_wdf_rdy)) begin
                    $display("MODEL ERROR: write cmd with no data"); model_errors = model_errors + 1;
                end
                for (b = 0; b < 16; b = b + 1)
`ifdef MASKBUG
                    mem[app_addr[7:3]][b*8 +: 8] <= wfifo_d[rd_ptr][b*8 +: 8];
`else
                    if (!wfifo_m[rd_ptr][b]) mem[app_addr[7:3]][b*8 +: 8] <= wfifo_d[rd_ptr][b*8 +: 8];
`endif
                rd_ptr <= rd_ptr + 1;
            end else if (app_cmd == 3'b001) begin
                rd_timer <= LAT; rd_addr <= app_addr;
            end
        end
        wcount <= wcount + ((app_wdf_wren && app_wdf_rdy) ? 1 : 0) - ((app_en && app_rdy && app_cmd == 3'b000) ? 1 : 0);
        // read return
        if (rd_timer == 0) begin
            app_rd_data <= mem[rd_addr[7:3]];
`ifdef FAULT
            if (rd_addr == 200 && dut.passes == 1) app_rd_data <= mem[rd_addr[7:3]] ^ (128'h1 << 77);
`endif
            app_rd_data_valid <= 1'b1;
        end
        if (rd_timer >= 0) rd_timer <= rd_timer - 1;
    end

    initial begin
        for (i = 0; i < 32; i = i + 1) mem[i] = {4{32'hDEAD_BEEF}};
        #50 rst = 0;
        #200 calib = 1;
        wait (dut.passes == 3 || dut.error);
        #100;
        $display("passes=%0d err_data=%0d err_mask=%0d fail_addr=%0d model_errors=%0d", passes, err_data, err_mask, fail_addr, model_errors);
`ifdef FAULT
        if (err_data && !err_mask && fail_addr == 200 && model_errors == 0) $display("RESULT: PASS (injected fault detected)");
        else $display("RESULT: FAIL (injected fault not reported correctly)");
`elsif OVERRANGE
        if (err_data && model_errors == 0) $display("RESULT: PASS (over-range aliasing detected, fail_addr=%0d)", fail_addr);
        else $display("RESULT: FAIL (aliasing not detected)");
`elsif MASKBUG
        if (err_mask && !err_data && model_errors == 0) $display("RESULT: PASS (mask bug reported on err_mask)");
        else $display("RESULT: FAIL (mask bug not isolated)");
`else
        if (!error && passes == 3 && model_errors == 0) $display("RESULT: PASS (3 clean passes)");
        else $display("RESULT: FAIL");
`endif
        $finish;
    end
    initial begin #20_000_000 $display("RESULT: FAIL (timeout)"); $finish; end
endmodule
