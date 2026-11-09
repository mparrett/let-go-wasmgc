#!/usr/bin/env bash
# checks/llvm-refs-check.sh — the llvm emitter records every module symbol a
# unit names (lower-llvm-ir/ref), and its shake follows only those, so a
# name written into text some other way could drop live code (D225). This
# compiles programs with LW_LL_CHECK_REFS=1, under which each unit's text is
# also scanned (src/lower_llvm_refcheck.lg); any "refs-check:" line is a
# symbol a unit named but did not record. Exit 0 iff there are none.
set -uo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
progs=(corpus/llvm/*.lg corpus/poly/*.lg corpus/control/*.lg corpus/scalar/fib.clj)
n=0; bad=0
for p in "${progs[@]}"; do
  n=$((n + 1))
  if ! LW_LL_CHECK_REFS=1 "$LG" -source-paths src src/driver.lg --target llvm --no-rtlib "$p" "$t/m.ll" > "$t/log" 2>&1; then
    echo "COMPILE FAIL $p"; bad=$((bad + 1)); continue
  fi
  if grep -q '^refs-check:' "$t/log"; then bad=$((bad + 1)); echo "MISSES $p"; grep '^refs-check:' "$t/log" | head -3
  else echo "OK $p"; fi
done
echo "llvm-refs: $((n - bad))/$n with every reference recorded"
[ "$bad" = 0 ]
