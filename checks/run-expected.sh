#!/usr/bin/env bash
# Runs each *.lg in the given dirs through $WASM_RUN (default
# checks/wasm-run.sh) and compares its stdout and exit status with
# <prog>.out, whose last line is `exit <n>`. For programs whose behavior is
# meant to differ from native lg (a lane's placeholder, Clojure semantics
# where let-go's differ), so the oracle cannot judge them. Prints MATCH or
# DIFF per program and a k/n total; exits 1 on any DIFF.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
run=${WASM_RUN:-$here/checks/wasm-run.sh}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
n=0; ok=0
for d in "$@"; do
  for p in "$d"/*.lg; do
    [ -f "$p.out" ] || { echo "NO-EXPECTED $p"; n=$((n + 1)); continue; }
    n=$((n + 1))
    "$run" "$p" > "$t/out" 2> "$t/err"; echo "exit $?" >> "$t/out"
    if cmp -s "$t/out" "$p.out"; then ok=$((ok + 1)); echo "MATCH $p"
    else echo "DIFF $p"; diff "$p.out" "$t/out" | head -20; head -3 "$t/err"; fi
  done
done
echo "$ok/$n MATCH"
[ "$ok" = "$n" ]
