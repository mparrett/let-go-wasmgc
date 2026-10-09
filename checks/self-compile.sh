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
# LW_HOST_FS=1 (D208): lw_rt reads files at load time (rt/wasm/README.md's
# load order, the runtime sources, lw_ext.lg), so the module is built with
# the host file-system row and run.mjs serves its slurp from this machine's
# files. lw_rt reads let-go's core.lg/string.lg with `git show`, which a
# module cannot run, so both runs read them from a git archive of the pinned
# commit instead (LW_LETGO_CORE, the same text `git show` gives).
# D209 (step 1): the copy also writes lw-rt's load-time snapshot, and the
# native run is repeated restored from it (LW_RT_SNAPSHOT, no runtime source
# read) and must print the same; the module build still reads the sources.
# The module's output must equal native lg's. Prints MATCH or MISMATCH, the
# module size and the wall time. Exit 0 iff MATCH. With LW_TRACE=1 a failure
# shows the evaluator's cause chain in place of `calling <ns-init>` (driver.lg).
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
letgo_commit=$(sed -n 's/^(def letgo-commit "\([0-9a-f]*\)")$/\1/p' "$root/src/lw_rt.lg")
mkdir -p "$t/letgo"
if ! git -C "$LETGO" archive "$letgo_commit" pkg/rt/core 2>"$t/git.err" | tar -x -C "$t/letgo"; then
  echo "cannot archive pkg/rt/core at let-go ${letgo_commit:-?} from $LETGO:"; cat "$t/git.err"; exit 1
fi
export LW_HOST_FS=1 LW_LETGO_CORE=$t/letgo/pkg/rt/core
if ! "$LG" -source-paths "$t/src" "$prog" >"$t/native.txt" 2>&1; then
  echo "native run failed (the renamed copy does not load natively):"; tail -5 "$t/native.txt"; exit 1
fi
if ! LW_RT_SNAPSHOT_WRITE=$t/rt-snapshot.edn "$LG" -source-paths "$t/src" -e "(require 'lwx.lw-rt)" >"$t/snapshot.log" 2>&1; then
  echo "snapshot write failed:"; tail -5 "$t/snapshot.log"; exit 1
fi
if ! LW_RT_SNAPSHOT=$t/rt-snapshot.edn "$LG" -source-paths "$t/src" "$prog" >"$t/native-restored.txt" 2>&1; then
  echo "native run restored from the snapshot failed:"; tail -5 "$t/native-restored.txt"; exit 1
fi
if ! cmp -s "$t/native.txt" "$t/native-restored.txt"; then
  echo "MISMATCH self-compile: the native run restored from the snapshot differs:"; diff "$t/native.txt" "$t/native-restored.txt" | head -20; exit 1
fi
echo "native restored from the snapshot ($(wc -c <"$t/rt-snapshot.edn" | tr -d ' ') bytes) prints: $(head -1 "$t/native-restored.txt")"
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
  echo "MISMATCH self-compile: module build/run exited $rc (module ${size:-?} bytes; ${secs}s):"
  grep -v '^kept ' "$t/module.err" | grep -v '^\s*at ' | grep -v '^\s*$' | head -8; exit 1
fi
if cmp -s "$t/native.txt" "$t/module.txt"; then
  echo "MATCH self-compile (module ${size:-?} bytes; ${secs}s)"
else
  echo "MISMATCH self-compile (module ${size:-?} bytes; ${secs}s):"; diff "$t/native.txt" "$t/module.txt" | head -20; exit 1
fi
