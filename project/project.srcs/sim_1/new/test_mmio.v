`timescale 1ns / 1ps
// Self-checking test of the peripheral block (mmio) on its own.
module test_mmio;
    localparam DIV = 4;
    reg clk = 0, rst = 1, commit = 1, sel = 0, rd = 0, uart_rxd = 1;
    reg stat_imiss = 0, stat_dmiss = 0, stat_stall = 0;
    reg [7:0] addr = 0;
    reg [3:0] we = 0;
    reg [31:0] wdata = 0;
    reg [15:0] dip = 16'h1234;
    reg [4:0] pb = 5'h0A;
    wire [31:0] rdata, sevenseg;
    wire [7:0] led;
    wire uart_txd, audio_bit, oled_write;
    wire [6:0] oled_col;
    wire [5:0] oled_row;
    wire [23:0] oled_data;

    always #5 clk = ~clk;

    mmio #(.UART_DIV(DIV)) dut (
        .clk(clk), .rst(rst), .commit(commit), .sel(sel), .addr(addr), .rd(rd), .we(we), .wdata(wdata),
        .rdata(rdata), .dip_in(dip), .pb_in(pb), .led(led), .sevenseg(sevenseg), .uart_rxd(uart_rxd),
        .uart_txd(uart_txd), .audio_bit(audio_bit), .oled_write(oled_write), .oled_col(oled_col),
        .oled_row(oled_row), .oled_data(oled_data), .stat_imiss(stat_imiss), .stat_dmiss(stat_dmiss),
        .stat_stall(stat_stall)
    );

    integer checks = 0, fails = 0;
    task check(input [40*8-1:0] name, input [31:0] got, input [31:0] expected);
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

    task write(input [7:0] a, input [31:0] d, input [3:0] mask);
        begin
            @(negedge clk);
            sel = 1; addr = a; wdata = d; we = mask;
            @(negedge clk);
            sel = 0; we = 0;
        end
    endtask
    reg [31:0] value;
    task read(input [7:0] a);
        begin
            @(negedge clk);
            sel = 1; addr = a; rd = 1;
            #1 value = rdata;
            @(negedge clk);
            sel = 0; rd = 0;
        end
    endtask

    // Count OLED writes and decode UART output
    integer n_pixels = 0, n_tx = 0, b;
    reg [7:0] tx_byte, tx_last = 0;
    always @(posedge clk) if (oled_write === 1'b1) n_pixels = n_pixels + 1;
    initial forever begin
        @(negedge uart_txd);
        repeat (DIV + DIV / 2) @(posedge clk);
        for (b = 0; b < 8; b = b + 1) begin
            tx_byte[b] = uart_txd;
            repeat (DIV) @(posedge clk);
        end
        tx_last = tx_byte;
        n_tx = n_tx + 1;
    end
    task uart_send(input [7:0] c);
        integer i;
        begin
            uart_rxd = 0;
            repeat (DIV) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                uart_rxd = c[i];
                repeat (DIV) @(posedge clk);
            end
            uart_rxd = 1;
            repeat (DIV) @(posedge clk);
        end
    endtask

    integer start_count;
    initial begin
        repeat (3) @(negedge clk);
        rst = 0;
        repeat (4) @(negedge clk);      // let the input synchronisers settle

        $display("Inputs");
        read(8'h64); check("switches", value, 32'h1234);
        read(8'h68); check("buttons", value, 32'h0A);
        read(8'h20); check("write-only register reads 0", value, 0);

        $display("LEDs and 7-segment display");
        write(8'h60, 32'hFFFF_FF5A, 4'b0001);
        check("LEDs", led, 8'h5A);
        write(8'h80, 32'h1234_5678, 4'b1111);
        check("7-segment", sevenseg, 32'h1234_5678);
        write(8'h80, 32'h0000_AB00, 4'b0010);
        check("7-segment byte write", sevenseg, 32'h1234_AB78);

        $display("Nothing happens until the instruction commits");
        commit = 0;
        write(8'h60, 32'hA5, 4'b0001);
        check("LEDs held", led, 8'h5A);
        write(8'h80, 32'hDEAD_BEEF, 4'b1111);
        check("7-segment held", sevenseg, 32'h1234_AB78);
        start_count = n_pixels;
        write(8'h28, 32'hFFFF, 4'b1111);
        @(negedge clk);
        check("no OLED write", n_pixels - start_count, 0);
        write(8'h0C, 32'h55, 4'b0001);
        repeat (DIV * 12) @(negedge clk);
        check("no UART byte sent", n_tx, 0);
        commit = 1;

        $display("A store repeated during a stall happens once");
        @(negedge clk);
        commit = 0; sel = 1; addr = 8'h60; wdata = 8'h11; we = 4'b0001;
        repeat (5) @(negedge clk);
        commit = 1;
        @(negedge clk);
        sel = 0; we = 0;
        check("LEDs written when it commits", led, 8'h11);

        $display("UART send");
        read(8'h08); check("ready", value, 1);
        write(8'h0C, 32'h5A, 4'b0001);
        #1 read(8'h08); check("busy while sending", value, 0);
        repeat (DIV * 12) @(negedge clk);
        check("one byte sent", n_tx, 1);
        check("byte", tx_last, 8'h5A);
        read(8'h08); check("ready again", value, 1);

        $display("UART receive");
        read(8'h00); check("nothing waiting", value, 0);
        uart_send(8'h41);
        uart_send(8'h42);
        repeat (3) @(negedge clk);
        read(8'h00); check("byte waiting", value, 1);
        commit = 0;
        read(8'h04); check("peek first byte, not committed", value, 8'h41);
        read(8'h04); check("not removed", value, 8'h41);
        commit = 1;
        read(8'h04); check("first byte", value, 8'h41);
        read(8'h04); check("second byte", value, 8'h42);
        read(8'h00); check("empty again", value, 0);
        read(8'hBC); check("no overflow", value, 0);

        $display("OLED");
        write(8'h20, 10, 4'b0001);
        write(8'h24, 20, 4'b0001);
        write(8'h2C, 32'h14, 4'b0001);          // 16-bit colour, auto-advance along the row
        start_count = n_pixels;
        write(8'h28, 32'hF800, 4'b1111);
        #1;
        check("first pixel stays at the column", oled_col, 10);
        check("row", oled_row, 20);
        check("colour", oled_data, 32'hF80000);
        write(8'h28, 32'h07E0, 4'b1111);
        #1;
        check("second pixel advances", oled_col, 11);
        check("colour", oled_data, 32'h00FC00);
        write(8'h20, 95, 4'b0001);
        write(8'h28, 32'h001F, 4'b1111);
        #1 check("wraps at column 96", oled_col, 0);
        check("to the next row", oled_row, 21);
        @(negedge clk);
        check("one write per store", n_pixels - start_count, 3);
        write(8'h2C, 32'h14, 4'b0001);          // writing CTRL re-arms the auto-advance
        write(8'h20, 40, 4'b0001);
        write(8'h28, 32'h001F, 4'b1111);
        #1 check("re-armed: stays at the column", oled_col, 40);

        $display("Counters");
        read(8'hA0); start_count = value;
        read(8'hA0); check("cycle counter counts", value - start_count > 0, 1);
        @(negedge clk); stat_imiss = 1; stat_stall = 1;
        @(negedge clk); stat_imiss = 0; stat_dmiss = 1;
        @(negedge clk); stat_dmiss = 0; stat_stall = 0;
        read(8'hB0); check("instruction misses", value, 1);
        read(8'hB4); check("data misses", value, 1);
        read(8'hB8); check("stall cycles", value, 2);

        $display("Audio registers");
        read(8'hDC); check("no voices playing", value, 0);
        write(8'hC0, 3, 4'b1111);               // voice 3
        write(8'hC4, 0, 4'b1111);
        write(8'hC8, 8'h80, 4'b1111);
        write(8'hC8, 8'h40, 4'b1111);
        write(8'hCC, 2, 4'b1111);
        write(8'hD0, 32'h4000_0000, 4'b1111);
        write(8'hD4, 127, 4'b1111);
        write(8'hD8, 1, 4'b1111);
        repeat (3) @(negedge clk);
        read(8'hDC); check("voice 3 playing", value, 32'h08);
        write(8'hD8, 0, 4'b1111);
        repeat (3) @(negedge clk);
        read(8'hDC); check("voice 3 stopped", value, 0);

        $display("test_mmio: %0d passed, %0d failed", checks - fails, fails);
        if (fails == 0) $display("==== test_mmio: PASS ====");
        else            $display("==== test_mmio: FAIL (%0d) ====", fails);
        $finish;
    end
endmodule
