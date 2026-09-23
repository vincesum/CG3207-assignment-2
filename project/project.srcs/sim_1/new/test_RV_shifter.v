`timescale 1ns / 1ps

module tb_RV_shifter;

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
        // 1. Initialize Default Inputs
        CLK = 0;
        RESET = 1;
        Instr = 0;
        ReadData_in = 0;

        // Wait for reset to clear
        #10;
        RESET = 0;
        #10;

        // Force is used to load values into reg files without implementing regwrites.
        // Force RD1 (Data to be shifted): 32'hF000000F
        // The MSB is 1 (negative) to verify Arithmetic vs Logical right shifts.
        force uut.RD1 = 32'hF000000F; 
        
        // Force RD2 (Shift amount): Shift by 4 bits
        force uut.RD2 = 32'd4;

        $display("=========================================================");
        $display("Starting Shifter Logic Verification");
        $display("Data Input (RD1)   = %b (%h)", uut.RD1, uut.RD1);
        $display("Shift Amount (RD2) = %d", uut.RD2);
        $display("=========================================================\n");

        // -----------------------------------------------------------
        // TEST 1: SLL (Shift Left Logical)
        // -----------------------------------------------------------
        // Encoding: funct7(0000000) | rs2(00010) | rs1(00001) | funct3(001) | rd(00011) | opcode(0110011)
        Instr = 32'b0000000_00010_00001_001_00011_0110011;
        #10; // Wait for combinational logic to settle
        
        $display("SLL Result: %b (%h)", ALUResult, ALUResult);
        if (ALUResult == 32'h000000F0) 
            $display(" -> SLL PASS: Bottom bits filled with 0s.\n");
        else 
            $display(" -> SLL FAIL\n");

        // -----------------------------------------------------------
        // TEST 2: SRL (Shift Right Logical)
        // -----------------------------------------------------------
        // Encoding: funct7(0000000) | rs2(00010) | rs1(00001) | funct3(101) | rd(00011) | opcode(0110011)
        Instr = 32'b0000000_00010_00001_101_00011_0110011;
        #10;
        
        $display("SRL Result: %b (%h)", ALUResult, ALUResult);
        if (ALUResult == 32'h0F000000) 
            $display(" -> SRL PASS: Top bits filled with 0s.\n");
        else 
            $display(" -> SRL FAIL\n");

        // -----------------------------------------------------------
        // TEST 3: SRA (Shift Right Arithmetic)
        // -----------------------------------------------------------
        // Encoding: funct7(0100000) | rs2(00010) | rs1(00001) | funct3(101) | rd(00011) | opcode(0110011)
        Instr = 32'b0100000_00010_00001_101_00011_0110011;
        #10;
        
        $display("SRA Result: %b (%h)", ALUResult, ALUResult);
        if (ALUResult == 32'hFF000000) 
            $display(" -> SRA PASS: Top bits filled with sign bit (1s).\n");
        else 
            $display(" -> SRA FAIL\n");

        $display("=========================================================");

        // Release the forced hardware nets back to the Register File
        release uut.RD1;
        release uut.RD2;

        $finish;
    end

endmodule