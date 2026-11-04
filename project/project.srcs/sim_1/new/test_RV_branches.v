`timescale 1ns / 1ps
// Branches and jumps: all six branch types taken and not taken, and jal and jalr with links.
// Program: test_RV_branches.asm. See rv_prog_runner.v for how results are checked. Use "run all" in Vivado.
module test_RV_branches;
    rv_prog_runner #(.PROG("test_RV_branches")) run ();
endmodule
