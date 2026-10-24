/* gc.c: the heap and its collector under --target llvm (spec decision 7).
 * The heap is one region the host hands over (lg_host_heap), so "is this
 * word a heap object" is a range test: static objects (the Bool singletons,
 * constant strings, fn globals) lie outside it. Every block starts with a
 * header {size | flags, descriptor}; the descriptor, emitted by the backend
 * beside each type, lists the fields that hold words to trace, so the scan
 * is precise. A collection runs only at the entry of a CPS function
 * (lg_gc, called when lg_gc_pending is set), with that function's arguments
 * as the roots, plus the module's globals (lg_gc_globals): every call is a
 * tail call, so nothing else is live. Mark-sweep, non-moving; freed blocks
 * are coalesced and reused through size-class free lists. */
#include <stddef.h>
#include <stdint.h>

void lg_host_write(int fd, const char *buf, size_t n);
void lg_host_exit(int status) __attribute__((noreturn));
void *lg_host_heap(size_t *n);

/* off[i]: byte offsets of word fields to trace; an array (kind 1) also
 * traces each of its len words from elem_off, len read at len_off. */
typedef struct { int32_t kind, len_off, elem_off, n; int32_t off[]; } lg_desc;
enum { DESC_STRUCT = 0, DESC_ARRAY = 1 };
const lg_desc lg_desc_noscan = {DESC_STRUCT, 0, 0, 0};

/* sz: the block's bytes (a multiple of 8) | MARK | FREE; a free block's d
 * is the next free block. 8 bytes on 32-bit, 16 on 64-bit: payloads stay
 * 8-aligned for i64 and double fields on every profile. */
typedef struct hdr { uintptr_t sz; const void *d; } hdr;
#define MARK ((uintptr_t)1)
#define FREE ((uintptr_t)2)
#define FLAGS ((uintptr_t)7)
#define SIZE(h) ((h)->sz & ~FLAGS)

extern void *const lg_gc_globals[];
extern const int32_t lg_gc_nglobals;
unsigned char lg_gc_pending;

static char *base, *top, *end;
static size_t since_gc, trigger, min_trigger, free_bytes;

#define NCLASS 64 /* exact free lists for blocks of 8 .. 512 bytes */
static hdr *small[NCLASS + 1];
static hdr *large;

static void oom(void) {
  static const char msg[] = "error: out of memory\n";
  lg_host_write(2, msg, sizeof msg - 1);
  lg_host_exit(1);
}

static void heap_init(void) {
  size_t n;
  char *p = lg_host_heap(&n);
  base = (char *)(((uintptr_t)p + 7) & ~(uintptr_t)7);
  end = base + ((n - (size_t)(base - p)) & ~(size_t)7);
  top = base;
  free_bytes = (size_t)(end - base);
  min_trigger = free_bytes / 16 > ((size_t)64 << 10) ? free_bytes / 16 : ((size_t)64 << 10);
  trigger = min_trigger;
}

static void push_free(hdr *h, size_t sz) {
  h->sz = sz | FREE;
  if (sz / 8 <= NCLASS) { h->d = small[sz / 8]; small[sz / 8] = h; }
  else { h->d = large; large = h; }
}

/* a free block of exactly sz bytes from block h of bsz >= sz; any remainder
 * of 16 bytes or more stays free */
static hdr *split(hdr *h, size_t bsz, size_t sz) {
  if (bsz - sz >= 16) push_free((hdr *)((char *)h + sz), bsz - sz);
  else sz = bsz;
  h->sz = sz;
  return h;
}

static hdr *take(size_t sz) {
  size_t c = sz / 8;
  if (c <= NCLASS && small[c]) { hdr *h = small[c]; small[c] = (hdr *)h->d; h->sz = sz; return h; }
  if ((size_t)(end - top) >= sz) { hdr *h = (hdr *)top; top += sz; h->sz = sz; return h; }
  for (hdr **pp = &large; *pp; pp = (hdr **)&(*pp)->d) {
    hdr *h = *pp;
    if (SIZE(h) >= sz) { *pp = (hdr *)h->d; return split(h, SIZE(h), sz); }
  }
  for (size_t k = c + 1; k <= NCLASS; k++)
    if (small[k]) { hdr *h = small[k]; small[k] = (hdr *)h->d; return split(h, k * 8, sz); }
  return 0;
}

