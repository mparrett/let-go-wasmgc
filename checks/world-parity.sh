#!/usr/bin/env bash
# checks/world-parity.sh [--keys wait|autoex|descend|deep|<string>] [N] [turns]
# Phase 3 oracle: corpus/dump-world.lg must print identical bytes under native
# lg and under the backend for seeds 1..N. Native side needs xsofy on the
# source path; the backend side is checks/wasm-run.sh, which reads the same
# -source-paths from LG_ARGS (P3.2). --keys picks the keystroke fixture
# (corpus/depth/measure.lg's shapes: autoex = "x" then waits, descend = ">"
# then waits; neither leaves floor 1 in 200 turns, since ">" only routes to
# stairs already seen). deep = 98 autoexplore steps then ">" each turn, which
# descends to floor 2 on seeds 7, 9 and 10 by turn ~130 (native, 2026-10-01).
# Any other value is passed through as dump-world's keys string.
# SEEDS="7 9 10" replaces 1..N.
# The module is compiled once and reused across seeds (LW_MODULE_CACHE).
# Prints one line per seed, the module size, and "n/N MATCH"; exit 0 iff all
# MATCH, 2 if the backend runner is missing.
set -uo pipefail
cd "$(dirname "$0")/.."
KEYS=wait
if [ "${1:-}" = --keys ]; then KEYS=$2; shift 2; fi
N=${1:-20}; TURNS=${2:-60}
. "$(dirname "$0")/env.sh"
XSOFY=${XSOFY:-$LW_ROOT/xsofy}
[ -x checks/wasm-run.sh ] || { echo "NOT IMPLEMENTED: checks/wasm-run.sh missing"; exit 2; }
dots=$(printf '%*s' "$TURNS" '' | tr ' ' .)
case "$KEYS" in
  wait) keys=. ;;
  autoex) keys="x${dots:1}" ;;
  descend) keys=">${dots:1}" ;;
  deep) keys="$(printf '%98s' '' | tr ' ' x)$(printf '%*s' "$TURNS" '' | tr ' ' '>')" ;;
  *) keys=$KEYS ;;
esac
cache=${LW_MODULE_CACHE:-$(mktemp -d)}
[ -n "${LW_MODULE_CACHE:-}" ] || trap 'rm -rf "$cache"' EXIT
export LW_MODULE_CACHE=$cache
ok=0
seeds=${SEEDS:-$(seq 1 "$N")}
N=$(wc -w <<<"$seeds" | tr -d ' ')
for seed in $seeds; do
  r=$(LG_ARGS="-source-paths $XSOFY" XSOFY_ROOT="$XSOFY" WASM_RUN=checks/wasm-run.sh checks/oracle.sh corpus/dump-world.lg "$seed" "$TURNS" "$keys" 2>&1)
  printf '%-16s seed %s\n' "$(head -1 <<<"$r")" "$seed"
  [ "$(head -1 <<<"$r")" = MATCH ] && ok=$((ok+1))
  [ "$(head -1 <<<"$r")" = MATCH ] || sed -n '2,4p' <<<"$r" | cut -c1-300
done
# the module this run used: the newest in the cache
m=""; for f in "$cache"/*.wasm; do [ -f "$f" ] && { [ -z "$m" ] || [ "$f" -nt "$m" ]; } && m=$f; done
if [ -n "$m" ]; then
  opt=$(/opt/homebrew/opt/binaryen/bin/wasm-opt -O3 --enable-gc --enable-reference-types --enable-exception-handling \
        --enable-bulk-memory --enable-tail-call --enable-multivalue "$m" -o - 2>/dev/null | wc -c | tr -d ' ')
  echo "module: $(wc -c <"$m" | tr -d ' ') bytes raw, $opt bytes after wasm-opt -O3"
fi
echo "$ok/$N MATCH (keys=$KEYS, turns=$TURNS)"
[ "$ok" -eq "$N" ]
