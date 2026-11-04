`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: NUS
// Engineer: Shahzor Ahmad, Rajesh C Panicker
// 
// Create Date: 27.09.2016 16:55:23
// Design Name: 
// Module Name: test_MCycle
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
/* 
----------------------------------------------------------------------------------
--	(c) Shahzor Ahmad, Rajesh C Panicker
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept the responsibility to ensure that your implementation does not violate any intellectual property of ARM Holdings or other entities.
--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(v) send an email to rajesh.panicker@ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(vi) retain this notice in this file or any files derived from this.
----------------------------------------------------------------------------------
*/

module test_MCycle();
    // Checks every pair of 4-bit operands for every operation against values computed here.
    parameter WIDTH = 4;
    reg CLK = 0, RESET = 1, Start = 0;
    reg [2:0] MCycleOp = 0;
    reg [WIDTH-1:0] Operand1 = 0, Operand2 = 0;
    wire [WIDTH-1:0] Result1, Result2;
    wire Busy;

    MCycle #(.width(WIDTH)) dut(CLK, RESET, Start, MCycleOp, Operand1, Operand2, Result1, Result2, Busy);

    always #5 CLK = ~CLK;

    integer op, a, b, sa, sb, prod, q, r, checks = 0, fails = 0, waited;
    reg [2*WIDTH-1:0] exp_prod;
    reg [WIDTH-1:0] exp1, exp2;

    task check(input [8*8-1:0] name);
        begin
            checks = checks + 1;
            if (Result1 !== exp1 || Result2 !== exp2) begin
                fails = fails + 1;
                if (fails <= 10)
                    $display("  FAIL %0s %0d, %0d: got %b %b, expected %b %b", name, a, b, Result2, Result1, exp2, exp1);
            end
        end
    endtask

    task run_one;
        begin
            @(negedge CLK);
            Start = 1'b1;
            @(negedge CLK);
            waited = 0;
            while (Busy && waited < 100) begin
                @(negedge CLK);
                waited = waited + 1;
            end
            if (Busy) begin
                fails = fails + 1;
                $display("  FAIL: Busy stuck high, op %b, %0d, %0d", MCycleOp, a, b);
            end
        end
    endtask

    initial begin
        repeat (2) @(negedge CLK);
        RESET = 0;
        for (op = 0; op < 5; op = op + 1)
            for (a = 0; a < 16; a = a + 1)
                for (b = 0; b < 16; b = b + 1) begin
                    Operand1 = a; Operand2 = b;
                    sa = (a > 7) ? a - 16 : a;
                    sb = (b > 7) ? b - 16 : b;
                    case (op)
                        0: begin MCycleOp = 3'b000; prod = sa * sb; end     // signed x signed
                        1: begin MCycleOp = 3'b001; prod = a * b;   end     // unsigned x unsigned
                        2: begin MCycleOp = 3'b100; prod = sa * b;  end     // signed x unsigned (mulhsu)
                        3: begin                                            // signed division
                            MCycleOp = 3'b010;
                            if (b == 0)                 begin q = -1; r = sa; end
                            else if (sa == -8 && sb == -1) begin q = -8; r = 0; end
                            else                        begin q = sa / sb; r = sa % sb; end
                        end
                        4: begin                                            // unsigned division
                            MCycleOp = 3'b011;
                            if (b == 0) begin q = 15; r = a; end
                            else        begin q = a / b; r = a % b; end
                        end
                    endcase
                    if (op < 3) begin
                        exp_prod = prod;
                        exp1 = exp_prod[WIDTH-1:0];
                        exp2 = exp_prod[2*WIDTH-1:WIDTH];
                    end
                    else begin
                        exp1 = q;
                        exp2 = r;
                    end
                    run_one;
                    check("MCycle");
                    Start = 1'b0;
                end
        $display("test_MCycle: %0d passed, %0d failed", checks - fails, fails);
        if (fails == 0) $display("==== test_MCycle: PASS ====");
        else            $display("==== test_MCycle: FAIL (%0d) ====", fails);
        $finish;
    end
endmodule
