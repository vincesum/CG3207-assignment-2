`timescale 1ns / 1ps
// Self-checking test of the whole SoC: CPU, boot ROM, caches, bridge and peripherals, against a
// model of the DDR2 controller. Program: test_soc_rom.asm, built into the ROM.
// It only looks at rv_soc's pins, so the same testbench also runs on the synthesized netlist
// (define POST_SYNTH and see soc_build/post_synth_sim.tcl). Use "run all" in Vivado.
module test_soc #(
    parameter RD_LAT = 22,                  // DDR2 read latency, in ui_clk cycles
    parameter MAX_CYCLES = 3000000
)();
    reg  ui_clk = 0, clk = 0;
    always #5 ui_clk = ~ui_clk;
    always @(posedge ui_clk) clk = ~clk;

    wire        calib;
    reg  [1:0]  rst_sync = 2'b11;
    always @(posedge clk) rst_sync <= {rst_sync[0], ~calib};
    wire        rst = rst_sync[1];

    reg  [15:0] dip = 16'hA5A5;
    reg  [4:0]  pb = 5'h15;
    reg         uart_rxd = 1'b1;
    wire        uart_txd, audio_bit, oled_write;
    wire [7:0]  led;
    wire [31:0] sevenseg;
    wire [6:0]  oled_col;
    wire [5:0]  oled_row;
    wire [23:0] oled_data;
    wire [26:0] app_addr;
    wire [2:0]  app_cmd;
    wire        app_en, app_rdy, app_wdf_wren, app_wdf_end, app_wdf_rdy, app_rd_data_valid;
    wire [127:0] app_wdf_data, app_rd_data;
    wire [15:0] app_wdf_mask;

`ifdef POST_SYNTH
    rv_soc dut (
`else
    rv_soc #(.ROM_FILE("test_soc_rom.mem")) dut (
`endif
        .clk(clk), .rst(rst), .ui_clk(ui_clk), .ui_rst(~calib),
        .dip(dip), .pb(pb), .led(led), .sevenseg(sevenseg),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd), .audio_bit(audio_bit),
        .oled_write(oled_write), .oled_col(oled_col), .oled_row(oled_row), .oled_data(oled_data),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_mask(app_wdf_mask), .app_wdf_wren(app_wdf_wren),
        .app_wdf_end(app_wdf_end), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid)
    );

    ddr_model #(.RD_LAT(RD_LAT)) ddr (
        .ui_clk(ui_clk), .calib(calib),
        .app_addr(app_addr), .app_cmd(app_cmd), .app_en(app_en), .app_rdy(app_rdy),
        .app_wdf_data(app_wdf_data), .app_wdf_mask(app_wdf_mask), .app_wdf_wren(app_wdf_wren),
        .app_wdf_end(app_wdf_end), .app_wdf_rdy(app_wdf_rdy),
        .app_rd_data(app_rd_data), .app_rd_data_valid(app_rd_data_valid)
    );

    localparam DIV = 25;                    // CPU cycles per UART bit
    localparam N_REPORTS = 33;

    // ---- What the program reports ----
    reg [31:0] report [1:N_REPORTS];
    integer    n_reports = 0;
    reg [7:0]  led_prev = 0;
    always @(posedge clk) begin
        if (!rst && led !== led_prev) begin
            led_prev <= led;
            if (led !== 8'hFF) begin
                n_reports = n_reports + 1;
                if (n_reports <= N_REPORTS) report[n_reports] = sevenseg;
            end
        end
    end

    // ---- OLED: log every pixel ----
    integer    n_pixels = 0;
    reg [6:0]  px_col [0:2];
    reg [5:0]  px_row [0:2];
    reg [23:0] px_data [0:2];
    always @(posedge clk) begin
        if (!rst && oled_write === 1'b1) begin
            if (n_pixels < 3) begin
                px_col[n_pixels] = oled_col;
                px_row[n_pixels] = oled_row;
                px_data[n_pixels] = oled_data;
            end
            n_pixels = n_pixels + 1;
        end
    end

    // ---- UART: decode what the SoC sends ----
    integer    n_tx = 0, b;
    reg [7:0]  tx_byte;
    reg [7:0]  tx_log [0:7];
    initial begin
        forever begin
            @(negedge uart_txd);
            if (!rst) begin
                repeat (DIV + DIV / 2) @(posedge clk);
                for (b = 0; b < 8; b = b + 1) begin
                    tx_byte[b] = uart_txd;
                    repeat (DIV) @(posedge clk);
                end
                if (n_tx < 8) tx_log[n_tx] = tx_byte;
                n_tx = n_tx + 1;
            end
        end
    end

    // ---- UART: send bytes to the SoC ----
    task uart_send(input [7:0] c);
        integer i;
        begin
            uart_rxd = 1'b0;
            repeat (DIV) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rxd = c[i];
                repeat (DIV) @(posedge clk);
            end
            uart_rxd = 1'b1;
            repeat (DIV) @(posedge clk);
        end
    endtask

    // ---- Checks ----
    integer checks = 0, fails = 0, cycles = 0;
    task check(input [32*8-1:0] name, input [31:0] got, input [31:0] expected);
        begin
            checks = checks + 1;
            if (got === expected)
                $display("  pass  %0s: %h", name, got);
            else begin
                fails = fails + 1;
                $display("  FAIL  %0s: got %h, expected %h", name, got, expected);
            end
        end
    endtask

    function [31:0] ddr_word(input [31:0] offset);
        reg [127:0] line;
        begin
            line = ddr.mem[offset[21:4]];
            ddr_word = line[{offset[3:2], 5'b00000} +: 32];
        end
    endfunction

    initial begin
        wait (rst === 1'b0);
        repeat (50) @(posedge clk);
        uart_send(8'h41);
        uart_send(8'h42);
    end

    initial begin
        wait (rst === 1'b0);
        while (led !== 8'hFF && cycles < MAX_CYCLES) begin
            @(posedge clk);
            cycles = cycles + 1;
        end
        repeat (400) @(posedge clk);        // let the last UART byte and DDR2 writes finish

        if (led !== 8'hFF) begin
            $display("  FAIL  program didn't finish in %0d cycles, LEDs %h", cycles, led);
            fails = fails + 1;
        end
        $display("Peripherals");
        check("reports, each exactly once", n_reports, N_REPORTS);
        check("switches",                report[1],  32'h0000_A5A5);
        check("buttons",                 report[2],  32'h0000_0015);
        check("UART bytes sent",         n_tx,       2);
        check("UART sent first",         tx_log[0],  32'h48);
        check("UART sent second",        tx_log[1],  32'h49);
        check("UART received first",     report[3],  32'h41);
        check("UART received second",    report[4],  32'h42);
        check("UART FIFO empty after",   report[5],  32'h0);
        check("OLED pixel 0 column",     px_col[0],  5);
        check("OLED pixel 0 row",        px_row[0],  6);
        check("OLED pixel 0 colour",     px_data[0], 32'hF80000);
        check("OLED pixel 1 column",     px_col[1],  6);
        check("OLED pixel 1 colour",     px_data[1], 32'h00FC00);
        check("OLED pixel 2 column",     px_col[2],  7);
        check("OLED pixel 2 colour",     px_data[2], 32'h0000F8);
        check("OLED pixels, once each",  n_pixels,   3 + 2 * 6);
        $display("Data cache");
        check("miss then hits: misses",  report[6],  1);
        check("data after a miss",       report[7],  32'h1111_1111);
        check("data on a hit",           report[8],  32'h2222_2222);
        check("a miss stalls the CPU",   report[9],  1);
        check("8 KB apart: misses",      report[10], 3);
        check("evicted line, reloaded",  report[11], 32'hB0B0_B0B0);
        check("line that evicted it",    report[12], 32'hC0C0_C0C0);
        check("store hit: misses",       report[13], 0);
        check("store hit: new data",     report[14], 32'h3333_3333);
        check("store miss: then misses", report[15], 1);
        check("store miss: data",        report[16], 32'h6666_6666);
        $display("Byte and halfword on DDR2");
        check("word after sb and sh",    report[17], 32'hBBCC_AA11);
        check("lb",                      report[18], 32'hFFFF_FFAA);
        check("lbu",                     report[19], 32'h0000_00AA);
        check("lh",                      report[20], 32'hFFFF_BBCC);
        check("lhu",                     report[21], 32'h0000_BBCC);
        check("sb on a cached line",     report[22], 32'hBBCC_AA55);
        check("high address",            report[23], 32'h5A5A_A5A5);
        $display("Instruction cache");
        check("routine in DDR2, first",  report[24], 574);
        check("first run missed",        report[25], 1);
        check("routine in DDR2, second", report[26], 574);
        check("second run: misses",      report[27], 0);
        $display("Hazards on a cache miss");
        check("load-use",                report[28], 32'h1235);
        check("load into a branch",      report[29], 0);
        $display("M extension");
        check("mulhsu",                  report[30], 32'hFFFF_FFFF);
        check("divide by zero",          report[31], 32'hFFFF_FFFF);
        check("remainder of that",       report[32], 5);
        $display("Other");
        check("cycle counter counts",    report[33], 1);
        check("write-through to DDR2",   ddr_word(32'h100), 32'h3333_3333);
        check("bytes reached DDR2",      ddr_word(32'h600), 32'hBBCC_AA55);
        check("mem-mem copy in DDR2",    ddr_word(32'h708), 101);
        check("DDR2 model errors",       ddr.errors, 0);

        $display("test_soc: %0d passed, %0d failed, %0d cycles, RD_LAT %0d", checks - fails, fails, cycles, RD_LAT);
        if (fails == 0) $display("==== test_soc: PASS ====");
        else            $display("==== test_soc: FAIL (%0d) ====", fails);
        $finish;
    end
endmodule
