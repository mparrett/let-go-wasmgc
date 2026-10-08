/* rt.c: the word-generic helpers of --target llvm (spec decision 6). Boxed
 * words are intptr_t: low bit 1 is a fixnum (v << 1 | 1); 0 nil; any other
 * value points at an object whose first word is its type id (the module's
 * lg_tid_* constants, from rt/llvm's declarations); false and true are the
 * module's Bool objects lg_false and lg_true. The fixnum width is the profile's :fixnum-bits, a signed width,
 * passed as -DLG_FIXNUM_BITS by checks/native-run.sh. Allocation and the
 * collector are host/native/gc.c. Numbers are formatted here, so a host
 * only has to write bytes (host/native/posix.c). */
#include <stddef.h>
#include <stdint.h>

#ifndef LG_FIXNUM_BITS
#error "LG_FIXNUM_BITS must be set from the hardware profile"
#endif

void lg_host_write(int fd, const char *buf, size_t n);
void lg_host_exit(int status) __attribute__((noreturn));
typedef struct lg_desc lg_desc;
extern const lg_desc lg_desc_noscan;
void *lg_alloc(size_t n, const lg_desc *d);

extern const intptr_t lg_tid_Int, lg_tid_Float, lg_tid_Bool, lg_tid_Bytes, lg_tid_Err,
    lg_tid_Fn, lg_tid_FnV, lg_tid_FnX;
typedef struct { intptr_t tid; int64_t value; } lg_bool;
extern lg_bool lg_false, lg_true;
#define LG_FALSE ((intptr_t)&lg_false)
#define LG_TRUE ((intptr_t)&lg_true)
typedef struct { intptr_t tid; int64_t value; } lg_int_box;
typedef struct { intptr_t tid; double value; } lg_float_box;
typedef struct { intptr_t tid; intptr_t len; unsigned char data[]; } lg_bytes;

static intptr_t lg_tid_of(intptr_t w) { return (w & 1) || w == 0 ? 0 : *(const intptr_t *)w; }


static void lg_puts(int fd, const char *s) {
  size_t n = 0;
  while (s[n]) n++;
  lg_host_write(fd, s, n);
}

static void lg_error(const char *msg) {
  lg_puts(2, "error: ");
  lg_puts(2, msg);
  lg_puts(2, "\n");
  lg_host_exit(1);
}

void lg_overflow(void) { lg_error("integer overflow"); }

static const int64_t fix_min = -((int64_t)1 << (LG_FIXNUM_BITS - 1));
static const int64_t fix_max = ((int64_t)1 << (LG_FIXNUM_BITS - 1)) - 1;

intptr_t lg_box_int(int64_t v) {
  if (v >= fix_min && v <= fix_max) return (intptr_t)(((uintptr_t)(intptr_t)v << 1) | 1);
  lg_int_box *b = lg_alloc(sizeof *b, &lg_desc_noscan);
  b->tid = lg_tid_Int;
  b->value = v;
  return (intptr_t)b;
}

int64_t lg_unbox_int(intptr_t w) {
  if (w & 1) return (int64_t)(w >> 1);
  if (lg_tid_of(w) == lg_tid_Int) return ((lg_int_box *)w)->value;
  lg_error("expected an int");
  return 0;
}

/* An Int or a Float as a double; anything else is an error. */
double lg_to_f64(intptr_t w) {
  if (w & 1) return (double)(int64_t)(w >> 1);
  if (lg_tid_of(w) == lg_tid_Int) return (double)((lg_int_box *)w)->value;
  if (lg_tid_of(w) == lg_tid_Float) return ((lg_float_box *)w)->value;
  lg_error("expected a number");
  return 0;
}

intptr_t lg_truthy(intptr_t w) { return w != 0 && w != LG_FALSE; }

void lg_div_zero(void) { lg_error("divide by zero"); }

