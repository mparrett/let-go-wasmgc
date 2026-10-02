#!/usr/bin/env bash
# checks/run-tests.sh [--filter a,b] <file.lg | list.txt>...
# checks/run-tests.sh --corpus <list.tsv>      (P2.14: the let-go core-test gate)
#
# Run test files (deftest/is/testing) under native lg and through the
# backend, and compare what native run-tests reports: the "Ran N tests
# containing M assertions." and "F failures, E errors." lines plus every
# "FAIL in (test)" / "ERROR in (test)" line (file:line suffixes stripped,
# sorted, since native runs a namespace's tests in var-map order). The
# backend side compiles the file with `driver.lg --test`, which swaps
# deftest/is/testing for src/testshim.lg's and makes wasm/trap throw the
# reference impl's catchable ex-info (so trap? assertions run).
#
# The native side LOADS the file by path and then runs its namespace's tests,
# as let-go's own harness does (test/language_test.go), so a file whose ns
# does not match its name (chunked_seq_test.lg declares test.chunked-seq)
# runs too. A file with no ns form is load-only (spec 12.2): it is run as a
# plain program on both sides (`lg <file>` vs checks/wasm-run.sh) and passes
# when stdout and exit status match.
#
# A .txt argument is a list of test files, one per line (# comments);
# --filter keeps the files whose path contains one of the comma-separated
# words. Deftests listed in checks/run-tests.skip are left out on both sides.
#
# Prints one line per file, PASS or FAIL (with the first differing line),
# then "pass/total". Exit 0 iff every file passes.
#
# --corpus <list>: lines `file<TAB>deftests` (# comments), files relative to
# LETGO_TEST, else to the list's dir, else to the cwd. Runs every file (P at
# a time, each under checks/sem.sh with a 300 s timeout), regenerates
# corpus/core-tests-results.tsv (for corpus/core-tests.txt only; other lists
# write a scratch table), and prints `files MATCH M/F` and `deftests N/T
# (skipped S, bar B)`. A deftest passes only where the backend agrees with
# native (P5.11): the file's backend run printed its summary, native's
# assertion count equals the backend's (otherwise none of the file's
# deftests count), and the deftest is not in exactly one side's FAIL/ERROR
# set. The rule that fired is in the table's `cause` column. A deftest named in run-tests.skip
# (and defined in its file) is not run and is NOT a pass: it is counted in S.
# --bar B (default ceil(90% of T), the P2.GATE bar, D112) is met when
# N >= B - S, so each skip excuses exactly one deftest and is printed with its
# reason; `--bar T` means every deftest not named in run-tests.skip passes.
# A `#bar B` line in the list sets its default bar.
#
# Source paths: files under a let-go checkout's test/ dir get the checkout
# root, test/ and scripts/ (what language_test.go's resolver searches:
# `test.<ns>` from the root, quality.* from scripts/) on both sides, and run
# with test/ as cwd (quality_cost reads ../scripts/quality). Other files get
# their own dir.
# Env: LG, KEEP=1 (keep the scratch dir), SRC_PATHS (override the source
# paths), LETGO_TEST (default ~/projects-new/3p/let-go/test), P (default 3).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
LETGO_TEST=${LETGO_TEST:-$HOME/projects-new/3p/let-go/test}
filter=""; files=(); corpus=""; one=""; bar_arg=""
while [ $# -gt 0 ]; do
  case $1 in
    --filter) filter=$2; shift 2 ;;
    --corpus) corpus=$2; shift 2 ;;
    --bar) bar_arg=$2; shift 2 ;;
    --one) one=$2; shift 2 ;;   # internal: --one <result file> <test file>
    -*) echo "unknown flag $1" >&2; exit 2 ;;
    # a list line may carry a deftest count after a tab; a bare name is
    # looked up beside the list, then in LETGO_TEST
    *.txt) ldir=$(dirname "$1")
           while IFS= read -r l; do case $l in ''|'#'*) ;; *) l=${l%%$'\t'*}
             if [ -f "$l" ]; then files+=("$l"); elif [ -f "$ldir/$l" ]; then files+=("$ldir/$l"); else files+=("$LETGO_TEST/$l"); fi ;; esac
           done < "$1"; shift ;;
    *) files+=("$1"); shift ;;
  esac
done

