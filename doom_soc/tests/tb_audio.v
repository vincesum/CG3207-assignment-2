`timescale 1ns/1ps
module tb_audio;
reg clk=0, rst=1, wr=0;
reg [7:0] addr=0;
reg [31:0] wdata=0;
wire [31:0] status;
wire audio_bit;
always #5 clk=~clk;
doom_audio dut(clk,rst,addr,wr,wdata,status,audio_bit);
task write_reg;
input [7:0] a; input [31:0] d;
begin @(negedge clk);addr=a;wdata=d;wr=1;
@(negedge clk);wr=0;end
endtask
initial begin
    repeat(3) @(negedge clk);rst=0;
    if(status!==0) $fatal(1,"reset status");
    write_reg(8'hC0,0);write_reg(8'hC4,0);
    write_reg(8'hC8,255);write_reg(8'hC8,0);
    write_reg(8'hCC,2);write_reg(8'hD0,32'h10000000);
    write_reg(8'hD4,127);write_reg(8'hD8,1);
    if(status!==1) $fatal(1,"start status");
    repeat(3) @(negedge clk);
    if(dut.voices[0].voice.value!==255) $fatal(1,"first PCM byte");
    repeat(16) @(negedge clk);
    if(dut.voices[0].voice.value!==0) $fatal(1,"second PCM byte");
    repeat(20) @(negedge clk);
    if(status!==0) $fatal(1,"automatic stop");
    write_reg(8'hD8,1);write_reg(8'hD8,0);
    if(status!==0) $fatal(1,"explicit stop");
    write_reg(8'hCC,0);write_reg(8'hD8,1);
    if(status!==0) $fatal(1,"zero length");
    write_reg(8'hC0,1);write_reg(8'hCC,8192);
    write_reg(8'hD0,1);write_reg(8'hD8,1);
    if(status!==2) $fatal(1,"channel independence");
    @(negedge clk);rst=1;@(negedge clk);
    if(status!==0) $fatal(1,"reset during playback");
    $display("audio RTL tests passed");$finish;
end
initial begin #100000; $fatal(1,"timeout"); end
endmodule
