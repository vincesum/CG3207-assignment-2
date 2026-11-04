`timescale 1ns / 1ps
// Pipeline hazards: forwarding, load-use stalls, mem-mem copy, branch flushes and MCycle. The program has no NOP padding, so it only passes if the hazard unit works.
// Program: test_hazards.asm. See rv_prog_runner.v for how results are checked. Use "run all" in Vivado.
module test_hazards;
    rv_prog_runner #(.PROG("test_hazards")) run ();
endmodule
