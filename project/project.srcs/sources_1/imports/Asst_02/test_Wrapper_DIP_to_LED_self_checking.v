`timescale 1ns / 1ps
/*
----------------------------------------------------------------------------------
--	(c) Rajesh Panicker
--	License terms :
--		(i) DO NOT post it on any public repository;
--		(ii) use it only for educational purposes;
--		(iii) accept the responsibility to ensure that your implementation does not violate any intellectual property of ARM Holdings or other entities.
--		(iv) accept that the program is provided "as is" without warranty of any kind or assurance regarding its suitability for any particular purpose;
--		(v) send an email to rajesh.panicker@ieee.org briefly mentioning its use (except when used for the course CG3207 at the National University of Singapore);
--		(vi) retain this notice in this file or any files derived from this.
----------------------------------------------------------------------------------
*/

// Checks through the Wrapper that the LEDs follow the switches. Program: test_dip_to_led.asm,
// assembled into test_dip_to_led_irom.mem.
module test_Wrapper #(
	   parameter N_LEDs_OUT	= 8,
	   parameter N_DIPs		= 16,
	   parameter N_PBs		= 3
	)
	(
	);

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
	reg  [31:0] ACCEL_Data = 0;
	wire ACCEL_DReady;
	reg  RESET = 1;
	reg  CLK = 0;

	Wrapper dut(DIP, PB, LED_OUT, LED_PC, SEVENSEGHEX, UART_TX, UART_TX_ready, UART_TX_valid, UART_RX, UART_RX_valid, UART_RX_ack, OLED_Write, OLED_Col, OLED_Row, OLED_Data, ACCEL_Data, ACCEL_DReady, RESET, CLK);

	always #5 CLK = ~CLK;

	integer i, fails = 0;
	reg [7:0] values [0:5];

	initial begin
		values[0] = 8'h00; values[1] = 8'hFF; values[2] = 8'hA5;
		values[3] = 8'h5A; values[4] = 8'h01; values[5] = 8'h80;
		#1;	// after Wrapper has loaded its default program
		$readmemh("test_dip_to_led_irom.mem", dut.IROM);
		#9 RESET = 0;
		for (i = 0; i < 6; i = i + 1) begin
			DIP = {8'h00, values[i]};
			#200;
			if (LED_OUT !== values[i]) begin
				fails = fails + 1;
				$display("  FAIL: switches %h, LEDs %h", values[i], LED_OUT);
			end
		end
		if (fails == 0) $display("==== test_Wrapper_DIP_to_LED: PASS ====");
		else            $display("==== test_Wrapper_DIP_to_LED: FAIL (%0d) ====", fails);
		$finish;
	end
endmodule
