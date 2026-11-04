`timescale 1ns / 1ps
// -----------------------------------------------------------------------------
// mig_bridge: one 16-byte request at a time from memctl (CPU clock) to the MIG
// native app_* interface (ui_clk).
//
// memctl holds req_* steady while req_tog != ack_tog. Here, a new request is seen
// when req_tog != seen; it is copied into local registers (so app_* are driven from
// ui_clk flops), and when the MIG has taken a write (command + data), or the read
// data has come back, ack_tog <= seen.
//
// The CPU clock is ui_clk / 2 from an MMCM fed by ui_clk, so both clocks are
// related and every crossing below is a normally timed path (13.33 ns budget).
// Do not use this with an unrelated CPU clock without adding synchronisers.
//
// cpu_rst (CPU reset, may arrive at any time) resets the toggles. A MIG transaction
// already in progress is completed silently (read data dropped, no acknowledge), so
// a stray app_rd_data_valid can never be taken as the answer to a later request.
// -----------------------------------------------------------------------------
module mig_bridge (
    input              ui_clk,
    input              ui_rst,
    input              cpu_rst,
    // from memctl
    input              req_tog,
    input              req_we,
    input      [22:0]  req_line,
    input      [127:0] req_wdata,
    input      [15:0]  req_wmask,     // 1 = write byte
    output reg         ack_tog = 1'b0,
    output reg [127:0] ack_rdata = 128'd0,
    // MIG native interface
    output     [26:0]  app_addr,
    output     [2:0]   app_cmd,
    output reg         app_en = 1'b0,
    input              app_rdy,
    output reg [127:0] app_wdf_data = 128'd0,
    output reg [15:0]  app_wdf_mask = 16'hFFFF,  // 1 = do NOT write byte
    output reg         app_wdf_wren = 1'b0,
    output             app_wdf_end,
    input              app_wdf_rdy,
    input      [127:0] app_rd_data,
    input              app_rd_data_valid
);
    localparam S_IDLE = 2'd0, S_WR = 2'd1, S_RD_CMD = 2'd2, S_RD_WAIT = 2'd3;
    reg [1:0]  st   = S_IDLE;
    reg        seen = 1'b0;
    reg        drop = 1'b0;      // finish the current MIG transaction without acknowledging it
    reg        we   = 1'b0;
    reg [22:0] line = 23'd0;

    // app_addr counts 16-bit words; [26] is the unused rank bit (must stay 0)
    assign app_addr    = {1'b0, line, 3'b000};
    assign app_cmd     = we ? 3'b000 : 3'b001;
    assign app_wdf_end = app_wdf_wren;   // BL8 with a 4:1 PHY: one beat per burst

    wire wr_cmd_done  = ~app_en       | app_rdy;
    wire wr_data_done = ~app_wdf_wren | app_wdf_rdy;
    wire finishing    = (st == S_WR      && wr_cmd_done && wr_data_done) ||
                        (st == S_RD_WAIT && app_rd_data_valid);

    always @(posedge ui_clk) begin
        if (ui_rst) begin
            st           <= S_IDLE;
            seen         <= 1'b0;
            ack_tog      <= 1'b0;
            drop         <= 1'b0;
            app_en       <= 1'b0;
            app_wdf_wren <= 1'b0;
        end
        else begin
            case (st)
                S_IDLE:
                    if (~cpu_rst && req_tog != seen) begin
                        seen         <= req_tog;
                        we           <= req_we;
                        line         <= req_line;
                        app_wdf_data <= req_wdata;
                        app_wdf_mask <= ~req_wmask;
                        app_en       <= 1'b1;
                        if (req_we) begin
                            app_wdf_wren <= 1'b1;
                            st <= S_WR;
                        end
                        else
                            st <= S_RD_CMD;
                    end
                S_WR: begin
                    if (app_en & app_rdy)           app_en       <= 1'b0;
                    if (app_wdf_wren & app_wdf_rdy) app_wdf_wren <= 1'b0;
                    if (finishing) begin
                        st <= S_IDLE;
                        if (drop) drop <= 1'b0; else ack_tog <= seen;
                    end
                end
                S_RD_CMD:
                    if (app_rdy) begin
                        app_en <= 1'b0;
                        st <= S_RD_WAIT;
                    end
                S_RD_WAIT:
                    if (finishing) begin
                        ack_rdata <= app_rd_data;
                        st <= S_IDLE;
                        if (drop) drop <= 1'b0; else ack_tog <= seen;
                    end
            endcase

            if (cpu_rst) begin                 // CPU reset: forget the handshake state
                seen    <= 1'b0;
                ack_tog <= 1'b0;
                if (st != S_IDLE && !finishing) drop <= 1'b1;
            end
        end
    end
endmodule
