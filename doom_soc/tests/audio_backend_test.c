#include <assert.h>
#include <stdint.h>
#include <string.h>
#define DOOM_SOC_H
#define CPU_HZ 37500000u
static volatile uint32_t registers[64];
#define MMIO(off) registers[(off)/4]
#include "../sw/doom/audio_soc.c"
static uint8_t lumpdata[20040];
static int lump_size, cache_calls;
int W_GetNumForName(char *name) { assert(strcmp(name,"dspistol")==0); return 1; }
int W_LumpLength(unsigned int lump) { (void)lump; return lump_size; }
void *W_CacheLumpNum(int lump,int tag) { (void)lump;(void)tag;cache_calls++;return lumpdata; }
void Z_ChangeTag2(void *ptr,int tag,char *file,int line) {
    (void)tag;(void)file;(void)line; assert(ptr==lumpdata);
}
static void make_lump(uint32_t n) {
    memset(lumpdata,128,sizeof(lumpdata));
    lumpdata[0]=3;lumpdata[1]=0;lumpdata[2]=0x11;lumpdata[3]=0x2b;
    for(int i=0;i<4;i++) lumpdata[4+i]=(n>>(8*i))&255;
    lump_size=n+8;
}
int main(void) {
    sfxinfo_t sfx={0}; strcpy(sfx.name,"pistol");sfx.lumpnum=1;
    assert(audio_init(true));assert(lumpnum(&sfx)==1);
    make_lump(1032);
    assert(start(&sfx,0,127,128)==0);
    assert(MMIO(LENGTH)==1000 && MMIO(COMMAND)==1);
    assert(MMIO(STEP)==(uint32_t)(((uint64_t)11025<<32)/CPU_HZ));
    assert(start(&sfx,0,70,0)==0 && cache_calls==1);
    assert(MMIO(VOLUME)==70);
    make_lump(20032);
    assert(start(&sfx,1,200,0)==1 && MMIO(LENGTH)==8192);
    assert(MMIO(VOLUME)==127);
    assert(MMIO(STEP)==(uint32_t)((((uint64_t)11025<<32)*8192/20000)/CPU_HZ));
    MMIO(STATUS)=2;assert(playing(1));assert(!playing(0));
    assert(start(&sfx,8,127,0)==-1);assert(!playing(-1));
    make_lump(1032);lumpdata[0]=0;assert(start(&sfx,2,127,0)==-1);
    make_lump(1032);lump_size=100;assert(start(&sfx,2,127,0)==-1);
    stop(1);assert(MMIO(COMMAND)==0);
    shutdown_audio();puts("audio backend: all assertions passed");return 0;
}
