#include <stdio.h>
#include <stdlib.h>

#ifndef VALUE
#define VALUE 1
#endif

/* Volatile keeps optimization from folding the constructor's observable work. */
static volatile int initialized;
__attribute__((constructor)) static void initialize(void) { initialized = 37; }
__attribute__((destructor)) static void finalize(void) { puts("destructor"); }

int main(int argc, char **argv) {
  const char *env = getenv("ORC_CHECK_VALUE");
  const char *path = getenv("ORC_CHECK_FILE");
  const char *status = getenv("ORC_CHECK_EXIT");
  int ch = -1;
  if (path) {
    FILE *file = fopen(path, "r");
    if (file) { ch = fgetc(file); fclose(file); }
  }
  printf("value=%d initialized=%d argc=%d argv1=%s argv2=%s env=%s file=%d\n",
         VALUE, initialized, argc, argc > 1 ? argv[1] : "-",
         argc > 2 ? argv[2] : "-", env ? env : "-", ch);
  return status ? atoi(status) : 0;
}
