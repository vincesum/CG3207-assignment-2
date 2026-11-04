`timescale 1ns / 1ps
// Self-checking mul/div test for RV, run three times: with MemStall low, then with random
// MemStall pulses of up to 25 and 70 cycles. Each check stores a result to 0x100.
// Covers all M instructions on corner-case and random operands, with forwarded operands,
// a result forwarded to the ALU, a store just before the instruction, and back-to-back use.
// Program and expected values are test_RV_muldiv_stall_prog.mem / _exp.mem; the two .mem
// files must be visible to the simulator. Use "run all" in Vivado.
module test_RV_muldiv_stall;
    parameter N_WORDS  = 19201;
    parameter N_CHECKS = 6400;
    parameter PC_INIT  = 32'h00400000;

    reg         CLK = 0, RESET = 1, MemStall = 0;
    reg  [31:0] rom [0:N_WORDS+15];
    reg  [31:0] expected [0:N_CHECKS-1];
    wire [31:0] PC, ALUResult, WriteData_out;
    wire [31:0] Instr = rom[(PC - PC_INIT) >> 2];
    wire [3:0]  MemWrite_out;
    wire        MemRead;

    RV #(.PC_INIT(PC_INIT)) dut (
        .CLK(CLK),
        .RESET(RESET),
        .Instr(Instr),
        .ReadData_in(32'b0),
        .MemRead(MemRead),
        .MemWrite_out(MemWrite_out),
        .PC(PC),
        .ALUResult(ALUResult),
        .WriteData_out(WriteData_out),
        .MemStall(MemStall)
    );

    always #5 CLK = ~CLK;

    integer i, m, checks, fails, total_fails = 0, stall_max = 0, stall_left = 0, cycles, seed = 3207;

    // Random stall pulses, changing just after the clock edge like the caches' stall
    always @(posedge CLK) begin
        if (RESET || stall_max == 0)
            MemStall <= 1'b0;
        else if (stall_left > 0) begin
            stall_left = stall_left - 1;
            MemStall <= (stall_left > 0);
        end
        else if ($unsigned($random(seed)) % 16 == 0) begin
            stall_left = 1 + $unsigned($random(seed)) % stall_max;
            MemStall <= 1'b1;
        end
    end

    // A store commits in the cycle MemStall is low
    always @(posedge CLK) begin
        if (!RESET && |MemWrite_out && !MemStall && checks < N_CHECKS) begin
            if (WriteData_out !== expected[checks] || ALUResult !== 32'h100) begin
                fails = fails + 1;
                if (fails <= 5)
                    $display("  FAIL check %0d: got %h at %h, expected %h", checks, WriteData_out, ALUResult, expected[checks]);
            end
            checks = checks + 1;
        end
    end

    initial begin
        for (i = 0; i <= N_WORDS + 15; i = i + 1) rom[i] = 32'h00000013;
        $readmemh("test_RV_muldiv_stall_prog.mem", rom);
        $readmemh("test_RV_muldiv_stall_exp.mem", expected);
        for (m = 0; m < 3; m = m + 1) begin
            stall_max = (m == 0) ? 0 : (m == 1) ? 25 : 70;
            stall_left = 0; checks = 0; fails = 0; cycles = 0;
            RESET = 1;
            repeat (5) @(posedge CLK);
            RESET <= 0;
            while (checks < N_CHECKS && cycles < 5000000) begin
                @(posedge CLK);
                cycles = cycles + 1;
            end
            if (checks < N_CHECKS) begin
                $display("  FAIL: timed out after %0d of %0d checks", checks, N_CHECKS);
                fails = fails + 1;
            end
            $display("MemStall up to %0d cycles: %0d passed, %0d failed (%0d cycles)", stall_max, checks - fails, fails, cycles);
            total_fails = total_fails + fails;
        end
        if (total_fails == 0) $display("==== test_RV_muldiv_stall: PASS ====");
        else                  $display("==== test_RV_muldiv_stall: FAIL (%0d) ====", total_fails);
        $finish;
    end
endmodule
