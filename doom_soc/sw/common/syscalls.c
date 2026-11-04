// newlib system calls for doom_soc.
//   stdout/stderr -> UART.  stdin -> nothing (DOOM reads input via DG_GetKey).
//   One read-only file, "doom1.wad", backed by the WAD the boot loader put in DDR
//   (header at WAD_HDR_ADDR). Everything else fails with ENOENT, so DOOM runs with
//   default settings and no save games.
#include <sys/stat.h>
#include <sys/time.h>
#include <errno.h>
#include <string.h>
#include <stddef.h>
#include "doom_soc.h"

#undef errno
extern int errno;

extern char __heap_start[];

#define WAD_FD 3
static uint32_t wad_pos;
static int      wad_open;

static const uint32_t *wad_hdr(void) { return (const uint32_t *)WAD_HDR_ADDR; }
static uint32_t wad_len(void)        { return wad_hdr()[0] == WAD_MAGIC ? wad_hdr()[1] : 0; }

static int is_wad_name(const char *p)
{
    const char *b = strrchr(p, '/');
    b = b ? b + 1 : p;
    return strcmp(b, "doom1.wad") == 0;
}

int _open(const char *path, int flags, int mode)
{
    (void)mode;
    if (is_wad_name(path) && (flags & 3) == 0 && wad_len()) {
        wad_open = 1;
        wad_pos = 0;
        return WAD_FD;
    }
    errno = ENOENT;
    return -1;
}

int _write(int fd, const char *buf, int len)
{
    if (fd != 1 && fd != 2) { errno = EBADF; return -1; }
    for (int i = 0; i < len; i++) {
        if (buf[i] == '\n') {
            while (!(MMIO(UART_TX_READY) & 1)) ;
            MMIO(UART_TX) = '\r';
        }
        while (!(MMIO(UART_TX_READY) & 1)) ;
        MMIO(UART_TX) = (unsigned char)buf[i];
    }
    return len;
}

int _read(int fd, char *buf, int len)
{
    if (fd == WAD_FD && wad_open) {
        uint32_t n = wad_len() - wad_pos;
        if ((uint32_t)len < n) n = (uint32_t)len;
        memcpy(buf, (const char *)WAD_DATA_ADDR + wad_pos, n);
        wad_pos += n;
        return (int)n;
    }
    return 0;                                   // stdin: EOF
}

int _lseek(int fd, int off, int whence)
{
    if (fd != WAD_FD || !wad_open) { errno = ESPIPE; return -1; }
    long p = whence == 0 ? off : whence == 1 ? (long)wad_pos + off : (long)wad_len() + off;
    if (p < 0 || p > (long)wad_len()) { errno = EINVAL; return -1; }
    wad_pos = (uint32_t)p;
    return (int)p;
}

int _close(int fd)
{
    if (fd == WAD_FD) { wad_open = 0; return 0; }
    return fd <= 2 ? 0 : -1;
}

int _fstat(int fd, struct stat *st)
{
    memset(st, 0, sizeof *st);
    if (fd == WAD_FD) { st->st_mode = S_IFREG; st->st_size = wad_len(); return 0; }
    st->st_mode = S_IFCHR;
    return 0;
}

int _stat(const char *path, struct stat *st)
{
    memset(st, 0, sizeof *st);
    if (is_wad_name(path) && wad_len()) { st->st_mode = S_IFREG; st->st_size = wad_len(); return 0; }
    errno = ENOENT;
    return -1;
}

int _isatty(int fd)                 { return fd <= 2; }
int _kill(int pid, int sig)         { (void)pid; (void)sig; errno = EINVAL; return -1; }
int _getpid(void)                   { return 1; }
int _unlink(const char *p)          { (void)p; errno = ENOENT; return -1; }
int _link(const char *a, const char *b) { (void)a; (void)b; errno = EMLINK; return -1; }
int _rename(const char *a, const char *b) { (void)a; (void)b; errno = ENOENT; return -1; }
int mkdir(const char *p, mode_t m)  { (void)p; (void)m; errno = EACCES; return -1; }

int _gettimeofday(struct timeval *tv, void *tz)
{
    (void)tz;
    static uint64_t acc; static uint32_t last;
    uint32_t now = cycles();
    acc += (uint32_t)(now - last);
    last = now;
    if (tv) { tv->tv_sec = (time_t)(acc / CPU_HZ); tv->tv_usec = (suseconds_t)((acc % CPU_HZ) / (CPU_HZ / 1000000u)); }
    return 0;
}

void *_sbrk(ptrdiff_t incr)
{
    static char *brk = __heap_start;
    char *sp;
    __asm__ volatile ("mv %0, sp" : "=r"(sp));
    if (brk + incr > sp - 65536) {              // keep 64 KB between heap and stack
        errno = ENOMEM;
        return (void *)-1;
    }
    char *old = brk;
    brk += incr;
    return old;
}

void _exit(int code)
{
    MMIO(SIM_CTRL) = ((unsigned)code << 1) | 1;
    MMIO(LED) = 0xEE;
    for (;;)
        ;
}
