#!/usr/bin/env bash
# checks/world-parity.sh [N] [turns] — Phase 3 oracle: corpus/dump-world.lg must
# print identical bytes under native lg and under the backend for seeds 1..N.
# Native side needs xsofy on the source path; the backend side is
# checks/wasm-run.sh, which must learn the same (P3.2). Prints one line per
# seed and "n/N MATCH"; exit 0 iff all MATCH, 2 if the backend runner is missing.
set -uo pipefail
cd "$(dirname "$0")/.."
N=${1:-20}; TURNS=${2:-60}
XSOFY=${XSOFY:-$HOME/projects-new/3p/xsofy}
[ -x checks/wasm-run.sh ] || { echo "NOT IMPLEMENTED: checks/wasm-run.sh missing"; exit 2; }
ok=0
for seed in $(seq 1 "$N"); do
  r=$(LG_ARGS="-source-paths $XSOFY" XSOFY_ROOT="$XSOFY" WASM_RUN=checks/wasm-run.sh checks/oracle.sh corpus/dump-world.lg "$seed" "$TURNS" 2>&1 | head -1)
  printf '%-16s seed %s\n' "$r" "$seed"
  [ "$r" = MATCH ] && ok=$((ok+1))
done
echo "$ok/$N MATCH"
[ "$ok" -eq "$N" ]
