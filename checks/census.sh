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
# D106 (6), sharded: the corpus's files are split into CENSUS_SHARDS (default
# 4) bins, longest-processing-time first by each file's summed `ms` in the
# previous TSV (file size when there is none), and one census.lg process per
# bin runs under checks/sem.sh. Every process still reads and declares ALL the
# corpus files (so the corpus-namespace set, and what each unit can resolve,
# are what a serial run sees) and lowers only its own share, numbering units
# as the serial run would (LW_CENSUS_ALL, see census.lg). The shards' rows are
# merged in idx order, so the TSV is the serial TSV except for the `ms`
# column (timings), and the summary is identical for the same day.
#
# Cache: corpus/census/<corpus>.key holds a content hash of every input
# (src/*.lg, rt/wasm/*.lg, checks/census.lg, checks/census-summary.py, and
# the name and bytes of each corpus file). When it matches, the corpus is not
# re-lowered: the summary and verdict are recomputed from the TSV, so
# checks/gate.sh's P1.5 and P1.6 rows share one census. Content, not mtime:
# a tree copy, a touch or a reverted edit does not invalidate it. A TSV with
# no .key yet is adopted once if it is newer than every input (the old rule).
# A per-corpus lock (corpus/census/.<corpus>.lock) makes a second census of
# the same corpus wait for the first and then reuse its result. FRESH=1
# forces a rerun.
#
# Env: LG, JOBS (parallel wasm-tools validations, default 8), CENSUS_SHARDS
# (default 4; 1 = one process, serial), FRESH=1, KEEP=1.
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
shards=${CENSUS_SHARDS:-4}
case $shards in ''|*[!0-9]*|0) echo "CENSUS_SHARDS must be a positive integer (got '$shards')" >&2; exit 2;; esac
t=$(mktemp -d); held=""; pids=()
# stop a subtree (shard subshell -> xargs -> sem.sh -> timeout -> lg) so an
# interrupted census leaves no workers or held slots behind
killtree() { local c kids; kids=$(pgrep -P "$1" 2>/dev/null); kill "$1" 2>/dev/null; for c in $kids; do killtree "$c"; done; return 0; }
cleanup() {
  local p; for p in ${pids[@]+"${pids[@]}"}; do killtree "$p"; done
  [ -n "$held" ] && rm -rf "$held"
  if [ -n "${KEEP:-}" ]; then echo "kept $t" >&2; else rm -rf "$t"; fi
}
trap cleanup EXIT
trap 'exit 130' INT; trap 'exit 143' TERM HUP
mkdir -p "$here/corpus/census"

# mkdir lock with dead-holder reclaim (as checks/sem.sh); a second census of
# the same corpus blocks here until the first has written its TSV and key.
lock_acquire() {
  local d=$1 p deadline=$(( $(date +%s) + ${CENSUS_LOCK_WAIT:-3600} ))
  while ! mkdir "$d" 2>/dev/null; do
    p=$(cat "$d/pid" 2>/dev/null)
    if { [ -n "$p" ] && ! kill -0 "$p" 2>/dev/null; } ||
       { [ -z "$p" ] && [ $(( $(date +%s) - $(stat -f %m "$d" 2>/dev/null || echo 0) )) -gt 10 ]; }; then
      command mv "$d" "$d.dead.$$" 2>/dev/null && rm -rf "$d.dead.$$"
      continue
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then echo "census: waited for $d; running without the lock" >&2; return 0; fi
    sleep 1
  done
  echo $$ > "$d/pid"; held=$d
}
lock_release() { [ -n "$held" ] && rm -rf "$held"; held=""; }

