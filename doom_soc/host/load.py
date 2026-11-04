#!/usr/bin/env python3
"""Load a program (and the DOOM WAD) into doom_soc over the USB-UART, then run it.

  python load.py --port COM5                       # doom.bin + doom1.wad, then keyboard mode
  python load.py --port COM5 --prog app.bin --no-wad
  python load.py --port COM5 --skip-wad            # WAD already in DDR2 (after a CPU reset)
  python load.py --emit stream.bin ...             # write the byte stream for simulation instead

Needs pyserial (python -m pip install --user pyserial). 1.5 Mbaud, 8N1.
Board side: sw/boot/boot.c (boot ROM). Press the red CPU_RESET button before loading.

Keyboard mode (after the jump, Windows only): arrows move/turn, Ctrl fire, Space use,
Enter, Esc, Shift run, Alt strafe, Tab map, 1-7 weapons, Y/N. Uses GetAsyncKeyState,
so it works without focus; press F12 to quit. UART output from the board is printed.
"""
import argparse, os, struct, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEF_PROG = os.path.join(ROOT, 'sw', 'build', 'doom', 'doom.bin')
if not os.path.exists(DEF_PROG):
    DEF_PROG = os.path.join(ROOT, 'prebuilt', 'doom.bin')
DEF_WAD = os.path.join(ROOT, 'third_party', 'doom1.wad')
PROG_ADDR = 0x80000000
WAD_HDR = 0x86FFFFF0
WAD_DATA = 0x87000000
WAD_MAGIC = 0x31444157
CHUNK = 32768


def fast_checksum(data):
    # Board computes s1 += b; s2 += s1 (32-bit). Closed form: s1 = sum(b_i), s2 = sum((n - i) * b_i).
    n = len(data)
    s1 = sum(data) & 0xFFFFFFFF
    s2 = 0
    w = n
    for b in data:
        s2 += w * b
        w -= 1
    return s1, s2 & 0xFFFFFFFF


class Link:
    def __init__(self, port=None, baud=1500000, emit=None):
        self.emit = open(emit, 'wb') if emit else None
        self.ser = None
        if not self.emit:
            import serial
            self.ser = serial.Serial(port, baud, timeout=2)
            self.ser.reset_input_buffer()

    def write(self, b):
        if self.emit:
            self.emit.write(b)
        else:
            self.ser.write(b)

    def expect_ack(self, what):
        if self.emit:
            return
        r = self.ser.read(1)
        if r != b'K':
            raise SystemExit(f'{what}: expected K, got {r!r}')

    def close(self):
        if self.emit:
            self.emit.close()


def load(link, addr, data, label):
    t0 = time.time()
    total = len(data)
    for off in range(0, total, CHUNK):
        part = data[off:off + CHUNK]
        s1, s2 = fast_checksum(part)
        for attempt in range(3):
            link.write(b'L' + struct.pack('<II', addr + off, len(part)) + part + struct.pack('<II', s1, s2))
            if link.emit:
                break
            r = link.ser.read(1)
            if r == b'K':
                break
            print(f'\n  chunk at {addr + off:08x}: got {r!r}, retrying')
        else:
            raise SystemExit('too many errors')
        if not link.emit:
            done = off + len(part)
            el = time.time() - t0
            print(f'\r  {label}: {done/1024:8.0f} / {total/1024:.0f} KB  {done/max(el,1e-3)/1024:6.0f} KB/s', end='', flush=True)
    if not link.emit:
        print()


KEYMAP = {  # Windows virtual key -> DOOM key code (doomkeys.h)
    0x26: 0xAD, 0x28: 0xAF, 0x25: 0xAC, 0x27: 0xAE,          # arrows
    0x11: 0xA3, 0x20: 0xA2, 0x0D: 13, 0x1B: 27,             # Ctrl fire, Space use, Enter, Esc
    0x10: 0x80 + 0x36, 0x12: 0x80 + 0x38, 0x09: 9,          # Shift run, Alt strafe, Tab map
    0x59: ord('y'), 0x4E: ord('n'), 0xBC: 0xA0, 0xBE: 0xA1,  # Y, N, ',' '.' strafe
    0xBB: ord('='), 0xBD: ord('-'),
}
for d in range(1, 8):
    KEYMAP[0x30 + d] = ord('0') + d


def keyboard(link):
    import ctypes
    gaks = ctypes.windll.user32.GetAsyncKeyState
    state = {vk: False for vk in KEYMAP}
    print('Keyboard mode: F12 quits. Board output follows.')
    link.ser.timeout = 0
    while True:
        out = link.ser.read(4096)
        if out:
            sys.stdout.write(out.decode('latin-1').replace('\r', ''))
            sys.stdout.flush()
        if gaks(0x7B) & 0x8000:                    # F12
            break
        for vk, key in KEYMAP.items():
            down = bool(gaks(vk) & 0x8000)
            if down != state[vk]:
                state[vk] = down
                link.write(bytes([0xE0 if down else 0xE1, key]))
        time.sleep(0.01)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--port', help='COM port of the Nexys 4 DDR USB-UART')
    ap.add_argument('--baud', type=int, default=1500000)
    ap.add_argument('--prog', default=DEF_PROG, help='raw binary for 0x80000000 (objcopy -O binary)')
    ap.add_argument('--wad', default=DEF_WAD)
    ap.add_argument('--no-wad', action='store_true', help='do not load a WAD')
    ap.add_argument('--skip-wad', action='store_true', help='WAD is already in DDR2')
    ap.add_argument('--no-keys', action='store_true', help='just print board output after the jump')
    ap.add_argument('--emit', help='write the byte stream to a file (simulation) instead of a port')
    a = ap.parse_args()
    if not a.emit and not a.port:
        ap.error('--port or --emit is required')

    link = Link(a.port, a.baud, a.emit)
    if not a.emit:
        link.ser.read(4096)                        # drop the boot banner if any
    link.write(b'P')
    link.expect_ack('ping (is the board in the boot ROM? press CPU_RESET)')

    if not a.no_wad and not a.skip_wad:
        wad = open(a.wad, 'rb').read()
        load(link, WAD_DATA, wad, os.path.basename(a.wad))
        load(link, WAD_HDR, struct.pack('<IIII', WAD_MAGIC, len(wad), WAD_DATA, 0), 'WAD header')
    prog = open(a.prog, 'rb').read()
    load(link, PROG_ADDR, prog, os.path.basename(a.prog))
    link.write(b'J' + struct.pack('<I', PROG_ADDR))
    link.expect_ack('jump')
    if a.emit:
        link.close()
        print('wrote', a.emit)
        return
    print('running')
    if a.no_keys or os.name != 'nt':
        link.ser.timeout = 0.1
        while True:
            out = link.ser.read(4096)
            if out:
                sys.stdout.write(out.decode('latin-1').replace('\r', ''))
                sys.stdout.flush()
    else:
        keyboard(link)


if __name__ == '__main__':
    main()
