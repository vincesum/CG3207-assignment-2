`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
-- Module Name: test_Wrapper_muldiv
-- Project Name: CG3207 Project
-- Description: Self-checking testbench for testmuldiv.asm (Assignment 3, mul / divu).
--              Waits for the program to reach display_loop, then checks
--              1. LED_OUT = pass mask from the program (expect 0xFF)
--              2. SEVENSEGHEX = results[DIP[2:0]] for every DIP[2:0] = 0..7
--              AA_IROM.mem / AA_DMEM.mem must hold the dumps of testmuldiv.asm.
----------------------------------------------------------------------------------
*/

module test_Wrapper_muldiv #(
	   parameter N_LEDs_OUT	= 8,
	   parameter N_DIPs		= 16,
	   parameter N_PBs		= 3,
	   parameter DISPLAY_LOOP_PC = 7'h2E,	// LED_PC (PC[8:2]) of display_loop in testmuldiv.asm (0x004000B8). Update if the program changes
	   parameter TIMEOUT = 20000			// ns to wait for display_loop before giving up
	)
	(
	);

	// Signals for the Unit Under Test (UUT)
	reg  [N_DIPs-1:0] DIP = 0;
	reg  [N_PBs-1:0] PB = 0;
	wire [N_LEDs_OUT-1:0] LED_OUT;
	wire [6:0] LED_PC;
	wire [31:0] SEVENSEGHEX;
	wire [7:0] UART_TX;
	reg  UART_TX_ready = 0;
	wire UART_TX_valid;
	reg  [7:0] UART_RX = 0;
	reg  UART_RX_valid = 0;
	wire UART_RX_ack;
	wire OLED_Write;
	wire [6:0] OLED_Col;
	wire [5:0] OLED_Row;
	wire [23:0] OLED_Data;
	reg [31:0] ACCEL_Data;
	wire ACCEL_DReady;
	reg  RESET = 0;
	reg  CLK = 0;

	// Instantiate UUT
    Wrapper dut(DIP, PB, LED_OUT, LED_PC, SEVENSEGHEX, UART_TX, UART_TX_ready, UART_TX_valid, UART_RX, UART_RX_valid, UART_RX_ack, OLED_Write, OLED_Col, OLED_Row, OLED_Data, ACCEL_Data, ACCEL_DReady, RESET, CLK) ;

	// Expected results, same table as the header of testmuldiv.asm
	reg [31:0] expected [0:7];
	initial begin
		expected[0] = 32'h0000002A;	// mul  7 * 6
		expected[1] = 32'hFFFFFFF1;	// mul  -3 * 5
		expected[2] = 32'h540BE400;	// mul  100000 * 100000 (low word)
		expected[3] = 32'h00000001;	// mul  0xFFFFFFFF * 0xFFFFFFFF
		expected[4] = 32'h0000000E;	// divu 100 / 7
		expected[5] = 32'h0FFFFFFF;	// divu 0xFFFFFFF0 / 16
		expected[6] = 32'h00000000;	// divu 5 / 9
		expected[7] = 32'h0000007B;	// mul then divu back to back: 123 * 456 / 456
	end

	integer i;
	integer fail_count = 0;
	integer stall_cycles = 0;

	// Count cycles where the PC is frozen by MCycle (for information only)
	always @(posedge CLK)
		if (!RESET && dut.RV1.MCycleBusy)
			stall_cycles = stall_cycles + 1;

	// STIMULI
    initial
    begin
	RESET = 1; #10; RESET = 0; //hold reset state for 10 ns.
	$display("[%0t] Starting testmuldiv testbench", $time);

		// 1. Wait for the program to finish the tests and reach display_loop
		fork : wait_display
			begin
				wait(LED_PC == DISPLAY_LOOP_PC);
				disable wait_display;
			end
			begin
				#TIMEOUT;
				$display("[%0t] FAIL: timeout, display_loop (LED_PC=0x%02X) never reached. Last LED_PC=0x%02X", $time, DISPLAY_LOOP_PC, LED_PC);
				$finish;
			end
		join
		$display("[%0t] Reached display_loop. MCycle stall cycles so far: %0d", $time, stall_cycles);

		// 2. Pass mask on the LEDs. Test i is bit 7-i
		if (LED_OUT == 8'hFF)
			$display("[%0t] PASS: LED_OUT = 0x%02X", $time, LED_OUT);
		else begin
			fail_count = fail_count + 1;
			$display("[%0t] FAIL: LED_OUT = 0x%02X, expected 0xFF", $time, LED_OUT);
			for (i = 0; i < 8; i = i + 1)
				if (!LED_OUT[7-i])
					$display("        program reports test %0d failed", i);
		end

		// 3. Step DIP[2:0] through every result. display_loop is 7 instructions, so 200 ns covers at least 2 iterations
		for (i = 0; i < 8; i = i + 1) begin
			DIP = i;
			#200;
			if (SEVENSEGHEX == expected[i])
				$display("[%0t] PASS: test %0d, SEVENSEGHEX = 0x%08X", $time, i, SEVENSEGHEX);
			else begin
				fail_count = fail_count + 1;
				$display("[%0t] FAIL: test %0d, SEVENSEGHEX = 0x%08X, expected 0x%08X", $time, i, SEVENSEGHEX, expected[i]);
			end
		end

		// Final summary
		$display("\n=== SUMMARY ===");
		if (fail_count == 0)
			$display("*** ALL TESTS PASSED ***");
		else
			$display("*** %0d CHECKS FAILED ***", fail_count);
		$display("===============\n");
		$finish;
    end

	// GENERATE CLOCK
    always
    begin
       #5 CLK = ~CLK ; // invert clk every 5 time units
    end

endmodule
