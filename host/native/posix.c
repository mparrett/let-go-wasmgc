/* posix.c: the :posix host of --target llvm (spec decision 11): bytes out
 * through write(2), memory from malloc, and main entering the module's
 * lg_run. host/native/rt.c holds everything word-generic. */
#include <fcntl.h>
#include <poll.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
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

int lg_host_open_c(const char *path, int mode) {
  int fl = mode == 0 ? O_RDONLY : mode == 1 ? (O_WRONLY | O_CREAT | O_TRUNC) : (O_WRONLY | O_CREAT | O_APPEND);
  return open(path, fl, 0644);
}

/* One key per call, as let-go's native key source: a read is buffered and
   split by key_tokenizer.go's scanKey into ESC, a CSI or SS3 sequence, or one
   UTF-8 rune (an invalid byte alone), refilled only when stdin has more, so
   ESC x arrives as two keys. The SIGWINCH wake is not ported. */
static unsigned char lg_keys[256];
static int lg_keys_len;

static int lg_stdin_ready(void) {
  struct pollfd p = {0, POLLIN, 0};
  return poll(&p, 1, 0) > 0;
}

/* utf8.FullRune then utf8.DecodeRune: the length of a valid rune at b, 1
   for an invalid sequence, *more when a valid prefix runs off the buffer */
static int lg_scan_rune(const unsigned char *b, int n, int *more) {
  unsigned c = b[0];
  int len = c >= 0xc2 && c <= 0xdf ? 2 : c >= 0xe0 && c <= 0xef ? 3 : c >= 0xf0 && c <= 0xf4 ? 4 : 1;
  if (len == 1) return 1;
  /* the second byte's range rules out overlongs, surrogates and > U+10FFFF */
  unsigned lo = c == 0xe0 ? 0xa0 : c == 0xf0 ? 0x90 : 0x80;
  unsigned hi = c == 0xed ? 0x9f : c == 0xf4 ? 0x8f : 0xbf;
  for (int i = 1; i < len; i++) {
    if (i >= n) { *more = 1; return n; }
    unsigned x = b[i];
    if (i == 1 ? (x < lo || x > hi) : (x < 0x80 || x > 0xbf)) return 1;
  }
  return len;
}

/* the front token's length; *more when it may continue past the buffer */
static int lg_scan_key(const unsigned char *b, int n, int *more) {
  *more = 0;
  if (b[0] == 0x1b) {
    if (n == 1) { *more = 1; return 1; }
    if (b[1] == '[') {
      int i = 2;
      while (i < n && (b[i] < 0x40 || b[i] > 0x7e)) i++;
      if (i < n) return i + 1;
      *more = 1; return n;
    }
    if (b[1] == 'O') {
      if (n < 3) { *more = 1; return n; }
      return 3;
    }
    return 1;
  }
  if (b[0] < 0x80) return 1;
  return lg_scan_rune(b, n, more);
}

int lg_host_read_key(unsigned char *buf, int cap) {
  for (;;) {
    if (lg_keys_len == 0) {
      ssize_t r = read(0, lg_keys, sizeof lg_keys);
      if (r <= 0) return 0;
      lg_keys_len = (int)r;
    }
    int more, n = lg_scan_key(lg_keys, lg_keys_len, &more);
    if (more && lg_keys_len < (int)sizeof lg_keys && lg_stdin_ready()) {
      ssize_t r = read(0, lg_keys + lg_keys_len, sizeof lg_keys - (size_t)lg_keys_len);
      if (r > 0) { lg_keys_len += (int)r; continue; }
    }
    if (n > cap) n = cap;
    memcpy(buf, lg_keys, (size_t)n);
    lg_keys_len -= n;
    memmove(lg_keys, lg_keys + n, (size_t)lg_keys_len);
    return n;
  }
}

int lg_host_key_ready(void) { return lg_keys_len > 0 || lg_stdin_ready(); }

/* stdout's size; -1, -1 when stdout is not a terminal (term.go's size
   is nil then), and the caller's defaults for a zero dimension */
void lg_host_term_dims(int *cols, int *rows) {
  struct winsize w;
  if (ioctl(1, TIOCGWINSZ, &w) != 0) { *cols = -1; *rows = -1; return; }
  if (w.ws_col && w.ws_row) { *cols = w.ws_col; *rows = w.ws_row; }
}

/* raw mode on stdin with the flags golang.org/x/term's MakeRaw sets */
static struct termios lg_saved_mode;
static int lg_mode_saved;
int lg_host_raw_mode(void) {
  if (lg_mode_saved) return 2;
  struct termios t;
  if (tcgetattr(0, &t) != 0) return 0;
  lg_saved_mode = t;
  t.c_iflag &= ~(tcflag_t)(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
  t.c_oflag &= ~(tcflag_t)OPOST;
  t.c_lflag &= ~(tcflag_t)(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
  t.c_cflag &= ~(tcflag_t)(CSIZE | PARENB);
  t.c_cflag |= CS8;
  t.c_cc[VMIN] = 1;
  t.c_cc[VTIME] = 0;
  if (tcsetattr(0, TCSANOW, &t) != 0) return 0;
  lg_mode_saved = 1;
  return 1;
}
int lg_host_restore_mode(void) {
  if (!lg_mode_saved) return 0;
  lg_mode_saved = 0;
  return tcsetattr(0, TCSANOW, &lg_saved_mode) == 0 ? 1 : 0;
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
