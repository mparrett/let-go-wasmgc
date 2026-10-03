#!/usr/bin/env bash
# checks/legmacs-parity.sh [N] — P6.3: legmacs headless parity oracle.
# corpus/legmacs/dump-session.lg runs main.lg's editor loop without the
# terminal (dispatch / buffers / render on chord strings) for key script n
# and prints every step, the final buffers and the rendered frame (as a text
# grid and as raw ANSI); it must print identical bytes under native lg and
# under the backend (checks/oracle.sh, WASM_RUN=checks/wasm-run.sh) for
# scripts 1..N (default 5; SCRIPTS="2 4" replaces 1..N).
# Native side: lg -source-paths <legmacs root>; the backend side reads the
# same -source-paths from LG_ARGS. The module is compiled once and reused
# across scripts (LW_MODULE_CACHE; the script index is a run-time arg).
# Prints one line per script, the module size, "n/N MATCH"; exit 0 iff all
# MATCH. A backend compile failure is a MISMATCH (exit 1): the first error
# line from the driver is shown. Env: LG, LEGMACS (default the canonical
# checkout), KEEP=1.
set -uo pipefail
cd "$(dirname "$0")/.."
N=${1:-5}
. "$(dirname "$0")/env.sh"
LEGMACS=${LEGMACS:-$LW_ROOT/legmacs}
[ -x checks/wasm-run.sh ] || { echo "NOT IMPLEMENTED: checks/wasm-run.sh missing"; exit 2; }
[ -f corpus/legmacs/dump-session.lg ] || { echo "NOT IMPLEMENTED: corpus/legmacs/dump-session.lg missing"; exit 2; }
[ -d "$LEGMACS/legmacs" ] || { echo "FAIL: no legmacs checkout at $LEGMACS"; exit 1; }
cache=${LW_MODULE_CACHE:-$(mktemp -d)}
[ -n "${LW_MODULE_CACHE:-}" ] || trap 'rm -rf "$cache"' EXIT
export LW_MODULE_CACHE=$cache LG
scripts=${SCRIPTS:-$(seq 1 "$N")}
N=$(wc -w <<<"$scripts" | tr -d ' ')
newest() { local m="" f; for f in "$cache"/*.wasm; do [ -f "$f" ] && { [ -z "$m" ] || [ "$f" -nt "$m" ]; } && m=$f; done; echo "$m"; }
# compile once up front (fills the cache); a compile failure ends the run
# here with the driver's first error instead of recompiling per script
LG_ARGS="-source-paths $LEGMACS" checks/sem.sh checks/wasm-run.sh corpus/legmacs/dump-session.lg 1 >/dev/null 2>"$cache/first.err"
if [ -z "$(newest)" ]; then
  echo "COMPILE FAILED     (backend; no script ran)"
  sed -E 's/\x1b\[[0-9;]*m//g' "$cache/first.err" | grep -v catalog | grep -m1 -iE 'error|unsupported|failed' | cut -c1-400 | sed 's/^/backend: /'
  echo "0/$N MATCH (legmacs $(git -C "$LEGMACS" rev-parse --short HEAD 2>/dev/null))"
  exit 1
fi
ok=0
for n in $scripts; do
  r=$(LG_ARGS="-source-paths $LEGMACS" WASM_RUN=checks/wasm-run.sh checks/sem.sh checks/oracle.sh corpus/legmacs/dump-session.lg "$n" 2>&1)
  printf '%-18s script %s\n' "$(head -1 <<<"$r")" "$n"
  if [ "$(head -1 <<<"$r")" = MATCH ]; then ok=$((ok+1)); else sed -n '2,6p' <<<"$r" | cut -c1-300; fi
done
# the oracle reports only the exit class of a failing run; show the module's own error
[ "$ok" -eq "$N" ] || sed -E 's/\x1b\[[0-9;]*m//g' "$cache/first.err" | grep -v catalog | grep -m1 -iE 'error' | cut -c1-400 | sed 's/^/backend (script 1): /'
m=$(newest)
opt=$(/opt/homebrew/opt/binaryen/bin/wasm-opt -O3 --enable-gc --enable-reference-types --enable-exception-handling \
      --enable-bulk-memory --enable-tail-call --enable-multivalue "$m" -o - 2>/dev/null | wc -c | tr -d ' ')
echo "module: $(wc -c <"$m" | tr -d ' ') bytes raw, $opt bytes after wasm-opt -O3"
echo "$ok/$N MATCH (legmacs $(git -C "$LEGMACS" rev-parse --short HEAD 2>/dev/null))"
[ "$ok" -eq "$N" ]
