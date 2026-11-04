// Bare-metal Doom SFX backend. Playback/mixing lives in FPGA BRAM.
#include <stdint.h>
#include <stdio.h>
#include "doomtype.h"
#include "i_sound.h"
#include "w_wad.h"
#include "z_zone.h"
#include "doom_soc.h"
#define SELECT 0xC0
#define UPLOAD 0xC4
#define DATA   0xC8
#define LENGTH 0xCC
#define STEP   0xD0
#define VOLUME 0xD4
#define COMMAND 0xD8
#define STATUS 0xDC
#define VOICES 8
#define CAPACITY 8192u
static boolean prefix;
static int cached[VOICES];
static uint32_t lengths[VOICES], steps[VOICES];
static snddevice_t devices[] = { SNDDEVICE_SB };
static void stop(int c) {
    if (c<0 || c>=VOICES) return;
    MMIO(SELECT)=c; MMIO(COMMAND)=0;
}
static boolean audio_init(boolean use_prefix) {
    prefix=use_prefix;
    for(int c=0;c<VOICES;c++) { stop(c); cached[c]=-1; }
    return true;
}
static void shutdown_audio(void) { for(int c=0;c<VOICES;c++) stop(c); }
static int lumpnum(sfxinfo_t *sfx) {
    char name[16];
    if(sfx->link) sfx=sfx->link;
    snprintf(name,sizeof(name),"%s%s",prefix ? "ds" : "",sfx->name);
    return W_GetNumForName(name);
}
static void params(int c,int vol,int sep) {
    (void)sep; // Jack is mono; retain Doom's distance attenuation.
    if(c<0 || c>=VOICES) return;
    if(vol<0) vol=0;
    if(vol>127) vol=127;
    MMIO(SELECT)=c; MMIO(VOLUME)=vol;
}
static int start(sfxinfo_t *sfx,int c,int vol,int sep) {
    if(c<0 || c>=VOICES) return -1;
    stop(c);
    int lump=sfx->lumpnum;
    if(lump<0) lump=lumpnum(sfx);
    if(cached[c]!=lump) {
        int size=W_LumpLength(lump);
        if(size<8) return -1;
        const uint8_t *data=W_CacheLumpNum(lump,PU_STATIC);
        uint32_t rate=(uint32_t)data[2] | ((uint32_t)data[3]<<8);
        uint32_t n=(uint32_t)data[4] | ((uint32_t)data[5]<<8)
                  | ((uint32_t)data[6]<<16) | ((uint32_t)data[7]<<24);
        // DMX format 3, unsigned PCM. Reject malformed or truncated lumps.
        if(data[0]!=3 || data[1]!=0 || !rate || n<49 || n>(uint32_t)(size-8)) {
            Z_ChangeTag((void*)data,PU_CACHE); return -1;
        }
        // DMX samples include 16 padding samples at each end.
        data+=24; n-=32;
        uint32_t count=n>CAPACITY ? CAPACITY : n;
        uint32_t increment=(uint32_t)((((uint64_t)rate<<32)*count/n)/CPU_HZ);
        MMIO(SELECT)=c; MMIO(UPLOAD)=0;
        for(uint32_t j=0;j<count;j++) MMIO(DATA)=data[(uint64_t)j*n/count];
        Z_ChangeTag((void*)(data-24),PU_CACHE);
        cached[c]=lump; lengths[c]=count; steps[c]=increment;
    }
    MMIO(SELECT)=c; MMIO(LENGTH)=lengths[c]; MMIO(STEP)=steps[c];
    params(c,vol,sep); MMIO(COMMAND)=1;
    return c;
}
static boolean playing(int c) {
    return c>=0 && c<VOICES && (MMIO(STATUS)&(1u<<c))!=0;
}
static void update(void) { }
static void cache(sfxinfo_t *sounds,int n) { (void)sounds; (void)n; }
sound_module_t DG_sound_module = {
    devices,1,audio_init,shutdown_audio,lumpnum,update,params,start,stop,playing,cache
};
