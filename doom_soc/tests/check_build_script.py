"""Structural Tcl test with mocked Vivado commands; NOT a Vivado execution."""
from pathlib import Path
import tkinter
root = Path(__file__).resolve().parents[2]
tcl = tkinter.Tcl()
src = (root/'soc_build/build.tcl').read_text()
assert tcl.call('info','complete',src) == 1
calls = []
def command(name):
    def run(*args):
        calls.append((name,args))
        if name == 'version': return '2018.2'
        if name == 'get_files': return args[-1]
        return ''
    return run
for name in ['create_project','set_property','add_files','get_files','current_project',
             'current_fileset','update_compile_order','version']:
    tcl.createcommand(name,command(name))
tcl.eval('set argv {}')
tcl.eval('proc launch_runs {args} {error BUILD_TEST_STOP_BEFORE_SYNTHESIS}')
try: tcl.call('source',str(root/'soc_build/build.tcl'))
except tkinter.TclError as e:
    assert 'BUILD_TEST_STOP_BEFORE_SYNTHESIS' in str(e), str(e)
else: raise AssertionError('did not reach synthesis')
added = [a[-1] for n,a in calls if n == 'add_files']
assert any(p.endswith('/rtl/ddr_mig.v') for p in added)
assert not any(p.endswith('.dcp') or p.endswith('ddr_mig_sim.v') for p in added)
assert any(p.endswith('constraints/ddr.xdc') for p in added)
assert not any(p.endswith('.xci') for p in added)
assert '\ngenerate_target ' not in src and '\nupgrade_ip ' not in src
assert any(n=='set_property' and a[:2]==('SCOPED_TO_REF','ddr') for n,a in calls)
print('Tcl syntax and pre-synthesis setup checks passed (Vivado commands mocked).')
