#!/usr/bin/env python3
"""Quick RTL checks for doom_soc with the OSS CAD Suite:
   1. iverilog -g2005 compile of doom_soc (Icarus is stricter than Vivado)
   2. yosys synth_xilinx of doom_soc -> cell counts (LUT/LUTRAM/FF/CARRY/DSP)
   python tools/rtl_check.py [--no-yosys]"""
import glob, os, subprocess, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = r'C:\oss-cad-suite\bin'
CORE = os.path.join(ROOT, '..', 'project', 'project.srcs', 'sources_1', 'imports')
CORE_SRCS = [os.path.join(CORE, 'Asst_02', f + '.v') for f in ('ALU', 'Decoder', 'Extend', 'PC_Logic', 'ProgramCounter', 'RegFile', 'RV', 'Shifter')] + [os.path.join(CORE, 'Asst_03', 'MCycle.v')]
SRCS = sorted(glob.glob(os.path.join(ROOT, 'rtl', 'soc', '*.v'))) + CORE_SRCS
ROM = os.path.join(ROOT, 'sw', 'build', 'boot', 'boot.hex').replace('\\', '/')


def main():
    tmp = os.path.join(ROOT, 'build_rtl')
    os.makedirs(tmp, exist_ok=True)
    r = subprocess.run([os.path.join(BIN, 'iverilog.exe'), '-g2005', '-Wall', '-s', 'doom_soc',
                        '-o', os.path.join(tmp, 'lint.vvp')] + SRCS, capture_output=True, text=True)
    msgs = [l for l in (r.stdout + r.stderr).splitlines() if 'sensitive to all' not in l and 'timescale' not in l and l.strip()]
    print('iverilog: exit', r.returncode)
    for l in msgs[:30]:
        print('  ' + l)
    if '--no-yosys' in sys.argv:
        return
    script = 'read_verilog ' + ' '.join(s.replace('\\', '/') for s in SRCS) + '; '
    script += f'chparam -set ROM_FILE "{ROM}" doom_soc; synth_xilinx -top doom_soc -family xc7 -flatten; tee -o yosys_stat.txt stat'
    env = dict(os.environ)
    env['PATH'] = BIN + ';' + os.path.join(os.path.dirname(BIN), 'lib') + ';' + env['PATH']
    r = subprocess.run([os.path.join(BIN, 'yosys.exe'), '-q', '-p', script], capture_output=True, text=True, env=env,
                       cwd=os.path.dirname(ROM))          # default ROM_FILE "boot.hex" resolves here
    out = r.stdout + r.stderr
    statf = os.path.join(os.path.dirname(ROM), 'yosys_stat.txt')
    if os.path.exists(statf):
        out += open(statf).read()
    print('yosys: exit', r.returncode)
    keep = ('LUT', 'RAM', 'FD', 'CARRY', 'DSP', 'MUXF', 'Number of cells', 'ERROR', 'Warning')
    for l in out.splitlines():
        if any(k in l for k in keep):
            print('  ' + l.strip())


if __name__ == '__main__':
    main()
