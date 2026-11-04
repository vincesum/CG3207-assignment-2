#!/usr/bin/env python3
"""Build the Verilator model of doom_soc (sim/tb_soc.v + sim/verilator/tb_main.cpp).

  python build.py [--rom HEXFILE] [--out NAME] [-j N]
Default ROM: sw/build/boot/boot.hex. Output: sim/verilator/<NAME>.exe (default tb_soc).
Uses OSS CAD Suite verilator_bin + MSYS2 mingw64 g++ (no make/perl needed).
"""
import argparse, glob, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CORE = os.path.join(ROOT, '..', 'project', 'project.srcs', 'sources_1', 'imports')
CORE_SRCS = [os.path.join(CORE, 'Asst_02', f + '.v') for f in ('ALU', 'Decoder', 'Extend', 'PC_Logic', 'ProgramCounter', 'RegFile', 'RV', 'Shifter')] + [os.path.join(CORE, 'Asst_03', 'MCycle.v')]
VROOT = r'C:\oss-cad-suite\share\verilator'
VBIN = r'C:\oss-cad-suite\bin\verilator_bin.exe'
GXX = r'C:\msys64\mingw64\bin\g++.exe'


def run(cmd, env=None):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
    if r.returncode != 0:
        print(' '.join(cmd))
        print(r.stdout[-6000:])
        raise SystemExit(1)
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--rom', default=os.path.join(ROOT, 'sw', 'build', 'boot', 'boot.hex'))
    ap.add_argument('--out', default='tb_soc')
    ap.add_argument('-j', type=int, default=os.cpu_count() or 8)
    a = ap.parse_args()

    env = dict(os.environ)
    env['VERILATOR_ROOT'] = VROOT
    env['PATH'] = r'C:\msys64\mingw64\bin;' + env['PATH']
    mdir = os.path.join(HERE, 'obj_' + a.out)
    os.makedirs(mdir, exist_ok=True)

    srcs = [os.path.join(ROOT, 'sim', 'tb_soc.v')]
    srcs += sorted(glob.glob(os.path.join(ROOT, 'rtl', 'soc', '*.v')))
    srcs += CORE_SRCS
    rom = os.path.abspath(a.rom).replace('\\', '/')
    out = run([VBIN, '--cc', '--top-module', 'tb_soc', '-Mdir', mdir, '--prefix', 'Vtb_soc',
               '-O3', '--x-assign', 'fast', '--x-initial', 'fast', '--noassert',
               '-Wno-fatal', '-Wno-lint', '-Wno-style', '-Wno-MULTIDRIVEN', '-Wno-UNOPTFLAT',
               '-Wno-TIMESCALEMOD', '-Wno-INITIALDLY', '-Wno-BLKANDNBLK',
               f'-GROM_FILE="{rom}"'] + srcs, env)
    warn = [l for l in out.splitlines() if l.startswith('%Warning') or l.startswith('%Error')]
    for l in warn[:20]:
        print(l)

    cpps = sorted(glob.glob(os.path.join(mdir, 'Vtb_soc*.cpp')))
    cpps += [os.path.join(HERE, 'tb_main.cpp')]
    cpps += [os.path.join(VROOT, 'include', f) for f in ('verilated.cpp', 'verilated_dpi.cpp', 'verilated_threads.cpp')]
    flags = ['-O2', '-std=c++17', '-I', mdir, '-I', os.path.join(VROOT, 'include'),
             '-I', os.path.join(VROOT, 'include', 'vltstd'), '-DVM_TRACE=0', '-Wno-attributes']

    def cc(src):
        obj = os.path.join(mdir, os.path.basename(src) + '.o')
        if os.path.exists(obj) and os.path.getmtime(obj) > os.path.getmtime(src):
            return obj
        run([GXX] + flags + ['-c', src, '-o', obj], env)
        return obj
    with ThreadPoolExecutor(a.j) as ex:
        objs = list(ex.map(cc, cpps))
    exe = os.path.join(HERE, a.out + '.exe')
    run([GXX, '-o', exe] + objs + ['-static', '-pthread'], env)
    print('->', exe)


if __name__ == '__main__':
    main()
