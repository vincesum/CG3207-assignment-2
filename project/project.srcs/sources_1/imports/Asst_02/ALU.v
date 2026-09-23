`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS	
-- Engineer: (c) Rajesh Panicker  
-- 
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: ALU
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor ALU Module
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

module ALU(
	input [31:0] Src_A,
	input [31:0] Src_B,
	input [3:0] ALUControl, // 0000 for add, 0001 for sub, 1110 for and, 1100 for or, 0010 for sll, 1010 for srl, 1011 for sra.
	output reg [31:0] ALUResult,
	output [2:0] ALUFlags //{eq, lt, ltu}
);
    
	// Shifter signals
	wire [1:0] Sh ; // sll, srl, sra shift type
	wire [4:0] Shamt5 ; // number of bits to shift
	wire [31:0] ShIn ; // shifter input
	wire [31:0] ShOut ; // shifter output
	
	// Other signals
	wire [32:0] S_wider ;
	reg [32:0] Src_A_comp ;
	reg [32:0] Src_B_comp ;
	reg [32:0] C_0 ;
	wire N, Z, C, V; 	// optional intermediate values to derive eq, lt, ltu
				// Hint: We need to care about V only for subtraction
	
	assign S_wider = Src_A_comp + Src_B_comp + C_0 ;
	
	always@(Src_A, Src_B, ALUControl, S_wider, ShOut) begin
        // default values; help avoid latches
		C_0 = 0 ; 
		Src_A_comp = {1'b0, Src_A} ;
		Src_B_comp = {1'b0, Src_B} ;
    
		case(ALUControl)
			4'b0000: ALUResult = S_wider[31:0] ;	//add          
	            	4'b0001: begin				//sub
				C_0[0] = 1 ;  
				Src_B_comp = {1'b0, ~ Src_B} ;
				ALUResult = S_wider[31:0] ;
			end
            4'b1110: ALUResult = Src_A & Src_B ;	// and
            4'b1100: ALUResult = Src_A | Src_B ; 	// or
            4'b0010: ALUResult = ShOut ;            // sll
            4'b1010: ALUResult = ShOut ;            // srl
            4'b1011: ALUResult = ShOut ;            // sra
            // -----------------------------
                    
            default: ALUResult = 32'bx;
            endcase
	    end
      
    //Shifter inputs
    assign ShIn = Src_A;
    assign Shamt5 = Src_B[4:0];
    
    assign N = S_wider[31];                 // sign bit of the 32-bit result
    assign C = S_wider[32];                 // carry-out of the 33-bit adder
    assign V = (Src_A_comp[31] == Src_B_comp[31]) &&
               (Src_A_comp[31] != S_wider[31]); // signed overflow
    
    assign Z = (ALUResult == 0) ? 1 : 0 ;
    
    assign ALUFlags = {Z, N ^ V, ~C} ;   //{eq, lt, ltu}
    						// todo: Will need to be modified in lab 3 to support blt, bltu, bge, bgeu.
    
    
	// todo: make shifter connections here
	// Sh signals can be derived directly from the appropriate ALUControl bits
    assign Sh = {ALUControl[3], ALUControl[0]}; //SLL 00, SRL 10, SRA 11
    
        
	// Instantiate Shifter        
	Shifter Shifter1(
                Sh,
        	Shamt5,
        	ShIn,
        	ShOut
        );
     
endmodule
