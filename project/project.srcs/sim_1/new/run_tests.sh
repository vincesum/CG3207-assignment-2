#!/bin/bash
# Runs every self-checking testbench with Icarus Verilog and prints one line for each.
# Usage: run_tests.sh [folder for the logs]
H=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$H/../.." && pwd)
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
I=$SRC/sources_1/imports
SOC=$SRC/sources_1/soc
CORE="$I/Asst_02/ALU.v $I/Asst_02/Decoder.v $I/Asst_02/Extend.v $I/Asst_02/PC_Logic.v $I/Asst_02/ProgramCounter.v $I/Asst_02/RegFile.v $I/Asst_02/RV.v $I/Asst_02/Shifter.v $I/Asst_03/MCycle.v"
MEM="$SOC/memory/dm_cache.v $SOC/memory/memctl.v"
SYS="$SOC/rv_soc.v $MEM $SOC/memory/mig_bridge.v $SOC/io/mmio.v $SOC/io/uart.v $SOC/io/soc_audio.v $H/ddr_model.v"
cd "$OUT"
cp "$H"/*.mem .
cp "$I"/Asst_02/*.mem .
cp "$H"/test_*_irom.mem "$H"/test_*_dmem.mem "$H"/test_*_exp.mem . 2>/dev/null
FAILED=0
run() {  # name, top module, extra iverilog options, sources
    local name=$1 top=$2 opts=$3; shift 3
    if ! iverilog -g2012 $opts -s "$top" -o "$name.vvp" "$@" > "$name.compile" 2>&1; then
        echo "COMPILE ERROR  $name (see $OUT/$name.compile)"; FAILED=$((FAILED+1)); return
    fi
    timeout "${TEST_TIMEOUT:-600}" vvp -n "$name.vvp" > "$name.log" 2>&1
    if grep -q -E '==== .*: PASS ====|==== [0-9]+ passed, 0 failed ====|audio RTL tests passed' "$name.log"; then
        echo "PASS  $name"
    else
        echo "FAIL  $name (see $OUT/$name.log)"; FAILED=$((FAILED+1))
    fi
}
RUN=$H/rv_prog_runner.v
run test_RV_dp       tb_RV_dp                $'' "$SRC/sim_3/new/test_RV_dp.v" "$RUN" $CORE
run test_RV_shifter  tb_RV_shifter           $'' "$H/test_RV_shifter.v" "$RUN" $CORE
run test_RV_branches test_RV_branches        $'' "$H/test_RV_branches.v" "$RUN" $CORE
run test_RV_lw_sw    test_RV_lw_sw_lui_auipc $'' "$SRC/sim_2/imports/new/test_RV_lw_sw.v" "$RUN" $CORE
run test_hazards     test_hazards            $'' "$H/test_hazards.v" "$RUN" $CORE
run test_MCycle      test_MCycle             $'' "$SRC/sim_1/imports/Asst_03/test_MCycle.v" "$I/Asst_03/MCycle.v"
run test_RV_muldiv_stall test_RV_muldiv_stall $'' "$H/test_RV_muldiv_stall.v" $CORE
run test_Wrapper_muldiv test_Wrapper_muldiv  $'' "$SRC/sim_1/imports/Asst_03/test_Wrapper_muldiv.v" "$I/Asst_02/Wrapper.v" $CORE
run test_RV_ldst     test_RV_ldst            $'' "$H/test_RV_ldst.v" "$I/Asst_02/Wrapper.v" $CORE
run test_Wrapper_DIP_to_LED test_Wrapper     $'' "$I/Asst_02/test_Wrapper_DIP_to_LED_self_checking.v" "$I/Asst_02/Wrapper.v" $CORE
run test_cache       test_cache              $'' "$H/test_cache.v" $MEM
run test_mmio        test_mmio               $'' "$H/test_mmio.v" "$SOC/io/mmio.v" "$SOC/io/uart.v" "$SOC/io/soc_audio.v"
run test_soc_audio   tb_audio                $'' "$H/test_soc_audio.v" "$SOC/io/soc_audio.v"
run test_soc         test_soc                $'' "$H/test_soc.v" $SYS $CORE
run test_soc_slow_ddr test_soc '-Ptest_soc.RD_LAT=90' "$H/test_soc.v" $SYS $CORE
echo
if [ "$FAILED" = 0 ]; then echo "All testbenches passed."; else echo "$FAILED testbench(es) failed."; fi
exit $FAILED