void *lg_alloc(size_t n, const lg_desc *d) {
  if (!base) heap_init();
  size_t sz = (n + sizeof(hdr) + 7) & ~(size_t)7;
  hdr *h = take(sz);
  if (!h) oom();
  sz = SIZE(h);
  h->d = d;
  /* fields the allocating code leaves unset must not look like pointers */
  for (uintptr_t *w = (uintptr_t *)(h + 1), *e = (uintptr_t *)((char *)h + sz); w < e; w++) *w = 0;
  since_gc += sz;
  free_bytes -= sz;
  if (since_gc >= trigger || free_bytes < (size_t)(end - base) / 16) lg_gc_pending = 1;
  return h + 1;
}

/* --- mark ----------------------------------------------------------------- */

#define STACK 8192
static uintptr_t stack[STACK];
static int sp, overflow;

static void mark(uintptr_t p) {
  if (p < (uintptr_t)base + sizeof(hdr) || p >= (uintptr_t)top || (p & 7)) return;
  hdr *h = (hdr *)p - 1;
  if (h->sz & (MARK | FREE)) return;
  h->sz |= MARK;
  if (sp < STACK) stack[sp++] = p;
  else overflow = 1;
}

static void scan(uintptr_t p) {
  const lg_desc *d = ((hdr *)p - 1)->d;
  for (int32_t i = 0; i < d->n; i++) mark(*(const uintptr_t *)(p + (uintptr_t)d->off[i]));
  if (d->kind == DESC_ARRAY) {
    intptr_t len = *(const intptr_t *)(p + (uintptr_t)d->len_off);
    const uintptr_t *e = (const uintptr_t *)(p + (uintptr_t)d->elem_off);
    for (intptr_t j = 0; j < len; j++) mark(e[j]);
  }
}

static void drain(void) {
  while (sp) scan(stack[--sp]);
  /* the stack overflowed: rescan marked blocks until no child is left */
  while (overflow) {
    overflow = 0;
    for (char *b = base; b < top; b += SIZE((hdr *)b))
      if (((hdr *)b)->sz & MARK) { scan((uintptr_t)((hdr *)b + 1)); while (sp) scan(stack[--sp]); }
  }
}

/* --- sweep ---------------------------------------------------------------- */

static size_t sweep(void) {
  size_t live = 0;
  for (int k = 0; k <= NCLASS; k++) small[k] = 0;
  large = 0;
  free_bytes = 0;
  char *b = base;
  while (b < top) {
    hdr *h = (hdr *)b;
    size_t sz = SIZE(h);
    if (h->sz & MARK) { h->sz &= ~MARK; live += sz; b += sz; continue; }
    /* a run of free and unmarked blocks becomes one free block */
    char *run = b;
    while (b < top && !(((hdr *)b)->sz & MARK)) b += SIZE((hdr *)b);
    if (b == top) top = run;
    else { push_free((hdr *)run, (size_t)(b - run)); free_bytes += (size_t)(b - run); }
  }
  free_bytes += (size_t)(end - top);
  return live;
}

/* A collection at a CPS function's entry: roots are its n word or pointer
 * arguments, then the globals. */
void lg_gc(void *const *roots, int32_t n) {
  for (int32_t i = 0; i < n; i++) mark((uintptr_t)roots[i]);
  for (int32_t i = 0; i < lg_gc_nglobals; i++) mark(*(const uintptr_t *)lg_gc_globals[i]);
  drain();
  size_t live = sweep();
#ifdef LG_GC_TRACE
  {
    char buf[96];
    int i = sizeof buf;
    buf[--i] = '\n';
    size_t v = free_bytes;
    do { buf[--i] = (char)('0' + v % 10); v /= 10; } while (v);
    buf[--i] = ' '; buf[--i] = 'e'; buf[--i] = 'e'; buf[--i] = 'r'; buf[--i] = 'f'; buf[--i] = ' ';
    v = live;
    do { buf[--i] = (char)('0' + v % 10); v /= 10; } while (v);
    lg_host_write(2, "gc: live ", 9);
    lg_host_write(2, buf + i, sizeof buf - (size_t)i);
  }
#endif
  since_gc = 0;
  trigger = live > min_trigger ? live : min_trigger;
  lg_gc_pending = 0;
}
