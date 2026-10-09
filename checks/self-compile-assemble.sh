#!/usr/bin/env bash
# checks/self-compile-assemble.sh — row P12.4: the host-import assembly seam
# (D206, D211). The backend carried as a program (checks/self-compile.sh's
# renamed copy of src/, here with driver.lg as lwx.driver) compiles
# corpus/scalar/ref.lg INSIDE the module through driver/compile-text and hands
# the text to env.assemble; src/run.mjs parses it with wasm-tools, writes the
# binary to LW_ASSEMBLE_OUT and the text beside it (<out>.wat).
#
# Oracle: wasm-tools parse of that saved text must give the saved binary
# byte for byte (MATCH; exit 0 iff it does). Also reported, not gating: the
# carried compiler's text against the native driver's for the same program
# and options (`driver.lg --no-rtlib`, same LW_* settings); a difference is
# a finding about the carried backend, not a failure of the seam.
#
# Builds as self-compile.sh does (LW_HOST_FS=1, the D209 snapshot written
# from the copy and restored in the module only, LW_LETGO_CORE and let-go's
# ir/ from the pinned commit, a persistent rtlib cache) plus LW_HOST_ASM=1,
# which is a term of the rtlib key and of the snapshot's flags, so the first
# run builds its own runtime library cold. --no-rtlib for ref.lg: the rtlib
# key hashes the lg binary through os/sh, which the module cannot run, so a
# carried compile would miss the cache and its rebuild would need spit.
#
# Prints the fixture's lines (the compile's "Elapsed time", the text's length
# and hex32, the binary's length), the module size and the build and run
# times. Env: LG, LETGO (env.sh), LW_SELF_COMPILE_CACHE (the rtlib dir), KEEP=1.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"
export LG
prog=$root/checks/fixtures/self-compile-assemble/main.lg
ref=$root/corpus/scalar/ref.lg
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
mkdir -p "$t/src/lwx"
# the rename of checks/self-compile.sh, plus the driver's own namespace
for f in lw_rt.lg lw_ext.lg lower_wasm.lg lower_linear.lg testshim.lg driver.lg; do
  sed -E \
    -e 's/(^|[^a-zA-Z0-9.-])lower-wasm([^a-zA-Z0-9:-]|$)/\1lwx.lower-wasm\2/g' \
    -e 's/(^|[^a-zA-Z0-9.-])lw-rt([^a-zA-Z0-9-]|$)/\1lwx.lw-rt\2/g' \
    -e 's/(^|[^a-zA-Z0-9.-])lw-ext([^a-zA-Z0-9-]|$)/\1lwx.lw-ext\2/g' \
    -e 's/^\(ns driver$/(ns lwx.driver/' \
    "$root/src/$f" > "$t/src/lwx/$f"
done
grep -q '^(ns lwx.driver$' "$t/src/lwx/driver.lg" || { echo "rename failed: driver.lg's ns form moved"; exit 1; }
export LW_RT_DIR=$root/rt/wasm
letgo_commit=$(sed -n 's/^(def letgo-commit "\([0-9a-f]*\)")$/\1/p' "$root/src/lw_rt.lg")
mkdir -p "$t/letgo" "$t/ir"
if ! git -C "$LETGO" archive "$letgo_commit" pkg/rt/core 2>"$t/git.err" | tar -x -C "$t/letgo" ||
   ! git -C "$LETGO" archive "$letgo_commit" pkg/rt/core/ir 2>"$t/git.err" | tar -x -C "$t/ir"; then
  echo "cannot archive pkg/rt/core at let-go ${letgo_commit:-?} from $LETGO:"; cat "$t/git.err"; exit 1
fi
export LW_HOST_FS=1 LW_HOST_ASM=1 LW_LETGO_CORE=$t/letgo/pkg/rt/core
lib=$t/src:$t/ir/pkg/rt/core
export LW_RTLIB_DIR=${LW_SELF_COMPILE_CACHE:-${TMPDIR:-/tmp}/lw-self-compile-rtlib}
mkdir -p "$LW_RTLIB_DIR"
if ! "$LG" -source-paths "$root/src" "$root/src/driver.lg" --no-rtlib "$ref" "$t/native.wat" >"$t/native.log" 2>&1; then
  echo "native compile of ref.lg failed:"; tail -5 "$t/native.log"; exit 1
fi
if ! LW_RT_SNAPSHOT_WRITE=$t/rt-snapshot.edn "$LG" -source-paths "$lib" -e "(require 'lwx.lw-rt)" >"$t/snapshot.log" 2>&1; then
  echo "snapshot write failed:"; tail -5 "$t/snapshot.log"; exit 1
fi
start=$(date +%s)
if ! LW_PROGRAM_TABLE=1 "$LG" -source-paths "$root/src:$lib" "$root/src/driver.lg" -source-paths "$lib" "$prog" "$t/m.wat" >"$t/module.err" 2>&1 ||
   ! wasm-tools parse "$t/m.wat" -o "$t/m.wasm" 2>>"$t/module.err"; then
  echo "MISMATCH self-compile-assemble: module build failed ($(( $(date +%s) - start ))s):"
  grep -v '^\s*at ' "$t/module.err" | grep -v '^\s*$' | head -8; exit 1
fi
size=$(wc -c <"$t/m.wasm" | tr -d ' ')
build=$(( $(date +%s) - start ))
echo "module built (${size} bytes; ${build}s)"
start=$(date +%s)
LW_RT_SNAPSHOT=$t/rt-snapshot.edn LW_ASSEMBLE_IN=$ref LW_ASSEMBLE_OUT=$t/ref.wasm \
  node "$root/src/run.mjs" "$t/m.wasm" "$prog" >"$t/module.txt" 2>"$t/module.err"
rc=$?
run=$(( $(date +%s) - start ))
sed 's/^/  module: /' "$t/module.txt"
if [ $rc -ne 0 ]; then
  echo "MISMATCH self-compile-assemble: the module exited $rc (${run}s):"
  grep -v '^\s*at ' "$t/module.err" | grep -v '^\s*$' | head -8; exit 1
fi
if [ ! -f "$t/ref.wasm" ] || [ ! -f "$t/ref.wasm.wat" ]; then
  echo "MISMATCH self-compile-assemble: the host kept no binary or text"; exit 1
fi
if cmp -s "$t/ref.wasm.wat" "$t/native.wat"; then
  echo "carried WAT for ref.lg is native's byte for byte ($(wc -c <"$t/native.wat" | tr -d ' ') bytes)"
else
  echo "carried WAT for ref.lg DIFFERS from native's (a finding, not this row's verdict):"
  diff "$t/native.wat" "$t/ref.wasm.wat" | head -12
fi
wasm-tools parse "$t/ref.wasm.wat" -o "$t/oracle.wasm" || { echo "MISMATCH self-compile-assemble: wasm-tools cannot parse the saved text"; exit 1; }
bin=$(wc -c <"$t/ref.wasm" | tr -d ' ')
if cmp -s "$t/ref.wasm" "$t/oracle.wasm" && grep -qx "binary $bin" "$t/module.txt"; then
  echo "MATCH self-compile-assemble (binary ${bin} bytes = wasm-tools'; module ${size} bytes; build ${build}s, run ${run}s)"
else
  echo "MISMATCH self-compile-assemble: the kept binary ($bin bytes) is not wasm-tools' for the same text ($(wc -c <"$t/oracle.wasm" | tr -d ' ') bytes) or the module saw another length"; exit 1
fi
