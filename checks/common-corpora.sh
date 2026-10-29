#!/usr/bin/env bash
# checks/common-corpora.sh <gc|llvm> — the program corpora both lanes run.
#
# Each corpus here is plain lg checked against native lg (checks/oracle.sh
# through checks/run-corpus.sh), so it is a behavior of the language, not of a
# lane: the GC lane's rows name these dirs themselves (their ids and commands
# unchanged), the llvm lane runs this list, and checks/lane-coverage.sh fails
# when a GC row runs a dir neither this list nor an llvm row covers. A test of one lane's mechanism is not common: it has a twin
# in the other lane's own corpus instead (refusals: `;; refuse-llvm:` in
# checks/refuse.sh; WasmGC's poly placeholders: corpus/poly).
#
# Prints run-corpus.sh's lines for each dir; exits 0 iff every dir MATCHes.
set -uo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
case ${1:-} in
  gc) runner=checks/wasm-run.sh ;;
  llvm) runner=checks/native-run.sh ;;
  *) echo "usage: $0 <gc|llvm>" >&2; exit 2 ;;
esac
fail=0
# dir [source paths]
while read -r d sp; do
  [ -z "$d" ] && continue
  case $d in \#*) continue ;; esac
  echo "== $d"
  if [ -n "$sp" ]; then
    WASM_RUN=$runner LG_ARGS="-source-paths ${sp//\$LW_ROOT/$LW_ROOT}" checks/run-corpus.sh "$d" || fail=1
  else
    WASM_RUN=$runner checks/run-corpus.sh "$d" || fail=1
  fi
done <<'EOF'
corpus/scalar
corpus/seqs
corpus/wasm
corpus/opmatrix
corpus/typed
corpus/control
corpus/closure
corpus/census/switch
corpus/review/fixed
corpus/wasm/pending/variadic
corpus/wasm/gaps
corpus/wasm/dynvars
corpus/wasm/arity
corpus/wasm/nsinit corpus/wasm/nsinit/lib
corpus/review3/fix-regex
corpus/review3/fix-twins
corpus/review3/fix-natives
corpus/review3/fix-meta
corpus/review3/fix-scope
corpus/review4/fix-traps
corpus/review4/fix-twins
corpus/review4/fix-backend
corpus/eval/errors
corpus/eval/fns
corpus/eval/macros
corpus/eval/ns
corpus/eval/program
corpus/eval/reader
corpus/eval/registry
corpus/eval/special
corpus/eval/program/multi corpus/eval/program/multi/lib
corpus/eval-buffer $LW_ROOT/legmacs
corpus/review5/fix-eval
corpus/review5/fix-rt
corpus/review5/fix-backend
EOF
exit $fail
