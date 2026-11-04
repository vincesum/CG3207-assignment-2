# Audio startup freeze fix

## Confirmed cause

The working executable has _start and ELF entry 0x80000000. The failing executable has _start and ELF entry 0x80000048. Its map shows audio_soc.o contributing 0x48 bytes of .text.init at 0x80000000, followed by crt0.o at 0x80000048.

GCC -ffunction-sections places a function named init in .text.init. The original startup assembly also used .text.init. The linker collected the audio initializer before startup because audio_soc.o precedes crt0.o in the link command. ENTRY(_start) sets ELF metadata; it does NOT ensure _start is physically at RAM base. host/load.py loads a raw binary and always jumps to 0x80000000, ignoring ELF entry metadata.

The audio initializer was therefore entered before initializing gp/sp. Disabling sound with -nosound cannot fix this: the failure occurs before main.

## Changes

* common/crt0.S: use a dedicated .text.boot.entry section.
* common/link_doom.ld: retain that section first, and ASSERT(_start == ORIGIN(RAM)).
* doom/audio_soc.c: rename init to audio_init to avoid the section-name collision as well.
* doom/doomgeneric_soc.c: remove the diagnostic -nosound flag and restore argc=3.
* build.py: reject a Doom/app ELF whose entry is not 0x80000000 before exporting the binary.

No FPGA rebuild or loader modification is required for this fix. Keep the audio bitstream that already runs the old software.

## Install and run

Back up your current sw folder. Extract this archive into the project root, so the supplied sw folder replaces/merges with the existing sw folder. Keep the project third_party directory and its patched Doom sound dispatcher from the audio project.

From that project root:

```
python sw\build.py doom --clean
```

Expected confirmation:

```
Startup verified: _start / ELF entry = 0x80000000
```

The archive retains the previously uploaded build outputs for reference; those binaries are NOT corrected. You MUST run the clean rebuild before loading. --clean removes the build folder, including boot outputs; the already programmed FPGA boot ROM is unaffected. If rebuilding FPGA hardware later, first run python sw\build.py all --clean.

Exit the old host keyboard session with F12, press CPU_RESET on the board, then:

```
python host\load.py --port COM7
```

The normal Doom startup banner should appear. Sound effects are enabled; music remains unsupported. If Doom starts but no sound is audible, verify the existing FPGA audio path with the supplied audio_test app before changing hardware.

## Validation and limits

* Inspected both user-supplied ELF/map files and confirmed the exact section collision.
* Ran the supplied failing ELF in the project's instruction simulator, overriding its entry to the loader's fixed 0x80000000: invalid store at PC 0x8000000c after three instructions (address 0x00000280).
* Running the same supplied ELF at its declared 0x80000048 entry reaches Doom initialization, isolating the entry mismatch. That executable contains the user's -nosound diagnostic flag; this run does not validate sound playback.
* The new build check accepts the supplied working ELF and rejects the supplied failing ELF.
* Exercised the corrected linker section order with native assembler/linker fixtures (host architecture substituted), deliberately putting a competing .text.init object first: _start remains at RAM base. This checks section placement, not RISC-V execution.
* Python compilation and audio-backend C syntax checks passed.

A RISC-V cross compiler and FPGA board are unavailable here, so the corrected source has not been cross-built or played on hardware in this environment. Rebuild with your existing compiler using the commands above.
