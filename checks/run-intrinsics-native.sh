#!/usr/bin/env bash
# checks/run-intrinsics-native.sh — P2.1 native half: run the intrinsic and
# pvec test files under native lg with the reference wasm.intrinsics.
# Exit 0 iff every assertion passes AND the number of tests run equals the
# number of deftest forms in the files (guards the run-tests zero-suite trap).
# Tiers (D51): the default must finish under 90 s (68 s on 2026-10-01);
# SLOW=1 adds the 10k map/set builds, every map/set path at 1000 keys and
# the 1e6 reduce gate (3.5 min). Both tiers run every deftest, so the count
# guard holds in each; checks/gate.sh 2 sets SLOW=1.
# The eventual P2.1 check is `checks/run-corpus.sh corpus/intrinsics --both`.
#
# D106 (7): one lg process per *_test.lg file, LW_PAR at a time (default 4;
# LW_PAR=1 runs them one after another), each holding a machine-wide slot
# (checks/sem.sh) and loading the runtime itself (~2 s startup, accepted).
# The deftest-count guard runs per file (the runner exits 1 when its file
# registers a different number of tests than it has deftest forms) AND in
# total, and the last line is the same summary the one-process run printed:
#   intrinsics-native: tests=N (expected N) pass=P fail=F error=E OK|FAILED
# with the counts summed over the files. Per-file output other than that
# summary (a failing test's report) is printed in file order before the
# one-process run's closing "Ran N tests containing M assertions." pair.
# Heaviest files start first (times measured 2026-10-01; files not listed
# default to light), because the run is bounded by the slowest file.
set -uo pipefail
cd "$(dirname "$0")/.."
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
export LG
par=${LW_PAR:-4}
case $par in ''|*[!0-9]*|0) echo "LW_PAR must be a positive integer (got '$par')" >&2; exit 2;; esac
files=(corpus/intrinsics/*_test.lg)
[ -e "${files[0]}" ] || { echo "no corpus/intrinsics/*_test.lg" >&2; exit 2; }
expected=$(cat "${files[@]}" | grep -c '^(deftest ')
echo "tier: $([ "${SLOW:-}" = 1 ] && echo slow || echo default)"
# stop a whole subtree (xargs -> sem.sh -> worker -> lg), parent first so xargs
# starts no replacement, so an interrupted run
# leaves no workers or held slots behind
killtree() { local c kids; kids=$(pgrep -P "$1" 2>/dev/null); kill "$1" 2>/dev/null; for c in $kids; do killtree "$c"; done; return 0; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
trap 'for c in $(pgrep -P $$ 2>/dev/null); do killtree "$c"; done; exit 143' TERM HUP INT
export t

weight() {
  case ${1##*/} in
    seq_test*) echo 86 ;; reader_test*) echo 74 ;; phm_test*) echo 71 ;; phs_test*) echo 37 ;;
    xsofy_natives_test*) echo 24 ;; pvec_test*|vkind_test*) echo 18 ;; str_test*) echo 11 ;; core_test*) echo 9 ;;
    *) echo 1 ;;
  esac
}
# the file's namespace is its name with _ -> - (the test namespaces arrive after the count)
one() {
  local f=$1 b n
  b=${1##*/}; b=${b%.lg}; n=$(grep -c '^(deftest ' "$f")
  "$LG" -source-paths rt:corpus/intrinsics checks/intrinsics-native-runner.lg "$n" "${b//_/-}" >"$t/$b.out" 2>&1
  echo $? >"$t/$b.rc"
}
export -f one

# background + wait, so a TERM reaches the trap while the workers run
{ for f in "${files[@]}"; do printf '%s %s\n' "$(weight "$f")" "$f"; done | sort -rn -s -k1,1 | cut -d' ' -f2- | tr '\n' '\0' \
  | xargs -0 -n 1 -P "$par" checks/sem.sh bash -c 'one "$1"' _; } &
wait $!

tests=0 pass=0 fail=0 err=0 asserts=0 ok=1
for f in "${files[@]}"; do
  b=${f##*/}; b=${b%.lg}
  rc=$(cat "$t/$b.rc" 2>/dev/null || echo 99)
  # a file's own "Ran N tests ..." / "F failures, E errors." pair is folded into one total below
  grep -v -e '^ir.form-heads catalog loaded' -e '^intrinsics-native: tests=' -e '^Ran [0-9]* tests containing' -e '^[0-9]* failures, [0-9]* errors' "$t/$b.out" 2>/dev/null
  fa=$(sed -nE 's/^Ran [0-9]+ tests containing ([0-9]+) assertions.*/\1/p' "$t/$b.out" 2>/dev/null | tail -1)
  asserts=$((asserts+${fa:-0}))
  s=$(grep '^intrinsics-native: tests=' "$t/$b.out" 2>/dev/null | tail -1)
  ft="" fp="" ff="" fe=""
  read -r ft fp ff fe < <(printf '%s\n' "$s" | sed -nE 's/^intrinsics-native: tests=([0-9]+) \(expected [0-9]+\) pass=([0-9]+) fail=([0-9]+) error=([0-9]+).*/\1 \2 \3 \4/p')
  if [ -z "$fe" ]; then echo "intrinsics-native: $b produced no summary (exit $rc)"; ok=0; continue; fi
  tests=$((tests+ft)); pass=$((pass+fp)); fail=$((fail+ff)); err=$((err+fe))
  [ "$rc" = 0 ] || ok=0
done
[ "$tests" = "$expected" ] || ok=0
[ "$fail" = 0 ] && [ "$err" = 0 ] || ok=0
echo "Ran $tests tests containing $asserts assertions."
echo "$fail failures, $err errors."
echo "intrinsics-native: tests=$tests (expected $expected) pass=$pass fail=$fail error=$err $([ $ok = 1 ] && echo OK || echo FAILED)"
[ $ok = 1 ]
