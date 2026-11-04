# Post-synthesis simulation of the SoC. Synthesizes rv_soc with the test program in its ROM, then
# runs test_soc.v on the resulting netlist. The DDR2 controller is outside rv_soc, so the
# testbench's model replaces it, which keeps this fast.
# In Vivado, with no project open: Tools > Run Tcl Script, then select this file.
# When it finishes, type "run all" in the Tcl Console. The result is at the end of the output.
# Creates soc_build/proj_post_synth. The other Vivado projects are not touched.
set root [file normalize [file dirname [info script]]]
set top  [file normalize $root/..]
set src  $top/project/project.srcs/sources_1
set soc  $src/soc
set core $src/imports
set sim  $top/project/project.srcs/sim_1/new
set work $root/proj_post_synth
set jobs [expr {[info exists argv] && [llength $argv] > 0 ? [lindex $argv 0] : 8}]

create_project rv_soc_post_synth $work -part xc7a100tcsg324-1 -force
set_property target_language Verilog [current_project]

foreach f {Asst_02/ALU.v Asst_02/Decoder.v Asst_02/Extend.v Asst_02/PC_Logic.v Asst_02/ProgramCounter.v Asst_02/RegFile.v Asst_02/RV.v Asst_02/Shifter.v Asst_03/MCycle.v} { add_files -norecurse $core/$f }
add_files -norecurse [glob $soc/memory/*.v]
add_files -norecurse [glob $soc/io/*.v]
add_files -norecurse $soc/rv_soc.v

# rv_soc reads a ROM file called boot.mem, so use a copy of the test program under that name
file mkdir $work/rom
file copy -force $sim/test_soc_rom.mem $work/rom/boot.mem
add_files -norecurse $work/rom/boot.mem
set_property file_type {Memory Initialization Files} [get_files boot.mem]

set_property top rv_soc [current_fileset]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value {-mode out_of_context} -objects [get_runs synth_1]

add_files -fileset sim_1 -norecurse [list $sim/test_soc.v $sim/ddr_model.v]
set_property top test_soc [get_filesets sim_1]
set_property verilog_define {POST_SYNTH} [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "synthesis failed" }
set_property -name {xsim.simulate.runtime} -value {0} -objects [get_filesets sim_1]
launch_simulation -mode post-synthesis -type functional
