# Build the doom_soc bitstream (Vivado 2018.2, batch):
#   vivado.bat -mode batch -nojournal -log build.log -source build.tcl [-tclargs <jobs>]
# Creates vivado/proj/doom_soc.xpr (can be opened in the GUI afterwards).
# DDR uses the original generated synthesis RTL and XDC; MIG is not invoked.
set root  [file normalize [file dirname [info script]]]
set top   [file normalize $root/..]
set jobs  [expr {[llength $argv] > 0 ? [lindex $argv 0] : 8}]
set rom   $top/sw/build/boot/boot.hex
if {![file exists $rom]} { error "missing $rom - run: python sw/build.py boot" }

# Use the original generated MIG synthesis RTL, with no managed XCI or OOC DCP.
# This avoids launching mig.exe and retains normal top-level synthesis timing.
set ipdst $root/ip/ddr
source $root/ddr_sources.tcl
foreach rel $ddr_synthesis_sources {
    if {![file exists $ipdst/$rel]} { error "Missing original DDR source: $ipdst/$rel" }
}
set ddr_xdc $ipdst/ddr/user_design/constraints/ddr.xdc
if {![file exists $ddr_xdc]} { error "Missing original DDR constraints: $ddr_xdc" }

create_project doom_soc $root/proj -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]

# The processor comes from the base project, so Doom and the lab design share one copy.
set core $top/../project/project.srcs/sources_1/imports
foreach f {Asst_02/ALU.v Asst_02/Decoder.v Asst_02/Extend.v Asst_02/PC_Logic.v Asst_02/ProgramCounter.v Asst_02/RegFile.v Asst_02/RV.v Asst_02/Shifter.v Asst_03/MCycle.v} { add_files -norecurse $core/$f }
add_files -norecurse [glob $top/rtl/soc/*.v]
add_files -norecurse $top/rtl/top/doom_top.v
add_files -norecurse $top/rtl/periph/pmodoledrgb_bitmap.vhd
add_files -norecurse $rom
set_property file_type {Memory Initialization Files} [get_files $rom]
# Exact synthesis source set from the original ddr.xml metadata.
# Do not add ddr_mig_sim.v: it duplicates the synthesis ddr_mig module.
foreach rel $ddr_synthesis_sources { add_files -norecurse $ipdst/$rel }
add_files -fileset constrs_1 -norecurse $ddr_xdc
set_property SCOPED_TO_REF {ddr} [get_files $ddr_xdc]
set_property PROCESSING_ORDER EARLY [get_files $ddr_xdc]
# ddr_ooc.xdc contains stand-alone IP clocks; do not import it at top level.
puts "DDR_MODE: original generated RTL and XDC (no MIG generation, no OOC DCP)"
add_files -fileset constrs_1 -norecurse $root/doom_top.xdc

set_property top doom_top [current_fileset]
# ROM_FILE keeps its default "boot.hex": synthesis finds it because boot.hex is a project
# memory file (a generic with a quoted path ends up with the quotes in the file name).
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
puts "SYNTH_STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "synthesis failed" }
# An unreadable $readmemh file is only a critical warning - make it fatal (empty boot ROM otherwise)
set fh [open $root/proj/doom_soc.runs/synth_1/runme.log r]; set slog [read $fh]; close $fh
if {[string match {*could not open $readmem*} $slog]} { error "boot ROM file not found by synthesis" }

launch_runs impl_1 -to_step write_bitstream -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS: $impl_status"
if {![string match "write_bitstream Complete*" $impl_status]} {
    error "Implementation did not complete: $impl_status. See impl_1/runme.log."
}

open_run impl_1
file mkdir $root/reports
report_timing_summary -max_paths 10 -file $root/reports/timing_summary.rpt
report_utilization -file $root/reports/utilization.rpt
report_clock_interaction -file $root/reports/clock_interaction.rpt
report_drc -file $root/reports/drc.rpt
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
puts "TIMING: WNS=$wns WHS=$whs"
foreach clk {clk_cpu_unbuf} {
    set p [get_timing_paths -quiet -max_paths 1 -nworst 1 -setup -to [get_clocks -quiet -of_objects [get_nets -hier -quiet $clk]]]
    if {[llength $p]} { puts "WORST_TO_$clk: [get_property SLACK $p] [get_property STARTPOINT_PIN $p] -> [get_property ENDPOINT_PIN $p]" }
}
set bit [glob -nocomplain $root/proj/doom_soc.runs/impl_1/*.bit]
if {![llength $bit]} { error "No new bitstream was produced." }
file copy -force [lindex $bit 0] $root/doom_top.bit
puts "BITSTREAM: $root/doom_top.bit"
