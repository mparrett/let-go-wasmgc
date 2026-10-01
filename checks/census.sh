#!/usr/bin/env bash
# checks/census.sh [--fallbacks] <corpus>...   corpus = xsofy | legmacs
#
# P1.5: every top-level fn unit of the corpus (the 2a census's harvesting) is
# lowered ALONE by the backend (checks/census.lg, compile only, nothing runs)
# and its module validated with wasm-tools; a unit that lowers but does not
# validate is bucketed `invalid-wat`. Writes corpus/census/<corpus>.tsv and
# corpus/census/<corpus>-summary.md.
#
# Exit 0 iff, on every corpus, no unit is `unsupported op` or `invalid-wat`.
# --fallbacks (P1.6) also requires 0 `goto fallback`, 0 `unsupported tree
# node`, and that legmacs.buffer/row-col-of and xsofy.fov/reveal-line compile
# (bucket ok / unbound-var / phase2-const).
#
# Calls to vars the corpus does not define compile to calls through nil
# var-table slots (native's run-time `TypeError: nil is not a function `);
# such units count as `unbound-var`, Phase 2/3's native-twin business.
#
# A corpus whose corpus/census/<corpus>.tsv is newer than every input (src/*.lg,
# checks/census.lg, checks/census-summary.py, the corpus's files) is not
# re-lowered: the summary and verdict are recomputed from that TSV, so
# checks/gate.sh's P1.5 and P1.6 rows share one census (~30 min for both under load on 2026-10-01). FRESH=1 forces
# a rerun.
#
# Env: LG, JOBS (parallel wasm-tools validations, default 8), FRESH=1, KEEP=1.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
fallbacks=0; corpora=()
for a in "$@"; do
  case $a in
    --fallbacks) fallbacks=1 ;;
    xsofy|legmacs) corpora+=("$a") ;;
    *) echo "usage: $0 [--fallbacks] xsofy|legmacs..." >&2; exit 2 ;;
  esac
done
[ ${#corpora[@]} -gt 0 ] || { echo "usage: $0 [--fallbacks] xsofy|legmacs..." >&2; exit 2; }
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
mkdir -p "$here/corpus/census"
fail=0
for c in "${corpora[@]}"; do
  root=$HOME/projects-new/3p/$c
  [ -d "$root" ] || { echo "no corpus at $root" >&2; exit 2; }
  # same file lists as ../emit-wasm-probe/census/coverage-report.md
  case $c in
    xsofy)   (cd "$root" && { echo main.lg; find xsofy -name '*.lg' | LC_ALL=C sort; }) > "$t/$c-files" ;;
    legmacs) (cd "$root" && { echo main.lg; find legmacs -name '*.lg' | LC_ALL=C sort; } | grep -v examples) > "$t/$c-files" ;;
  esac
  tsv=$here/corpus/census/$c.tsv
  if [ -z "${FRESH:-}" ] && [ -s "$tsv" ] && [ -z "$(cd "$root" && find $(cat "$t/$c-files") "$here"/src/*.lg \
        "$here/checks/census.lg" "$here/checks/census-summary.py" -newer "$tsv" 2>/dev/null | head -1)" ]; then
    echo "== $c: reusing $tsv (newer than every input; FRESH=1 to rerun)"
    mkdir -p "$t/$c-nobad"
    python3 "$here/checks/census-summary.py" "$c" "$tsv" "$t/$c-nobad" "$t/$c.tsv" \
        "$here/corpus/census/$c-summary.md" "$fallbacks" || fail=1
    continue
  fi
  mkdir -p "$t/$c-wat"
  echo "== $c: $(wc -l < "$t/$c-files" | tr -d ' ') files"
  # the corpus must be the cwd: its main.lg loads siblings relative to it
  (cd "$root" && LG_SOURCE_PATHS="$root:$here/src" xargs timeout 3600 "$LG" "$here/checks/census.lg" \
      "$root" "$c" "$t/$c.raw.tsv" "$t/$c-wat" < "$t/$c-files") > "$t/$c.log" 2>&1
  [ -s "$t/$c.raw.tsv" ] || { echo "census.lg failed for $c:"; tail -20 "$t/$c.log"; exit 1; }
  # validate every unit module that lowered; first error line per failure
  mkdir -p "$t/$c-bad"
  find "$t/$c-wat" -name '*.wat' -print0 | xargs -0 -P "${JOBS:-8}" -n 1 sh -c \
    'wasm-tools validate "$1" >/dev/null 2>"$1.err" || { b=$(basename "$1" .wat); head -1 "$1.err" > "'"$t/$c-bad"'/$b"; }; rm -f "$1.err"' _
  python3 "$here/checks/census-summary.py" "$c" "$t/$c.raw.tsv" "$t/$c-bad" \
      "$here/corpus/census/$c.tsv" "$here/corpus/census/$c-summary.md" "$fallbacks" || fail=1
done
exit $fail
