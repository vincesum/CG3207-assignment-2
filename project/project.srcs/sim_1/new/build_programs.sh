#!/bin/bash
# Assembles the test programs with RARS. Run this after changing a .asm file.
# Set RARS to the path of rars.jar if it isn't ~/rars.jar.
set -e
RARS=${RARS:-$HOME/rars.jar}
cd "$(dirname "$0")"
# Programs that RARS can also simulate: it computes the expected final data memory.
for p in test_RV_dp test_RV_shifter test_RV_branches test_RV_lw_sw test_hazards test_muldiv test_dip_to_led; do
    java -jar "$RARS" ae1 a nc dump .text HexText ${p}_irom.mem dump .data HexText ${p}_dmem.mem $p.asm | grep -v -E "^$|maximum step limit" || true
    java -jar "$RARS" ae1 nc 300000 dump .data HexText ${p}_exp.mem $p.asm | grep -v -E "^$|maximum step limit" || true
done
# test_soc uses SoC hardware that RARS doesn't have, so it's only assembled.
java -jar "$RARS" ae1 a nc dump .text HexText test_soc_rom.mem test_soc_rom.asm | grep -v -E "^$|maximum step limit" || true