/* A failed cast or an index out of range (wasm traps there). */
void lg_trap(const char *msg) { lg_error(msg); }

static void lg_copy(unsigned char *d, const unsigned char *s, size_t n) {
  if (d < s) for (size_t i = 0; i < n; i++) d[i] = s[i];
  else for (size_t i = n; i > 0; i--) d[i - 1] = s[i - 1];
}

/* arch/array-new's fill of n slots, each a word. */
void lg_fill_word(intptr_t *p, intptr_t n, intptr_t v) { for (intptr_t i = 0; i < n; i++) p[i] = v; }
void lg_fill_i8(int8_t *p, intptr_t n, int8_t v) { for (intptr_t i = 0; i < n; i++) p[i] = v; }
void lg_fill_i32(int32_t *p, intptr_t n, int32_t v) { for (intptr_t i = 0; i < n; i++) p[i] = v; }
void lg_fill_i64(int64_t *p, intptr_t n, int64_t v) { for (intptr_t i = 0; i < n; i++) p[i] = v; }
void lg_fill_double(double *p, intptr_t n, double v) { for (intptr_t i = 0; i < n; i++) p[i] = v; }
void lg_fill_ptr(void **p, intptr_t n, void *v) { for (intptr_t i = 0; i < n; i++) p[i] = v; }

/* arch/array-copy: n slots of size sz from src[si] to dst[di], overlap
 * allowed; out of range traps, as wasm's array.copy does. */
void lg_array_copy(unsigned char *dst, intptr_t dn, int64_t di, const unsigned char *src, intptr_t sn,
                   int64_t si, int64_t n, int64_t sz) {
  if (di < 0 || si < 0 || n < 0 || di + n > dn || si + n > sn) lg_error("array-copy: index out of range");
  lg_copy(dst + di * sz, src + si * sz, (size_t)(n * sz));
}

/* arch/bytes-new: n zero bytes. */
intptr_t lg_bytes_new(int64_t n) {
  lg_bytes *b = lg_alloc(sizeof *b + (size_t)n, &lg_desc_noscan);
  b->tid = lg_tid_Bytes;
  b->len = (intptr_t)n;
  for (int64_t i = 0; i < n; i++) b->data[i] = 0;
  return (intptr_t)b;
}

/* arch/host-write: a Bytes to fd; the count written. */
int64_t lg_host_write_bytes(int64_t fd, intptr_t w) {
  const lg_bytes *b = (const lg_bytes *)w;
  lg_host_write((int)fd, (const char *)b->data, (size_t)b->len);
  return b->len;
}

/* arch/host-argc and arch/host-arg (os/args): the host's argv, each a Bytes. */
int lg_host_argc(void);
const char *lg_host_argv(int i);
int64_t lg_host_argc64(void) { return lg_host_argc(); }
intptr_t lg_host_arg(int64_t i) {
  const char *a = lg_host_argv((int)i);
  size_t n = 0;
  while (a[n]) n++;
  lg_bytes *b = lg_alloc(sizeof *b + n, &lg_desc_noscan);
  b->tid = lg_tid_Bytes;
  b->len = (intptr_t)n;
  for (size_t j = 0; j < n; j++) b->data[j] = (unsigned char)a[j];
  return (intptr_t)b;
}

/* A fn value: the runtime's Fn (rt/llvm/seq.lg), code per arity around env,
 * then its FnInfo (kind, arity, name Bytes or 0). */
typedef struct { intptr_t tid; int32_t kind, arity; intptr_t name; } lg_fn_info;
typedef struct { intptr_t tid; void *code0, *code1, *code2; intptr_t env; void *code3, *code4;
                 const lg_fn_info *info; int64_t hash; } lg_fn;

static void lg_put_bytes(int fd, intptr_t w) {
  const lg_bytes *b = (const lg_bytes *)w;
  lg_host_write(fd, (const char *)b->data, (size_t)b->len);
}

