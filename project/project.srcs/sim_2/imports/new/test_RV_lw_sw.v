`timescale 1ns / 1ps
// Loads and stores: lw and sw with both offset signs, lui and auipc, and byte and halfword accesses.
// Program: test_RV_lw_sw.asm. See rv_prog_runner.v for how results are checked. Use "run all" in Vivado.
module test_RV_lw_sw_lui_auipc;
    rv_prog_runner #(.PROG("test_RV_lw_sw")) run ();
endmodule
