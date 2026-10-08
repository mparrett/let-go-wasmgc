#!/usr/bin/env bash
# checks/self-compile.sh — row P12.0: the backend carried as a program
# (stage 2 of the self-compiling-backend plan, D205/D206).
#
# Copies src/ to a temp dir with the namespaces renamed (lower-wasm ->
# lwx.lower-wasm, lw-rt -> lwx.lw-rt, lw-ext -> lwx.lw-ext; files under
# lwx/ so require finds them) so the driver's own lower-wasm stays loaded
# beside the copy, leaves driver.lg out (it calls -main at load), and
# compiles checks/fixtures/self-compile/main.lg with the copy as a library
# source path. LW_RT_DIR points the copy at the real rt/wasm. LW_PROGRAM_TABLE=1
# because lw_rt's load-time code resolves through the registry.
# The module's output must equal native lg's. Prints MATCH or MISMATCH, the
# module size and the wall time. Exit 0 iff MATCH.
#
# Rename trap: the sed must also match a name at end of line ((ns lw-rt with
# nothing after it) or the file defines into the old ns and its in-ns switches
# to the new one, which reads as "Can't resolve <first def> in this context".
#
# Env: LG, LETGO (env.sh), LW_RTLIB_DIR.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"
export LG
prog=$root/checks/fixtures/self-compile/main.lg
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
mkdir -p "$t/src/lwx"
for f in lw_rt.lg lw_ext.lg lower_wasm.lg lower_linear.lg testshim.lg; do
  sed -E \
    -e 's/(^|[^a-zA-Z0-9.-])lower-wasm([^a-zA-Z0-9:-]|$)/\1lwx.lower-wasm\2/g' \
    -e 's/(^|[^a-zA-Z0-9.-])lw-rt([^a-zA-Z0-9-]|$)/\1lwx.lw-rt\2/g' \
    -e 's/(^|[^a-zA-Z0-9.-])lw-ext([^a-zA-Z0-9-]|$)/\1lwx.lw-ext\2/g' \
    "$root/src/$f" > "$t/src/lwx/$f"
done
export LW_RT_DIR=$root/rt/wasm
if ! "$LG" -source-paths "$t/src" "$prog" >"$t/native.txt" 2>&1; then
  echo "native run failed (the renamed copy does not load natively):"; tail -5 "$t/native.txt"; exit 1
fi
start=$(date +%s)
LW_PROGRAM_TABLE=1 LG_ARGS="-source-paths $t/src" KEEP=1 \
  bash "$root/checks/wasm-run.sh" "$prog" >"$t/module.txt" 2>"$t/module.err"
rc=$?
kept=$(sed -n 's/^kept //p' "$t/module.err" | tail -1)
size=""
[ -n "$kept" ] && [ -f "$kept/m.wasm" ] && size=$(wc -c <"$kept/m.wasm" | tr -d ' ')
[ -n "$kept" ] && command rm -rf "$kept"
secs=$(( $(date +%s) - start ))
if [ $rc -ne 0 ]; then
  echo "MISMATCH self-compile: module build/run exited $rc (${secs}s):"
  grep -v '^kept ' "$t/module.err" | grep -v '^\s*at ' | grep -v '^\s*$' | head -8; exit 1
fi
if cmp -s "$t/native.txt" "$t/module.txt"; then
  echo "MATCH self-compile (module ${size:-?} bytes; ${secs}s)"
else
  echo "MISMATCH self-compile (module ${size:-?} bytes; ${secs}s):"; diff "$t/native.txt" "$t/module.txt" | head -20; exit 1
fi
