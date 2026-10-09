#!/usr/bin/env bash
# GC regression guard, baseline frozen at the last pre-linear main (re-frozen 2026-10-07 at
# 4d6fbc2, D204 with its review fixes (symbol of a var without the #' prefix, instance? with nil); before that 2026-10-07 at
# d0693f3, D199's directly lowered constants; before that 167f95e, the let-go ff1e6dac pin with D198 and the deferred read-json conversion; before
# that 6a8401b, the pin alone; before that 2026-10-05 at 138f341, after
# D185-D187; 2026-10-04 at 7b87007, first 2026-10-03 at 3c5011e).
# Inputs: src/, rt/, corpus/scalar/, corpus/eval/, legmacs' main.lg, pinned baseline commit.
# --capture compiles the baseline only; otherwise compare default and explicit GC.
# --default-only skips the explicit-GC compile and cmp, halving the run: use it
# for iteration. The final run before a commit or PR is both lanes (no flag).
# --capture and --default-only together are rejected: capture compares nothing.
# The baseline cache is shared: one dir per base SHA is the intended use, so
# several agents reuse one capture instead of each paying ~30 min for its own.
# Private dirs (LW_GC_BASELINE_DIR) are only for experiments. A cache dir is valid
# only with a $cache/.complete marker, written after EVERY program has been
# captured in one pass, in corpus order, through one rtlib dir; a dir without it
# (a partial or older capture) is recaptured in full, never filled in one
# program at a time. The pass holds a mkdir lock ($cache/.lock, holder pid
# inside; a dead holder is reclaimed) from start to marker, so a concurrent run
# waits and then finds the marker. Each baseline is moved into place atomically
# and nothing is read before the marker exists. Wait is bounded by LW_GC_LOCK_WAIT
# (default 7200 s), after which the pass runs anyway with a warning: it only
# costs duplicate work.
# Each compile holds one slot of the machine-wide pool (checks/sem.sh).
# The cache is keyed by base SHA, but its bytes also depend on the lg binary and
# the legmacs checkout. $cache/.meta records lg's md5 and legmacs' commit; a run
# whose values differ refuses (never recaptures silently). A dir with baselines
# but no .meta (captured before this check) gets one written, with a warning.
# The lg path is recorded for the reader only: a copied binary with the same md5
# is the same lg.
# Covers the default option set (no --no-rt, --test, --no-shake or LW_NO_EVAL).
# Baseline and compare both compile in corpus order through ONE warm rtlib dir
# per lane, and the output of some programs depends on that order: on 2026-10-08
# registry-probe came out with one local $v64 vs $v65 in a wasm.natives fn when
# compared warm against a baseline captured alone from a fresh rtlib. That is a
# backend determinism defect, recorded in STATUS.md (P8.0 notes) as a named
# finding; the guard's answer is to capture and compare in the same order, not
# to hide it. legmacs is here because load-time compiler state (D174) shifted
# its IR numbering while every small program stayed identical.
set -euo pipefail
cd "$(dirname "$0")/.."
capture=0 default_only=0
for a in "$@"; do
  case "$a" in
    --capture) capture=1 ;;
    --default-only) default_only=1 ;;
    *) echo "usage: $0 [--capture | --default-only]" >&2; exit 2 ;;
  esac
