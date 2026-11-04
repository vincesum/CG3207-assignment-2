# doom_soc — DOOM on the CG3207 RV32IM pipeline (Nexys 4 DDR, 96×64 PmodOLEDrgb)

SoC built around the base processor in `project/` at the top of this repository. There is no separate copy of the core: the Vivado build and the simulations use `project/project.srcs/sources_1/imports` directly. Merge `master` into this branch to pick up core changes; don't merge this branch into `master`.

The base project is unchanged on this branch, so you can still open it and program the board as usual. Its `project.xpr` is not in git and stays in your working copy.

## Run DOOM on the board

These steps start from a fresh clone. The commands are for Windows Command Prompt or PowerShell; on Linux, use the versions under [Linux commands](#linux-commands).

### 1. What you need

**Hardware**

- Nexys 4 DDR (or Nexys A7-100T) and its micro-USB cable
- PmodOLEDrgb plugged into **JB**, the same port the lab uses
- Optional: speakers or headphones on the **J8** audio jack. Start with the volume low.

**Software**

| Tool | Notes |
|---|---|
| Vivado | **2023.2** builds this design from a clean clone, and **2018.2** built the earlier audio version. The Windows commands below assume `C:\Xilinx\Vivado\2018.2`, so change the path if yours differs. |
| RISC-V GCC with newlib | Only needed to rebuild the software. Use the [xPack RISC-V toolchain](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases); version 15.2.0 built the working DOOM binary. Unpack it and add its `bin` folder to `PATH`, then check with `riscv-none-elf-gcc --version`. |
| Python 3 with pyserial | `python -m pip install --user pyserial` |

### 2. Get the code

```
git clone https://github.com/vincesum/CG3207-assignment-2.git
cd CG3207-assignment-2
git switch doom
cd doom_soc
```

Run the remaining commands from `doom_soc` unless a step says otherwise.

### 3. Build the software

This step is optional unless you've changed the software: `prebuilt/` holds a ready-made `boot.hex` and `doom.bin`, and the build and loader use them when `sw\build` doesn't exist.

```
python sw\build.py all --clean
```

This creates `sw\build\doom\doom.bin` and the boot ROM image `sw\build\boot\boot.hex`. Check that the output includes:

```
Startup verified: _start / ELF entry = 0x80000000
```

Build the software first: the Vivado build copies `boot.hex` into the bitstream and stops if the file is missing. If you later change anything under `sw\boot`, rebuild the bitstream as well. Changes to DOOM itself only need this step.

### 4. Build the bitstream

Close any open copy of this Vivado project, then run:

```
cd vivado
C:\Xilinx\Vivado\2018.2\bin\vivado.bat -mode batch -nojournal -log build.log -source build.tcl
cd ..
```

Near the end of `vivado\build.log`, check these lines:

| Line | What to look for |
|---|---|
| `DDR_MODE: original generated RTL and XDC ...` | Present |
| `TIMING: WNS=... WHS=...` | Both values are 0 or higher. If not, don't trust the bitstream. |
| `BITSTREAM: ...doom_top.bit` | Present |

The build took about 4 minutes on a 24-thread PC. The result is `vivado\doom_top.bit`. Reports are in `vivado\reports`, and you can open `vivado\proj\doom_soc.xpr` in the GUI after a successful build.

### 5. Program the board

Connect the USB cable, turn the board on, and leave the switches down. Then either use Vivado's Hardware Manager to program `vivado\doom_top.bit`, or run:

```
C:\Xilinx\Vivado\2018.2\bin\vivado.bat -mode batch -nojournal -nolog -source vivado\program.tcl
```

Programming lasts until the board loses power, so repeat this step after a power cycle.

Wait until these LEDs are on before continuing:

| LED | Meaning |
|---|---|
| LED15 | DDR2 calibrated |
| LED14 | CPU clock locked |
| LED8 | Heartbeat (CPU clock running) |
| LED7 | Boot ROM is waiting for the PC |
| LED13 | Should be **off**. On means the CPU is in reset. |

### 6. Load and start DOOM

Find the board's COM port in Device Manager under **Ports (COM & LPT)**, listed as "USB Serial Port". Then run this, using your port number:

```
python host\load.py --port COM4
```

This sends `doom1.wad` (about 30 s at 1.5 Mbaud) and `doom.bin` over USB, checks each chunk, and jumps to `0x8000_0000`. The terminal then shows `running` and DOOM's startup messages, and the title screen and demos appear on the OLED.

Leave the terminal open to play from the PC keyboard. **F12** closes the keyboard link, and DOOM keeps running.

### 7. Start a game

1. Press **Esc** on the keyboard, or flip **SW15** on the board, to open the menu.
2. Choose **New Game**, then an episode and a skill level, using the arrow keys and **Enter**. On the board, use **BTNU** / **BTND** and **BTNC**.

See [Controls](#controls) for the rest. The 7-segment display shows health on the left and ammo on the right.

### 8. Restart without reloading everything

Press the red **CPU_RESET** button. The CPU returns to the boot ROM and the WAD stays in DDR2, so the reload takes much less time:

```
python host\load.py --port COM4 --skip-wad
```

Press F12 first if the previous `load.py` is still running, because it holds the COM port. After a power cycle or reprogramming, do the full load in step 6.

### 9. Test the sound

Sound effects are on by default; music isn't implemented. If there's no sound, this plays a repeating tone of about 440 Hz through J8:

```
python sw\build.py app audio_test
python host\load.py --port COM4 --prog sw\build\apps\audio_test\audio_test.bin --no-wad
```

Press CPU_RESET and do the normal load to return to DOOM.

### Linux commands

These replace the commands in steps 3 to 6. Run them from `doom_soc`, and change the Vivado path and toolchain path to match your install:

```
export PATH=/path/to/xpack-riscv-none-elf-gcc/bin:$PATH
python3 sw/build.py all --clean

cd vivado
/tools/Xilinx/Vivado/2023.2/bin/vivado -mode batch -nojournal -log build.log -source build.tcl
cd ..

/tools/Xilinx/Vivado/2023.2/bin/vivado -mode batch -nojournal -nolog -source vivado/program.tcl

ls /dev/ttyUSB*
python3 host/load.py --port /dev/ttyUSB1
```

- **Serial port:** the board shows up as two ports, and the UART is usually the higher-numbered one. If the ping fails, press CPU_RESET and try the other. Your user needs to be in the `dialout` group.
- **Controls:** keyboard forwarding is Windows only, so play with the board's buttons and switches.

### Troubleshooting

| Symptom | What to check |
|---|---|
| `ping (is the board in the boot ROM? press CPU_RESET)` | Press CPU_RESET, check that LED7 is on, and check the COM port. |
| `could not open port` or access denied | Another program has the port open, such as an earlier `load.py` or a serial terminal. Close it. |
| `ModuleNotFoundError: serial` | Install pyserial (step 1). |
| Vivado can't find the board on Linux | Install the cable drivers once, as root, by running `data/xicom/cable_drivers/lin64/install_script/install_drivers/install_drivers` from the Vivado folder. Then reconnect the board. |
| LED15 stays off | DDR2 hasn't calibrated. Power cycle the board and program it again. |
| LED5 is on, or `too many errors` | Checksum errors on the USB link. Press CPU_RESET, reload, and try another cable or USB port. |
| OLED stays black | Check that the Pmod is in JB, then check the terminal for DOOM's startup messages. |
| Terminal freezes at startup, with no DOOM messages | Rebuild with `python sw\build.py doom --clean` and confirm the `Startup verified` line. See [docs/AUDIO_STARTUP_FIX.md](docs/AUDIO_STARTUP_FIX.md). |
| `missing ...boot.hex` | Do step 3 before step 4. |
| Vivado `Project 1-863`, or MIG generation hangs | Run `build.tcl` as in step 4 rather than opening an older project. See [docs/DDR_FIX_README.md](docs/DDR_FIX_README.md). |

### Go back to the base processor

The lab project works as usual on this branch. Open your local `project/project.xpr` (it isn't in git, so a fresh clone won't have it) and program the board from Vivado as normal. That replaces DOOM on the FPGA until you repeat step 5.

## Controls
| Board | DOOM |
|---|---|
| BTNU / BTND | forward / back (menu up/down) |
| BTNL / BTNR | turn left / right (strafe when SW1 is on) |
| BTNC | fire + Enter (use + Enter when SW0 is on) |
| SW2 (on) | run |
| SW15 / SW14 / SW13 (flip) | Esc (menu) / `y` / Tab (automap) |
| SW3..SW9 (flip) | weapons 1..7 |
| PC keyboard (load.py) | arrows, Ctrl fire, Space use, Enter, Esc, Shift run, Alt strafe, Tab, 1–7, Y/N |

7-segment: health (left) and ammo (right). Full-screen view, low detail (both set in `DG_Init`).

## Architecture
| Block | File | Notes |
|---|---|---|
| CPU | `../project/project.srcs/sources_1/imports` | The base processor, including mulhsu and **MemStall** (tied to 0 in the lab Wrapper) |
| Caches + boot ROM | `rtl\soc\memctl.v`, `dm_cache.v` | 8 KB I + 8 KB D, direct-mapped, 16 B lines, LUTRAM (async read: pipeline unchanged). D: write-through, no write-allocate, posted writes. MemStall from F/M registers only |
| MIG bridge | `rtl\soc\mig_bridge.v` | toggle handshake CPU (37.5 MHz) ↔ ui_clk (75 MHz), related clocks from one MMCM → no CDC |
| MMIO | `rtl\soc\mmio.v`, `uart.v` | Wrapper offsets; side effects only on commit; UART 1.5 Mbaud (37.5 MHz / 25, exact for the FT2232 too) + 512 B RX FIFO; OLED CTRL write re-arms auto-advance; PB[4:0]; counters 0xB0–0xBC |
| SoC | `rtl\soc\doom_soc.v` | board-independent |
| Top | `rtl\top\doom_top.v`, `vivado\doom_top.xdc` | MMCM 100→200 MHz, MIG (`ddr` IP copied from `ddr2_bringup`), MMCM ui_clk→37.5 MHz, OLED, 7-seg |

Memory map: boot ROM `0x0040_0000` (4 KB) · DDR2 `0x8000_0000` (128 MB: program, heap, stack top `0x86FF_0000`, WAD header `0x86FF_FFF0`, WAD `0x8700_0000`) · MMIO `0xFFFF_0000`.

## Software
- `sw\doom\doomgeneric_soc.c` — platform layer: 320×200 palette → RGB565 → nearest-neighbour 96×64 → OLED; ticks from CYCLECOUNT; buttons/switches/UART keys.
- `sw\common\syscalls.c` — newlib stubs; `doom1.wad` is a read-only in-memory file.
- `sw\boot\` — boot ROM loader (protocol in `boot.c`, host side `host\load.py`).
- `third_party\doomgeneric` (upstream, unmodified), `third_party\doom1.wad` (shareware v1.9).

## Simulation / verification
Build the instruction-set simulator first: `gcc -O2 -o iss\rv32sim.exe iss\rv32sim.c`.

Icarus Verilog can't run `sim\tb_soc.v` directly because it uses DPI for DDR2. If you write a testbench for it, zero `RegBank` and the cache arrays first, as the FPGA does at power-up. Otherwise `x` from unwritten registers spreads until the PC is unknown.

| Tool | Command |
|---|---|
| ISS (functional model, ~140 MIPS) | `iss\rv32sim.exe -wad third_party\doom1.wad -frames DIR -every 35 sw\build\doom\doom.elf` |
| Verilator SoC (RTL + MIG model, ~3.5 MHz) | `python sim\verilator\build.py` → `sim\verilator\tb_soc.exe -uartin STREAM` (boot ROM) or `--rom sw\boot\jump.hex --out tb_jump` → `tb_jump.exe prog.elf -wad ...` |
| Lockstep RTL vs ISS | `tb_jump.exe -trace t.trc ...` then `rv32sim.exe -rom sw\boot\jump.hex -check t.trc ...` |
| Frames → PNG sheet | `python tools\frames.py DIR` |
| Lint + yosys cell count | `python tools\rtl_check.py` |
| Loader byte stream for simulation | `python host\load.py --emit stream.bin [--prog X.bin --no-wad]` |

Results for the current core, in this repository:

- Vivado 2023.2 from a clean clone: timing met (WNS +1.312 ns, WHS +0.025 ns), 11,550 LUTs (18 %), 20 block RAMs.
- `project/project.srcs/sim_1/new/test_RV_muldiv_stall.v`: 6,400 mul/div checks pass with and without random MemStall.
- DOOM startup on the RTL with Icarus Verilog, through `M_Init`: 2.1 M register writes match the ISS, with no DDR2 model errors.
- Not yet checked on this core: riscv-tests, gameplay on the RTL, and a run on the board.

Results (2026-10-29, on the earlier copy of the core, before audio; see `docs/DOOM_SoC_Change_Log.docx`): riscv-tests 48/48 on ISS and on the RTL SoC; hello world through boot ROM + UART;
DOOM lockstep RTL = ISS for 7.57 M register writes; DOOM demo on RTL ≈ **24 fps** at 37.5 MHz
(1.54 M cycles/frame, MemStall 22 %).
