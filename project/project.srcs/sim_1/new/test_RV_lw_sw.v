`timescale 1ns / 1ps

module test_RV_lw_sw_lui_auipc;

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

    reg [31:0] auipc_pc;
    reg [31:0] expected_auipc_result;

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
    // Test sequence
    // ---------------------------------------------------------
    initial begin
        CLK          = 1'b0;
        RESET        = 1'b1;
        Instr        = 32'h0000_0013; // nop: addi x0, x0, 0
        ReadData_in  = 32'hDEAD_BEEF;

        test_count = 0;
        pass_count = 0;
        fail_count = 0;

        auipc_pc = 32'b0;
        expected_auipc_result = 32'b0;

        $display("");
        $display("========================================");
        $display("Starting RV instruction tests");
        $display("========================================");

        // Hold reset for at least one positive clock edge
        #12;
        RESET = 1'b0;

        // Directly initialize x1.
        // This avoids needing LUI or ADDI to create an address.
        dut.RegFile1.RegBank[1] = 32'h1001_0000;

        // =====================================================
        // TEST 1: LW
        //
        // lw x2, 0(x1)
        //
        // x1          = 0x10010000
        // ReadData_in = 0xDEADBEEF
        //
        // Expected:
        // ALUResult = 0x10010000
        // x2        = 0xDEADBEEF
        // MemRead   = 1
        // =====================================================

        $display("");
        $display("TEST 1: lw x2, 0(x1)");

        Instr = 32'h0000_A103;

        // Allow combinational datapath to settle
        #1;

        test_count = test_count + 1;

        if (ALUResult === 32'h1001_0000) begin
            pass_count = pass_count + 1;
            $display("PASS: lw address = 0x%08h", ALUResult);
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: lw address expected 0x10010000, got 0x%08h",
                ALUResult
            );
        end

        test_count = test_count + 1;

        if (MemRead === 1'b1) begin
            pass_count = pass_count + 1;
            $display("PASS: lw asserted MemRead");
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: lw expected MemRead=1, got %b",
                MemRead
            );
        end

        // At this clock edge, ReadData_in should be written to x2
        @(posedge CLK);
        #1;

        test_count = test_count + 1;

        if (dut.RegFile1.RegBank[2] === 32'hDEAD_BEEF) begin
            pass_count = pass_count + 1;
            $display(
                "PASS: lw wrote 0x%08h into x2",
                dut.RegFile1.RegBank[2]
            );
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: lw expected x2=0xDEADBEEF, got 0x%08h",
                dut.RegFile1.RegBank[2]
            );
        end

        // =====================================================
        // TEST 2: SW
        //
        // sw x2, 4(x1)
        //
        // Expected:
        // ALUResult     = 0x10010004
        // WriteData_out = 0xDEADBEEF
        // MemWrite_out  = 4'b1111
        // =====================================================

        $display("");
        $display("TEST 2: sw x2, 4(x1)");

        Instr = 32'h0020_A223;

        // Allow combinational datapath to settle
        #1;

        test_count = test_count + 1;

        if (ALUResult === 32'h1001_0004) begin
            pass_count = pass_count + 1;
            $display("PASS: sw address = 0x%08h", ALUResult);
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: sw address expected 0x10010004, got 0x%08h",
                ALUResult
            );
        end

        test_count = test_count + 1;

        if (WriteData_out === 32'hDEAD_BEEF) begin
            pass_count = pass_count + 1;
            $display(
                "PASS: sw write data = 0x%08h",
                WriteData_out
            );
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: sw expected data 0xDEADBEEF, got 0x%08h",
                WriteData_out
            );
        end

        test_count = test_count + 1;

        if (MemWrite_out === 4'b1111) begin
            pass_count = pass_count + 1;
            $display(
                "PASS: sw asserted MemWrite_out=1111"
            );
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: sw expected MemWrite_out=1111, got %b",
                MemWrite_out
            );
        end

        // Complete the SW clock cycle
        @(posedge CLK);
        #1;

        // =====================================================
        // TEST 3: LUI
        //
        // lui x3, 0x12345
        //
        // Expected:
        // x3 = 0x12345000
        // =====================================================

        $display("");
        $display("TEST 3: lui x3, 0x12345");

        Instr = 32'h1234_51B7;

        #1;

        test_count = test_count + 1;

        if (ALUResult === 32'h1234_5000) begin
            pass_count = pass_count + 1;
            $display(
                "PASS: lui ALU result = 0x%08h",
                ALUResult
            );
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: lui expected ALUResult=0x12345000, got 0x%08h",
                ALUResult
            );
        end

        // Write result into x3
        @(posedge CLK);
        #1;

        test_count = test_count + 1;

        if (dut.RegFile1.RegBank[3] === 32'h1234_5000) begin
            pass_count = pass_count + 1;
            $display(
                "PASS: lui wrote 0x%08h into x3",
                dut.RegFile1.RegBank[3]
            );
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: lui expected x3=0x12345000, got 0x%08h",
                dut.RegFile1.RegBank[3]
            );
        end

        // =====================================================
        // TEST 4: AUIPC
        //
        // auipc x4, 0x2
        //
        // Expected:
        // x4 = current instruction PC + 0x00002000
        // =====================================================

        $display("");
        $display("TEST 4: auipc x4, 0x2");

        Instr = 32'h0000_2217;

        // Allow instruction decoding and datapath to settle
        #1;

        // Save the PC belonging to the AUIPC instruction
        auipc_pc = PC;
        expected_auipc_result = auipc_pc + 32'h0000_2000;

        $display(
            "INFO: AUIPC instruction PC = 0x%08h",
            auipc_pc
        );

        test_count = test_count + 1;

        if (ALUResult === expected_auipc_result) begin
            pass_count = pass_count + 1;
            $display(
                "PASS: auipc ALU result = 0x%08h",
                ALUResult
            );
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: auipc expected ALUResult=0x%08h, got 0x%08h",
                expected_auipc_result,
                ALUResult
            );
        end

        // Write AUIPC result into x4
        @(posedge CLK);
        #1;

        test_count = test_count + 1;

        if (dut.RegFile1.RegBank[4] === expected_auipc_result) begin
            pass_count = pass_count + 1;
            $display(
                "PASS: auipc wrote 0x%08h into x4",
                dut.RegFile1.RegBank[4]
            );
        end
        else begin
            fail_count = fail_count + 1;
            $display(
                "FAIL: auipc expected x4=0x%08h, got 0x%08h",
                expected_auipc_result,
                dut.RegFile1.RegBank[4]
            );
        end

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