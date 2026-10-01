#!/usr/bin/env bash
# checks/run-tests.sh [--filter a,b] <file.lg | list.txt>...
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
# A .txt argument is a list of test files, one per line (# comments);
# --filter keeps the files whose path contains one of the comma-separated
# words. Deftests listed in checks/run-tests.skip are left out on both sides.
#
# Prints one line per file, PASS or FAIL (with the first differing line),
# then "pass/total". Exit 0 iff every file passes.
# Env: LG, KEEP=1 (keep the scratch dir), SRC_PATHS (native -source-paths,
# default rt:<file's dir>).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
filter=""; files=()
while [ $# -gt 0 ]; do
  case $1 in
    --filter) filter=$2; shift 2 ;;
    -*) echo "unknown flag $1" >&2; exit 2 ;;
    *.txt) while IFS= read -r l; do case $l in ''|'#'*) ;; *) files+=("$l") ;; esac; done < "$1"; shift ;;
    *) files+=("$1"); shift ;;
  esac
done
if [ -n "$filter" ]; then
  kept=()
  for f in "${files[@]}"; do
    IFS=, read -ra words <<<"$filter"
    for w in "${words[@]}"; do case $f in *"$w"*) kept+=("$f"); break ;; esac; done
  done
  files=("${kept[@]+"${kept[@]}"}")
fi
[ ${#files[@]} -gt 0 ] || { echo "usage: $0 [--filter a,b] <file.lg|list.txt>..." >&2; exit 2; }

t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
# the comparable lines of a run-tests transcript
norm() {
  grep -E '^(Ran [0-9]+ tests containing [0-9]+ assertions\.|[0-9]+ failures, [0-9]+ errors\.|(FAIL|ERROR) in \()' \
    | sed -E 's/^((FAIL|ERROR) in \([^)]*\)).*/\1/' \
    | awk '/^(FAIL|ERROR)/{print "1 " $0; next} {print "2 " $0}' | LC_ALL=C sort -s -k1,1 | cut -c3-
}
pass=0
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "FAIL $f: no such file"; continue; }
  b=$(basename "$f" .lg)
  ns=$(sed -nE 's/^\(ns ([^ )]+).*/\1/p' "$f" | head -1)
  skips=$(awk -v ns="$ns" '$1==ns{print $2}' "$here/checks/run-tests.skip" | paste -sd, -)
  "$LG" -source-paths "${SRC_PATHS:-$here/rt:$(dirname "$f")}" "$here/checks/native-test-runner.lg" "$ns" ${skips//,/ } \
    >"$t/$b.native" 2>&1
  start=$(date +%s)
  if ! "$LG" -source-paths "$here/src:$(dirname "$f")" "$here/src/driver.lg" "$f" "$t/$b.wat" --test ${skips:+--skip "$skips"} \
       >"$t/$b.drv" 2>&1; then
    echo "FAIL $f: compile: $(grep -v catalog "$t/$b.drv" | grep -m1 -iE 'error|lower-wasm' | sed -E 's/\x1b\[[0-9;]*m//g')"
    continue
  fi
  secs=$(( $(date +%s) - start ))
  if ! wasm-tools parse "$t/$b.wat" -o "$t/$b.wasm" 2>"$t/$b.asm"; then
    echo "FAIL $f: assemble: $(head -1 "$t/$b.asm")"; continue
  fi
  node "$here/src/run.mjs" "$t/$b.wasm" >"$t/$b.wasm.out" 2>&1
  norm <"$t/$b.native" >"$t/$b.n"; norm <"$t/$b.wasm.out" >"$t/$b.w"
  if [ ! -s "$t/$b.n" ]; then
    echo "FAIL $f: native run printed no summary: $(grep -v catalog "$t/$b.native" | head -1)"
  elif cmp -s "$t/$b.n" "$t/$b.w"; then
    echo "PASS $f ($(grep -m1 '^Ran' "$t/$b.n"); compile ${secs}s)"; pass=$((pass+1))
  else
    first=$(diff "$t/$b.n" "$t/$b.w" | grep -m1 '^[<>]')
    echo "FAIL $f: $first   [native: $(grep -m1 '^Ran' "$t/$b.n" | cut -c5-) | wasm: $(grep -m1 '^Ran' "$t/$b.w" | cut -c5-)]"
    grep -m1 '^error' "$t/$b.wasm.out" | sed 's/^/    wasm /'
  fi
done
echo "$pass/${#files[@]} pass"
[ $pass -eq ${#files[@]} ]
