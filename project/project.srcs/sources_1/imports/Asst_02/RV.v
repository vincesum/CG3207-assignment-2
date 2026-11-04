`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Company: NUS	
-- Engineer: (c) Rajesh Panicker  
-- 
-- Create Date: 09/22/2020 06:49:10 PM
-- Module Name: RV
-- Project Name: CG3207 Project
-- Target Devices: Nexys 4 / Basys 3
-- Tool Versions: Vivado 2019.2
-- Description: RISC-V Processor Module
-- 
-- Dependencies: NIL
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments: The interface SHOULD NOT be modified (except making output reg) unless you modify Wrapper.v/vhd too. 
                        The implementation can be modified.
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

// Change wire to reg if assigned inside a procedural (always) block. However, where it is easy enough, use assign instead of always.
// A 2-1 multiplexing can be done easily using an assign with a ternary operator
// For multiplexing with number of inputs > 2, a case construct within an always block is a natural fit. DO NOT to use nested ternary assignment operator as it hampers the readability of your code.


module RV #(
    parameter PC_INIT = 32'h00400000
)(
    input CLK,
    input RESET,
    //input Interrupt,      // for optional future use.
    input [31:0] Instr,
    input [31:0] ReadData_in,       // Name mangled to support lb/lbu/lh/lhu
    output MemRead,
    output [3:0] MemWrite_out,		// Column-wise write enable to support sb/sw. Each column is a byte.
    output [31:0] PC,
    output [31:0] ALUResult,
    output [31:0] WriteData_out,	// Name mangled to support sb/sw
    input MemStall                  // doom_soc: freeze the whole pipeline (cache miss / memory busy)
);
    
    // Please read Lab 4 Enhancement: Implementing additional instructions on how to support lb/lbu/lh/lhu/sb/sh

    // ============================================================
    // Signal declarations, grouped by pipeline stage
    // ============================================================

    // ---------------- Fetch ----------------
    // Next-PC logic (selected by Execute-stage PCSrcE)
    reg  [31:0] PC_Base ;
    wire [31:0] PC_Offset ;
    // ProgramCounter
    wire        WE_PC ;
    wire [31:0] PC_IN ;
    // Fetch outputs
    wire [31:0] PCF ;
    wire [31:0] InstrF ;

    // ---------------- Decode ----------------
    // Pipeline register F -> D
    reg  [31:0] PCD ;
    reg  [31:0] InstrD ;
    // Instruction fields
    wire [6:0]  Opcode ;
    wire [2:0]  Funct3D ;
    wire [6:0]  Funct7 ;
    wire [4:0]  rs1D ;
    wire [4:0]  rs2D ;
    wire [4:0]  rdD ;
    wire [24:0] InstrImm ;
    // Decoder control outputs
    wire        RegWriteD ;
    wire        MemtoRegD ;
    wire        MemWriteD ;
    wire [1:0]  PCSD ;
    wire [3:0]  ALUControlD ;
    wire [1:0]  ALUSrcAD ;
    wire [1:0]  ALUSrcBD ;
    wire [2:0]  ImmSrc ;            // used only by Extend in this stage
    wire        MCycleStartD ;
    wire [2:0]  MCycleOpD ;
    wire        MCycleResultSelD ;
    // RegFile read ports
    wire [31:0] RD1D ;
    wire [31:0] RD2D ;
    // Extend
    wire [31:0] ExtImmD ;

    // ---------------- Execute ----------------
    // Pipeline register D -> E: control
    reg         RegWriteE ;
    reg         MemtoRegE ;
    reg         MemWriteE ;
    reg  [1:0]  PCSE ;
    reg  [2:0]  Funct3E ;           // branch condition for PC_Logic; access size for loads/stores
    reg  [3:0]  ALUControlE ;
    reg  [1:0]  ALUSrcAE ;
    reg  [1:0]  ALUSrcBE ;
    reg         MCycleStartE ;
    reg  [2:0]  MCycleOpE ;
    reg         MCycleResultSelE ;
    // Pipeline register D -> E: data
    reg  [31:0] PCE ;
    reg  [31:0] RD1E ;
    reg  [31:0] RD2E ;
    reg  [31:0] ExtImmE ;
    reg  [4:0]  rs1E ;
    reg  [4:0]  rs2E ;
    reg  [4:0]  rdE ;
    // ALU
    reg  [31:0] Src_A ;
    reg  [31:0] Src_B ;
    wire [31:0] ALUResultE ;
    wire [2:0]  ALUFlags ;
    // PC_Logic
    wire [2:0]  PCSrcE ;
    // MCycle
    wire [31:0] MCycleResult1 ;
    wire [31:0] MCycleResult2 ;
    wire [31:0] MCycleResult ;
    wire        MCycleBusy ;
    // Execute result (ALU or MCycle)
    wire [31:0] ResultE ;
    // Store data to Memory
    wire [31:0] WriteDataE ;

    // ---------------- Memory ----------------
    // Pipeline register E -> M: control
    reg         RegWriteM ;
    reg         MemtoRegM ;
    reg         MemWriteM ;
    // Pipeline register E -> M: data
    reg  [31:0] ResultM ;
    reg  [31:0] WriteDataM ;
    reg  [4:0]  rs2M ;
    reg  [4:0]  rdM ;
    reg  [2:0]  Funct3M ;           // load/store size: 000 b, 001 h, 010 w, 100 bu, 101 hu
    // Data memory interface
    reg  [31:0] ReadDataM ;         // load data after byte/halfword selection and extension
    wire [2:0]  SizeSel ;           // to support lb/lbu/lh/lhu/sb/sh

    // ---------------- Writeback ----------------
    // Pipeline register M -> W: control
    reg         RegWriteW ;
    reg         MemtoRegW ;
    // Pipeline register M -> W: data
    reg  [31:0] ReadDataW ;
    reg  [31:0] ResultW ;
    reg  [4:0]  rdW ;
    // RegFile write port
    wire        WE ;
    wire [31:0] WD ;

    // ---------------- Hazard control ----------------
    wire        StallF ;
    wire        StallD ;
    wire        StallE ;
    wire        FlushD ;
    wire        FlushE ;
    wire        FlushM ;
    // Forwarding
    reg  [1:0]  ForwardAE ;
    reg  [1:0]  ForwardBE ;
    reg  [31:0] FwdRD1E ;           // rs1 value used in Execute
    reg  [31:0] FwdRD2E ;           // rs2 value used in Execute
    wire [31:0] FwdRD1D ;           // rs1 value latched into Execute
    wire [31:0] FwdRD2D ;           // rs2 value latched into Execute
    wire        ForwardM ;
    wire [31:0] FwdWriteDataM ;     // store data in Memory, before byte alignment
    // Stall / flush causes
    wire        lwStall ;
    wire        BranchTakenE ;

    // ============================================================
    // Fetch Stage
    // ============================================================

    // Next PC uses a single adder: PC_Base + PC_Offset
    // Note that this differs from the schematic, which did not include support for jalr
    // PCSrc: 000: PCF + 4, 101: PCE + ExtImm (branch, jal), 111: RD1 + ExtImm (jalr)
    always @(*) begin
        case (PCSrcE[1:0])
            2'b00:   PC_Base = PCF;     // PC + 4
            2'b01:   PC_Base = PCE;     // branch, jal
            2'b11:   PC_Base = FwdRD1E; // jalr
            default: PC_Base = PCF;     // 2'b10 unused
        endcase
    end
    assign PC_Offset = PCSrcE[2] ? ExtImmE : 32'd4;
    assign PC_IN = PC_Base + PC_Offset;

    assign WE_PC = ~StallF & ~MemStall ;

    // Fetch outputs (PC register is updated on posedge CLK inside ProgramCounter)
    assign PCF = PC;
    assign InstrF = Instr;

    // Instantiate ProgramCounter
    ProgramCounter #(.PC_INIT(PC_INIT)) ProgramCounter1(
                    CLK,
                    RESET,
                    WE_PC,
                    PC_IN,
                    PC
                );

    // ============================================================
    // Decode Stage
    // ============================================================

    // Pipeline register F -> D (FlushD inserts a NOP)
    always @(posedge CLK) begin
        if (RESET | (FlushD & ~MemStall)) begin
            InstrD <= 32'h00000013;     // NOP
            PCD    <= 32'b0;
        end
        else if (~StallD & ~MemStall) begin
            InstrD <= InstrF;
            PCD    <= PCF;
        end
    end

    // Split the 32-bit instruction into its fields
    assign Opcode   = InstrD[6:0];
    assign rdD      = InstrD[11:7];
    assign Funct3D  = InstrD[14:12];
    assign rs1D     = InstrD[19:15];
    assign rs2D     = InstrD[24:20];
    assign Funct7   = InstrD[31:25];
    assign InstrImm = InstrD[31:7];

    // Instantiate Decoder
    Decoder Decoder1(
                    Opcode,
                    Funct3D,
                    Funct7,
                    PCSD,
                    RegWriteD,
                    MemWriteD,
                    MemtoRegD,
                    ALUSrcAD,
                    ALUSrcBD,
                    ImmSrc,
                    ALUControlD,
                    MCycleStartD,
                    MCycleOpD,
                    MCycleResultSelD
                );

    // Instantiate RegFile (read in Decode; write port WE/rdW/WD is driven from Writeback)
    RegFile RegFile1(
                    CLK,
                    WE,
                    rs1D,
                    rs2D,
                    rdW,
                    WD,
                    RD1D,
                    RD2D
                );

    // Instantiate Extend Module
    Extend Extend1(
                    ImmSrc,
                    InstrImm,
                    ExtImmD
                );

    // ============================================================
    // Execute Stage
    // ============================================================

    // Pipeline register D -> E (FlushE inserts a bubble)
    always @(posedge CLK) begin
        if (RESET | (FlushE & ~MemStall)) begin
            RegWriteE   <= 1'b0;
            MemtoRegE   <= 1'b0;
            MemWriteE   <= 1'b0;
            PCSE        <= 2'b0;
            Funct3E     <= 3'b0;
            ALUControlE <= 4'b0;
            ALUSrcAE    <= 2'b0;
            ALUSrcBE    <= 2'b0;
            MCycleStartE     <= 1'b0;
            MCycleOpE        <= 3'b0;
            MCycleResultSelE <= 1'b0;
            PCE         <= 32'b0;
            RD1E        <= 32'b0;
            RD2E        <= 32'b0;
            ExtImmE     <= 32'b0;
            rs1E        <= 5'b0;
            rs2E        <= 5'b0;
            rdE         <= 5'b0;
        end
        else if (~StallE & ~MemStall) begin
            RegWriteE   <= RegWriteD;
            MemtoRegE   <= MemtoRegD;
            MemWriteE   <= MemWriteD;
            PCSE        <= PCSD;
            Funct3E     <= Funct3D;
            ALUControlE <= ALUControlD;
            ALUSrcAE    <= ALUSrcAD;
            ALUSrcBE    <= ALUSrcBD;
            MCycleStartE     <= MCycleStartD;
            MCycleOpE        <= MCycleOpD;
            MCycleResultSelE <= MCycleResultSelD;
            PCE         <= PCD;
            RD1E        <= FwdRD1D;
            RD2E        <= FwdRD2D;
            ExtImmE     <= ExtImmD;
            rs1E        <= rs1D;
            rs2E        <= rs2D;
            rdE         <= rdD;
        end
    end

    // Multiplexers for ALU inputs
    always @(*) begin
        case (ALUSrcAE)
            2'b00:   Src_A = FwdRD1E;   // RD1
            2'b01:   Src_A = 32'd0;     // 0 (lui)
            2'b11:   Src_A = PCE;       // PC (auipc, jal, jalr)
            default: Src_A = FwdRD1E;   // 2'b10 unused
        endcase
    end

    always @(*) begin
        case (ALUSrcBE)
            2'b00:   Src_B = FwdRD2E;   // RD2
            2'b01:   Src_B = 32'd4;     // 4 (link address for jal, jalr)
            2'b11:   Src_B = ExtImmE;   // ExtImm
            default: Src_B = FwdRD2E;   // 2'b10 unused
        endcase
    end

    assign MCycleResult = MCycleResultSelE ? MCycleResult2 : MCycleResult1; // Result2 for mulh, mulhu, rem, remu. Result1 for mul, div, divu
    assign ResultE = MCycleStartE ? MCycleResult : ALUResultE;              // mul/div/rem write back the MCycle result instead of the ALU result

    // Store data in Execute stage
    assign WriteDataE = FwdRD2E;

    // Instantiate ALU
    ALU ALU1(
                    Src_A,
                    Src_B,
                    ALUControlE,
                    ALUResultE,
                    ALUFlags
                );

    // Instantiate PC_Logic
    PC_Logic PC_Logic1(
                    PCSE,
                    Funct3E,
                    ALUFlags,
                    PCSrcE
                );

    // doom_soc: if MemStall freezes Execute in the cycle MCycle finishes, Start would still be high
    // in the next cycle and MCycle would start the same operation again (its result registers are
    // cleared by the load cycle). Hold Start off until Execute moves on; the results stay valid.
    reg  MCycleDoneHold = 1'b0 ;
    wire MCycleStartGated = MCycleStartE & ~MCycleDoneHold ;
    always @(posedge CLK) begin
        if (RESET | ~MemStall)
            MCycleDoneHold <= 1'b0;
        else if (MCycleStartE & ~MCycleBusy)
            MCycleDoneHold <= 1'b1;
    end

    // Instantiate MCycle
    MCycle #(.width(32)) MCycle1(
                    CLK,
                    RESET,
                    MCycleStartGated,
                    MCycleOpE,
                    FwdRD1E,
                    FwdRD2E,
                    MCycleResult1,
                    MCycleResult2,
                    MCycleBusy
                );

    // ============================================================
    // Memory Stage
    // ============================================================

    // Pipeline register E -> M (FlushM inserts a bubble)
    always @(posedge CLK) begin
        if (RESET | (FlushM & ~MemStall)) begin
            RegWriteM  <= 1'b0;
            MemtoRegM  <= 1'b0;
            MemWriteM  <= 1'b0;
            ResultM    <= 32'b0;
            WriteDataM <= 32'b0;
            rs2M       <= 5'b0;
            rdM        <= 5'b0;
            Funct3M    <= 3'b0;
        end
        else if (~MemStall) begin
            RegWriteM  <= RegWriteE;
            MemtoRegM  <= MemtoRegE;
            MemWriteM  <= MemWriteE;
            ResultM    <= ResultE;
            WriteDataM <= WriteDataE;
            rs2M       <= rs2E;
            rdM        <= rdE;
            Funct3M    <= Funct3E;
        end
    end

    // Data memory interface (memory itself is in the Wrapper)
    assign ALUResult = ResultM;             // Address sent to the Wrapper; data comes back as ReadData_in
    assign MemRead = MemtoRegM;             // This is needed for the proper functionality of some devices such as UART CONSOLE

    // Byte / halfword load-store support (lb/lbu/lh/lhu/sb/sh)
    // SizeSel is funct3 of the load/store in M: 000 b, 001 h, 010 w, 100 bu, 101 hu.
    // ResultM[1:0] is the byte offset within the word. Misaligned accesses ignore the
    // low address bits that do not apply (e.g. sh at offset 1 acts as offset 0).
    assign SizeSel = Funct3M;
    wire [1:0] ByteOffsetM = ResultM[1:0];

    // Stores: byte-lane write enables, with the data replicated across lanes so that the
    // enabled lane(s) carry the value. (MMIO writes in the Wrapper look at lane 0.)
    reg  [3:0]  ByteEnM ;
    reg  [31:0] WriteDataAlignedM ;
    always @(*) begin
        case (SizeSel[1:0])
            2'b00: begin    // sb
                ByteEnM           = 4'b0001 << ByteOffsetM;
                WriteDataAlignedM = {4{FwdWriteDataM[7:0]}};
            end
            2'b01: begin    // sh
                ByteEnM           = ByteOffsetM[1] ? 4'b1100 : 4'b0011;
                WriteDataAlignedM = {2{FwdWriteDataM[15:0]}};
            end
            default: begin  // sw
                ByteEnM           = 4'b1111;
                WriteDataAlignedM = FwdWriteDataM;
            end
        endcase
    end
    assign MemWrite_out  = MemWriteM ? ByteEnM : 4'b0000;
    assign WriteData_out = WriteDataAlignedM;

    // Loads: select the addressed byte / halfword, then sign- or zero-extend
    reg  [7:0]  LoadByteM ;
    reg  [15:0] LoadHalfM ;
    always @(*) begin
        case (ByteOffsetM)
            2'b00:   LoadByteM = ReadData_in[7:0];
            2'b01:   LoadByteM = ReadData_in[15:8];
            2'b10:   LoadByteM = ReadData_in[23:16];
            default: LoadByteM = ReadData_in[31:24];
        endcase
        LoadHalfM = ByteOffsetM[1] ? ReadData_in[31:16] : ReadData_in[15:0];

        case (SizeSel)
            3'b000:  ReadDataM = {{24{LoadByteM[7]}}, LoadByteM};   // lb
            3'b001:  ReadDataM = {{16{LoadHalfM[15]}}, LoadHalfM};  // lh
            3'b100:  ReadDataM = {24'b0, LoadByteM};                // lbu
            3'b101:  ReadDataM = {16'b0, LoadHalfM};                // lhu
            default: ReadDataM = ReadData_in;                       // lw
        endcase
    end

    // ============================================================
    // Writeback Stage
    // ============================================================

    // Pipeline register M -> W
    always @(posedge CLK) begin
        if (RESET) begin
            RegWriteW  <= 1'b0;
            MemtoRegW  <= 1'b0;
            ReadDataW  <= 32'b0;
            ResultW    <= 32'b0;
            rdW        <= 5'b0;
        end
        else if (~MemStall) begin
            RegWriteW  <= RegWriteM;
            MemtoRegW  <= MemtoRegM;
            ReadDataW  <= ReadDataM;
            ResultW    <= ResultM;
            rdW        <= rdM;
        end
    end

    // RegFile write port
    assign WE = RegWriteW;
    assign WD = MemtoRegW ? ReadDataW : ResultW;    // Data from Memory, or the Execute result (ALU or MCycle)

    // ============================================================
    // Hazard control
    // ============================================================

    // 1. Multi-cycle (mul/div/rem) in Execute: hold F, D and E until MCycle is done,
    //    and insert bubbles into M so that older instructions in M and W can still complete.
    //    (Combined into the stall/flush signals at the end of this section.)

    // 2-3. RAW, producer 1 or 2 instructions ahead: forward into Execute.
    //      10: from M (ResultM), 01: from W (WD), 00: no forwarding. M is newer, so it has priority.
    always @(*) begin
        if (RegWriteM & (rdM != 5'b0) & (rdM == rs1E))      ForwardAE = 2'b10;
        else if (RegWriteW & (rdW != 5'b0) & (rdW == rs1E)) ForwardAE = 2'b01;
        else                                                ForwardAE = 2'b00;
    end

    always @(*) begin
        if (RegWriteM & (rdM != 5'b0) & (rdM == rs2E))      ForwardBE = 2'b10;
        else if (RegWriteW & (rdW != 5'b0) & (rdW == rs2E)) ForwardBE = 2'b01;
        else                                                ForwardBE = 2'b00;
    end

    always @(*) begin
        case (ForwardAE)
            2'b10:   FwdRD1E = ResultM;
            2'b01:   FwdRD1E = WD;
            default: FwdRD1E = RD1E;
        endcase
    end

    always @(*) begin
        case (ForwardBE)
            2'b10:   FwdRD2E = ResultM;
            2'b01:   FwdRD2E = WD;
            default: FwdRD2E = RD2E;
        endcase
    end

    // 4. RAW, producer 3 instructions ahead: RegFile is written at the end of the cycle
    //    in which Decode reads it, so forward WD into Decode.
    assign FwdRD1D = (RegWriteW & (rdW != 5'b0) & (rdW == rs1D)) ? WD : RD1D;
    assign FwdRD2D = (RegWriteW & (rdW != 5'b0) & (rdW == rs2D)) ? WD : RD2D;

    // 5. Mem-mem copy (lw followed by sw of the loaded register): forward the loaded data
    //    from W into the store data in M. RegWriteW guards against MemtoReg being set by a non-load.
    assign ForwardM      = MemWriteM & MemtoRegW & RegWriteW & (rdW != 5'b0) & (rs2M == rdW);
    assign FwdWriteDataM = ForwardM ? ReadDataW : WriteDataM;

    // 6. Load-use: lw in Execute, and the instruction in Decode needs its result.
    //    Stall F and D for one cycle and insert a bubble into E; W-to-E forwarding then supplies the data.
    //    sw rs2 is excluded since mem-mem copy forwarding (5) handles it.
    assign lwStall = MemtoRegE & (rdE != 5'b0) &
                     ((rs1D == rdE) | ((rs2D == rdE) & ~MemWriteD));

    // 7. Control: taken branch or jump in Execute. Flush the two wrong-path instructions in D and E.
    assign BranchTakenE = (PCSrcE != 3'b000);

    // Stall / flush signals. 1, 6 and 7 need different instructions in Execute, so they never coincide.
    assign StallF = MCycleBusy | lwStall ;
    assign StallD = MCycleBusy | lwStall ;
    assign StallE = MCycleBusy ;
    assign FlushD = BranchTakenE ;
    assign FlushE = BranchTakenE | lwStall ;
    assign FlushM = MCycleBusy ;
    // doom_soc: MemStall (from the caches, computed from F/M-stage registers only) overrides all of
    // the above: PC and every pipeline register hold, nothing is flushed. RegFile writes from W repeat
    // the same value while frozen, which is harmless.

endmodule
