#!/usr/bin/env bash
# checks/jank-suite.sh: jank's clojure-test-suite against native lg, deftest
# by deftest. The suite is let-go's submodule test/clojure-test-suite at the
# pinned commit (bd610c8 at e9789b7d); its core_test and
# string_test files are compared the way checks/run-tests.sh --corpus compares
# let-go's core tests: native lg's run-tests report (checks/jank-native.lg,
# let-go's own harness setup: :clj reader conditionals, the portability shim
# from test/compat at the pin) against the backend's `driver --test
# --read-clj` build, run through WASM_RUN (unset: the WasmGC lane).
#
#   checks/jank-suite.sh [--filter w,...]   run the suite, print the summary
#                                           and the cause table
#   checks/jank-suite.sh --ratchet          also exit 1 when a file listed in the
#                                           baseline has fewer passing deftests
#   checks/jank-suite.sh --update-baseline  rewrite the baseline from this run
#   checks/jank-suite.sh --list             regenerate corpus/jank/files.tsv
#   checks/jank-suite.sh --self-test        the harness on corpus/jank-harness
#
# The baseline is LW_JANK_BASELINE (default corpus/jank/baseline.tsv, the llvm
# lane's, P13.4); the WasmGC lane ratchets against corpus/jank/baseline-wasm.tsv
# (P5.13). One file per lane: the lanes pass different sets. The ratchet also
# fails when a baseline file is missing from the run (a crashed or filtered
# run would otherwise pass vacuously).
#
# Causes, per file that does not fully agree: d15 (the backend names Ratio,
# BigInt or BigDecimal, D15), compile (the driver refused the file), crash
# (no result, a timeout or a runner crash), mismatch (anything else).
# Env: LG, LETGO, WASM_RUN, P (parallel files, default 3), LW_CACHE,
# LW_JANK_OUT (results dir, default a mktemp), LW_JANK_BASELINE, LW_JANK_REUSE
# (with an LW_JANK_OUT holding results.tsv: skip the ~30 min run and only
# re-evaluate the mode over it; exit 2 when there is nothing to reuse).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
mode=run; filter=""
while [ $# -gt 0 ]; do
  case $1 in
    --ratchet|--update-baseline|--list|--self-test) mode=${1#--}; shift ;;
    --filter) filter=$2; shift 2 ;;
    *) echo "unknown argument $1" >&2; exit 2 ;;
  esac
done
commit=$(sed -nE 's/^\(def letgo-commit "([0-9a-f]+)"\)$/\1/p' "$here/src/lw_rt.lg")
suite=$LETGO/test/clojure-test-suite/test
want=$(git -C "$LETGO" ls-tree "$commit" test/clojure-test-suite | awk '{print $3}')
have=$(git -C "$LETGO/test/clojure-test-suite" rev-parse HEAD 2>/dev/null)
[ -n "$want" ] && [ "$have" = "$want" ] || { echo "SKIP jank-suite: $LETGO/test/clojure-test-suite is at ${have:-nothing}, the pin $commit records $want" >&2; exit 2; }
# let-go's test/compat at the pin (the portability shim the native harness loads)
compat=${LW_CACHE:-$HOME/.cache/let-go-wasmgc}/letgo-compat-$commit/test/compat
if [ ! -f "$compat/clojure/core-test/portability.lg" ]; then
  d=${LW_CACHE:-$HOME/.cache/let-go-wasmgc}/letgo-compat-$commit
  mkdir -p "$d" && git -C "$LETGO" archive "$commit" test/compat | tar -x -C "$d" || exit 1
fi
export JANK_PORTABILITY=$compat/clojure/core-test/portability.lg
export NATIVE_RUNNER=$here/checks/jank-native.lg DRIVER_FLAGS="--read-clj ${DRIVER_FLAGS:-}"

