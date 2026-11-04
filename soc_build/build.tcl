# Generates the rv_soc bitstream: RV32IM core, caches, DDR2, OLED, UART and audio.
# In Vivado, with no project open: Tools > Run Tcl Script, then select this file.
# Or from a terminal: vivado -mode batch -nojournal -log build.log -source build.tcl
# Creates soc_build/proj/rv_soc.xpr and the bitstream soc_build/soc_top.bit.
# The lab project in project/ is not touched.
# DDR uses the original generated synthesis RTL and XDC; MIG is not invoked.
set root  [file normalize [file dirname [info script]]]
set top   [file normalize $root/..]
set src   $top/project/project.srcs/sources_1
set soc   $src/soc
set core  $src/imports
set jobs  [expr {[info exists argv] && [llength $argv] > 0 ? [lindex $argv 0] : 8}]
set rom   $soc/memory/boot.mem
if {![file exists $rom]} { error "missing $rom" }

# Use the original generated MIG synthesis RTL, with no managed XCI or OOC DCP.
# This avoids launching mig.exe and retains normal top-level synthesis timing.
set ipdst $soc
source $root/ddr_sources.tcl
foreach rel $ddr_synthesis_sources {
    if {![file exists $ipdst/$rel]} { error "Missing original DDR source: $ipdst/$rel" }
}
set ddr_xdc $ipdst/ddr/user_design/constraints/ddr.xdc
if {![file exists $ddr_xdc]} { error "Missing original DDR constraints: $ddr_xdc" }

create_project rv_soc $root/proj -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]

# The processor is shared with the lab design in imports/.
foreach f {Asst_02/ALU.v Asst_02/Decoder.v Asst_02/Extend.v Asst_02/PC_Logic.v Asst_02/ProgramCounter.v Asst_02/RegFile.v Asst_02/RV.v Asst_02/Shifter.v Asst_03/MCycle.v} { add_files -norecurse $core/$f }
add_files -norecurse [glob $soc/memory/*.v]
add_files -norecurse [glob $soc/io/*.v]
add_files -norecurse $soc/rv_soc.v
add_files -norecurse $soc/soc_top.v
add_files -norecurse $core/Asst_02/pmodoledrgb_bitmap.vhd
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
add_files -fileset constrs_1 -norecurse $soc/soc_top.xdc

set_property top soc_top [current_fileset]
# Simulation: test_soc is the default. The others can be chosen with Set as Top.
set sim $top/project/project.srcs/sim_1/new
add_files -fileset sim_1 -norecurse [list $sim/test_soc.v $sim/test_cache.v $sim/test_mmio.v $sim/test_soc_audio.v $sim/ddr_model.v $sim/test_soc_rom.mem]
set_property top test_soc [get_filesets sim_1]
# ROM_FILE keeps its default "boot.mem": synthesis finds it because boot.mem is a project
# memory file (a generic with a quoted path ends up with the quotes in the file name).
update_compile_order -fileset sources_1

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
puts "SYNTH_STATUS: [get_property STATUS [get_runs synth_1]]"
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "synthesis failed" }
# An unreadable $readmemh file is only a critical warning - make it fatal (empty boot ROM otherwise)
set fh [open $root/proj/rv_soc.runs/synth_1/runme.log r]; set slog [read $fh]; close $fh
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
set bit [glob -nocomplain $root/proj/rv_soc.runs/impl_1/*.bit]
if {![llength $bit]} { error "No new bitstream was produced." }
file copy -force [lindex $bit 0] $root/soc_top.bit
puts "BITSTREAM: $root/soc_top.bit"
