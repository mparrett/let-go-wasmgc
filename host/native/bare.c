/* bare.c: the :bare host of --target llvm (spec decision 11), for boards
 * with no OS. Output and exit go through Arm semihosting (qemu
 * -semihosting-config enable=on,target=native), so qemu prints the program's
 * output and exits with its status. Memory is the linker's heap region
 * (host/native/boards/<board>/link.ld); running past it is a named
 * out-of-memory error. host/native/rt.c holds everything word-generic. */
#include <stddef.h>
#include <stdint.h>

void lg_run(void);

enum { SYS_OPEN = 0x01, SYS_WRITE = 0x05, SYS_EXIT_EXTENDED = 0x20 };
enum { ADP_STOPPED_APPLICATION_EXIT = 0x20026 };

static intptr_t semihost(intptr_t op, void *block) {
  register intptr_t r0 __asm__("r0") = op;
  register void *r1 __asm__("r1") = block;
  __asm__ volatile("svc 0x123456" : "+r"(r0) : "r"(r1) : "memory");
  return r0;
}

static intptr_t handles[3] = {-1, -1, -1};

static intptr_t handle(int fd) {
  if (handles[fd] < 0) {
    /* ":tt" opened for writing is stdout; opened for appending, stderr */
    intptr_t block[3] = {(intptr_t)":tt", fd == 2 ? 8 : 4, 3};
    handles[fd] = semihost(SYS_OPEN, block);
  }
  return handles[fd];
}

void lg_host_write(int fd, const char *buf, size_t n) {
  intptr_t block[3] = {handle(fd == 2 ? 2 : 1), (intptr_t)buf, (intptr_t)n};
  semihost(SYS_WRITE, block);
}

void lg_host_exit(int status) {
  intptr_t block[2] = {ADP_STOPPED_APPLICATION_EXIT, status};
  semihost(SYS_EXIT_EXTENDED, block);
  for (;;) {}
}

#ifndef LG_HEAP_BYTES
#error "LG_HEAP_BYTES must be set from the hardware profile's :heap :bytes"
#endif

extern char __heap_start[];

/* os/args on a board: no program path to report, only the lg name. */
int lg_host_argc(void) { return 1; }
const char *lg_host_argv(int i) { return i == 0 ? "lg" : ""; }

/* The heap (host/native/gc.c collects it): the profile's :heap bytes from
 * the linker's __heap_start; exhausting it is gc.c's "out of memory". */
void *lg_host_heap(size_t *n) {
  *n = LG_HEAP_BYTES;
  return __heap_start;
}

void lg_bare_main(void) {
  lg_run();
  lg_host_exit(0);
}
