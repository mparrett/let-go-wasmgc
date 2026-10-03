#!/usr/bin/env bash
# checks/bench-fib.sh — P1.GATE perf bar: fib(32) compiled by the backend from
# corpus/scalar/fib.clj (checked arithmetic, hybrid boxing, as shipped) must
# run within 1.5x of the probe's fib-i31 variant (unchecked, i31 boxing,
# ^long-hinted source; ../emit-wasm-probe/ext/gen-ext.lg), both built fresh
# and timed in one node process. Exits 0 iff backend/probe <= 1.5.
# Env: LG, REPS (default 5).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/env.sh"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
"$LG" -source-paths "$here/src" "$here/src/driver.lg" "$here/corpus/scalar/fib.clj" "$t/backend.wat" >"$t/drv.log" 2>&1 \
  || { cat "$t/drv.log"; exit 1; }
"$LG" -source-paths "$here/../emit-wasm-probe" "$here/checks/bench-fib-probe.lg" "$t/probe.wat" >"$t/probe.log" 2>&1 \
  || { cat "$t/probe.log"; exit 1; }
wasm-tools parse "$t/backend.wat" -o "$t/backend.wasm" || exit 1
wasm-tools parse "$t/probe.wat" -o "$t/probe.wasm" || exit 1
node "$here/checks/bench-fib.mjs" "$t/backend.wasm" "$t/probe.wasm" "${REPS:-5}"
