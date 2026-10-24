#!/usr/bin/env bash
# checks/compile-times.sh [--runs N] [--targets gc,llvm] [--source-paths SP]
#                          [<program>...] — how
# long the driver takes to compile each program, per target.
#
# Each target first compiles each program once, unmeasured, so its runtime
# library cache is warm; then it compiles it N times (default 5) with
# LW_PHASE_TIMES=1. Prints one TSV row per run (target, program, run, wall ms,
# then the driver's phases: read, load, rtlib, analyze+lower, assemble, write),
# then per target and program the median of each column, then per program the
# ratio of the llvm and gc wall medians. `read` is the program file alone; its
# libraries are read during `load`. Wall time also covers what no phase does:
# starting lg, loading the driver, and the analysis between `load` and
# `rtlib`. Programs are named by file name, so give two programs with one name
# separately. A program's own directory and SP
# are on its source path. Default programs: a one-line (println 1),
# corpus/scalar/fib.clj and xsofy's world dump (corpus/dump-world.lg, with
# $XSOFY on the source path).
#
# Not a gate row: a time means something only on a quiet machine, so run it
# through checks/quiet.sh and record the revision and load average with it.
# The llvm target asks clang for the data layout: LLVM_BIN names clang's
# directory where it is not Homebrew's.
set -uo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
runs=5 targets=gc,llvm progs=() sp=
while [ $# -gt 0 ]; do
  case $1 in
    --runs) runs=${2:?}; shift 2 ;;
    --targets) targets=${2:?}; shift 2 ;;
    --source-paths) sp=${2:?}; shift 2 ;;
    -*) echo "usage: $0 [--runs N] [--targets gc,llvm] [--source-paths SP] [<program>...]" >&2; exit 2 ;;
    *) progs+=("$1"); shift ;;
  esac
done
case $runs in ''|*[!0-9]*|0) echo "--runs must be a positive integer (got '$runs')" >&2; exit 2 ;; esac
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
if [ ${#progs[@]} = 0 ]; then
  echo '(println 1)' > "$t/one-line.lg"
  progs=("$t/one-line.lg" corpus/scalar/fib.clj corpus/dump-world.lg)
  sp=${sp:-$XSOFY}
fi
phases="read load rtlib analyze+lower assemble write"
now_ms() { perl -MTime::HiRes=time -e 'printf "%d\n", time*1000'; }
compile() {  # compile <target> <program> <log file>: exit of the driver
  # both streams to the log: lg prints a compile error on stdout
  # lg's -source-paths loads the driver; the driver's own finds the program's
  # libraries (as checks/native-run.sh passes them)
  local psp=$(dirname "$2")${sp:+:$sp}
  LW_PHASE_TIMES=1 "$LG" -source-paths "src:$psp" src/driver.lg --target "$1" -source-paths "$psp" "$2" "$t/out" >"$3" 2>&1
}
fail=0
printf 'target\tprogram\trun\twall'; for p in $phases; do printf '\t%s' "$p"; done; echo
IFS=, read -r -a tl <<<"$targets"
for tg in "${tl[@]}"; do
  for pr in "${progs[@]}"; do
    name=$(basename "$pr")
    compile "$tg" "$pr" "$t/warm.err" || { echo "compile-times: $tg $name failed to compile:" >&2; grep -Ev '^(phase|WARNING:) ' "$t/warm.err" | head -3 >&2; fail=1; continue; }
    for ((r = 1; r <= runs; r++)); do
      t0=$(now_ms); compile "$tg" "$pr" "$t/err" || { echo "compile-times: $tg $name run $r failed:" >&2; grep -Ev '^(phase|WARNING:) ' "$t/err" | head -3 >&2; fail=1; break; }; t1=$(now_ms)
      printf '%s\t%s\t%s\t%s' "$tg" "$name" "$r" $((t1 - t0))
      for p in $phases; do printf '\t%s' "$(awk -v p="$p" '$1=="phase" && $2==p{s+=$3; f=1} END{print f ? s : "-"}' "$t/err")"; done
      echo
    done
  done
done > "$t/rows"
cat "$t/rows"
echo
echo "# median of $runs runs"
printf 'target\tprogram\twall'; for p in $phases; do printf '\t%s' "$p"; done; echo
awk -F'\t' 'NF { k=$1 "\t" $2; keys[k]=1; n[k]++; for (c=4; c<=NF; c++) v[k, c, n[k]]=$c; nc=NF }
  function med(k, c,   i, j, m, a, tmp) { m=n[k]; for (i=1; i<=m; i++) a[i]=v[k, c, i]
    for (i=1; i<=m; i++) if (a[i]=="-") return "-"
    for (i=1; i<=m; i++) for (j=i+1; j<=m; j++) if (a[j]+0 < a[i]+0) { tmp=a[i]; a[i]=a[j]; a[j]=tmp }
    return (m % 2) ? a[(m+1)/2] : (a[m/2] + a[m/2+1]) / 2 }
  END { for (k in keys) { line=k; for (c=4; c<=nc; c++) line=line "\t" med(k, c); print line } }' "$t/rows" | sort > "$t/med"
cat "$t/med"
echo
echo "# llvm/gc wall median"
awk -F'\t' '{ w[$1, $2]=$3; p[$2]=1 } END { for (q in p) if ((("llvm", q) in w) && (("gc", q) in w) && w["gc", q] > 0) printf "%s\t%.2f\n", q, w["llvm", q] / w["gc", q] }' "$t/med" | sort
exit $fail
