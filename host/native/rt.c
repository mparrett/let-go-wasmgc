/* rt.c: the word-generic helpers of --target llvm (spec decision 6). Boxed
 * words are intptr_t: low bit 1 is a fixnum (v << 1 | 1); 0 nil; 2 false;
 * 4 true; any other value points at a heap object whose first word is its
 * kind. The fixnum width is the profile's :fixnum-bits, a signed width,
 * passed as -DLG_FIXNUM_BITS by checks/native-run.sh. Allocation never frees
 * (M1); the collector is M2. Numbers are formatted here, so a host only
 * has to write bytes (host/native/posix.c). */
#include <stddef.h>
#include <stdint.h>

#ifndef LG_FIXNUM_BITS
#error "LG_FIXNUM_BITS must be set from the hardware profile"
#endif

void lg_host_write(int fd, const char *buf, size_t n);
void lg_host_exit(int status) __attribute__((noreturn));
void *lg_host_chunk(size_t n);

enum { KIND_INT = 1 };
typedef struct { intptr_t kind; int64_t value; } lg_int_box;

static char *heap_top, *heap_end;

void *lg_alloc(size_t n) {
  size_t a = sizeof(int64_t) > sizeof(void *) ? sizeof(int64_t) : sizeof(void *);
  n = (n + a - 1) & ~(a - 1);
  if (heap_top == 0 || (size_t)(heap_end - heap_top) < n) {
    size_t chunk = n > ((size_t)1 << 20) ? n : ((size_t)1 << 20);
    heap_top = lg_host_chunk(chunk);
    heap_end = heap_top + chunk;
  }
  void *p = heap_top;
  heap_top += n;
  return p;
}

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
  lg_int_box *b = lg_alloc(sizeof *b);
  b->kind = KIND_INT;
  b->value = v;
  return (intptr_t)b;
}

int64_t lg_unbox_int(intptr_t w) {
  if (w & 1) return (int64_t)(w >> 1);
  if (w > 4 && ((lg_int_box *)w)->kind == KIND_INT) return ((lg_int_box *)w)->value;
  lg_error("expected an int");
  return 0;
}

intptr_t lg_truthy(intptr_t w) { return w != 0 && w != 2; }

/* A fn value (spec decision 10): kind 16, its %FnInfo, code per arity. */
enum { KIND_FN = 16 };
typedef struct { int32_t kind, arity; const char *name; } lg_fn_info;
typedef struct { intptr_t kind; const lg_fn_info *info; void *code[5]; } lg_fn;

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
  const lg_fn *fn = (f & 1) || (uintptr_t)f <= 4 ? 0 : (const lg_fn *)f;
  if (!fn || fn->kind != KIND_FN) {
    lg_puts(2, "error: TypeError: <let-go.lang.");
    lg_puts(2, (f & 1) ? "Int" : f == 0 ? "Nil" : (f == 2 || f == 4) ? "Boolean" : "Unknown");
    lg_puts(2, "> is not a function \n");
    lg_host_exit(1);
  }
  if (fn->info->kind == 1) {
    lg_puts(2, "error: <mfn ");
    if (fn->info->name) { lg_puts(2, fn->info->name); lg_puts(2, " "); }
    lg_put_hex(2, (uintptr_t)f);
    lg_puts(2, "> doesn't have a ");
    lg_put_int(2, argc);
    lg_puts(2, "-arity variant\n");
  } else {
    lg_puts(2, "error: function <fn ");
    if (fn->info->name) { lg_puts(2, fn->info->name); lg_puts(2, " "); }
    lg_put_hex(2, (uintptr_t)f);
    lg_puts(2, "> expected ");
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

void lg_print_bool(int b) { lg_puts(1, b ? "true" : "false"); }
void lg_print_space(void) { lg_host_write(1, " ", 1); }
void lg_print_nl(void) { lg_host_write(1, "\n", 1); }

void lg_print_box(intptr_t w) {
  if (w & 1) lg_print_i64((int64_t)(w >> 1));
  else if (w == 0) lg_puts(1, "nil");
  else if (w == 2) lg_puts(1, "false");
  else if (w == 4) lg_puts(1, "true");
  else if (((lg_int_box *)w)->kind == KIND_INT) lg_print_i64(((lg_int_box *)w)->value);
  else lg_puts(1, "#<object>");
}
