"""Generate the program and expected results for test_RV_muldiv_stall.v on the master branch.

  python gen_muldiv_stall.py <output dir>
"""
import os,random,sys
random.seed(3207); M=0xffffffff
def s(x): return x-(1<<32) if x>>31 else x
def tdiv(a,b):
    q=abs(a)//abs(b); return -q if (a<0)!=(b<0) else q
def gold(op,a,b):
    sa,sb=s(a),s(b)
    if op=='mul': return (a*b)&M
    if op=='mulh': return ((sa*sb)>>32)&M
    if op=='mulhsu': return ((sa*b)>>32)&M
    if op=='mulhu': return ((a*b)>>32)&M
    if op=='div': return M if b==0 else tdiv(sa,sb)&M
    if op=='divu': return M if b==0 else a//b
    if op=='rem': return a if b==0 else (sa-sb*tdiv(sa,sb))&M
    if op=='remu': return a if b==0 else a%b
F3=dict(mul=0,mulh=1,mulhsu=2,mulhu=3,div=4,divu=5,rem=6,remu=7)
def R(op,rd,a,b): return (1<<25)|(b<<20)|(a<<15)|(F3[op]<<12)|(rd<<7)|0x33
def add(rd,a,b): return (b<<20)|(a<<15)|(rd<<7)|0x33
def addi(rd,a,i): return ((i&0xfff)<<20)|(a<<15)|(rd<<7)|0x13
def lui(rd,i): return (i<<12)|(rd<<7)|0x37
def sw(r,o): return ((o>>5)<<25)|(r<<20)|(2<<12)|((o&31)<<7)|0x23
def li(r,v):
    hi=((v+0x800)>>12)&0xfffff; lo=v&0xfff
    return [lui(r,hi),addi(r,r,lo-0x1000 if lo>=0x800 else lo)]
C=[0,1,2,M,0x80000000,0x7fffffff,0xfffffffe,0x80000001,0x55555555,0xaaaaaaaa]
pairs=[(a,b) for a in C for b in C]+[(random.getrandbits(32),random.getrandbits(32)) for _ in range(60)]
prog=[];exp=[]
def chk(reg,val,tag): prog.append(sw(reg,0x100)); exp.append((tag,val))
for op in F3:
    for a,b in pairs:
        prog+=li(5,a)+li(6,b)
        prog.append(R(op,7,5,6)); chk(7,gold(op,a,b),op)           # forwarded operands, result to store
        prog.append(R(op,8,5,6)); prog.append(add(9,8,5)); chk(9,(gold(op,a,b)+a)&M,op+'+fwd')   # result to ALU
        prog.append(sw(5,0x100)); exp.append(('sw-before',a)); prog.append(R(op,10,6,5)); chk(10,gold(op,b,a),op)  # store in M during start
        prog.append(R(op,11,5,6)); prog.append(R(op,12,11,6)); chk(12,gold(op,gold(op,a,b),b),op+'+chain')  # back to back
prog.append(0x0000006f)      # spin at the end
out=sys.argv[1]
open(os.path.join(out,'test_RV_muldiv_stall_prog.mem'),'w').write('\n'.join('%08x'%x for x in prog)+'\n')
open(os.path.join(out,'test_RV_muldiv_stall_exp.mem'),'w').write('\n'.join('%08x'%e[1] for e in exp)+'\n')
print('instructions',len(prog),'checks',len(exp))
