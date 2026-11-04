> **Note:** this page describes the project before the hardware moved to the `master` branch. The bitstream is now built with `soc_build/build.tcl`; see [the README](../README.md) for current steps.

# Doom audio addition

This source update adds eight-channel mono sound effects through the Nexys 4 DDR / Nexys A7 J8 3.5 mm audio output. Music is not implemented.

IMPORTANT: the pre-existing doom_top.bit, doom.bin, doom.elf, Vivado project and simulation binaries in this archive are from the original upload. They do not contain audio. Rebuild both software and FPGA hardware using the commands below. Do not program the old bitstream or simply rerun implementation on the old project.

## Build and run (Windows, from doom_soc)

Use the same RISC-V compiler and Vivado installation as the original project.

```
python sw\build.py all --clean
cd vivado
C:\Xilinx\Vivado\2018.2\bin\vivado.bat -mode batch -nojournal -log build_audio.log -source build.tcl
cd ..
```

Close an already-open Vivado project before rebuilding. The updated build.tcl uses the original generated DDR synthesis RTL and original DDR XDC directly; it imports no XCI or DCP and does not invoke MIG generation. See DDR_FIX_README.md. The script automatically discovers the new rtl/soc/doom_audio.v file and recreates the project. Check the generated timing and utilization reports: this addition allocates 64 KiB of sample block RAM plus mixer/control logic. Hardware fit and timing have not been verified here.

Program the NEW vivado/doom_top.bit using Hardware Manager. Connect speakers/headphones to J8, start with low game sound volume, then use the normal loader (replace COM4 with your board's port):

```
python host\load.py --port COM4
```

The original Doom sound menu controls effect volume. Normal gameplay triggers gunshots, doors, monsters and other effects. Output is mono: stereo positioning is unavailable, but Doom's volume attenuation with distance is retained.

## Standalone jack test

After programming the new bitstream, build and load a repeating approximately 440 Hz tone:

```
python sw\build.py app audio_test
python host\load.py --port COM4 --prog sw\build\apps\audio_test\audio_test.bin --no-wad
```

Press CPU_RESET and run the normal loader afterwards to return to Doom.

## Implementation

* rtl/soc/doom_audio.v: eight independent unsigned 8-bit PCM voices, synchronous block RAM, per-voice phase accumulator, volume, mixer and 8-bit PWM. Playback runs without CPU polling or interrupts, including during rendering stalls.
* rtl/soc/mmio.v: audio register decoding; writes use the existing commit gating to prevent repeated writes during CPU stalls.
* rtl/soc/doom_soc.v and rtl/top/doom_top.v: audio signal routing. AUD_PWM is open drain (0/Z); AUD_SD enables the output stage outside CPU reset.
* vivado/doom_top.xdc: A11 AUD_PWM and D12 AUD_SD.
* sw/doom/audio_soc.c: Doom sound backend; validates DMX format-3 lumps, removes DMX end padding, uploads samples and configures playback.
* sw/build.py and third_party/doomgeneric/doomgeneric/i_sound.[ch]: SOC_AUDIO build integration, separate from the upstream SDL backend. No SDL dependency or music backend is introduced.
* sw/tests/audio_test.c: repeating tone test.

Each voice holds 8192 samples. Sounds longer than this are reduced to 8192 samples using nearest-neighbour downsampling, with playback rate adjusted to preserve duration. This reduces quality and may alias on long sounds. Sound data is uploaded when a channel switches to a different effect; repeated instances on the same channel reuse its RAM. Uploads may cause a brief CPU pause. Eight voices match Doom's existing default channel count; do not increase snd_channels above eight. The mixer reserves headroom for all eight voices, so individual effects are comparatively quiet.

MMIO addresses below are offsets from 0xFFFF0000. Registers operate on the selected voice, except STATUS.

| Offset | Register | Meaning |
|---|---|---|
| C0 | SELECT | voice 0..7 |
| C4 | UPLOAD | sample upload index 0..8191 |
| C8 | DATA | low byte written to RAM; index increments; writes ignored during playback |
| CC | LENGTH | sample count, capped at 8192 |
| D0 | STEP | sample rate * 2^32 / 37500000 |
| D4 | VOLUME | 0..127, clamped |
| D8 | COMMAND | 0 stops, 1 starts/restarts from sample zero |
| DC | STATUS | read-only active-channel bitmap |

Stop a voice before uploading; configure all registers before starting it. RAM is intentionally not reset to allow block RAM inference. Never start a voice before uploading its samples. Changing the CPU clock requires updating CPU_HZ in software and the existing top-level clock setup.

## Validation

Executed here: native GCC backend tests with -Wall -Wextra -Werror (all assertions passed), C syntax checks for the backend, Doom sound dispatcher and tone test, and Python build-script compilation. Tests cover valid/invalid DMX data, short/long playback rates, reuse of uploaded samples, volume bounds, channel status and invalid channels.

Not executed here: RTL simulation, RISC-V cross compilation, Vivado synthesis/implementation, resource/timing closure or on-board audio. This is an implementation requiring those checks, not a tested bitstream.

Re-run the backend tests with a native GCC toolchain:

```
gcc -std=gnu99 -Wall -Wextra -Werror -I third_party/doomgeneric/doomgeneric -I sw/common tests/audio_backend_test.c -o audio_backend_test
./audio_backend_test
```

An RTL testbench is included for Icarus Verilog:

```
iverilog -g2005-sv -s tb_audio -o audio_test.vvp ../project/project.srcs/sources_1/soc/io/soc_audio.v ../project/project.srcs/sim_1/new/test_soc_audio.v
vvp audio_test.vvp
```

It checks reset, upload, sample progression, automatic/explicit stop, zero-length rejection and channel independence. The original ISS and frame simulation do not render or validate audio; use this testbench and the board tone test.
