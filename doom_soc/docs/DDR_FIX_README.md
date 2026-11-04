# DDR build correction: original generated RTL

The earlier direct ddr.dcp import caused Vivado Project 1-863. That approach has been removed. This build imports neither ddr.xci nor ddr.dcp, so it neither launches MIG generation nor uses an OOC checkpoint as a direct source.

The script instead synthesizes the original generated DDR RTL together with the SoC, using exactly the Verilog synthesis file list from the original ddr.xml. It imports the original ddr.xdc in the ddr module scope, including the board pinout, PHY placement and timing constraints. It excludes ddr_mig_sim.v (duplicate simulation module), the stub, simulation netlist, example design and ddr_ooc.xdc (stand-alone clocks). All original DDR files remain unchanged.

## Run

Stop the old build, close the GUI project, extract this full ZIP into a fresh folder, and run from the project root:

```
python sw\build.py all --clean
cd vivado
C:\Xilinx\Vivado\2018.2\bin\vivado.bat -mode batch -nojournal -log build_audio.log -source build.tcl
```

Expected: DDR_MODE: original generated RTL and XDC (no MIG generation, no OOC DCP)

This replaces the generated project. Do not open the archived XPR instead of running the script. After success you may open vivado/proj/doom_soc.xpr. Old bundled binaries/bitstreams predate audio; rebuild them. DDR is now synthesized with the top-level design, which can take time, but should not invoke mig.exe.

## Verification

All 119 original DDR IP files are byte-identical. Source selection is derived from the original IP synthesis metadata, not a recursive glob. Checks confirm files exist, module names are unique, and no simulation alternative or OOC clock constraints are imported. Tcl syntax and pre-synthesis setup were checked with mocked Vivado commands.

Vivado is unavailable here. Actual synthesis, constraint resolution, timing closure and on-board operation remain unverified. This corrects the specific checkpoint warning and bypasses the observed MIG generation stall; it is not a verified bitstream.
