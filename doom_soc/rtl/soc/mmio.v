`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// mmio: memory-mapped peripherals for doom_soc, same offsets as Wrapper.v.
//
// Differences from Wrapper.v:
//  * Every side effect (register write, OLED write, UART TX, UART RX pop) happens only
//    in the cycle the M-stage instruction commits (commit = ~MemStall), because the
//    pipeline can now be frozen with the instruction sitting in M.
//  * UART RX has a FIFO: UART_RX_VALID = FIFO not empty, reading UART_RX pops a byte.
//  * Writing OLED_CTRL re-arms the auto-advance (the next OLED_DATA write goes to the
//    current COL/ROW instead of COL+1), so software can re-sync at the start of a frame.
//  * PB is 5 bits: {BTND, BTNU, BTNL, BTNC, BTNR}; reset is the CPU_RESET button.
//  * New read-only counters: 0xB0 I-cache refills, 0xB4 D-cache refills,
//    0xB8 MemStall cycles, 0xBC RX FIFO overflow flag.
// -----------------------------------------------------------------------------
module mmio #(
    parameter UART_DIV = 25
)(
    input              clk,
    input              rst,
    input              commit,       // ~MemStall: the M-stage instruction completes this cycle
    input              sel,          // address is in the MMIO page
    input      [7:0]   addr,
    input              rd,           // MemRead
    input      [3:0]   we,           // byte write enables
    input      [31:0]  wdata,
    output reg [31:0]  rdata,
    // board I/O
    input      [15:0]  dip_in,
    input      [4:0]   pb_in,
    output reg [7:0]   led = 8'd0,
    output reg [31:0]  sevenseg = 32'd0,
    input              uart_rxd,
    output             uart_txd,
    output             audio_bit,
    output reg         oled_write = 1'b0,
    output reg [6:0]   oled_col = 7'd0,
    output reg [5:0]   oled_row = 6'd0,
    output reg [23:0]  oled_data = 24'd0,
    // statistics from memctl
    input              stat_imiss,
    input              stat_dmiss,
    input              stat_stall
);
    localparam UART_RX_VALID_OFF = 8'h00, UART_RX_OFF   = 8'h04, UART_TX_READY_OFF = 8'h08,
               UART_TX_OFF       = 8'h0C, OLED_COL_OFF  = 8'h20, OLED_ROW_OFF      = 8'h24,
               OLED_DATA_OFF     = 8'h28, OLED_CTRL_OFF = 8'h2C, ACCEL_DATA_OFF    = 8'h40,
               ACCEL_DREADY_OFF  = 8'h44, LED_OFF       = 8'h60, DIP_OFF           = 8'h64,
               PB_OFF            = 8'h68, SEVENSEG_OFF  = 8'h80, CYCLECOUNT_OFF    = 8'hA0,
               IMISS_OFF         = 8'hB0, DMISS_OFF     = 8'hB4, STALL_OFF         = 8'hB8,
               RXOVF_OFF         = 8'hBC;

    wire [7:0] off = {addr[7:2], 2'b00};
    wire [3:0] wr  = (sel & commit) ? we : 4'b0000;
    wire       rdc = sel & commit & rd;

    // ---------------- inputs (synchronised) ----------------
    reg [15:0] dip_s1 = 0, dip = 0;
    reg [4:0]  pb_s1 = 0, pb = 0;
    always @(posedge clk) begin
        dip_s1 <= dip_in; dip <= dip_s1;
        pb_s1  <= pb_in;  pb  <= pb_s1;
    end

    // ---------------- counters ----------------
    reg [31:0] cycle_count = 0, imiss = 0, dmiss = 0, stalls = 0;
    always @(posedge clk) begin
        if (rst) begin
            cycle_count <= 0; imiss <= 0; dmiss <= 0; stalls <= 0;
        end
        else begin
            cycle_count <= cycle_count + 1;
            imiss  <= imiss  + stat_imiss;
            dmiss  <= dmiss  + stat_dmiss;
            stalls <= stalls + stat_stall;
        end
    end

    // ---------------- UART ----------------
    wire       tx_ready;
    wire [7:0] rx_byte, rx_head;
    wire       rx_strobe, rx_nonempty, rx_overflow;
    wire       tx_start = wr[0] && off == UART_TX_OFF;

    uart_tx #(.DIV(UART_DIV)) u_tx (.clk(clk), .rst(rst), .data(wdata[7:0]), .start(tx_start),
                                    .ready(tx_ready), .txd(uart_txd));
    uart_rx #(.DIV(UART_DIV)) u_rx (.clk(clk), .rst(rst), .rxd(uart_rxd), .data(rx_byte), .valid(rx_strobe));
    byte_fifo #(.AW(9)) u_rxq (.clk(clk), .rst(rst), .wdata(rx_byte), .we(rx_strobe),
                               .rdata(rx_head), .nonempty(rx_nonempty),
                               .re(rdc && off == UART_RX_OFF), .overflow(rx_overflow));

    wire [31:0] audio_status;
    doom_audio audio (.clk(clk), .rst(rst), .addr(off), .wr(wr[0]),
        .wdata(wdata), .status(audio_status), .audio_bit(audio_bit));

    // ---------------- reads ----------------
    always @(*) begin
        case (off)
            8'hDC: rdata = audio_status;
            UART_RX_VALID_OFF: rdata = {31'd0, rx_nonempty};
            UART_RX_OFF:       rdata = {24'd0, rx_nonempty ? rx_head : 8'd0};
            UART_TX_READY_OFF: rdata = {31'd0, tx_ready};
            DIP_OFF:           rdata = {16'd0, dip};
            PB_OFF:            rdata = {27'd0, pb};
            CYCLECOUNT_OFF:    rdata = cycle_count;
            IMISS_OFF:         rdata = imiss;
            DMISS_OFF:         rdata = dmiss;
            STALL_OFF:         rdata = stalls;
            RXOVF_OFF:         rdata = {31'd0, rx_overflow};
            default:           rdata = 32'd0;   // ACCEL_* (not fitted), write-only registers
        endcase
    end

    // ---------------- LED / 7-seg ----------------
    integer j;
    always @(posedge clk) begin
        if (rst) begin
            led <= 8'd0;
            sevenseg <= 32'd0;
        end
        else begin
            if (wr[0] && off == LED_OFF) led <= wdata[7:0];
            for (j = 0; j < 4; j = j + 1)
                if (wr[j] && off == SEVENSEG_OFF) sevenseg[8*j +: 8] <= wdata[8*j +: 8];
        end
    end

    // ---------------- OLED (same behaviour as Wrapper.v, plus CTRL re-arm) ----------------
    // [3:0] 0000 vary_pix_data, 0001 vary_col, 0010 vary_row, 0100 autoadvance_col (row major),
    //       0101 autoadvance_row (column major); [7:4] 0000 8-bit, 0001 16-bit, 0010 24-bit colour
    reg [7:0] oled_ctrl = 8'd0;
    reg       auto_row = 1'b0, auto_col = 1'b0;
    wire dec_col  = (off == OLED_COL_OFF);
    wire dec_row  = (off == OLED_ROW_OFF);
    wire dec_data = (off == OLED_DATA_OFF);
    wire dec_ctrl = (off == OLED_CTRL_OFF);
    wire any_wr   = |wr;

    always @(posedge clk) begin
        oled_write <= 1'b0;
        case (oled_ctrl[3:0])
            4'b0001:
                if (wr[0] && dec_col) begin
                    oled_write <= 1'b1; auto_row <= 1'b0; auto_col <= 1'b0;
                end
            4'b0010:
                if (wr[0] && dec_row) begin
                    oled_write <= 1'b1; auto_row <= 1'b0; auto_col <= 1'b0;
                end
            4'b0100:
                if (wr[0] && dec_data) begin
                    oled_write <= 1'b1; auto_row <= 1'b0; auto_col <= 1'b1;
                    if (auto_col) begin
                        if (oled_col >= 95) begin
                            oled_col <= 7'd0;
                            oled_row <= oled_row + 1'b1;     // 63 rolls over to 0
                        end
                        else oled_col <= oled_col + 1'b1;
                    end
                end
            4'b0101:
                if (wr[0] && dec_data) begin
                    oled_write <= 1'b1; auto_row <= 1'b1; auto_col <= 1'b0;
                    if (auto_row) begin
                        if (oled_row == 63) begin
                            oled_row <= 6'd0;
                            oled_col <= (oled_col >= 95) ? 7'd0 : oled_col + 1'b1;
                        end
                        else oled_row <= oled_row + 1'b1;
                    end
                end
            default:
                if (any_wr && dec_data) begin
                    oled_write <= 1'b1; auto_row <= 1'b0; auto_col <= 1'b0;
                end
        endcase

        case (oled_ctrl[7:4])
            4'b0001:
                if (wr[1] && wr[0] && dec_data)
                    oled_data <= {wdata[15:11], 3'd0, wdata[10:5], 2'd0, wdata[4:0], 3'd0};
            4'b0010: begin
                if (wr[2] && dec_data) oled_data[23:16] <= wdata[23:16];
                if (wr[1] && dec_data) oled_data[15:8]  <= wdata[15:8];
                if (wr[0] && dec_data) oled_data[7:0]   <= wdata[7:0];
            end
            default:
                if (wr[0] && dec_data)
                    oled_data <= {wdata[7:5], 5'd0, wdata[4:2], 5'd0, wdata[1:0], 6'd0};
        endcase

        if (wr[0] && dec_ctrl) begin
            oled_ctrl <= wdata[7:0];
            auto_row  <= 1'b0;                        // re-arm auto-advance
            auto_col  <= 1'b0;
        end
        if (wr[0] && dec_row) oled_row <= wdata[5:0];
        if (wr[0] && dec_col) oled_col <= wdata[6:0];
    end
endmodule
