#!/usr/bin/env bash
# checks/run-review2.sh — item P2.10: the corpus/review2 runtime bugs stay fixed.
#
# 1. Every corpus/review2/bug-*.lg runs, and corpus/review2/selfcheck.lg (the
#    repros' expressions as [native runtime] pairs, the native side a fresh
#    run in the same lg process) prints MATCH for it. A repro listed in
#    corpus/review2/known-diffs.txt may MISMATCH (printed DEFERRED).
# 2. FUZZ_SEEDS seeds (default 300, from FUZZ_FROM=1000) of fuzz.lg with
#    FUZZ_NOFOUND=1 (its filters for the reported bugs off), through
#    corpus/review2/fuzz-check.lg, in FUZZ_SHARDS parallel lg processes
#    (default 6): every FAIL signature must be in known-diffs.txt.
# Exit 0 iff both hold. RT=<dir> points the runtime at another rt/ copy
# (the falsification run uses a scratch copy with a fix reverted).
set -uo pipefail
cd "$(dirname "$0")/.."
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
RT=${RT:-rt}
SEEDS=${FUZZ_SEEDS:-300}; FROM=${FUZZ_FROM:-1000}; SHARDS=${FUZZ_SHARDS:-6}
allow=corpus/review2/known-diffs.txt
allowed() { grep -v '^#' "$allow" | cut -f1 | grep -qxF -- "$1"; }
tmp=$(mktemp -d "${TMPDIR:-/tmp}/review2.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
fail=0

echo "== repros (selfcheck, native lg in the same process)"
"$LG" -source-paths "$RT" corpus/review2/selfcheck.lg > "$tmp/self.out" 2>&1
for f in corpus/review2/bug-*.lg; do
  b=${f##*/}; id=${b:0:6}                              # bug-NN
  if ! "$LG" -source-paths "$RT" "$f" > "$tmp/$id.run" 2>&1; then
    echo "$b CRASH"; sed 's/^/    /' "$tmp/$id.run" | head -5; fail=1; continue
  fi
  line=$(grep "^$id " "$tmp/self.out")
  case "$line" in
    "$id MATCH"*) echo "$b MATCH" ;;
    "$id MISMATCH"*) if allowed "$id"; then echo "$b DEFERRED (known-diffs.txt)"; else echo "$b MISMATCH"; fail=1; fi
                     awk -v id="$id" '$0 ~ "^"id" " {p=1; next} /^bug-/ {p=0} p' "$tmp/self.out" ;;
    *) echo "$b NO SELFCHECK ENTRY"; fail=1 ;;
  esac
done
grep -q '^bug-' "$tmp/self.out" || { echo "selfcheck did not run:"; head -20 "$tmp/self.out"; fail=1; }

echo "== fuzz: $SEEDS seeds from $FROM, FUZZ_NOFOUND=1, $SHARDS shards"
per=$(( (SEEDS + SHARDS - 1) / SHARDS )); pids=()
for ((k = 0; k < SHARDS; k++)); do
  a=$((FROM + k * per)); z=$((a + per)); [ "$z" -gt $((FROM + SEEDS)) ] && z=$((FROM + SEEDS)); [ "$a" -ge "$z" ] && continue
  FUZZ_FROM=$a FUZZ_TO=$z FUZZ_NOFOUND=1 FUZZ_NOSHRINK=1 \
    "$LG" -source-paths "$RT" corpus/review2/fuzz.lg --eval corpus/review2/fuzz-check.lg > "$tmp/fuzz$k.out" 2>&1 &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
done_n=$(cat "$tmp"/fuzz*.out | grep -c '^DONE')
[ "$done_n" -eq "${#pids[@]}" ] || { echo "fuzz: $done_n of ${#pids[@]} shards finished"; tail -5 "$tmp"/fuzz*.out; fail=1; }
grep -h 'sig=' "$tmp"/fuzz*.out | sed 's/.*sig=\(\[[^]]*\]\).*/\1/' | sort | uniq -c > "$tmp/sigs"
while read -r n sig; do
  if allowed "$sig"; then echo "  allowed  $n x $sig"; else echo "  NEW      $n x $sig"; fail=1
    grep -h -m1 -F "sig=$sig" "$tmp"/fuzz*.out | cut -c1-400 | sed 's/^/           /'; fi
done < "$tmp/sigs"
[ -s "$tmp/sigs" ] || echo "  no FAIL signatures"
[ "$fail" = 0 ] && echo "run-review2: OK" || echo "run-review2: FAILED"
exit "$fail"
