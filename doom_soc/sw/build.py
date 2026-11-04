#!/usr/bin/env python3
"""Build doom_soc software.

  python build.py doom          -> build/doom/doom.elf, doom.bin (load at 0x80000000)
  python build.py boot          -> build/boot/boot.elf, boot.hex (boot ROM image, $readmemh words)
  python build.py all
Options: -j N (parallel jobs), --clean
"""
import argparse, os, re, subprocess, sys, shutil, struct
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DG = os.path.join(ROOT, 'third_party', 'doomgeneric', 'doomgeneric')
BUILD = os.path.join(HERE, 'build')
COMMON = os.path.join(HERE, 'common')

CC = 'riscv-none-elf-gcc'
OBJCOPY = 'riscv-none-elf-objcopy'
SIZE = 'riscv-none-elf-size'
ARCH = ['-march=rv32im', '-mabi=ilp32']
CFLAGS = ARCH + ['-O2', '-g', '-mstrict-align', '-ffunction-sections', '-fdata-sections',
                 '-fno-common', '-Wall', '-Wno-unused', '-Wno-pointer-sign', '-Wno-format-truncation',
                 '-Wno-stringop-truncation', '-Wno-dangling-pointer', '-Wno-misleading-indentation',
                 '-Wno-format', '-Wno-implicit-function-declaration', '-Wno-int-conversion', '-Wno-incompatible-pointer-types',
                 '-std=gnu99']

DOOM_SRC = ('dummy am_map doomdef doomstat dstrings d_event d_items d_iwad d_loop d_main d_mode d_net '
            'f_finale f_wipe g_game hu_lib hu_stuff info i_cdmus i_endoom i_joystick i_scale i_sound '
            'i_system i_timer memio m_argv m_bbox m_cheat m_config m_controls m_fixed m_menu m_misc '
            'm_random p_ceilng p_doors p_enemy p_floor p_inter p_lights p_map p_maputl p_mobj p_plats '
            'p_pspr p_saveg p_setup p_sight p_spec p_switch p_telept p_tick p_user r_bsp r_data r_draw '
            'r_main r_plane r_segs r_sky r_things sha1 sounds statdump st_lib st_stuff s_sound tables '
            'v_video wi_stuff w_checksum w_file w_main w_wad z_zone w_file_stdc i_input i_video '
            'doomgeneric').split()


def run(cmd):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        print(' '.join(cmd))
        print(r.stdout)
        raise SystemExit(1)
    return r.stdout


def compile_all(jobs, outdir, srcs, extra):
    os.makedirs(outdir, exist_ok=True)
    def one(src):
        obj = os.path.join(outdir, os.path.splitext(os.path.basename(src))[0] + '.o')
        if os.path.exists(obj) and os.path.getmtime(obj) > os.path.getmtime(src) and \
           os.path.getmtime(obj) > os.path.getmtime(__file__):
            return obj
        out = run([CC] + CFLAGS + extra + ['-c', src, '-o', obj])
        if out.strip():
            print(out.strip())
        return obj
    with ThreadPoolExecutor(jobs) as ex:
        return list(ex.map(one, srcs))


def tohex(binfile, hexfile, words=None):
    data = open(binfile, 'rb').read()
    data += b'\0' * (-len(data) % 4)
    n = len(data) // 4
    if words is not None:
        if n > words:
            raise SystemExit(f'{binfile}: {n} words does not fit in {words}')
    with open(hexfile, 'w') as f:
        for i in range(n):
            f.write('%08x\n' % int.from_bytes(data[4*i:4*i+4], 'little'))
        if words is not None:
            for i in range(n, words):
                f.write('00000013\n' if False else '00000000\n')


def check_doom_entry(elf):
    """The serial loader jumps to DDR_BASE, not the ELF's entry address."""
    with open(elf, 'rb') as f:
        header = f.read(52)
    if len(header) < 52 or header[:6] != b'\x7fELF\x01\x01':
        raise SystemExit('Expected a little-endian ELF32 executable: ' + elf)
    entry = struct.unpack_from('<I', header, 24)[0]
    if entry != 0x80000000:
        raise SystemExit('Refusing unsafe image: ELF entry is 0x%08x; loader jumps to 0x80000000' % entry)
    print('Startup verified: _start / ELF entry = 0x80000000')


def build_doom(jobs):
    out = os.path.join(BUILD, 'doom')
    srcs = [os.path.join(DG, s + '.c') for s in DOOM_SRC]
    srcs += [os.path.join(HERE, 'doom', 'doomgeneric_soc.c'), os.path.join(HERE, 'doom', 'audio_soc.c'), os.path.join(COMMON, 'syscalls.c'),
             os.path.join(COMMON, 'crt0.S')]
    extra = ['-I', DG, '-I', COMMON, '-DCMAP256', '-DDOOMGENERIC_RESX=320', '-DDOOMGENERIC_RESY=200',
             '-DNORMALUNIX', '-D_DEFAULT_SOURCE', '-DSOC_AUDIO']
    objs = compile_all(jobs, os.path.join(out, 'obj'), srcs, extra)
    elf = os.path.join(out, 'doom.elf')
    run([CC] + ARCH + ['-nostartfiles', '-T', os.path.join(COMMON, 'link_doom.ld'),
                       '-Wl,--gc-sections', '-Wl,-Map,' + os.path.join(out, 'doom.map'), '-o', elf]
        + objs + ['-lm', '-lc', '-lgcc'])
    check_doom_entry(elf)
    run([OBJCOPY, '-O', 'binary', elf, os.path.join(out, 'doom.bin')])
    print(run([SIZE, elf]).strip())
    print('->', elf)


def build_boot(jobs):
    out = os.path.join(BUILD, 'boot')
    srcs = [os.path.join(HERE, 'boot', 'start.S'), os.path.join(HERE, 'boot', 'boot.c')]
    objs = compile_all(jobs, os.path.join(out, 'obj'), srcs, ['-Os', '-I', COMMON])
    elf = os.path.join(out, 'boot.elf')
    run([CC] + ARCH + ['-nostartfiles', '-nostdlib', '-T', os.path.join(HERE, 'boot', 'boot.ld'),
                       '-Wl,--gc-sections', '-Wl,-Map,' + os.path.join(out, 'boot.map'), '-o', elf] + objs + ['-lgcc'])
    run([OBJCOPY, '-O', 'binary', elf, os.path.join(out, 'boot.bin')])
    tohex(os.path.join(out, 'boot.bin'), os.path.join(out, 'boot.hex'), words=1024)
    print(run([SIZE, elf]).strip())
    print('->', os.path.join(out, 'boot.hex'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('what', choices=['doom', 'boot', 'all'])
    ap.add_argument('-j', type=int, default=os.cpu_count() or 4)
    ap.add_argument('--clean', action='store_true')
    a = ap.parse_args()
    if a.clean and os.path.isdir(BUILD):
        shutil.rmtree(BUILD)
    if a.what in ('doom', 'all'):
        build_doom(a.j)
    if a.what in ('boot', 'all'):
        build_boot(a.j)


if __name__ == '__main__':
    main()
