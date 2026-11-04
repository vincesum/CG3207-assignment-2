# doom_soc

The hardware on `master` has no game in it, and its DDR2 memory is empty after programming. This folder holds DOOM and the script that sends it to the SoC over USB. To run it, follow the [main README](../README.md).

## What's here

| Path | What it is |
|---|---|
| `host/load.py` | Runs on your PC and sends DOOM to the board |
| `prebuilt/doom.bin` | DOOM, compiled for our processor |
| `third_party/doom1.wad` | The game's data: levels, graphics and sounds |
| `sw/`, `third_party/doomgeneric/` | Source code for `doom.bin`, and for the boot ROM on `master` |

## How DOOM gets onto the SoC

```
PC: load.py ──USB (1.5 Mbaud)──> boot ROM ──data cache──> DDR2
                                    │
                                    └── jumps to DOOM ──instruction cache──> runs from DDR2
```

1. **The boot ROM waits.** The only code built into the bitstream is a small boot ROM, which the CPU runs first. It waits for commands over USB. LED7 shows it's waiting.
2. **`load.py` checks the connection.** It sends a ping and expects a reply from the boot ROM.
3. **`load.py` sends the data, in 32 KB chunks.** The boot ROM checks each chunk's checksum, and `load.py` tries a failed chunk up to three times. It sends these in order:

   | Data | DDR2 address |
   |---|---|
   | `doom1.wad` | `0x8700_0000` |
   | WAD header (a marker, the length and the address) | `0x86FF_FFF0` |
   | `doom.bin` | `0x8000_0000` |

4. **The boot ROM stores it.** Each word it receives is a normal CPU store, which goes through the data cache to DDR2.
5. **The boot ROM jumps to DOOM.** `load.py` sends a jump command, and the CPU continues at `0x8000_0000`. The first fetches miss the instruction cache, so the code comes from DDR2.
6. **DOOM finds its data.** DOOM asks to open `doom1.wad` as if it were a file. `sw/common/syscalls.c` uses the header to find it in DDR2.

After that, `load.py` shows DOOM's messages on your terminal. On Windows, it also forwards your keyboard to the game.

DDR2 keeps its contents through CPU_RESET, so `--skip-wad` reloads only `doom.bin`. Programming the board or turning it off clears it, so everything has to be sent again.

## Rebuilding DOOM

You only need this if you change the code. With the [xPack RISC-V toolchain](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases) on your `PATH`, run this from `doom_soc`:

```
python3 sw/build.py all --clean
```

`load.py` then uses `sw/build/doom/doom.bin` instead of the prebuilt one.
