/* posix.c: the :posix host of --target llvm (spec decision 11): bytes out
 * through write(2), memory from malloc, and main entering the module's
 * lg_run. host/native/rt.c holds everything word-generic. */
#include <stdlib.h>
#include <unistd.h>

void lg_run(void);

void lg_host_write(int fd, const char *buf, size_t n) {
  while (n > 0) {
    ssize_t w = write(fd, buf, n);
    if (w <= 0) return;
    buf += w;
    n -= (size_t)w;
  }
}

void lg_host_exit(int status) { _exit(status); }

void *lg_host_chunk(size_t n) {
  void *p = malloc(n);
  if (!p) {
    static const char msg[] = "error: out of memory\n";
    lg_host_write(2, msg, sizeof msg - 1);
    _exit(1);
  }
  return p;
}

int main(void) {
  lg_run();
  return 0;
}