if [ -n "$corpus" ]; then
  [ -f "$corpus" ] || { echo "no such corpus $corpus" >&2; exit 2; }
  t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
  awk -F'\t' '!/^#/ && NF>=2 {print $1 "\t" $2}' "$corpus" >"$t/list"
  [ -n "$filter" ] && { IFS=, read -ra words <<<"$filter"
    for w in "${words[@]}"; do grep -F -- "$w" "$t/list"; done | sort -u >"$t/list2"; command mv -f "$t/list2" "$t/list"; }
  # build the runtime library cache once (an edited src/ or rt/ invalidates
  # it), before P workers would each rebuild it
  printf '(println 1)\n' >"$t/warm.lg"
  "$here/checks/sem.sh" "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$t/warm.lg" "$t/warm.wat" >"$t/warm.log" 2>&1 \
    || { echo "driver failed on a trivial program:"; tail -5 "$t/warm.log"; exit 1; }
  # a list entry is relative to LETGO_TEST, else to the list's dir, else to
  # the cwd; its result file is named after the entry with / flattened
  cdir=$(dirname "$corpus")
  src_of() { if [ -f "$LETGO_TEST/$1" ]; then echo "$LETGO_TEST/$1"; elif [ -f "$cdir/$1" ]; then echo "$cdir/$1"; else echo "$1"; fi; }
  while IFS=$'\t' read -r f n; do printf '%s\t%s\n' "$t/$(printf '%s' "$f" | tr / _).res" "$(src_of "$f")"; done <"$t/list" \
    | tr '\n' '\0' | xargs -0 -P "${P:-3}" -I{} bash -c 'IFS=$'"'"'\t'"'"' read -r res src <<<"$1"
        exec "$2/checks/sem.sh" timeout -k 5 300 env KEEP= "$2/checks/run-tests.sh" --one "$res" "$src" >/dev/null 2>&1' _ {} "$here"
  # only the core-test corpus owns the committed results table
  tsv=$t/results.tsv
  [ -z "$filter" ] && [ "$(basename "$corpus")" = core-tests.txt ] && tsv=$here/corpus/core-tests-results.tsv
  printf 'file\tdeftests\toracle\tbackend_passing_deftests\tnative_tests\tnative_assertions\tnative_failures\tnative_errors\tbackend_tests\tbackend_assertions\tbackend_failures\tbackend_errors\twall_s\texterns\tfailing_deftests\tfirst_failure\tcause\tskipped_deftests\n' >"$tsv"
  match=0 nfiles=0 ok=0 total=0 skipped=0; : >"$t/skipped"
  while IFS=$'\t' read -r f n; do
    nfiles=$((nfiles+1)); total=$((total+n))
    r=$t/$(printf '%s' "$f" | tr / _).res; src=$(src_of "$f")
    # skips of this file's ns that name one of its deftests (a stale entry excuses nothing)
    fns=$(sed -nE 's/^\(ns ([^ )]+).*/\1/p' "$src" | head -1)
    sk=$(awk -v ns="$fns" '$1==ns{print $2}' "$here/checks/run-tests.skip" | while read -r d; do
           awk -v d="$d" '$1=="(deftest" && $2==d {f=1} END {exit !f}' "$src" && echo "$d"; done | paste -sd, -)
    ns_sk=$(printf '%s' "$sk" | tr ',' '\n' | grep -c . || true)
    skipped=$((skipped+ns_sk))
    [ -n "$sk" ] && awk -v ns="$fns" '$1==ns' "$here/checks/run-tests.skip" >>"$t/skipped"
    [ -s "$r" ] || printf 'MISMATCH\tnone\t\t\t\t\t\t\t\t\t\t\t\ttimeout or crash (no result)\ttimeout or crash (no result)\n' >"$r"
    oracle=$(cut -f1 "$r"); bt=$(cut -f2 "$r"); fails=$(cut -f3 "$r"); nfails=$(cut -f16 "$r")
    na=$(cut -f5 "$r"); ba=$(cut -f9 "$r"); cause=$(cut -f15 "$r"); rule=""
    # P5.11: a deftest passes only where the backend agrees with native. No
    # backend summary: the file scores 0. Assertion counts differ (an
    # assertion that never ran, or ran extra, names no test): the file
    # scores 0. Otherwise the deftests in exactly one side's FAIL/ERROR set
    # do not count; one failing on both sides agrees with native.
    # (a load-only file has no summary on either side; MATCH says it agreed)
    if [ "$bt" = none ]; then pd=0; [ "$oracle" = MATCH ] || rule="no backend summary"
    elif [ "$na" != "$ba" ]; then pd=0; rule="assertion counts differ (native ${na:-none}, backend ${ba:-none}): file scores 0"
    else
      diff_names=$(comm -3 <(printf '%s' "$nfails" | tr ',' '\n' | grep . | sort -u) \
                           <(printf '%s' "$fails" | tr ',' '\n' | grep . | sort -u) | tr -d '\t' | paste -sd, -)
      nf=$(printf '%s' "$diff_names" | tr ',' '\n' | grep -c . || true)
      pd=$((n - nf - ns_sk)); [ $pd -lt 0 ] && pd=0
      [ "$nf" -gt 0 ] && rule="FAIL/ERROR sets differ from native on: $diff_names"
    fi
    [ -n "$rule" ] && cause="counter: $rule${cause:+; $cause}"
    [ "$oracle" = MATCH ] && match=$((match+1))
    ok=$((ok+pd))
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$f" "$n" "$oracle" "$pd" "$(cut -f4-13 "$r")" "$fails" "$(cut -f14 "$r")" "$cause" "$sk" >>"$tsv"
    printf '%-40s %-8s %3s/%-3s %s%s\n' "$f" "$oracle" "$pd" "$n" "${sk:+[skipped $sk] }" "$(printf '%s' "$cause" | cut -c1-140)"
  done <"$t/list"
  # a list may declare its default bar on a `#bar B` line (counter.txt, the
  # P5.11 self-test, expects 0 passing); --bar overrides it
  list_bar=$(sed -nE 's/^#bar ([0-9]+)$/\1/p' "$corpus" | head -1)
  bar=${bar_arg:-${list_bar:-$(( (total * 9 + 9) / 10 ))}}
  if [ -s "$t/skipped" ]; then echo "skipped (checks/run-tests.skip):"; sed 's/^/  /' "$t/skipped"; fi
  echo "files MATCH $match/$nfiles"
  echo "deftests $ok/$total (skipped $skipped, bar $bar: need $((bar - skipped)) passing)"
  [ "$ok" -ge $((bar - skipped)) ]
  exit
