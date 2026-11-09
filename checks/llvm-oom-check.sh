#!/usr/bin/env bash
# Plan review focus 5 (spec decision 11): running out of heap is a named
# error, not a hang or a fault. corpus/llvm/deep.lg keeps 10M pending
# continuations live, so no collection can make room: on a bare profile under
# targets/armv7-virt-tiny.edn (64 KB heap), on the host under a 1 MB
# LG_HEAP_BYTES budget. Each must exit 1 with "error: out of memory".
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
fail=0
check() {
  local what=$1; shift
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qx 'error: out of memory'; then echo "ok   $what: out of memory is a named error (exit 1)"
  else echo "FAIL $what: exit $rc: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"; fail=1; fi
}
check bare env LW_PROFILE=armv7-virt-tiny timeout 300 "$here/checks/native-run.sh" "$here/corpus/llvm/deep.lg"
check host env LG_HEAP_BYTES=1048576 timeout 300 "$here/checks/native-run.sh" "$here/corpus/llvm/deep.lg"
exit $fail
