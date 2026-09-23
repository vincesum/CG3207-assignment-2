`timescale 1ns / 1ps

module test_RV_branches;

    // ---------------------------------------------------------
    // Inputs to RV
    // ---------------------------------------------------------
    reg CLK;
    reg RESET;
    reg [31:0] Instr;
    reg [31:0] ReadData_in;

    // ---------------------------------------------------------
    // Outputs from RV
    // ---------------------------------------------------------
    wire MemRead;
    wire [3:0] MemWrite_out;
    wire [31:0] PC;
    wire [31:0] ALUResult;
    wire [31:0] WriteData_out;

    // ---------------------------------------------------------
    // Testbench variables
    // ---------------------------------------------------------
    integer test_count;
    integer pass_count;
    integer fail_count;

    reg [31:0] old_pc;
    reg [31:0] expected_pc;

    // ---------------------------------------------------------
    // Opcodes / Funct3
    // ---------------------------------------------------------
    localparam BEQ  = 3'b000;
    localparam BNE  = 3'b001;
    localparam BLT  = 3'b100;
    localparam BGE  = 3'b101;
    localparam BLTU = 3'b110;
    localparam BGEU = 3'b111;

    // ---------------------------------------------------------
    // Instruction encoders
    // ---------------------------------------------------------
    // B-type: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] 1100011
    function [31:0] enc_branch;
        input [2:0]  f3;
        input [4:0]  rs1;
        input [4:0]  rs2;
        input [12:0] imm;
        begin
            enc_branch = {imm[12], imm[10:5], rs2, rs1, f3, imm[4:1], imm[11], 7'b1100011};
        end
    endfunction

    // J-type: imm[20|10:1|11|19:12] rd 1101111
    function [31:0] enc_jal;
        input [4:0]  rd;
        input [20:0] imm;
        begin
            enc_jal = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'b1101111};
        end
    endfunction

    // I-type jalr: imm[11:0] rs1 000 rd 1100111
    function [31:0] enc_jalr;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] imm;
        begin
            enc_jalr = {imm, rs1, 3'b000, rd, 7'b1100111};
        end
    endfunction

    // ---------------------------------------------------------
    // Instantiate the processor
    // ---------------------------------------------------------
    RV dut (
        .CLK(CLK),
        .RESET(RESET),
        .Instr(Instr),
        .ReadData_in(ReadData_in),
        .MemRead(MemRead),
        .MemWrite_out(MemWrite_out),
        .PC(PC),
        .ALUResult(ALUResult),
        .WriteData_out(WriteData_out)
    );

    // ---------------------------------------------------------
    // Generate a 10 ns clock period
    // ---------------------------------------------------------
    always begin
        #5 CLK = ~CLK;
    end

    // ---------------------------------------------------------
    // Apply one instruction for one clock cycle, letting PC
    // free-run through PC_Logic / PC_IN / ProgramCounter, then
    // check the new PC against old_PC + offset (taken) or
    // old_PC + 4 (not taken).
    // ---------------------------------------------------------
    task run_and_check_pc;
        input [8*32:1] name;
        input [31:0]   instr;
        input          taken;
        input [31:0]   offset;
        begin
            Instr = instr;

            // Allow combinational datapath to settle
            #1;

            old_pc      = PC;
            expected_pc = taken ? (old_pc + offset) : (old_pc + 32'd4);

            // Branches must never write the register file or memory
            if (instr[6:0] == 7'b1100011) begin
                test_count = test_count + 1;
                if (dut.RegWrite === 1'b0 && MemWrite_out === 4'b0000) begin
                    pass_count = pass_count + 1;
                end
                else begin
                    fail_count = fail_count + 1;
                    $display(
                        "FAIL: %0s asserted RegWrite=%b / MemWrite_out=%b",
                        name, dut.RegWrite, MemWrite_out
                    );
                end
            end

            @(posedge CLK);
            #1;

            test_count = test_count + 1;

            if (PC === expected_pc) begin
                pass_count = pass_count + 1;
                $display(
                    "PASS: %0s -> %0s, PC 0x%08h -> 0x%08h",
                    name, taken ? "taken    " : "not taken", old_pc, PC
                );
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL: %0s expected %0s, PC 0x%08h -> expected 0x%08h, got 0x%08h (ALUFlags=%b, PCSrc=%b)",
                    name, taken ? "taken" : "not taken", old_pc, expected_pc, PC,
                    dut.ALUFlags, dut.PCSrc
                );
            end
        end
    endtask

    // Check a register's value (used for jal/jalr link address)
    task check_reg;
        input [8*32:1] name;
        input [4:0]    r;
        input [31:0]   expected;
        begin
            test_count = test_count + 1;

            if (dut.RegFile1.RegBank[r] === expected) begin
                pass_count = pass_count + 1;
                $display(
                    "PASS: %0s wrote 0x%08h into x%0d",
                    name, dut.RegFile1.RegBank[r], r
                );
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL: %0s expected x%0d=0x%08h, got 0x%08h",
                    name, r, expected, dut.RegFile1.RegBank[r]
                );
            end
        end
    endtask

    // ---------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------
    initial begin
        CLK          = 1'b0;
        RESET        = 1'b1;
        Instr        = 32'h0000_0013; // nop: addi x0, x0, 0
        ReadData_in  = 32'h0000_0000;

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        old_pc      = 32'b0;
        expected_pc = 32'b0;

        $display("");
        $display("========================================");
        $display("Starting RV branch / PC_Logic tests");
        $display("========================================");

        // Hold reset for at least one positive clock edge
        #12;
        RESET = 1'b0;

        // Directly initialize comparison operands
        dut.RegFile1.RegBank[1]  = 32'h0000_0005;   // 5
        dut.RegFile1.RegBank[2]  = 32'h0000_0005;   // 5
        dut.RegFile1.RegBank[3]  = 32'h0000_0007;   // 7
        dut.RegFile1.RegBank[4]  = 32'h7FFF_FFFF;   // max positive
        dut.RegFile1.RegBank[5]  = 32'h8000_0000;   // min negative
        dut.RegFile1.RegBank[6]  = 32'hFFFF_FFFF;   // -1 / max unsigned
        dut.RegFile1.RegBank[7]  = 32'h0000_0001;   // 1
        dut.RegFile1.RegBank[12] = 32'h0040_0100;   // jalr base

        // =====================================================
        // beq / bne
        // =====================================================
        $display("");
        $display("TEST: beq / bne");
        run_and_check_pc("beq  x1,x2 (5==5)",        enc_branch(BEQ,  1, 2, 13'd16),  1'b1, 32'd16);
        run_and_check_pc("beq  x1,x3 (5!=7)",        enc_branch(BEQ,  1, 3, 13'd16),  1'b0, 32'd16);
        run_and_check_pc("bne  x1,x3 (5!=7) bwd",    enc_branch(BNE,  1, 3, -13'sd8), 1'b1, -32'sd8);
        run_and_check_pc("bne  x1,x2 (5==5)",        enc_branch(BNE,  1, 2, 13'd32),  1'b0, 32'd32);

        // =====================================================
        // blt / bge (signed)
        // =====================================================
        $display("");
        $display("TEST: blt / bge");
        run_and_check_pc("blt  x1,x3 (5<7)",         enc_branch(BLT,  1, 3, 13'd12),  1'b1, 32'd12);
        run_and_check_pc("blt  x3,x1 (7<5)",         enc_branch(BLT,  3, 1, 13'd12),  1'b0, 32'd12);
        run_and_check_pc("blt  x1,x2 (5<5)",         enc_branch(BLT,  1, 2, 13'd12),  1'b0, 32'd12);
        run_and_check_pc("bge  x3,x1 (7>=5)",        enc_branch(BGE,  3, 1, 13'd20),  1'b1, 32'd20);
        run_and_check_pc("bge  x1,x2 (5>=5)",        enc_branch(BGE,  1, 2, 13'd20),  1'b1, 32'd20);
        run_and_check_pc("bge  x1,x3 (5>=7)",        enc_branch(BGE,  1, 3, 13'd20),  1'b0, 32'd20);
        run_and_check_pc("blt  x6,x7 (-1<1)",        enc_branch(BLT,  6, 7, 13'd24),  1'b1, 32'd24);
        run_and_check_pc("blt  x7,x6 (1<-1)",        enc_branch(BLT,  7, 6, 13'd24),  1'b0, 32'd24);

        // =====================================================
        // bltu / bgeu (unsigned)
        // =====================================================
        $display("");
        $display("TEST: bltu / bgeu");
        run_and_check_pc("bltu x1,x3 (5<7)",         enc_branch(BLTU, 1, 3, 13'd28),  1'b1, 32'd28);
        run_and_check_pc("bltu x3,x1 (7<5)",         enc_branch(BLTU, 3, 1, 13'd28),  1'b0, 32'd28);
        run_and_check_pc("bltu x7,x6 (1<0xFFFFFFFF)",enc_branch(BLTU, 7, 6, 13'd28),  1'b1, 32'd28);
        run_and_check_pc("bgeu x6,x7 (0xFFFFFFFF>=1)",enc_branch(BGEU, 6, 7, -13'sd16),1'b1, -32'sd16);
        run_and_check_pc("bgeu x1,x2 (5>=5)",        enc_branch(BGEU, 1, 2, 13'd36),  1'b1, 32'd36);
        run_and_check_pc("bgeu x1,x3 (5>=7)",        enc_branch(BGEU, 1, 3, 13'd36),  1'b0, 32'd36);

        // =====================================================
        // Signed / unsigned disagreement (validates N^V)
        //   x4 = 0x7FFFFFFF, x5 = 0x80000000
        //   x4 - x5 overflows: N=1, V=1 -> lt = N^V = 0
        // =====================================================
        $display("");
        $display("TEST: signed/unsigned edge cases (0x7FFFFFFF vs 0x80000000)");
        run_and_check_pc("blt  x4,x5 (signed)",      enc_branch(BLT,  4, 5, 13'd40),  1'b0, 32'd40);
        run_and_check_pc("bltu x4,x5 (unsigned)",    enc_branch(BLTU, 4, 5, 13'd40),  1'b1, 32'd40);
        run_and_check_pc("bge  x4,x5 (signed)",      enc_branch(BGE,  4, 5, 13'd44),  1'b1, 32'd44);
        run_and_check_pc("bgeu x4,x5 (unsigned)",    enc_branch(BGEU, 4, 5, 13'd44),  1'b0, 32'd44);
        run_and_check_pc("blt  x5,x4 (signed)",      enc_branch(BLT,  5, 4, 13'd48),  1'b1, 32'd48);
        run_and_check_pc("bltu x5,x4 (unsigned)",    enc_branch(BLTU, 5, 4, 13'd48),  1'b0, 32'd48);

        // =====================================================
        // jal (always taken, PCS=10)
        // =====================================================
        $display("");
        $display("TEST: jal");
        run_and_check_pc("jal  x10, +0x100",         enc_jal(10, 21'h100),            1'b1, 32'h100);
        check_reg("jal  x10, +0x100", 10, old_pc + 32'd4);
        run_and_check_pc("jal  x0, -0x40",           enc_jal(0, -21'sh40),            1'b1, -32'sh40);

        // =====================================================
        // jalr (PCS=11): PC = x12 + 4
        // =====================================================
        $display("");
        $display("TEST: jalr");
        Instr = enc_jalr(11, 12, 12'd4);
        #1;
        old_pc = PC;
        @(posedge CLK);
        #1;
        test_count = test_count + 1;
        if (PC === 32'h0040_0104) begin
            pass_count = pass_count + 1;
            $display("PASS: jalr x11, 4(x12), PC 0x%08h -> 0x%08h", old_pc, PC);
        end
        else begin
            fail_count = fail_count + 1;
            $display("FAIL: jalr x11, 4(x12) expected PC=0x00400104, got 0x%08h", PC);
        end
        check_reg("jalr x11, 4(x12)", 11, old_pc + 32'd4);

        // =====================================================
        // Final summary
        // =====================================================

        $display("");
        $display("========================================");
        $display("FINAL TEST SUMMARY");
        $display("Total checks : %0d", test_count);
        $display("Passed       : %0d", pass_count);
        $display("Failed       : %0d", fail_count);

        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** SOME TESTS FAILED ***");

        $display("========================================");
        $display("");

        $finish;
    end

endmodule
