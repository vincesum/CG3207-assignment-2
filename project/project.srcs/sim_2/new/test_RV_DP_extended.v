`timescale 1ns / 1ps

module test_RV_DP_extended;

    reg CLK;
    reg RESET;
    reg [31:0] Instr;
    reg [31:0] ReadData_in;

    wire MemRead;
    wire [3:0] MemWrite_out;
    wire [31:0] PC;
    wire [31:0] ALUResult;
    wire [31:0] WriteData_out;

    integer test_count;
    integer pass_count;
    integer fail_count;

    // ---------------------------------------------------------
    // Instantiate processor
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
    // Clock: 10 ns period
    // ---------------------------------------------------------
    always begin
        #5 CLK = ~CLK;
    end

    // ---------------------------------------------------------
    // Reusable instruction test
    //
    // Every instruction writes into x3.
    // ---------------------------------------------------------
    task run_test;

        input [8*12-1:0] test_name;
        input [31:0] instruction;
        input [31:0] value_x1;
        input [31:0] value_x2;
        input [31:0] expected;

        begin
            // Direct register initialization for testing
            dut.RegFile1.RegBank[1] = value_x1;
            dut.RegFile1.RegBank[2] = value_x2;
            dut.RegFile1.RegBank[3] = 32'h0000_0000;

            Instr = instruction;

            // Allow combinational logic to settle
            #1;

            $display("");
            $display("----------------------------------------");
            $display("Testing %0s", test_name);
            $display("Instruction = 0x%08h", instruction);
            $display("x1          = 0x%08h", value_x1);
            $display("x2          = 0x%08h", value_x2);
            $display("Expected    = 0x%08h", expected);

            // Check combinational ALU result
            test_count = test_count + 1;

            if (ALUResult === expected) begin
                pass_count = pass_count + 1;
                $display(
                    "PASS: %0s ALUResult = 0x%08h",
                    test_name,
                    ALUResult
                );
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL: %0s expected ALUResult=0x%08h, got 0x%08h",
                    test_name,
                    expected,
                    ALUResult
                );
            end

            // Wait for result to be written into x3
            @(posedge CLK);
            #1;

            test_count = test_count + 1;

            if (dut.RegFile1.RegBank[3] === expected) begin
                pass_count = pass_count + 1;
                $display(
                    "PASS: %0s wrote x3 = 0x%08h",
                    test_name,
                    dut.RegFile1.RegBank[3]
                );
            end
            else begin
                fail_count = fail_count + 1;
                $display(
                    "FAIL: %0s expected x3=0x%08h, got 0x%08h",
                    test_name,
                    expected,
                    dut.RegFile1.RegBank[3]
                );
            end
        end
    endtask

    // ---------------------------------------------------------
    // Test sequence
    // ---------------------------------------------------------
    initial begin
        CLK         = 1'b0;
        RESET       = 1'b1;
        Instr       = 32'h0000_0013; // nop: addi x0, x0, 0
        ReadData_in = 32'h0000_0000;

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        $display("");
        $display("========================================");
        $display("Starting extended DP instruction tests");
        $display("========================================");

        // Hold reset across at least one positive clock edge
        #12;
        RESET = 1'b0;

        // -----------------------------------------------------
        // XOR
        //
        // xor x3, x1, x2
        //
        // 0xA5A5F0F0 XOR 0x0F0FFF00 = 0xAAAA0FF0
        // -----------------------------------------------------
        run_test(
            "xor",
            32'h0020_C1B3,
            32'hA5A5_F0F0,
            32'h0F0F_FF00,
            32'hAAAA_0FF0
        );

        // -----------------------------------------------------
        // XORI
        //
        // xori x3, x1, 0x0F0
        //
        // 0x12345678 XOR 0x000000F0 = 0x12345688
        // -----------------------------------------------------
        run_test(
            "xori",
            32'h0F00_C193,
            32'h1234_5678,
            32'h0000_0000, // x2 is unused
            32'h1234_5688
        );

        // -----------------------------------------------------
        // SLT
        //
        // slt x3, x1, x2
        //
        // Signed interpretation:
        // x1 = -1
        // x2 = 1
        // -1 < 1, therefore result = 1
        // -----------------------------------------------------
        run_test(
            "slt",
            32'h0020_A1B3,
            32'hFFFF_FFFF,
            32'h0000_0001,
            32'h0000_0001
        );

        // -----------------------------------------------------
        // SLTU
        //
        // sltu x3, x1, x2
        //
        // Unsigned interpretation:
        // x1 = 4,294,967,295
        // x2 = 1
        // x1 is not less than x2, therefore result = 0
        // -----------------------------------------------------
        run_test(
            "sltu",
            32'h0020_B1B3,
            32'hFFFF_FFFF,
            32'h0000_0001,
            32'h0000_0000
        );

        // -----------------------------------------------------
        // SLTI
        //
        // slti x3, x1, 1
        //
        // Signed interpretation:
        // x1 = -1
        // immediate = 1
        // -1 < 1, therefore result = 1
        // -----------------------------------------------------
        run_test(
            "slti",
            32'h0010_A193,
            32'hFFFF_FFFF,
            32'h0000_0000,
            32'h0000_0001
        );

        // -----------------------------------------------------
        // SLTIU
        //
        // sltiu x3, x1, 1
        //
        // Unsigned interpretation:
        // x1 = 4,294,967,295
        // immediate = 1
        // x1 is not less than 1, therefore result = 0
        // -----------------------------------------------------
        run_test(
            "sltiu",
            32'h0010_B193,
            32'hFFFF_FFFF,
            32'h0000_0000,
            32'h0000_0000
        );

        // -----------------------------------------------------
        // SLLI
        //
        // slli x3, x1, 4
        //
        // 0x00000003 << 4 = 0x00000030
        // -----------------------------------------------------
        run_test(
            "slli",
            32'h0040_9193,
            32'h0000_0003,
            32'h0000_0000,
            32'h0000_0030
        );

        // -----------------------------------------------------
        // SRLI
        //
        // srli x3, x1, 1
        //
        // Logical right shift inserts zero:
        // 0x80000000 >> 1 = 0x40000000
        // -----------------------------------------------------
        run_test(
            "srli",
            32'h0010_D193,
            32'h8000_0000,
            32'h0000_0000,
            32'h4000_0000
        );

        // -----------------------------------------------------
        // SRAI
        //
        // srai x3, x1, 1
        //
        // Arithmetic right shift copies the sign bit:
        // 0x80000000 >>> 1 = 0xC0000000
        // -----------------------------------------------------
        run_test(
            "srai",
            32'h4010_D193,
            32'h8000_0000,
            32'h0000_0000,
            32'hC000_0000
        );

        // -----------------------------------------------------
        // Final summary
        // -----------------------------------------------------
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