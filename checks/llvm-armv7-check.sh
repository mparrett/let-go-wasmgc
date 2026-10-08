#!/usr/bin/env bash
# P12.20 (D202): the 32-bit early check. Runs the fixnum edges and the scalar
# programs that fit without a collector on targets/armv7-virt.edn under qemu
# through checks/oracle.sh; exit 0 when every one MATCHes native lg.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
fail=0
for p in corpus/llvm/fixnum-edges.lg corpus/llvm-scalar/loop-recur.clj corpus/llvm-scalar/fib.clj corpus/llvm-scalar/ref.lg; do
  r=$(LW_PROFILE=armv7-virt WASM_RUN="$here/checks/native-run.sh" "$here/checks/oracle.sh" "$here/$p" 2>&1 | head -1)
  echo "$r $p"; [ "$r" = MATCH ] || fail=1
done
exit $fail