done
[ "$capture$default_only" != 11 ] || { echo "--capture and --default-only cannot combine: capture compares nothing" >&2; exit 2; }
. checks/env.sh
base=4d6fbc2faec2a03db3ed2b37fd976dabcfb1322e
cache=${LW_GC_BASELINE_DIR:-${TMPDIR:-/tmp}/lw-gc-byte-identity-$base}
mkdir -p "$cache"
t=$(mktemp -d)
held=""
unlock() { if [ -n "$held" ]; then rm -rf "$held"; held=""; fi; }
trap 'unlock; rm -rf "$t"' EXIT
# mkdir is the atomic primitive (no flock on macOS bash 3); see checks/sem.sh
lock() {
  local l=$cache/.lock deadline=$(( $(date +%s) + ${LW_GC_LOCK_WAIT:-7200} )) p dead
  while ! mkdir "$l" 2>/dev/null; do
    p=$(cat "$l/pid" 2>/dev/null || true)
    # no pid yet and older than 5 s: the holder died between mkdir and the write
    if { [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; } || { [ -z "$p" ] && [ $(( $(date +%s) - $(stat -f %m "$l" 2>/dev/null || echo 0) )) -gt 5 ]; }; then
      dead=$l.dead.$$
      # rename, not rm: two reclaimers cannot both delete a lock a third just took
      if command mv "$l" "$dead" 2>/dev/null; then rm -rf "$dead"; fi
      continue
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "gc-byte-identity: lock wait exceeded, capturing without the lock (atomic mv keeps it safe)" >&2
      return 0
    fi
    sleep 0.5
  done
  echo $$ > "$l/pid"
  held=$l
}
git archive "$base" src rt | tar -xf - -C "$t"
find corpus/scalar corpus/eval -type f \( -name '*.lg' -o -name '*.clj' \) ! -path '*/lib/*' | LC_ALL=C sort > "$t/programs"
echo "$LEGMACS/main.lg" >> "$t/programs"
# a moved corpus or a wrong tree must not pass with nothing compared
n=$(wc -l < "$t/programs" | tr -d ' ')
[ "$n" -ge 21 ] || { echo "GC byte identity: only $n programs found, expected at least 21" >&2; exit 1; }
compile() {
  local source=$1 f=$2 out=$3 target=${4:-} sp="" lane=baseline
  if [ "$source" = "$PWD" ]; then lane=${target:-default}; fi
  # legmacs builds its own rtlib in every lane: a restored rtlib differs from a
  # fresh one (D173)
  case "$f" in */multi/*) sp="$PWD/corpus/eval/program/multi/lib" ;; "$LEGMACS"/*) sp=$LEGMACS lane=$lane-legmacs ;; esac
  local args=("$LG" -source-paths "$source/src${sp:+:$sp}" "$source/src/driver.lg")
  [ -z "$sp" ] || args+=(-source-paths "$sp")
  [ -z "$target" ] || args+=(--target "$target")
  env -u LW_TARGET -u LW_RT_DIR LW_NO_EVAL=0 LW_NO_PROGRAM_TABLE=0 LW_RTLIB_DIR="$t/rtlib-$lane" "$PWD/checks/sem.sh" "${args[@]}" "$f" "$t/m.wat" > "$t/compile.log" 2>&1 || { cat "$t/compile.log" >&2; return 1; }
  wasm-tools parse "$t/m.wat" -o "$out"
}
# bytes depend on the lg binary and the legmacs checkout, not only the base SHA
meta_now="lg_md5=$(md5 -q "$LG")
legmacs=$(git -C "$LEGMACS" rev-parse HEAD 2>/dev/null || echo none)"
write_meta() { { echo "lg=$LG"; echo "$meta_now"; } > "$cache/.meta.tmp$$"; mv "$cache/.meta.tmp$$" "$cache/.meta"; }
meta_check() {
  local m=$cache/.meta field have want
  if [ ! -f "$m" ]; then
    echo "warning: $cache is complete but has no .meta; recording the current lg and legmacs, assuming they match" >&2
    write_meta; return
  fi
  for field in lg_md5 legmacs; do
    have=$(sed -n "s/^$field=//p" "$m"); want=$(printf '%s\n' "$meta_now" | sed -n "s/^$field=//p")
    [ "$have" = "$want" ] || { echo "GC baseline cache $cache was captured with $field=$have, this run has $field=$want: use another LW_GC_BASELINE_DIR (or delete the cache) rather than compare across them" >&2; exit 1; }
  done
}
# One pass over every program, in the order the compare loop uses, so the
# baseline sees the same rtlib warm-up as the compare (see the header).
capture_all() {
  lock
  # another run may have finished the pass while this one waited
  if [ ! -f "$cache/.complete" ]; then
    rm -f "$cache/.meta"
    write_meta
    while IFS= read -r f; do
      mkdir -p "$(dirname "$cache/$f.wasm")"
      echo "capturing $f"
      compile "$t" "$f" "$cache/$f.wasm.tmp$$" || { rm -f "$cache/$f.wasm.tmp$$"; exit 1; }
      mv "$cache/$f.wasm.tmp$$" "$cache/$f.wasm"
    done < "$t/programs"
    : > "$cache/.complete"
  fi
  unlock
}
[ -f "$cache/.complete" ] || capture_all
meta_check
if [ "$capture" = 0 ]; then
  while IFS= read -r f; do
    bin="$cache/$f.wasm"
    compile "$PWD" "$f" "$t/default.wasm"
    cmp "$bin" "$t/default.wasm" || { wasm-tools print "$bin" -o "$cache/baseline-failure.wat"; wasm-tools print "$t/default.wasm" -o "$cache/current-failure.wat"; echo "GC BYTE MISMATCH $f (diagnostics retained in baseline cache)" >&2; exit 1; }
    if [ "$default_only" = 0 ]; then
      compile "$PWD" "$f" "$t/explicit.wasm" gc
      cmp "$bin" "$t/explicit.wasm" || { echo "EXPLICIT GC BYTE MISMATCH $f" >&2; exit 1; }
    fi
    echo "IDENTICAL $f"
  done < "$t/programs"
fi
if [ "$capture" = 1 ]; then lanes="none (capture only)"
elif [ "$default_only" = 1 ]; then lanes="default only"
else lanes="default, explicit-gc"; fi
echo "GC byte identity: $n programs (baseline $base) lanes: $lanes, $(date +%F)"