# Content hash of every input; paths are relative so a tree copy hashes the same.
census_key() {
  local root=$1 list=$2 f
  export LC_ALL=C
  {
    ( cd "$root" && while IFS= read -r f; do printf 'F %s\n' "$f"; cat "$f" 2>/dev/null; done < "$list" )
    for f in "$here"/src/*.lg "$here"/rt/wasm/*.lg "$here/checks/census.lg" "$here/checks/census-summary.py"; do
      printf 'F %s\n' "${f#"$here"/}"; cat "$f" 2>/dev/null
    done
  } | shasum -a 256 | cut -d' ' -f1
}

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
  keyf=$here/corpus/census/$c.key
  lock_acquire "$here/corpus/census/.$c.lock"
  key=$(census_key "$root" "$t/$c-files")
  reuse=0
  if [ -z "${FRESH:-}" ] && [ -s "$tsv" ]; then
    if [ -f "$keyf" ]; then
      [ "$(cat "$keyf")" = "$key" ] && reuse=1
    elif [ -z "$(cd "$root" && find $(cat "$t/$c-files") "$here"/src/*.lg "$here"/rt/wasm/*.lg \
          "$here/checks/census.lg" "$here/checks/census-summary.py" -newer "$tsv" 2>/dev/null | head -1)" ]; then
      reuse=1; echo "$key" > "$keyf.tmp$$" && command mv "$keyf.tmp$$" "$keyf"   # adopt a pre-key TSV once
    fi
  fi
  if [ $reuse -eq 1 ]; then
    echo "== $c: reusing $tsv (content hash of every input unchanged; FRESH=1 to rerun)"
    mkdir -p "$t/$c-nobad"
    python3 "$here/checks/census-summary.py" "$c" "$tsv" "$t/$c-nobad" "$t/$c.tsv" \
        "$here/corpus/census/$c-summary.md" "$fallbacks" || fail=1
    lock_release
    continue
  fi
  mkdir -p "$t/$c-wat"
  nfiles=$(wc -l < "$t/$c-files" | tr -d ' ')
  echo "== $c: $nfiles files"
  # LPT bins by the previous TSV's per-file ms (size when absent or incomplete)
  python3 - "$t/$c-files" "$tsv" "$shards" "$t/$c-shard" "$root" >/dev/null <<'PYEOF'
import os, sys
listf, prev, n, prefix, root = sys.argv[1:6]
files = [l.rstrip("\n") for l in open(listf) if l.strip()]
w = {}
try:
    with open(prev) as fh:
        hdr = fh.readline().rstrip("\n").split("\t")
        fi, mi = hdr.index("file"), hdr.index("ms")
        for line in fh:
            p = line.rstrip("\n").split("\t")
            if len(p) > mi and p[mi].isdigit():
                w[p[fi]] = w.get(p[fi], 0) + int(p[mi])
except (OSError, ValueError):
    w = {}
if any(f not in w for f in files):  # a new or unmeasured file: sizes for all
    w = {f: os.path.getsize(os.path.join(root, f)) if os.path.exists(os.path.join(root, f)) else 0 for f in files}
n = max(1, min(int(n), len(files)))
bins = [[0, []] for _ in range(n)]
for f in sorted(files, key=lambda f: (-w[f], f)):
    b = min(bins, key=lambda b: b[0])
    b[0] += w[f]; b[1].append(f)
for k, (_, fs) in enumerate(bins):
    with open(f"{prefix}.{k}", "w") as out:
        out.write("\n".join(f for f in files if f in set(fs)) + "\n")
print(n)
PYEOF
  nshards=$(ls "$t/$c-shard".* 2>/dev/null | wc -l | tr -d ' ')
  # the corpus must be the cwd: its main.lg loads siblings relative to it
  pids=()
  for ((k=0; k<nshards; k++)); do
    ( cd "$root" && LG_SOURCE_PATHS="$root:$here/src" LW_CENSUS_ALL="$t/$c-files" \
        xargs "$here/checks/sem.sh" timeout 3600 "$LG" "$here/checks/census.lg" \
        "$root" "$c" "$t/$c.raw.$k.tsv" "$t/$c-wat" < "$t/$c-shard.$k" ) > "$t/$c.log.$k" 2>&1 &
    pids+=($!)
  done
  for p in "${pids[@]}"; do wait "$p"; done
  for ((k=0; k<nshards; k++)); do
    [ -s "$t/$c.raw.$k.tsv" ] || { echo "census.lg failed for $c (shard $k):"; tail -20 "$t/$c.log.$k"; exit 1; }
  done
  # merge the shards' rows in idx order (header from shard 0)
  { head -1 "$t/$c.raw.0.tsv"
    for ((k=0; k<nshards; k++)); do tail -n +2 "$t/$c.raw.$k.tsv"; done | grep -v '^$' | sort -t "$(printf '\t')" -k1,1n -s
  } > "$t/$c.raw.tsv"
  # validate every unit module that lowered; first error line per failure
  mkdir -p "$t/$c-bad"
  find "$t/$c-wat" -name '*.wat' -print0 | xargs -0 -P "${JOBS:-8}" -n 1 sh -c \
    'wasm-tools validate "$1" >/dev/null 2>"$1.err" || { b=$(basename "$1" .wat); head -1 "$1.err" > "'"$t/$c-bad"'/$b"; }; rm -f "$1.err"' _
  python3 "$here/checks/census-summary.py" "$c" "$t/$c.raw.tsv" "$t/$c-bad" \
      "$tsv" "$here/corpus/census/$c-summary.md" "$fallbacks"
  prc=$?
  [ $prc -le 1 ] && [ -s "$tsv" ] && { echo "$key" > "$keyf.tmp$$" && command mv "$keyf.tmp$$" "$keyf"; }
  [ $prc -eq 0 ] || fail=1
  lock_release
done
exit $fail
