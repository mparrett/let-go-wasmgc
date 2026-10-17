#!/usr/bin/env bash
# Compare real compiled behavior with analysis reuse enabled and disabled.
# Build only the reachable runtime for the closure/exception fixture; the
# scalar fixture needs no runtime. Neither test builds a full snapshot.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
bash checks/llvm-analysis-input-check.sh
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
fixbits=$("$LG" -source-paths src checks/profile-field.lg host fixnum-bits)
for name in boxing forward templates; do
  prog="checks/fixtures/analysis-reuse/$name.lg"
  "$LG" "$prog" > "$t/$name.native"
  runtime=--no-rt
  [ "$name" != templates ] || runtime=--no-rtlib
  for mode in 0 1; do
    base="$t/$name.$mode"
    LW_LL_ANALYSIS_REUSE=$mode LW_LL_ANALYSIS_STATS=1 \
      "$LG" -source-paths src src/driver.lg --target llvm --profile host "$runtime" \
      "$prog" "$base.ll" > "$base.log" 2>&1 || { cat "$base.log"; exit 1; }
    "$llvm/clang" -O2 -w "-DLG_FIXNUM_BITS=$fixbits" \
      host/native/rt.c host/native/gc.c host/native/posix.c "$base.ll" -o "$base.bin"
    "$base.bin" > "$base.out"
    diff -u "$t/$name.native" "$base.out"
  done
  python3 - "$t/$name.0.log" "$t/$name.1.log" "$name" <<'PY'
import re, sys
from pathlib import Path
def stats(path):
    matches = re.findall(r'llvm-analysis-cache executed=(\d+) reused=(\d+) bypassed=(\d+) rounds=(\d+)', Path(path).read_text())
    assert len(matches) == 1, f'{path}: expected one cache statistics line, got {matches}'
    return tuple(map(int, matches[0]))
off, on = stats(sys.argv[1]), stats(sys.argv[2])
assert off[1] == 0, f'disabled reuse: {off}'
assert on[1] > 0, f'no actual reuse: {on}'
assert on[0] < off[0], f'analysis work did not fall: {off} -> {on}'
assert off[3] == on[3] and on[3] > 1, f'convergence rounds changed: {off} -> {on}'
if sys.argv[3] == 'templates':
    assert on[2] > 0, f'expected mutable child templates to bypass cache: {on}'
print(f'{sys.argv[3]}: native behavior matches; analyses {off[0]} -> {on[0]}, reused {on[1]}, rounds {on[3]}')
PY
done
