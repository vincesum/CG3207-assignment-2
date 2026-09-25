`timescale 1ns / 1ps

module tb_RV_dp;

    // Inputs to the RV module
    reg CLK;
    reg RESET;
    reg [31:0] Instr;
    reg [31:0] ReadData_in;

    // Outputs from the RV module
    wire MemRead;
    wire [3:0] MemWrite_out;
    wire [31:0] PC;
    wire [31:0] ALUResult;
    wire [31:0] WriteData_out;

    // Instantiate the top-level processor
    RV uut (
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

    // Clock generation
    always #5 CLK = ~CLK;

    initial begin
        // Initialize Default Inputs
        CLK = 0;
        RESET = 1;
        Instr = 0;
        ReadData_in = 0;

        // Wait for reset to clear
        #10;
        RESET = 0;
        #10;

        // -----------------------------------------------------------
        // ISOLATING THE DATAPATH
        // -----------------------------------------------------------
        // We will force RD1 and RD2 to specific decimal values to make
        // the arithmetic easy to verify in the console. 
        // RD1 = 10 (base data)
        // RD2 = 5  (second operand for R-type instructions)
        // For I-type instructions, the immediate field in the machine 
        // code is set to 7. 
        
        force uut.RD1 = 32'd10; 
        force uut.RD2 = 32'd5;

        $display("=========================================================");
        $display("Starting Basic ALU Logic Verification");
        $display("RD1 (Base)      = %d", uut.RD1);
        $display("RD2 (R-Type Op) = %d", uut.RD2);
        $display("Immediate Op    = 7");
        $display("=========================================================\n");

        // -----------------------------------------------------------
        // TEST 1: ADD (R-Type) -> 10 + 5 = 15
        // -----------------------------------------------------------
        // funct7(0) | rs2(2) | rs1(1) | funct3(0) | rd(3) | opcode(0110011)
        Instr = 32'b0000000_00010_00001_000_00011_0110011;
        #10;
        $display("ADD Result: %d", ALUResult);
        if (ALUResult == 32'd15) $display(" -> ADD PASS\n"); else $display(" -> ADD FAIL\n");

        // -----------------------------------------------------------
        // TEST 2: SUB (R-Type) -> 10 - 5 = 5
        // -----------------------------------------------------------
        // funct7(32) | rs2(2) | rs1(1) | funct3(0) | rd(3) | opcode(0110011)
        Instr = 32'b0100000_00010_00001_000_00011_0110011;
        #10;
        $display("SUB Result: %d", ALUResult);
        if (ALUResult == 32'd5) $display(" -> SUB PASS\n"); else $display(" -> SUB FAIL\n");

        // -----------------------------------------------------------
        // TEST 3: AND (R-Type) -> 10 (1010) & 5 (0101) = 0
        // -----------------------------------------------------------
        // funct7(0) | rs2(2) | rs1(1) | funct3(7) | rd(3) | opcode(0110011)
        Instr = 32'b0000000_00010_00001_111_00011_0110011;
        #10;
        $display("AND Result: %d", ALUResult);
        if (ALUResult == 32'd0) $display(" -> AND PASS\n"); else $display(" -> AND FAIL\n");

        // -----------------------------------------------------------
        // TEST 4: OR (R-Type) -> 10 (1010) | 5 (0101) = 15
        // -----------------------------------------------------------
        // funct7(0) | rs2(2) | rs1(1) | funct3(6) | rd(3) | opcode(0110011)
        Instr = 32'b0000000_00010_00001_110_00011_0110011;
        #10;
        $display("OR  Result: %d", ALUResult);
        if (ALUResult == 32'd15) $display(" -> OR  PASS\n"); else $display(" -> OR  FAIL\n");

        // -----------------------------------------------------------
        // TEST 5: ADDI (I-Type) -> 10 + 7 = 17
        // -----------------------------------------------------------
        // imm(7) | rs1(1) | funct3(0) | rd(3) | opcode(0010011)
        Instr = 32'b000000000111_00001_000_00011_0010011;
        #10;
        $display("ADDI Result: %d", ALUResult);
        if (ALUResult == 32'd17) $display(" -> ADDI PASS\n"); else $display(" -> ADDI FAIL\n");

        // -----------------------------------------------------------
        // TEST 6: ANDI (I-Type) -> 10 (1010) & 7 (0111) = 2
        // -----------------------------------------------------------
        // imm(7) | rs1(1) | funct3(7) | rd(3) | opcode(0010011)
        Instr = 32'b000000000111_00001_111_00011_0010011;
        #10;
        $display("ANDI Result: %d", ALUResult);
        if (ALUResult == 32'd2) $display(" -> ANDI PASS\n"); else $display(" -> ANDI FAIL\n");

        // -----------------------------------------------------------
        // TEST 7: ORI (I-Type) -> 10 (1010) | 7 (0111) = 15
        // -----------------------------------------------------------
        // imm(7) | rs1(1) | funct3(6) | rd(3) | opcode(0010011)
        Instr = 32'b000000000111_00001_110_00011_0010011;
        #10;
        $display("ORI Result: %d", ALUResult);
        if (ALUResult == 32'd15) $display(" -> ORI PASS\n"); else $display(" -> ORI FAIL\n");

        $display("=========================================================");

        // Release the forced hardware nets
        release uut.RD1;
        release uut.RD2;

        $finish;
    end

endmodule