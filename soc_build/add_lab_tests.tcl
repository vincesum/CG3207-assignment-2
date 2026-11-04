# Adds the CPU testbenches and their programs to the lab project. Open project/project.xpr first,
# then choose Tools > Run Tcl Script and select this file. Pick a test with Set as Top in the
# Simulation Sources, and use "run all". It changes your local project.xpr, which isn't in git.
set root [file normalize [file dirname [info script]]]
set srcs [file normalize $root/../project/project.srcs]
set sim  $srcs/sim_1/new
set tests [list $sim/rv_prog_runner.v $sim/test_hazards.v $sim/test_RV_branches.v $sim/test_RV_shifter.v \
    $sim/test_RV_muldiv_stall.v $sim/test_RV_ldst.v $srcs/sim_1/imports/Asst_03/test_Wrapper_muldiv.v \
    $srcs/sim_2/imports/new/test_RV_lw_sw.v $srcs/sim_3/new/test_RV_dp.v]
foreach f [concat $tests [glob $sim/*_irom.mem] [glob $sim/*_dmem.mem] [glob $sim/*_exp.mem] [glob $sim/test_RV_muldiv_stall_*.mem]] {
    if {[llength [get_files -quiet -of_objects [get_filesets sim_1] $f]] == 0} { add_files -fileset sim_1 -norecurse $f }
}
update_compile_order -fileset sim_1
