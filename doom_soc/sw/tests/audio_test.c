// Approximately 440 Hz tone, repeated once per second. Uses the new bitstream.
#include <stdio.h>
#include "doom_soc.h"
int main(void) {
    MMIO(0xC0)=0; MMIO(0xD8)=0; MMIO(0xC4)=0;
    for(unsigned i=0;i<8192;i++) MMIO(0xC8)=((i*880u/11025u)&1u) ? 192 : 64;
    MMIO(0xCC)=8192;
    MMIO(0xD0)=(uint32_t)(((uint64_t)11025<<32)/CPU_HZ);
    MMIO(0xD4)=100;
    printf("Audio test: repeated tone on J8\n");
    for(;;) {
        MMIO(0xD8)=1;
        uint32_t begin=cycles();
        while((uint32_t)(cycles()-begin)<CPU_HZ) { }
    }
}
