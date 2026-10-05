#!/usr/bin/env bash
# checks/eval-native.sh [dir...] — the evaluator against let-go's own eval,
# native lg only (no wasm toolchain).
#
# Every program in corpus/eval/{special,macros,fns,errors,ns,reader,program}/,
# corpus/eval/program/multi/ (with -source-paths corpus/eval/program/multi/lib)
# and corpus/review5/fix-eval/ runs under stock lg twice, through
# checks/oracle.sh (the plan's match relation: stdout, exit class, first
# normalised error line):
#   native   as is: let-go's `eval`;
#   seam     the same text with a one-line prelude joined to its line 1, so
#            every line keeps its number: (require 'wasm.eval-native) loads
#            the host-free evaluator (rt/wasm/eval.lg) and then its native
#            host (rt/wasm/eval_native.lg, D187), and
#            (alter-var-root #'clojure.core/eval ..) makes `eval` wasm.eval/eval.
#            The joined copy lives in a scratch dir; -source-paths gains rt/
#            (and keeps '.', lg's default).
# Prints one MATCH/MISMATCH line per program, then "n/total MATCH" and the
# wall time. corpus/eval/native-ledger.md explains each MISMATCH. A program
# in `known` below (each a ledger entry) prints KNOWN-MISMATCH instead and
# does not fail the run; if it starts to MATCH it prints UNEXPECTED-MATCH
# and does fail, so the list cannot go stale. Exit 0 iff every other
# program MATCHes. Env: LG (env.sh).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"

# The seam side, called by oracle.sh as WASM_RUN: $0 --run <program> [args...]
if [ "${1:-}" = --run ]; then
  prog=$2; shift 2
  d=$(mktemp -d "${TMPDIR:-/tmp}/eval-native.XXXXXX"); trap 'rm -rf "$d"' EXIT
  j=$d/$(basename "$prog")
  { printf "(require 'wasm.eval-native) (alter-var-root (var clojure.core/eval) (fn [_] wasm.eval/eval)) "
    cat "$prog"; } >"$j"
  "$LG" -source-paths ".:$root/rt${EV_SP:+:$EV_SP}" "$j" "$@"
  exit $?
fi

# Native-seam limits (native-ledger.md, "Seam gaps"): let-go's 2-arg intern
# binds a new var to nil, so an evaluated (def x)/(declare x) is bound.
known=" corpus/eval/macros/destructure.lg corpus/review5/fix-eval/bug-02-declare-makes-var-bound.lg "

cd "$root"
t0=$(date +%s)
if [ $# -gt 0 ]; then dirs=("$@"); else
  dirs=(corpus/eval/special corpus/eval/macros corpus/eval/fns corpus/eval/errors corpus/eval/ns
        corpus/eval/reader corpus/eval/program corpus/eval/program/multi corpus/review5/fix-eval)
fi
n=0 match=0 kn=0 bad=0
for d in "${dirs[@]}"; do
  [ -d "$d" ] || { echo "no such dir: $d" >&2; exit 2; }
  while IFS= read -r f; do
    n=$((n+1))
    sp=""; case $d in */program/multi) sp=$d/lib ;; esac
    o=$(EV_SP=$sp LG_ARGS=${sp:+-source-paths $sp} WASM_RUN="$root/checks/eval-native.sh --run" checks/oracle.sh "$f" 2>&1)
    rc=$?
    case $known in *" $f "*) k=1 ;; *) k=0 ;; esac
    if [ $rc -eq 0 ]; then match=$((match+1))
      if [ $k = 1 ]; then bad=1; echo "UNEXPECTED-MATCH $f (listed as known: update native-ledger.md and this script)"
      else echo "MATCH $f"; fi
    elif [ $k = 1 ]; then kn=$((kn+1)); echo "KNOWN-MISMATCH $f: $(printf '%s' "$o" | head -1) (native-ledger.md)"
    else bad=1; echo "MISMATCH $f: $(printf '%s' "$o" | head -1)"; printf '%s\n' "$o" | sed -n '2,6p' | sed 's/^/    /'; fi
  done < <(find "$d" -maxdepth 1 -type f -name '*.lg' | LC_ALL=C sort)
done
echo "$match/$n MATCH, $kn known mismatches (native-ledger.md)"
echo "eval-native: wall $(( $(date +%s) - t0 ))s"
[ $bad = 0 ]