if [ "$mode" = self-test ]; then
  fail=0; h=$here/corpus/jank-harness
  for f in conditionals.cljc conditionals-wrong.cljc; do
    out=$(SRC_PATHS=$h "$here/checks/run-tests.sh" "$h/$f" 2>&1)
    case "$out" in *"PASS $h/$f"*) echo "ok   $f agrees" ;; *) echo "FAIL $f: $(printf '%s\n' "$out" | head -3 | tr '\n' ' ')"; fail=1 ;; esac
  done
  # the driver finds namespaces as let-go's resolver does (.cljc, hyphenated dirs)
  r=$(LG_ARGS="-source-paths $h/resolve" WASM_RUN=${WASM_RUN:-$here/checks/wasm-run.sh} "$here/checks/oracle.sh" "$h/resolve/main.lg" 2>&1 | head -1)
  [ "$r" = MATCH ] && echo "ok   namespace resolution (.cljc, hyphenated dir)" || { echo "FAIL namespace resolution: $r"; fail=1; }
  n=$("$LG" -source-paths "$h" "$here/checks/jank-native.lg" "$h/conditionals-wrong.cljc" 2>&1 | grep -c '^FAIL in')
  [ "$n" = 3 ] && echo "ok   the wrong fixture fails 3 assertions natively" || { echo "FAIL wrong fixture: $n native failures, want 3"; fail=1; }
  exit $fail
fi

if [ "$mode" = list ]; then
  (cd "$suite/clojure" && for f in core_test/*.cljc string_test/*.cljc; do
     n=$(grep -cE '\((t/)?deftest ' "$f"); [ "$n" -gt 0 ] && printf '%s\t%s\n' "$f" "$n"; done) > "$here/corpus/jank/files.tsv"
  wc -l < "$here/corpus/jank/files.tsv"; exit 0
fi

out=${LW_JANK_OUT:-$(mktemp -d)}; mkdir -p "$out"
export LW_TEST_LOG_DIR="$(cd "$out" && pwd)/failures"
baseline=${LW_JANK_BASELINE:-$here/corpus/jank/baseline.tsv}
# the way to falsify the ratchet, or to write a baseline from a run already made
if [ -n "${LW_JANK_REUSE:-}" ]; then
  [ -f "$out/results.tsv" ] || { echo "jank-suite: LW_JANK_REUSE set but no $out/results.tsv to reuse"; exit 2; }
  [ -z "$filter" ] || { echo "jank-suite: --filter has no effect on a reused run"; exit 2; }
  echo "jank-suite: reusing $out/results.tsv"
else
  RESULTS_TSV=$out/results.tsv LETGO_TEST=$suite/clojure SRC_PATHS="$compat:$suite" \
    "$here/checks/run-tests.sh" --corpus "$here/corpus/jank/files.tsv" ${filter:+--filter "$filter"} --bar 0 > "$out/run.log" 2>&1 || {
      status=$?
      cat "$out/run.log" >&2
      exit "$status"
    }
fi
tail -2 "$out/run.log"
# the cause of each file that does not fully agree (columns: file deftests oracle passing ... first_failure cause)
awk -F'\t' 'NR>1 && $4<$2 {
    c = tolower($16 " " $17)
    cause = (c ~ /(^|[^a-z])(ratio|bigint|big int|bigdec|big dec)/) ? "d15" : (c ~ /^compile|compile: / ? "compile" : (c ~ /timeout or crash/ ? "crash" : "mismatch"))
    files[cause]++; lost[cause] += $2 - $4
  } END { printf "%-10s %6s %8s\n", "cause", "files", "deftests"; for (k in files) printf "%-10s %6d %8d\n", k, files[k], lost[k] }' "$out/results.tsv" | sort
# passing deftests: file<TAB>count, for the ratchet
awk -F'\t' 'NR>1 {print $1 "\t" $4}' "$out/results.tsv" | sort > "$out/passing.tsv"
case $mode in
  update-baseline) cp "$out/passing.tsv" "$baseline"; echo "baseline $baseline: $(awk -F'\t' '{s+=$2} END{print s}' "$out/passing.tsv") deftests" ;;
  ratchet)
    [ -f "$baseline" ] || { echo "NOT IMPLEMENTED: ratchet: no baseline at $baseline (run --update-baseline first)"; exit 3; }
    missing=$(join -t $'\t' -v1 "$baseline" "$out/passing.tsv")
    if [ -n "$missing" ]; then echo "ratchet: baseline files missing from this run (a filtered or crashed run?):"; cut -f1 <<<"$missing" | sed 's/^/  /'; exit 1; fi
    worse=$(join -t $'\t' "$baseline" "$out/passing.tsv" | awk -F'\t' '$3 < $2 {print $1 " " $2 " -> " $3}')
    if [ -n "$worse" ]; then echo "ratchet: fewer passing deftests than $baseline:"; printf '  %s\n' "$worse"; exit 1; fi
    echo "ratchet: no file below its baseline ($baseline)" ;;
esac
echo "results: $out"
