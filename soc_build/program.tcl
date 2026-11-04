# Program the Nexys 4 DDR with soc_top.bit (volatile, over JTAG):
#   C:\Xilinx\Vivado\2018.2\bin\vivado.bat -mode batch -nojournal -nolog -source program.tcl
set root [file normalize [file dirname [info script]]]
open_hw
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $root/soc_top.bit $dev
program_hw_devices $dev
puts "PROGRAMMED: $dev"
close_hw_target
disconnect_hw_server
close_hw
