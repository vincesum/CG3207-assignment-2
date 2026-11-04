`timescale 1ns / 1ps
// Runs a RARS-assembled program on RV and checks the result. Used by the CPU testbenches.
// Files, all made by build_programs.sh from PROG.asm:
//   PROG_irom.mem  instructions          PROG_dmem.mem  initial data
//   PROG_exp.mem   data memory at the end of the program, as computed by the RARS simulator
// The program finishes by storing 0xFF to the LEDs (0xFFFF0060). It runs twice: once normally,
// and once with random MemStall pulses, which must not change any result.
module rv_prog_runner #(
    parameter PROG = "test",
    parameter DIP_VALUE = 32'd0,
    parameter STALL_MAX = 30,
    parameter MAX_CYCLES = 200000
)();
    localparam IWORDS = 4096, DWORDS = 1024, TEXT_BASE = 32'h0040_0000, DATA_BASE = 32'h1001_0000;

    reg         CLK = 0, RESET = 1, MemStall = 0;
    reg  [31:0] IMEM [0:IWORDS-1];
    reg  [31:0] DMEM [0:DWORDS-1];
    reg  [31:0] DINIT [0:DWORDS-1];
    reg  [31:0] DEXP [0:DWORDS-1];
    wire [31:0] PC, ALUResult, WriteData_out;
    wire [3:0]  MemWrite_out;
    wire        MemRead;
    wire [31:0] Instr = IMEM[(PC - TEXT_BASE) >> 2];
    wire        in_dmem = (ALUResult[31:12] == DATA_BASE[31:12]);
    wire [31:0] ReadData_in = in_dmem ? DMEM[ALUResult[11:2]] :
                              (ALUResult == 32'hFFFF_0064) ? DIP_VALUE : 32'd0;

    RV #(.PC_INIT(TEXT_BASE)) dut (
        .CLK(CLK), .RESET(RESET), .Instr(Instr), .ReadData_in(ReadData_in), .MemRead(MemRead),
        .MemWrite_out(MemWrite_out), .PC(PC), .ALUResult(ALUResult), .WriteData_out(WriteData_out),
        .MemStall(MemStall)
    );

    always #5 CLK = ~CLK;

    integer i, b, run, cycles, checks, fails, total_fails = 0, stall_limit = 0, stall_left = 0, seed = 3207;
    reg     done = 0;
    reg [31:0] led = 0;

    // Random stall pulses, changing just after the clock edge like a real memory system
    always @(posedge CLK) begin
        if (RESET || stall_limit == 0) MemStall <= 1'b0;
        else if (stall_left > 0) begin
            stall_left = stall_left - 1;
            MemStall <= (stall_left > 0);
        end
        else if ($unsigned($random(seed)) % 8 == 0) begin
            stall_left = 1 + $unsigned($random(seed)) % stall_limit;
            MemStall <= 1'b1;
        end
    end

    // A store happens in the cycle MemStall is low
    always @(posedge CLK) begin
        if (!RESET && !MemStall && |MemWrite_out) begin
            if (in_dmem) begin
                for (b = 0; b < 4; b = b + 1)
                    if (MemWrite_out[b]) DMEM[ALUResult[11:2]][8*b +: 8] <= WriteData_out[8*b +: 8];
            end
            else if (ALUResult == 32'hFFFF_0060) begin
                led <= WriteData_out;
                done <= 1'b1;
            end
        end
    end

    initial begin
        for (i = 0; i < IWORDS; i = i + 1) IMEM[i] = 32'h0000_0013;
        for (i = 0; i < DWORDS; i = i + 1) begin DINIT[i] = 0; DEXP[i] = 0; end
        $readmemh({PROG, "_irom.mem"}, IMEM);
        $readmemh({PROG, "_dmem.mem"}, DINIT);
        $readmemh({PROG, "_exp.mem"}, DEXP);
        for (run = 0; run < 2; run = run + 1) begin
            for (i = 0; i < DWORDS; i = i + 1) DMEM[i] = DINIT[i];
            stall_limit = run ? STALL_MAX : 0;
            stall_left = 0; done = 0; led = 0; cycles = 0; checks = 0; fails = 0;
            RESET = 1;
            repeat (5) @(posedge CLK);
            RESET <= 0;
            while (!done && cycles < MAX_CYCLES) begin
                @(posedge CLK);
                cycles = cycles + 1;
            end
            repeat (2) @(posedge CLK);
            if (!done) begin
                $display("  FAIL: timed out after %0d cycles at PC=%h", cycles, PC);
                fails = fails + 1;
            end
            else if (led[7:0] !== 8'hFF) begin
                $display("  FAIL: program reported LEDs = %h, expected ff", led[7:0]);
                fails = fails + 1;
            end
            for (i = 0; i < DWORDS; i = i + 1) begin
                checks = checks + 1;
                if (DMEM[i] !== DEXP[i]) begin
                    fails = fails + 1;
                    if (fails <= 8)
                        $display("  FAIL: word %0d at %h: got %h, expected %h", i, DATA_BASE + 4*i, DMEM[i], DEXP[i]);
                end
            end
            $display("%0s, %0s: %0d words checked, %0d failed (%0d cycles)", PROG,
                     run ? "with random MemStall" : "no stalls", checks, fails, cycles);
            total_fails = total_fails + fails;
        end
        if (total_fails == 0) $display("==== %0s: PASS ====", PROG);
        else                  $display("==== %0s: FAIL (%0d) ====", PROG, total_fails);
        $finish;
    end
endmodule
