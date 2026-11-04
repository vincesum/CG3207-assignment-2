# Generate the MIG DDR2 IP for the Nexys 4 DDR from Digilent's published mig.prj
set root [file normalize [file dirname [info script]]]
create_project ddr2_bringup $root/vivado -part xc7a100tcsg324-1 -force
create_ip -name mig_7series -vendor xilinx.com -library ip -module_name ddr
set ipdir [get_property IP_DIR [get_ips ddr]]
file copy -force $root/mig.prj $ipdir/mig_a.prj
set_property -dict [list CONFIG.XML_INPUT_FILE {mig_a.prj} CONFIG.RESET_BOARD_INTERFACE {Custom} CONFIG.MIG_DONT_TOUCH_PARAM {Custom} CONFIG.BOARD_MIG_PARAM {Custom}] [get_ips ddr]
generate_target {instantiation_template synthesis implementation} [get_ips ddr]
puts "MIG_VERSION: [get_property VLNV [get_ips ddr]]"
puts "IPDIR: $ipdir"