static void lg_put_hex(int fd, uintptr_t v) {
  char buf[2 + 2 * sizeof v];
  int i = sizeof buf;
  do { buf[--i] = "0123456789abcdef"[v & 15]; v >>= 4; } while (v);
  buf[--i] = 'x'; buf[--i] = '0';
  lg_host_write(fd, buf + i, sizeof buf - i);
}

static void lg_put_int(int fd, int64_t v);

/* A call through a value that is not a fn, or has no code for the call's
 * arity, with native lg's texts (D56). */
void lg_arity_fail(intptr_t f, int32_t argc) {
  intptr_t t = lg_tid_of(f);
  const lg_fn *fn = t == lg_tid_Fn || t == lg_tid_FnV || t == lg_tid_FnX ? (const lg_fn *)f : 0;
  if (!fn) {
    lg_puts(2, "error: TypeError: <let-go.lang.");
    lg_puts(2, (f & 1) || t == lg_tid_Int ? "Int" : f == 0 ? "Nil" : t == lg_tid_Bool ? "Boolean" : "Unknown");
    lg_puts(2, "> is not a function \n");
    lg_host_exit(1);
  }
  if (fn->info->kind == 1) {
    lg_puts(2, "error: <mfn ");
    if (fn->info->name) { lg_put_bytes(2, fn->info->name); lg_puts(2, " "); }
    lg_put_hex(2, (uintptr_t)f);
    lg_puts(2, "> doesn't have a ");
    lg_put_int(2, argc);
    lg_puts(2, "-arity variant\n");
  } else {
    lg_puts(2, "error: function <fn ");
    if (fn->info->name) { lg_put_bytes(2, fn->info->name); lg_puts(2, " "); }
    lg_put_hex(2, (uintptr_t)f);
    lg_puts(2, fn->info->kind == 3 ? "> expected at least " : "> expected ");
    lg_put_int(2, fn->info->arity);
    lg_puts(2, " args, got ");
    lg_put_int(2, argc);
    lg_puts(2, "\n");
  }
  lg_host_exit(1);
}

static void lg_put_int(int fd, int64_t v) {
  char buf[24];
  int i = sizeof buf;
  uint64_t u = v < 0 ? (uint64_t)0 - (uint64_t)v : (uint64_t)v;
  do { buf[--i] = (char)('0' + u % 10); u /= 10; } while (u);
  if (v < 0) buf[--i] = '-';
  lg_host_write(fd, buf + i, sizeof buf - i);
}

void lg_print_i64(int64_t v) { lg_put_int(1, v); }

/* An uncaught throw (spec decision 9): an Err's message, as native's error
 * line; any other thrown value by type. */
typedef struct { intptr_t tid; int32_t kind; intptr_t msg, cmsg, data, cause; } lg_err;
void lg_uncaught(intptr_t v) {
  const lg_err *e = lg_tid_of(v) == lg_tid_Err ? (const lg_err *)v : 0;
  lg_puts(2, "error: ");
  if (e && e->msg) {
    lg_put_bytes(2, e->msg);
  } else {
    lg_puts(2, "uncaught non-exception value");
  }
  lg_puts(2, "\n");
  lg_host_exit(1);
}

void lg_print_bool(int b) { lg_puts(1, b ? "true" : "false"); }
void lg_print_space(void) { lg_host_write(1, " ", 1); }
void lg_print_nl(void) { lg_host_write(1, "\n", 1); }

void lg_print_box(intptr_t w) {
  if (w & 1) lg_print_i64((int64_t)(w >> 1));
  else if (w == 0) lg_puts(1, "nil");
  else if (w == LG_FALSE) lg_puts(1, "false");
  else if (w == LG_TRUE) lg_puts(1, "true");
  else if (lg_tid_of(w) == lg_tid_Int) lg_print_i64(((lg_int_box *)w)->value);
  else lg_puts(1, "#<object>");
}
