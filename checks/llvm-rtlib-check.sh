#!/usr/bin/env bash
# checks/llvm-rtlib-check.sh — the llvm target's runtime compile cache (D221).
# Behavior and bounds, never bytes:
#   1. each program behaves the same (stdout, exit) compiled with --no-rtlib
#      and through the cache;
#   2. with a warm cache a compile takes at most LLVM_RTLIB_WARM_S seconds
#      (default 5; the uncached compile took ~22 s on 2026-10-09);
#   3. (LLVM_RTLIB_PARTIAL=1, once the cache is a dependency graph: D221
#      part 3) partial invalidation, on a copy of rt/ (LW_RT_DIR): a comment-only edit
#      of a runtime file rebuilds no node, and a changed body of one runtime
#      fn rebuilds at most LLVM_RTLIB_EDIT_MAX nodes (default 8), as the
#      driver's "rtlib-llvm: N reused, M rebuilt" line (LW_RTLIB_STATS=1) says.
# Exit 0 iff every part holds. A scratch cache dir keeps it off src/.rtlib.
# Each compile in parts 1 and 3 takes a slot of the machine-wide pool
# (checks/sem.sh); part 2's timed compile runs on a quiet machine
# (checks/quiet.sh), so the bound measures the cache, not other agents' load.
# The gate row runs this unslotted: a quiet run cannot drain a pool it holds.
set -uo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
warm_max=${LLVM_RTLIB_WARM_S:-5}
edit_max=${LLVM_RTLIB_EDIT_MAX:-8}
progs=(corpus/scalar/fib.clj corpus/poly/types.lg corpus/llvm/closures.lg corpus/llvm/unbox-catch.lg)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export LW_RTLIB_DIR="$t/rtlib"
fail=0
now() { python3 -c 'import time; print(time.time())'; }

# 1. behavior, cached against uncached
for p in "${progs[@]}"; do
  a=$(LW_DRIVER_ARGS=--no-rtlib checks/sem.sh checks/native-run.sh "$p" 2>&1; echo "exit $?")
  b=$(checks/sem.sh checks/native-run.sh "$p" 2>&1; echo "exit $?")
  if [ "$a" = "$b" ]; then echo "SAME $p"; else echo "DIFFER $p"; diff <(echo "$a") <(echo "$b") | head -10; fail=1; fi
done

# 2. a warm compile within the bound (the cache is warm after part 1)
# quiet.sh prints the timed command's output after the lease; it is the
# duration line only (the compile's own output goes to warm.log)
timed() { local s e; s=$(now); "$LG" -source-paths src src/driver.lg --target llvm corpus/scalar/fib.clj "$t/fib.ll" > "$t/warm.log" 2>&1; local rc=$?; e=$(now); echo "$rc $(python3 -c "print(round($e - $s, 2))")"; }
export -f now timed; export LG t
read -r rc secs < <(checks/quiet.sh bash -c timed)
if [ $rc -eq 0 ] && python3 -c "import sys; sys.exit(0 if $secs <= $warm_max else 1)"; then
  echo "WARM ${secs}s <= ${warm_max}s"
else echo "WARM ${secs}s exceeds ${warm_max}s (exit $rc)"; tail -3 "$t/warm.log"; fail=1; fi

# 3. partial invalidation on a copy of the runtime
if [ "${LLVM_RTLIB_PARTIAL:-0}" = 1 ]; then
cp -R rt "$t/rt"
export LW_RT_DIR="$t/rt/llvm"
stats() { LW_RTLIB_STATS=1 checks/sem.sh "$LG" -source-paths src src/driver.lg --target llvm corpus/scalar/fib.clj "$t/p.ll" 2>&1 | grep -E '^rtlib-llvm: [0-9]+ reused, [0-9]+ rebuilt' | tail -1; }
rebuilt() { echo "$1" | sed -E 's/.* ([0-9]+) rebuilt.*/\1/'; }
base=$(stats); echo "BASE ${base:-<no stats line>}"
printf '\n;; a comment-only edit\n' >> "$t/rt/llvm/math.lg"
c=$(stats); n=$(rebuilt "$c")
if [ -n "$c" ] && [ "$n" = 0 ]; then echo "COMMENT-EDIT rebuilt 0"; else echo "COMMENT-EDIT ${c:-<no stats line>}"; fail=1; fi
# one fn body changes: math/next-rand's shift 13 becomes 12
sed -i '' 's/(arch\/i64-shl x 13)/(arch\/i64-shl x 12)/' "$t/rt/llvm/math.lg"
c=$(stats); n=$(rebuilt "$c")
if [ -n "$c" ] && [ "$n" -ge 1 ] && [ "$n" -le "$edit_max" ]; then echo "BODY-EDIT rebuilt $n <= $edit_max"
else echo "BODY-EDIT ${c:-<no stats line>} (want 1..$edit_max)"; fail=1; fi
else echo "PARTIAL skipped (LLVM_RTLIB_PARTIAL=1 runs it)"; fi

[ $fail -eq 0 ] && echo "llvm-rtlib: OK" || echo "llvm-rtlib: FAILED"
exit $fail
