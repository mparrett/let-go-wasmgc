#!/usr/bin/env bash
# P12.3 (spec decision 6): no word-size assumptions in --target llvm output.
# Compiles a program under corpus/llvm-profile/word32-i686.edn (a 32-bit
# word, never run) and asserts that the module names its triple and data
# layout, that llc accepts it for that triple, and that boxed words are i32:
# the runtime helpers taking or returning a boxed word are declared with i32.
# Inputs: src/lower_llvm*.lg corpus/llvm/fixnum-edges.lg corpus/llvm-profile/.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
cp "$here/corpus/llvm/fixnum-edges.lg" "$t/p.lg"
if ! "$LG" -source-paths "$here/src" "$here/src/driver.lg" --target llvm --profile "$here/corpus/llvm-profile/word32-i686.edn" "$t/p.lg" "$t/p.ll" > "$t/c.log" 2>&1; then
  echo "FAIL compile"; sed -E 's/\x1b\[[0-9;]*m//g' "$t/c.log" | grep -m1 error; exit 1
fi
grep -q '^target triple = "i686-unknown-linux-gnu"' "$t/p.ll" && echo "ok   target triple" || { echo "FAIL target triple"; fail=1; }
grep -q '^target datalayout = ' "$t/p.ll" && echo "ok   target datalayout" || { echo "FAIL target datalayout"; fail=1; }
if "$llvm/llc" -O2 -mtriple=i686-unknown-linux-gnu "$t/p.ll" -o /dev/null 2> "$t/llc.log"; then echo "ok   llc i686"; else echo "FAIL llc i686: $(head -1 "$t/llc.log")"; fail=1; fi
for d in 'declare i32 @lg_box_int(i64)' 'declare i64 @lg_unbox_int(i32)' 'declare i32 @lg_truthy(i32)' 'declare void @lg_print_box(i32)'; do
  grep -qF "$d" "$t/p.ll" && echo "ok   $d" || { echo "FAIL missing: $d"; fail=1; }
done
exit $fail
