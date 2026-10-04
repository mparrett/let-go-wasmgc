#!/usr/bin/env bash
# checks/rtlib-cold-warm.sh [program] — P9.0 (D181). The runtime-library
# cache must be transparent: compiling a program from a fresh cache (cold,
# builds and saves the library) and again from the saved one (warm) must
# produce byte-identical module text. A restored library that forgets
# session state (the var-k / invoke-max counters, found 2026-10-03) shows
# up here as a diff in the dispatch helpers. Default program: the D181
# regression, whose eval reaches a k = 6 runtime fn value.
set -uo pipefail
. "$(dirname "$0")/env.sh"
cd "$(dirname "$0")/.."
prog=${1:-corpus/eval/program/apply-update-warm-cache.lg}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export LW_RTLIB_DIR="$t/rtlib"
drv=("$LG" -source-paths "$PWD/src" src/driver.lg)
"${drv[@]}" "$prog" "$t/cold.wat" >"$t/cold.log" 2>&1 || { echo "cold compile failed"; tail -5 "$t/cold.log"; exit 1; }
n=$(ls "$LW_RTLIB_DIR"/rtlib-*.edn 2>/dev/null | wc -l | tr -d ' ')
[ "$n" = 1 ] || { echo "expected one saved library after the cold compile, found $n"; exit 1; }
"${drv[@]}" "$prog" "$t/warm.wat" >"$t/warm.log" 2>&1 || { echo "warm compile failed"; tail -5 "$t/warm.log"; exit 1; }
if cmp -s "$t/cold.wat" "$t/warm.wat"; then
  echo "IDENTICAL cold/warm $prog ($(wc -c <"$t/cold.wat") bytes)"
else
  echo "DIFFER cold/warm $prog"; diff "$t/cold.wat" "$t/warm.wat" | head -20; exit 1
fi
