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
