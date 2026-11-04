`timescale 1ns / 1ps
// Data processing instructions: register and immediate forms, including signed and unsigned comparisons.
// Program: test_RV_dp.asm. See rv_prog_runner.v for how results are checked. Use "run all" in Vivado.
module tb_RV_dp;
    rv_prog_runner #(.PROG("test_RV_dp")) run ();
endmodule
