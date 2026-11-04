`timescale 1ns/1ps
// Eight autonomous unsigned-8-bit PCM voices, 8 KiB each, mono PWM.
// C0 voice, C4 upload cursor, C8 byte (auto increment), CC length,
// D0 phase increment (Hz * 2^32 / clk Hz), D4 volume 0..127,
// D8 command (0 stop, 1 start), DC active voice bitmap (read).
module doom_audio(input clk, input rst, input [7:0] addr, input wr,
    input [31:0] wdata, output [31:0] status, output audio_bit);
    reg [2:0] selected = 0;
    wire [7:0] active;
    wire signed [16:0] samples [0:7];
    reg signed [20:0] mix;
    reg [7:0] pwm = 0;
    reg [7:0] level = 128;
    integer i;
    always @* begin
        mix = 0;
        for (i=0; i<8; i=i+1) mix = mix + samples[i];
    end
    always @(posedge clk) begin
        if (rst) begin selected <= 0; pwm <= 0; level <= 128; end
        else begin
            if (wr && addr == 8'hC0) selected <= wdata[2:0];
            pwm <= pwm + 1'b1;
            // Eight voices, volume /128. Latch only at PWM boundaries.
            if (pwm == 255) level <= 128 + (mix >>> 10);
        end
    end
    assign audio_bit = pwm < level;
    assign status = {24'b0, active};
    genvar v;
    generate for (v=0; v<8; v=v+1) begin: voices
        doom_audio_voice voice (.clk(clk), .rst(rst), .addr(addr),
          .wr(wr && selected == v), .wdata(wdata),
          .active(active[v]), .sample(samples[v]));
    end endgenerate
endmodule

module doom_audio_voice(input clk, input rst, input [7:0] addr,
    input wr, input [31:0] wdata, output reg active = 0,
    output signed [16:0] sample);
    (* ram_style = "block" *) reg [7:0] pcm [0:8191];
    reg [12:0] upload = 0, cursor = 0;
    reg [13:0] length = 0;
    reg [31:0] phase = 0, step = 0;
    reg [6:0] volume = 0;
    reg [7:0] value;
    wire [32:0] next_phase = {1'b0,phase} + {1'b0,step};
    wire signed [8:0] centered = $signed({1'b0,value}) - 9'sd128;
    assign sample = active ? centered * $signed({1'b0,volume}) : 17'sd0;
    // Synchronous read/write permits block RAM inference. No RAM reset.
    always @(posedge clk) begin
        value <= pcm[cursor];
        if (wr && addr == 8'hC8 && !active) pcm[upload] <= wdata[7:0];
    end
    always @(posedge clk) begin
        if (rst) begin
            active <= 0; upload <= 0; cursor <= 0; length <= 0;
            phase <= 0; step <= 0; volume <= 0;
        end else begin
            if (active) begin
                phase <= next_phase[31:0];
                if (next_phase[32]) begin
                    if ({1'b0,cursor} + 14'd1 >= length) active <= 0;
                    else cursor <= cursor + 1'b1;
                end
            end
            if (wr) case (addr)
                8'hC4: upload <= wdata[12:0];
                8'hC8: if (!active) upload <= upload + 1'b1;
                8'hCC: length <= wdata > 8192 ? 14'd8192 : wdata[13:0];
                8'hD0: step <= wdata;
                8'hD4: volume <= wdata > 127 ? 7'd127 : wdata[6:0];
                8'hD8: begin
                    active <= wdata[0] && length != 0 && step != 0;
                    cursor <= 0; phase <= 0;
                end
            endcase
        end
    end
endmodule
