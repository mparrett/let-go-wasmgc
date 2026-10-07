#!/usr/bin/env bash
# checks/rtlib-rooted-share.sh — P9.3 (D201). A runtime fn that calls a native
# the program roots (alter-var-root of #'future*, which core/pmap calls)
# lowers through the var's root, so the runtime library depends on the
# program's rooted natives. Compiles checks/fixtures/rtlib-rooted/plain.lg
# (roots nothing) and then rooted.lg through one shared library cache, and
# rooted.lg again from a fresh cache: the two rooted.lg modules must be
# byte-identical. Before the key included the rooted natives, the shared
# compile restored plain.lg's library, pmap called future* statically, and
# the program counted 0 futures where native lg counts 3.
# Inputs: src/, rt/, the two fixtures, checks/env.sh. Two library builds.
set -uo pipefail
. "$(dirname "$0")/env.sh"
cd "$(dirname "$0")/.."
fx=checks/fixtures/rtlib-rooted
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
drv=("$LG" -source-paths "$PWD/src" src/driver.lg)
LW_RTLIB_DIR="$t/shared" "${drv[@]}" "$fx/plain.lg" "$t/plain.wat" >"$t/plain.log" 2>&1 || { echo "plain compile failed"; tail -5 "$t/plain.log"; exit 1; }
LW_RTLIB_DIR="$t/shared" "${drv[@]}" "$fx/rooted.lg" "$t/shared.wat" >"$t/shared.log" 2>&1 || { echo "shared-cache compile failed"; tail -5 "$t/shared.log"; exit 1; }
LW_RTLIB_DIR="$t/fresh" "${drv[@]}" "$fx/rooted.lg" "$t/fresh.wat" >"$t/fresh.log" 2>&1 || { echo "fresh-cache compile failed"; tail -5 "$t/fresh.log"; exit 1; }
if cmp -s "$t/shared.wat" "$t/fresh.wat"; then
  echo "IDENTICAL shared/fresh $fx/rooted.lg ($(wc -c <"$t/fresh.wat") bytes)"
else
  echo "DIFFER shared/fresh $fx/rooted.lg"; diff "$t/fresh.wat" "$t/shared.wat" | head -8 | cut -c1-200; exit 1
fi
