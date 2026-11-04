# DOOM on our RISC-V processor

Run DOOM on a Nexys A7 using the RISC-V processor and hardware from the `master` branch. This branch adds the game itself. The game shows on a small OLED display and you play with the board's buttons.

## What you need

- Nexys A7-100T board and its USB cable. The 50T version won't work.
- PmodOLEDrgb display plugged into port **JB**
- Vivado
- Python 3 and Git
- Optional: speakers or headphones on the audio jack, for sound effects

## 1. Get the code

```
git clone --branch doom https://github.com/vincesum/CG3207-assignment-2.git
cd CG3207-assignment-2
```

## 2. Generate the bitstream

1. Open Vivado, without opening a project.
2. Choose **Tools > Run Tcl Script**, then select `soc_build/build.tcl`.
3. Wait for it to finish. This can take several minutes, and Vivado may look frozen while it runs.

The bitstream is saved as `soc_build/soc_top.bit`.

## 3. Program the board

1. Plug the display into JB, then connect the board over USB and turn it on. The display must be plugged in before you program the board.
2. In Vivado, choose **Flow > Open Hardware Manager**.
3. Click **Open target > Auto Connect**.
4. Click **Program device**, select `soc_build/soc_top.bit`, and click **Program**.

Once it's programmed, LED15 and LED14 should be on.

## 4. Load DOOM

From the repository folder, run these commands in a terminal.

**Linux**

```
python3 -m pip install --user pyserial
python3 -m serial.tools.list_ports
python3 doom_soc/host/load.py --port /dev/ttyUSB1
```

**Windows**

```
python -m pip install --user pyserial
python -m serial.tools.list_ports
python doom_soc/host/load.py --port COM4
```

The second command lists the serial ports. Use the board's port in the third command in place of `/dev/ttyUSB1` or `COM4`.

Loading takes about 40 seconds, and then DOOM starts on the display. On Linux, press **Ctrl+C** to get your terminal back; DOOM keeps running.

## 5. Play

| Control | Action |
|---|---|
| BTNU / BTND | Move forward / back, or move through the menu |
| BTNL / BTNR | Turn left / right |
| BTNC | Fire, or select in the menu |
| Flip SW15 | Open the menu |
| Flip SW14 | Answer yes (`y`) |
| Flip SW13 | Show the map |
| Flip SW3 to SW9 | Choose weapons 1 to 7 |
| SW0 on | BTNC opens doors instead of firing |
| SW1 on | BTNL / BTNR strafe instead of turning |
| SW2 on | Run |

To start a game, flip SW15, then select **New Game**, an episode and a skill level with BTNU, BTND and BTNC.

On Windows you can also play from the keyboard while `load.py` is running. Use the arrow keys to move, Ctrl to fire, Space to open doors, Enter to select and Esc for the menu. Press F12 to stop using the keyboard.

To restart, press the red **CPU_RESET** button and run the `load.py` command again. After turning the board off, repeat from step 3.

## If something goes wrong

| Problem | Try this |
|---|---|
| `ping (is the board in the boot ROM?...)` | Press CPU_RESET and run `load.py` again. If that fails, try the other serial port from the list. |
| Can't open the serial port | Close anything else using it, such as an earlier `load.py`. On Linux, your user needs to be in the `dialout` group. |
| The Tcl script stops straight away | Close any open project in Vivado and run it again. |
| Vivado can't find the board | Check the USB cable and that the board is on. You may need to install Vivado's cable drivers. |
| The display stays black | Check that the display is fully seated in JB, using both rows of pins. If you plugged it in after programming, press CPU_RESET and run `load.py` again. |

The technical details are in [doom_soc/README.md](doom_soc/README.md).
