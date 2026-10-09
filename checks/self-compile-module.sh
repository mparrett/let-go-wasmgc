# checks/self-compile-module.sh — sourced by checks/self-compile-assemble.sh
# (P12.4) and checks/self-compiled-run.sh (P12.5), so both build the same
# module the same way. Needs $root, $t (a scratch dir) and env.sh sourced.
#
# sc_setup: the rename of checks/self-compile.sh, plus the driver's own
# namespace, into $t/src/lwx; let-go's pkg/rt/core at the pinned commit into
# $t/letgo (LW_LETGO_CORE) and $t/ir (the ir/ library root, D210); exports
# LW_RT_DIR, LW_HOST_FS=1, LW_HOST_ASM=1 (both terms of the rtlib key and of
# the snapshot's flags), LW_LETGO_CORE and the persistent rtlib dir
# LW_RTLIB_DIR (LW_SELF_COMPILE_CACHE); sets $lib. Then writes the D209
# snapshot from the copy to $t/rt-snapshot.edn.
# sc_build <fixture.lg>: builds the fixture against the copy (program table on)
# to $t/m.wasm; sets $size and $build (seconds). Both return 1 with the reason
# on stdout.
sc_setup() {
  mkdir -p "$t/src/lwx"
  local f
  for f in lw_rt.lg lw_ext.lg lower_wasm.lg lower_linear.lg testshim.lg driver.lg; do
    sed -E \
      -e 's/(^|[^a-zA-Z0-9.-])lower-wasm([^a-zA-Z0-9:-]|$)/\1lwx.lower-wasm\2/g' \
      -e 's/(^|[^a-zA-Z0-9.-])lw-rt([^a-zA-Z0-9-]|$)/\1lwx.lw-rt\2/g' \
      -e 's/(^|[^a-zA-Z0-9.-])lw-ext([^a-zA-Z0-9-]|$)/\1lwx.lw-ext\2/g' \
      -e 's/^\(ns driver$/(ns lwx.driver/' \
      "$root/src/$f" > "$t/src/lwx/$f"
  done
  grep -q '^(ns lwx.driver$' "$t/src/lwx/driver.lg" || { echo "rename failed: driver.lg's ns form moved"; return 1; }
  export LW_RT_DIR=$root/rt/wasm
  local letgo_commit
  letgo_commit=$(sed -n 's/^(def letgo-commit "\([0-9a-f]*\)")$/\1/p' "$root/src/lw_rt.lg")
  mkdir -p "$t/letgo" "$t/ir"
  if ! git -C "$LETGO" archive "$letgo_commit" pkg/rt/core 2>"$t/git.err" | tar -x -C "$t/letgo" ||
     ! git -C "$LETGO" archive "$letgo_commit" pkg/rt/core/ir 2>"$t/git.err" | tar -x -C "$t/ir"; then
    echo "cannot archive pkg/rt/core at let-go ${letgo_commit:-?} from $LETGO:"; cat "$t/git.err"; return 1
  fi
  export LW_HOST_FS=1 LW_HOST_ASM=1 LW_LETGO_CORE=$t/letgo/pkg/rt/core
  lib=$t/src:$t/ir/pkg/rt/core
  export LW_RTLIB_DIR=${LW_SELF_COMPILE_CACHE:-${TMPDIR:-/tmp}/lw-self-compile-rtlib}
  mkdir -p "$LW_RTLIB_DIR"
  if ! LW_RT_SNAPSHOT_WRITE=$t/rt-snapshot.edn "$LG" -source-paths "$lib" -e "(require 'lwx.lw-rt)" >"$t/snapshot.log" 2>&1; then
    echo "snapshot write failed:"; tail -5 "$t/snapshot.log"; return 1
  fi
}
sc_build() {
  local start; start=$(date +%s)
  if ! LW_PROGRAM_TABLE=1 "$LG" -source-paths "$root/src:$lib" "$root/src/driver.lg" -source-paths "$lib" "$1" "$t/m.wat" >"$t/module.err" 2>&1 ||
     ! wasm-tools parse "$t/m.wat" -o "$t/m.wasm" 2>>"$t/module.err"; then
    echo "module build failed ($(( $(date +%s) - start ))s):"
    grep -v '^\s*at ' "$t/module.err" | grep -v '^\s*$' | head -8; return 1
  fi
  size=$(wc -c <"$t/m.wasm" | tr -d ' ')
  build=$(( $(date +%s) - start ))
}
