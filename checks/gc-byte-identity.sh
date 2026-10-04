#!/usr/bin/env bash
# GC regression guard, baseline frozen at the last pre-linear main (re-frozen 2026-10-04 at
# 7b87007, after D181-D184; first frozen 2026-10-03 at 3c5011e).
# Inputs: src/, rt/, corpus/scalar/, corpus/eval/, pinned baseline commit.
# --capture compiles the baseline only; otherwise compare default and explicit GC.
# Each current lane gets an independent fresh rtlib, matching the baseline
# capture sequence. The original emitter has cold/warm cache byte variance.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
base=7b8700749665aa6748e42c2c15206ec07cda5f32
cache=${LW_GC_BASELINE_DIR:-${TMPDIR:-/tmp}/lw-gc-byte-identity-$base}
mkdir -p "$cache"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
git archive "$base" src rt | tar -xf - -C "$t"
find corpus/scalar corpus/eval -type f \( -name '*.lg' -o -name '*.clj' \) ! -path '*/lib/*' | LC_ALL=C sort > "$t/programs"
compile() {
  local source=$1 f=$2 out=$3 target=${4:-} sp="" lane=baseline
  if [ "$source" = "$PWD" ]; then lane=${target:-default}; fi
  case "$f" in */multi/*) sp="$PWD/corpus/eval/program/multi/lib" ;; esac
  local args=("$LG" -source-paths "$source/src${sp:+:$sp}" "$source/src/driver.lg")
  [ -z "$sp" ] || args+=(-source-paths "$sp")
  [ -z "$target" ] || args+=(--target "$target")
  env -u LW_TARGET -u LW_RT_DIR LW_NO_EVAL=0 LW_NO_PROGRAM_TABLE=0 LW_RTLIB_DIR="$t/rtlib-$lane" "${args[@]}" "$f" "$t/m.wat" > "$t/compile.log" 2>&1 || { cat "$t/compile.log" >&2; return 1; }
  wasm-tools parse "$t/m.wat" -o "$out"
}
while IFS= read -r f; do
  bin="$cache/$f.wasm"
  if [ ! -f "$bin" ]; then
    mkdir -p "$(dirname "$bin")"
    compile "$t" "$f" "$bin.tmp$$"
    mv "$bin.tmp$$" "$bin"
  fi
  if [ "${1:-}" != --capture ]; then
    compile "$PWD" "$f" "$t/default.wasm"
    cmp "$bin" "$t/default.wasm" || { wasm-tools print "$bin" -o "$cache/baseline-failure.wat"; wasm-tools print "$t/default.wasm" -o "$cache/current-failure.wat"; echo "GC BYTE MISMATCH $f (diagnostics retained in baseline cache)" >&2; exit 1; }
    compile "$PWD" "$f" "$t/explicit.wasm" gc
    cmp "$bin" "$t/explicit.wasm" || { echo "EXPLICIT GC BYTE MISMATCH $f" >&2; exit 1; }
    echo "IDENTICAL $f"
  else
    echo "CAPTURED $f"
  fi
done < "$t/programs"
echo "GC byte identity: $(wc -l < "$t/programs" | tr -d ' ') programs (baseline $base)"
