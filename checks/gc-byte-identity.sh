#!/usr/bin/env bash
# GC regression guard, baseline frozen at the last pre-linear main (re-frozen 2026-10-09 at
# d3aa439, D212: the evaluator's dotimes writes core/< and core/inc, so every program carrying the
# evaluator moves and dotimes-hygiene.lg joins the corpus; before that 2026-10-09 at
# 6782b56, D211's lw-ext \p{Lu}/\p{Ll}/\p{L} classes: every corpus/eval program and legmacs
# grow ~4,982 bytes (they reach the regex engine), regex-uprops.lg joins the corpus; before that
# 2026-10-09 at 90da78e, D210 with the P12.0 fixes: alter-own-defn.lg joins the corpus; before that 2026-10-08 at
# 1c5ff7c, D209 step 2: wasm.natives' create-ns twin and interned vars carrying meta; before that 2026-10-08 at
# dcf502c, P12.0f load-string twin; before that 2026-10-08 at 8bdbf97, the D207 rooting rule; before that 2026-10-07 at 4d6fbc2, D204 with its review fixes (symbol of a var without the #' prefix, instance? with nil); before that 2026-10-07 at
# d0693f3, D199's directly lowered constants; before that 167f95e, the let-go ff1e6dac pin with D198 and the deferred read-json conversion; before
# that 6a8401b, the pin alone; before that 2026-10-05 at 138f341, after
# D185-D187; 2026-10-04 at 7b87007, first 2026-10-03 at 3c5011e).
# Inputs: src/, rt/, corpus/scalar/, corpus/eval/, legmacs' main.lg, pinned baseline commit.
# --capture compiles the baseline only; otherwise compare default and explicit GC.
# Covers the default option set from a fresh rtlib only (no --no-rt, --test,
# --no-shake, LW_NO_EVAL or warm cache). legmacs is here because load-time
# compiler state (D174) shifted its IR numbering while every small program
# stayed identical.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
base=d3aa4398f57653fbb0fcc0e07392ef3f6dff0a85
cache=${LW_GC_BASELINE_DIR:-${TMPDIR:-/tmp}/lw-gc-byte-identity-$base}
mkdir -p "$cache"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
git archive "$base" src rt | tar -xf - -C "$t"
find corpus/scalar corpus/eval -type f \( -name '*.lg' -o -name '*.clj' \) ! -path '*/lib/*' | LC_ALL=C sort > "$t/programs"
echo "$LEGMACS/main.lg" >> "$t/programs"
# a moved corpus or a wrong tree must not pass with nothing compared
n=$(wc -l < "$t/programs" | tr -d ' ')
[ "$n" -ge 21 ] || { echo "GC byte identity: only $n programs found, expected at least 21" >&2; exit 1; }
compile() {
  local source=$1 f=$2 out=$3 target=${4:-} sp="" lane=baseline
  if [ "$source" = "$PWD" ]; then lane=${target:-default}; fi
  # legmacs builds its own rtlib in every lane: its baseline may be captured in a
  # later run than the corpus, and a restored rtlib differs from a fresh one (D173)
  case "$f" in */multi/*) sp="$PWD/corpus/eval/program/multi/lib" ;; "$LEGMACS"/*) sp=$LEGMACS lane=$lane-legmacs ;; esac
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
echo "GC byte identity: $n programs (baseline $base)"
