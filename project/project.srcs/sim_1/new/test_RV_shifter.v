`timescale 1ns / 1ps
// Shift instructions: register and immediate forms, including amounts 0 and 31, and signed values.
// Program: test_RV_shifter.asm. See rv_prog_runner.v for how results are checked. Use "run all" in Vivado.
module tb_RV_shifter;
    rv_prog_runner #(.PROG("test_RV_shifter")) run ();
endmodule
