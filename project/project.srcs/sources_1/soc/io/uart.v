`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// Simple 8N1 UART for rv_soc, clocked by the CPU clock.
// DIV = clock / baud, an integer: 37.5 MHz / 1.5 Mbaud = 25 (also exact for the
// FT2232's 3 MHz baud generator: 3 MHz / 2). At 75 MHz use DIV = 50.
// The receiver samples the middle of each bit, timed from the start-bit edge.
// -----------------------------------------------------------------------------
module uart_tx #(parameter DIV = 25) (
    input            clk,
    input            rst,
    input      [7:0] data,
    input            start,       // ignored while busy
    output           ready,
    output reg       txd = 1'b1
);
    reg [$clog2(DIV)-1:0] cnt = 0;
    reg [3:0]             bitn = 0;     // 0 = idle, 1..10 = start, 8 data, stop
    reg [8:0]             sh = 9'h1FF;
    assign ready = (bitn == 0);

    always @(posedge clk) begin
        if (rst) begin
            bitn <= 0; txd <= 1'b1; cnt <= 0;
        end
        else if (bitn == 0) begin
            if (start) begin
                sh   <= {data, 1'b0};             // start bit first
                bitn <= 1;
                cnt  <= 0;
            end
        end
        else begin
            txd <= sh[0];
            if (cnt == DIV - 1) begin
                cnt  <= 0;
                sh   <= {1'b1, sh[8:1]};
                bitn <= (bitn == 10) ? 4'd0 : bitn + 1'b1;
            end
            else
                cnt <= cnt + 1'b1;
        end
    end
endmodule

module uart_rx #(parameter DIV = 25) (
    input            clk,
    input            rst,
    input            rxd,
    output reg [7:0] data = 8'd0,
    output reg       valid = 1'b0      // one-cycle pulse per received byte
);
    reg [2:0]             sync = 3'b111;
    reg [$clog2(DIV)-1:0] cnt = 0;
    reg [3:0]             bitn = 0;    // 0 idle, 1 start, 2..9 data, 10 stop
    reg [7:0]             sh = 0;
    wire                  rx = sync[2];

    always @(posedge clk) begin
        sync  <= {sync[1:0], rxd};
        valid <= 1'b0;
        if (rst) begin
            bitn <= 0; cnt <= 0;
        end
        else if (bitn == 0) begin
            if (~rx) begin                       // start bit edge
                bitn <= 1;
                cnt  <= DIV / 2;                 // first sample in the middle of the start bit
            end
        end
        else if (cnt == DIV - 1) begin
            cnt <= 0;
            case (bitn)
                4'd1:    bitn <= rx ? 4'd0 : 4'd2;           // false start: back to idle
                4'd10:   begin
                             bitn <= 0;
                             if (rx) begin data <= sh; valid <= 1'b1; end   // stop bit ok
                         end
                default: begin sh <= {rx, sh[7:1]}; bitn <= bitn + 1'b1; end
            endcase
        end
        else
            cnt <= cnt + 1'b1;
    end
endmodule

// Byte FIFO, first-word-fall-through, distributed RAM. Overflow drops bytes.
module byte_fifo #(parameter AW = 9) (
    input            clk,
    input            rst,
    input      [7:0] wdata,
    input            we,
    output     [7:0] rdata,
    output           nonempty,
    input            re,
    output reg       overflow = 1'b0   // sticky
);
    (* ram_style = "distributed" *) reg [7:0] mem [0:(1<<AW)-1];
    reg [AW:0] wp = 0, rp = 0;
    wire full = (wp - rp) == (1 << AW);
    assign nonempty = (wp != rp);
    assign rdata    = mem[rp[AW-1:0]];

    always @(posedge clk) begin
        if (we & ~full) mem[wp[AW-1:0]] <= wdata;
        if (rst) begin
            wp <= 0; rp <= 0; overflow <= 1'b0;
        end
        else begin
            if (we) begin
                if (~full) wp <= wp + 1'b1;
                else       overflow <= 1'b1;
            end
            if (re & nonempty) rp <= rp + 1'b1;
        end
    end
endmodule