fi

if [ -n "$filter" ]; then
  kept=()
  for f in "${files[@]}"; do
    IFS=, read -ra words <<<"$filter"
    for w in "${words[@]}"; do case $f in *"$w"*) kept+=("$f"); break ;; esac; done
  done
  files=("${kept[@]+"${kept[@]}"}")
fi
[ ${#files[@]} -gt 0 ] || { echo "usage: $0 [--filter a,b] <file.lg|list.txt>... | --corpus <list>" >&2; exit 2; }

t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
# the comparable lines of a run-tests transcript
norm() {
  grep -E '^(Ran [0-9]+ tests containing [0-9]+ assertions\.|[0-9]+ failures, [0-9]+ errors\.|(FAIL|ERROR) in \()' \
    | sed -E 's/^((FAIL|ERROR) in \([^)]*\)).*/\1/' \
    | awk '/^(FAIL|ERROR)/{print "1 " $0; next} {print "2 " $0}' | LC_ALL=C sort -s -k1,1 -k2 | cut -c3-
}
# "<tests>\t<assertions>\t<failures>\t<errors>" from a transcript, or 4 empty fields
counts() {
  local r e
  r=$(grep -m1 -E '^Ran [0-9]+ tests' "$1" | sed -E 's/^Ran ([0-9]+) tests containing ([0-9]+) .*/\1\t\2/')
  e=$(grep -m1 -E '^[0-9]+ failures, [0-9]+ errors\.' "$1" | sed -E 's/^([0-9]+) failures, ([0-9]+) .*/\1\t\2/')
  printf '%s\t%s' "${r:-$'\t'}" "${e:-$'\t'}"
}
strip() { sed -E 's/\x1b\[[0-9;]*m//g' | tr '\t' ' ' | cut -c1-200; }
# result record for --corpus: oracle, backend tests (or none), failing deftest
# names, then the TSV's columns 5-13 and 16-17
record() {   # record <oracle> <first-failure> <cause>
  [ -n "$one" ] || return 0
  local bt fails nfails nc wc ext
  bt=$(grep -m1 -E '^Ran [0-9]+ tests' "$t/$b.wasm.out" 2>/dev/null | sed -E 's/^Ran ([0-9]+) .*/\1/')
  fails=$(grep -E '^(FAIL|ERROR) in \(' "$t/$b.wasm.out" 2>/dev/null | sed -E 's/^(FAIL|ERROR) in \(([^)]*)\).*/\2/' | sort -u | paste -sd, -)
  nfails=$(grep -E '^(FAIL|ERROR) in \(' "$t/$b.native" 2>/dev/null | sed -E 's/^(FAIL|ERROR) in \(([^)]*)\).*/\2/' | sort -u | paste -sd, -)
  nc=$(counts "$t/$b.native"); wc=$( [ -f "$t/$b.wasm.out" ] && counts "$t/$b.wasm.out" || printf '\t\t\t')
  ext=$(grep -oE '\(global \$ext_[^ ]+' "$t/$b.wat" 2>/dev/null | sed 's/(global \$ext_//' | sort -u | paste -sd, -)
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "${bt:-none}" "$fails" "$nc" "$wc" "${secs:-}" "$ext" "$2" "$3" "$nfails" >"$one"
}

# source paths of test file f (see the header)
paths_of() {
  local d; d=$(cd "$(dirname "$1")" && pwd)
  if [ -n "${SRC_PATHS:-}" ]; then echo "$SRC_PATHS"
  elif [ "$(basename "$d")" = test ] && [ -d "$d/../scripts" ] && [ -d "$d/../pkg/rt/core" ]; then
    local root; root=$(cd "$d/.." && pwd); echo "$root:$d:$root/scripts"
  else echo "$d"; fi
}

# absolute paths up front: the loop cds into each file's dir, so a second
# relative argument would no longer resolve
for i in "${!files[@]}"; do
  [ -f "${files[$i]}" ] && files[$i]=$(cd "$(dirname "${files[$i]}")" && pwd)/$(basename "${files[$i]}")
done
pass=0
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "FAIL $f: no such file"; record MISMATCH "no such file" "no such file"; continue; }
  b=$(basename "$f" .lg)
  sp=$(paths_of "$f")
  ns=$(sed -nE 's/^\(ns ([^ )]+).*/\1/p' "$f" | head -1)
  secs=""
  cd "$(dirname "$f")" || exit 2
  if [ -z "$ns" ]; then
    # load-only file: a plain program on both sides
    "$LG" -source-paths "$sp" "$f" >"$t/$b.native" 2>&1; ne=$?
    start=$(date +%s)
    LG_ARGS="-source-paths $sp" "$here/checks/wasm-run.sh" "$f" >"$t/$b.wasm.out" 2>&1; we=$?
    secs=$(( $(date +%s) - start ))
    if [ $ne -eq $we ] && cmp -s "$t/$b.native" "$t/$b.wasm.out"; then
      echo "PASS $f (load-only, exit $ne)"; pass=$((pass+1)); record MATCH "" ""
    else
      first="load-only: native exit $ne, wasm exit $we: $(diff "$t/$b.native" "$t/$b.wasm.out" | grep -m1 '^[<>]' | strip)"
      echo "FAIL $f: $first"; record MISMATCH "$first" "$(grep -m1 -iE 'error' "$t/$b.wasm.out" | strip)"
    fi
    continue
  fi
  skips=$(awk -v ns="$ns" '$1==ns{print $2}' "$here/checks/run-tests.skip" | paste -sd, -)
  "$LG" -source-paths "$here/rt:$sp" "$here/checks/native-test-runner.lg" "$f" ${skips//,/ } \
    >"$t/$b.native" 2>&1
  start=$(date +%s)
  if ! "$LG" -source-paths "$here/src:$sp" "$here/src/driver.lg" -source-paths "$sp" "$f" "$t/$b.wat" --test ${skips:+--skip "$skips"} \
       >"$t/$b.drv" 2>&1; then
    msg="compile: $(grep -v catalog "$t/$b.drv" | grep -m1 -iE 'error|lower-wasm' | strip)"
    echo "FAIL $f: $msg"; record MISMATCH "$msg" "$msg"
    continue
  fi
  secs=$(( $(date +%s) - start ))
  if ! wasm-tools parse "$t/$b.wat" -o "$t/$b.wasm" 2>"$t/$b.asm"; then
    msg="assemble: $(head -1 "$t/$b.asm" | strip)"
    echo "FAIL $f: $msg"; record MISMATCH "$msg" "$msg"; continue
  fi
  node "$here/src/run.mjs" "$t/$b.wasm" >"$t/$b.wasm.out" 2>&1
  norm <"$t/$b.native" >"$t/$b.n"; norm <"$t/$b.wasm.out" >"$t/$b.w"
  werr=$(grep -m1 -E '^(error|lower-wasm)' "$t/$b.wasm.out" | strip)
  if [ ! -s "$t/$b.n" ]; then
    msg="native run printed no summary: $(grep -v catalog "$t/$b.native" | head -1 | strip)"
    echo "FAIL $f: $msg"; record MISMATCH "$msg" "$msg"
  elif cmp -s "$t/$b.n" "$t/$b.w"; then
    echo "PASS $f ($(grep -m1 '^Ran' "$t/$b.n"); compile ${secs}s)"; pass=$((pass+1)); record MATCH "" ""
  else
    first=$(diff "$t/$b.n" "$t/$b.w" | grep -m1 '^[<>]' | strip)
    echo "FAIL $f: $first   [native: $(grep -m1 '^Ran' "$t/$b.n" | cut -c5-) | wasm: $(grep -m1 '^Ran' "$t/$b.w" | cut -c5-)]"
    [ -n "$werr" ] && echo "    wasm $werr"
    record MISMATCH "$first" "$werr"
  fi
done
echo "$pass/${#files[@]} pass"
[ $pass -eq ${#files[@]} ]
