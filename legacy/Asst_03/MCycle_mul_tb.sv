`timescale 1ns / 1ps

// Simulation-only testbench for the user's MCycle module.
// Compile as SystemVerilog. Select MCycle_mul_tb as the simulation top.
// Keep the original NUS license notice in MCycle.v.
module MCycle_mul_tb;
    localparam integer WIDTH = 32;
    localparam integer TIMEOUT_CYCLES = 100;
    localparam integer RANDOM_TESTS_PER_MODE = 1000;

    reg CLK = 0;
    reg RESET = 1;
    reg Start = 0;
    reg [1:0] MCycleOp = 0;
    reg [31:0] Operand1 = 0;
    reg [31:0] Operand2 = 0;
    wire [31:0] Result1, Result2;
    wire Busy;

    integer tests = 0;
    integer failures = 0;
    integer seed = 32'h3207_2026;
    integer mode, i, j;
    reg [31:0] values [0:11];
    reg [31:0] random_a, random_b;

    MCycle #(.width(WIDTH)) dut (
        .CLK(CLK), .RESET(RESET), .Start(Start),
        .MCycleOp(MCycleOp), .Operand1(Operand1), .Operand2(Operand2),
        .Result1(Result1), .Result2(Result2), .Busy(Busy)
    );

    always #5 CLK = ~CLK; // 10 ns clock period

    task automatic check_multiply;
        input unsigned_mode;
        input [31:0] a;
        input [31:0] b;
        reg signed [63:0] signed_a, signed_b;
        reg [63:0] unsigned_a, unsigned_b;
        reg [63:0] expected, actual;
        integer cycles, hold_cycle;
        begin
            // Explicit 64-bit extension avoids reference-expression width errors.
            if (unsigned_mode) begin
                unsigned_a = {32'b0, a};
                unsigned_b = {32'b0, b};
                expected = unsigned_a * unsigned_b;
            end else begin
                signed_a = {{32{a[31]}}, a};
                signed_b = {{32{b[31]}}, b};
                expected = signed_a * signed_b;
            end

            // Drive on the falling edge to avoid races with the DUT.
            @(negedge CLK);
            Operand1 = a;
            Operand2 = b;
            MCycleOp = unsigned_mode ? 2'b01 : 2'b00;
            Start = 1;
            #1;
            if (Busy !== 1'b1)
                $fatal(1, "Busy did not assert after Start");

            // The posted DUT initializes and processes its first group here.
            @(posedge CLK);
            #1;
            cycles = 1;
            @(negedge CLK);
            Start = 0;
            #1;

            while ((Busy !== 1'b0) && (cycles < TIMEOUT_CYCLES)) begin
                @(posedge CLK);
                #1; // Allow nonblocking assignments and FSM logic to settle.
                cycles = cycles + 1;
            end

            if (Busy !== 1'b0)
                $fatal(1, "TIMEOUT: mode=%b a=%h b=%h", MCycleOp, a, b);

            tests = tests + 1;
            actual = {Result2, Result1};
            if (actual !== expected) begin
                failures = failures + 1;
                $display("FAIL mode=%b a=%h b=%h expected=%h actual=%h cycles=%0d",
                         MCycleOp, a, b, expected, actual, cycles);
            end else if (tests <= 10) begin
                $display("PASS mode=%b a=%h b=%h product=%h cycles=%0d",
                         MCycleOp, a, b, actual, cycles);
            end

            // Hold inputs/mode stable and verify the completed product remains
            // unchanged while the FSM returns to IDLE and waits there.
            for (hold_cycle = 0; hold_cycle < 3; hold_cycle = hold_cycle + 1) begin
                @(posedge CLK);
                #1;
                if ({Result2, Result1} !== actual) begin
                    failures = failures + 1;
                    $display("FAIL result changed after completion: mode=%b a=%h b=%h",
                             MCycleOp, a, b);
                end
                if (Busy !== 1'b0)
                    $fatal(1, "Busy reasserted without a new Start");
            end
        end
    endtask

    initial begin
        // Zero, small numbers, signed boundaries, unsigned maximum,
        // and bit patterns exercising the Booth recoding groups.
        values[0]  = 32'h00000000;
        values[1]  = 32'h00000001;
        values[2]  = 32'h00000002;
        values[3]  = 32'h00000005;
        values[4]  = 32'h00000007;
        values[5]  = 32'h7fffffff;
        values[6]  = 32'h80000000;
        values[7]  = 32'hffffffff;
        values[8]  = 32'hfffffffe;
        values[9]  = 32'haaaaaaaa;
        values[10] = 32'h55555555;
        values[11] = 32'h12345678;

        // Active-high reset, as in the provided MCycle module.
        repeat (3) @(posedge CLK);
        @(negedge CLK);
        RESET = 0;
        repeat (2) @(posedge CLK);

        // Cross-test every directed operand pair in both modes: 288 tests.
        for (mode = 0; mode < 2; mode = mode + 1)
            for (i = 0; i < 12; i = i + 1)
                for (j = 0; j < 12; j = j + 1)
                    check_multiply(mode == 1, values[i], values[j]);

        // Reproducible random sequence within the same simulator.
        for (mode = 0; mode < 2; mode = mode + 1) begin
            for (i = 0; i < RANDOM_TESTS_PER_MODE; i = i + 1) begin
                random_a = $random(seed);
                random_b = $random(seed);
                check_multiply(mode == 1, random_a, random_b);
            end
        end

        $display("Completed %0d multiplication tests; failures=%0d", tests, failures);
        if (failures != 0)
            $fatal(1, "MULTIPLICATION TESTS FAILED");
        $display("ALL MULTIPLICATION TESTS PASSED");
        $finish;
    end

    // Global watchdog for stalled simulation/control.
    initial begin
        #10000000;
        $fatal(1, "Global simulation timeout");
    end
endmodule
