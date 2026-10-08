/* posix.c: the :posix host of --target llvm (spec decision 11): bytes out
 * through write(2), memory from malloc, and main entering the module's
 * lg_run. host/native/rt.c holds everything word-generic. */
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <time.h>
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

/* The heap (host/native/gc.c collects it): one region of LG_HEAP_BYTES
 * (environment; default 1 GiB), as a board's is its profile's :heap. The
 * pages are committed as the allocator first touches them. */
void *lg_host_heap(size_t *n) {
  const char *e = getenv("LG_HEAP_BYTES");
  *n = e && *e ? (size_t)strtoull(e, 0, 10) : (size_t)1 << 30;
  void *p = malloc(*n);
  if (!p) {
    static const char msg[] = "error: out of memory\n";
    lg_host_write(2, msg, sizeof msg - 1);
    _exit(1);
  }
  return p;
}

/* host/ABI.md's env.sleep, env.nanotime, env.getenv and term.* (rt.c
 * wraps them as the intrinsics' helpers); the capture buffers grow with
 * realloc. */
void lg_host_sleep(int64_t ms) {
  if (ms <= 0) return;
  struct timespec t = {(time_t)(ms / 1000), (long)(ms % 1000) * 1000000L};
  while (nanosleep(&t, &t) != 0) {}
}

int64_t lg_host_nanotime(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

const char *lg_host_getenv_c(const char *name) { return getenv(name); }

int lg_host_read_key(unsigned char *buf, int cap) {
  ssize_t n = read(0, buf, (size_t)cap);
  return n < 0 ? 0 : (int)n;
}

int lg_host_key_ready(void) {
  struct pollfd p = {0, POLLIN, 0};
  return poll(&p, 1, 0) > 0;
}

void lg_host_term_dims(int *cols, int *rows) {
  struct winsize w;
  if (ioctl(1, TIOCGWINSZ, &w) == 0 && w.ws_col && w.ws_row) { *cols = w.ws_col; *rows = w.ws_row; }
}

void *lg_host_grow(void *p, size_t old, size_t n) {
  (void)old;
  void *q = realloc(p, n);
  if (!q) { static const char msg[] = "error: out of memory\n"; lg_host_write(2, msg, sizeof msg - 1); _exit(1); }
  return q;
}

/* os/args: native's [lg-path prog args...]; native-run.sh passes the
 * program path first, and the lg path is $LG, as src/run.mjs reports it. */
static int host_argc;
static char **host_argv;
int lg_host_argc(void) { return host_argc; }
const char *lg_host_argv(int i) {
  if (i == 0) { const char *lg = getenv("LG"); return lg && *lg ? lg : "lg"; }
  return i < host_argc ? host_argv[i] : "";
}

int main(int argc, char **argv) {
  host_argc = argc;
  host_argv = argv;
  lg_run();
  return 0;
}
