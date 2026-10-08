#!/usr/bin/env bash
# Plan review focus 5 (spec decision 11): on a bare profile, running out of
# heap is a named error, not a hang or a fault. Runs corpus/scalar/fib.clj
# under targets/armv7-virt-tiny.edn (64 KB heap) and asserts exit 1 with
# "error: out of memory" in the output.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
out=$(LW_PROFILE=armv7-virt-tiny timeout 300 "$here/checks/native-run.sh" "$here/corpus/scalar/fib.clj" 2>&1); rc=$?
if [ "$rc" = 1 ] && printf '%s\n' "$out" | grep -qx 'error: out of memory'; then echo "ok   out of memory is a named error (exit 1)"; exit 0; fi
echo "FAIL exit $rc: $(printf '%s\n' "$out" | tail -2 | tr '\n' ' ')"; exit 1
