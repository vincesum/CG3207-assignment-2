`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS	
-- Engineer: (c) Rajesh Panicker  
-- 
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: Decoder
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Decoder Module
-- 
-- Dependencies: NIL
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments: Interface and implementation can be modified.
-- 
----------------------------------------------------------------------------------

----------------------------------------------------------------------------------
--	License terms :
--	You are free to use this code as long as you
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept the responsibility to ensure that your implementation does not violate anyone's intellectual property.
--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(v) send an email to rajesh<dot>panicker<at>ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(vi) retain this notice in this file as well as any files derived from this.
----------------------------------------------------------------------------------
*/

module Decoder(
    input [6:0] Opcode ,
    input [2:0] Funct3 ,
    input [6:0] Funct7 ,
    output reg [1:0] PCS,		// 00 for non-control, 01 for conditional branch, 10 for jal, 11 for jalr
    output reg RegWrite,		// Asserted only by instructions which write to register file (load, auipc, lui, DPImm, DPReg);
    output reg MemWrite,		// Asserted only by store (sw)
    output reg MemtoReg,        //Asserted only for load (lw)
    output reg [1:0] ALUSrcA, 	// Needed for lui, auipic. Refer to the microarchitecture for its use. Uncomment wire and port map in RV.v as well
    output reg [1:0] ALUSrcB,		// Asserted by all instructions which use an immediate (load, store, lui, auipc, DPImm). Needs to be expanded to a 2-bit signal to support link functionality for jal, jalr. Change wire width in RV.v as well
    output reg [2:0] ImmSrc, 	// 000 for U, 010 for UJ, 011 for I, 110 for S, 111 for SB.
    output reg [3:0] ALUControl,	// 0000 for add, 0001 for sub, 1110 for and, 1100 for or, 0010 for sll, 1010 for srl, 1011 for sra, 0001 for branch, 0000 for all others.
    					// Note that the most significant 3 bits are Funct3 for all DP instrns. LSB is the same as Funct[5] for DPReg type and DPImm_shifts. For other DPImms, Funct[5] is 0.
    					// It is the same as sub for branches, and add for all others not mentioned in the line above.
    output reg MCycleStart,		// Asserted by mul, mulh, mulhu, div, divu, rem, remu. Also tells the datapath to write back the MCycle result instead of ALUResult
    output reg [1:0] MCycleOp,	// 00 for signed mul, 01 for unsigned mul, 10 for signed div, 11 for unsigned div
    output reg MCycleResultSel	// 0 for Result1 (mul, div, divu), 1 for Result2 (mulh, mulhu, rem, remu)
    );
// Change wire to reg if assigned inside a procedural (always) block. However, where it is easy enough, use assign instead of always.
// A 2-1 multiplexing can be done easily using an assign with a ternary operator
// For multiplexing with number of inputs > 2, a case construct within an always block is a natural fit. DO NOT to use nested ternary assignment operator as it hampers the readability of your code.
    
    	// todo: Implement Decoder here
	
	always @(*) begin
	   // --- DEFAULT VALUES (Prevents Latches) ---
        PCS = 2'b00;
        RegWrite = 0;
        MemWrite = 0;
        MemtoReg = 0;
        ALUSrcA = 2'b00;
        ALUSrcB = 2'b00;
        ImmSrc = 3'b000;
        ALUControl = 4'b0000;
        MCycleStart = 0;
        MCycleOp = 2'b00;
        MCycleResultSel = 0;
        if (Opcode == 7'b0110011) begin
            // DP Reg
            PCS = 2'b00;
            MemtoReg = 0;
            RegWrite = 1;
            MemWrite = 0;
            ALUSrcA[0] = 0;
            ALUSrcB[0] = 0;
            //ImmSrc value not required here
            ALUControl = {Funct3, Funct7[5]};

            if (Funct7[0]) begin
                // M extension (Funct7 = 0000001). ALUControl is unused; the MCycle result is written back instead
                MCycleStart = 1;
                case (Funct3)
                    3'b000: begin MCycleOp = 2'b01; MCycleResultSel = 0; end // mul: low word is the same signed or unsigned, so use the faster unsigned mode
                    3'b001: begin MCycleOp = 2'b00; MCycleResultSel = 1; end // mulh
                    3'b011: begin MCycleOp = 2'b01; MCycleResultSel = 1; end // mulhu
                    3'b100: begin MCycleOp = 2'b10; MCycleResultSel = 0; end // div
                    3'b101: begin MCycleOp = 2'b11; MCycleResultSel = 0; end // divu
                    3'b110: begin MCycleOp = 2'b10; MCycleResultSel = 1; end // rem
                    3'b111: begin MCycleOp = 2'b11; MCycleResultSel = 1; end // remu
                    default: begin // mulhsu not supported: treat as a no-op
                        MCycleStart = 0;
                        RegWrite = 0;
                    end
                endcase
            end

        end else if (Opcode == 7'b0010011) begin
            // DP Immediate
            PCS = 2'b00;
            MemtoReg = 0;
            RegWrite = 1;
            MemWrite = 0;
            ALUSrcA[0] = 0;
            ALUSrcB = 2'b11;
            ImmSrc = 3'b011;
            ALUControl[3:1] = Funct3;
            ALUControl[0] = (Funct3 == 3'h5) ? Funct7[5] : 1'b0;
            
        end else if (Opcode == 7'b0000011) begin
            // LOAD
            PCS = 2'b00;
            MemtoReg = 1;
            RegWrite = 1;
            MemWrite = 0;
            ALUSrcA[0]= 0;
            ALUSrcB = 2'b11;
            ImmSrc = 3'b011;
            ALUControl[3:0] = 4'b0000;
        end else if (Opcode == 7'b0100011) begin
            // STORE
            PCS = 2'b00;
            // MemtoReg
            RegWrite = 0;
            MemWrite = 1;
            ALUSrcA[0] = 0;
            ALUSrcB = 2'b11;
            ImmSrc = 3'b110;
            ALUControl[3:0] = 4'b0000;
        end else if (Opcode == 7'b1100011) begin
            // BRANCH
            PCS = 2'b01;
            //MemtoReg
            RegWrite = 0;
            MemWrite = 0;
            ALUSrcA[0] = 0;
            ALUSrcB[0] = 0;
            ImmSrc = 3'b111;
            ALUControl[3:0] = 4'b0001;
        end else if (Opcode == 7'b1101111) begin
            // JAL
            PCS = 2'b10;
            MemtoReg = 0;
            RegWrite = 1;
            MemWrite = 0;
            ALUSrcA = 2'b11;
            ALUSrcB = 2'b01;
            ImmSrc = 3'b010;
            ALUControl[3:0] = 4'b0000;
        end else if (Opcode == 7'b0010111) begin
            // AUIPC
            PCS = 2'b00;
            MemtoReg = 0;
            RegWrite = 1;
            MemWrite = 0;
            ALUSrcA = 2'b11;
            ALUSrcB = 2'b11;
            ImmSrc = 3'b000;
            ALUControl[3:0] = 4'b0000;
        end else if (Opcode == 7'b0110111) begin
            // LUI
            PCS = 2'b00;
            MemtoReg = 0;
            RegWrite = 1;
            MemWrite = 0;
            ALUSrcA = 2'b01;
            ALUSrcB = 2'b11;
            ImmSrc = 3'b000;
            ALUControl[3:0] = 4'b0000;
        end else if (Opcode == 7'b1100111) begin
            // JALR
            PCS = 2'b11;
            MemtoReg = 0;
            RegWrite = 1;
            MemWrite = 0;
            ALUSrcA = 2'b11;
            ALUSrcB = 2'b01;
            ImmSrc = 3'b011;
            ALUControl[3:0] = 4'b0000;

        end else begin
            // Default / Catch-all for unknown or unsupported opcodes
        end
    end
	    
endmodule



