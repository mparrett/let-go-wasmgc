#!/usr/bin/env bash
# checks/llvm-behavior-gates.sh — the llvm branch's behavior gates, serially:
# every row is an oracle, .out or unit check (no byte or WAT comparison).
# Prints "ROW <id> exit <n>" per row and exits 1 if any row failed.
# GC_LANE=0 skips the GC lane's rows; LW_PAR sets the corpora's parallelism
# (default 1: the rows run one after another).
cd "$(dirname "$0")/.."
. checks/env.sh
export LW_PAR=${LW_PAR:-1}
fail=0
row() { local name=$1; shift; "$@"; local rc=$?; echo "ROW $name exit $rc"; [ $rc = 0 ] || fail=1; }
llvm() { env WASM_RUN=checks/native-run.sh "$@"; }
row P12.3a llvm checks/run-corpus.sh corpus/llvm-scalar corpus/llvm
row P12.3b llvm LW_PROFILE=host-aarch64-darwin-fix31 checks/run-corpus.sh corpus/llvm-scalar corpus/llvm
row P12.3c checks/llvm-word-check.sh
row P12.20 checks/llvm-armv7-check.sh
row P12.21 checks/llvm-oom-check.sh
row P12.23 env TEST_DIR=corpus/llvm-rt checks/run-intrinsics-native.sh
row llvm-corpora llvm checks/run-corpus.sh corpus/scalar corpus/seqs corpus/wasm
row P1.10 checks/run-corpus.sh corpus/reader-ns
row P1.10-llvm llvm checks/run-corpus.sh corpus/reader-ns
row P12.30 checks/run-expected.sh corpus/poly-wasm
row P12.31 llvm checks/run-corpus.sh corpus/poly
row P12.32 llvm checks/run-expected.sh corpus/poly-clj
row P12.37 checks/llvm-rtlib-check.sh
row P12.38 checks/llvm-xsofy-check.sh
row P12.39 checks/llvm-refs-check.sh
# P12.40: lowering reads the session only through questions (red until
# the function cache's groundwork plan, Task 4)
row P12.40 checks/llvm-funnel-check.sh
if [ "${GC_LANE:-1}" = 1 ]; then
  row gc-corpora checks/run-corpus.sh corpus/scalar corpus/seqs corpus/wasm
  row P7.0 checks/run-corpus.sh corpus/eval/*/
  row P7.11 env LG_ARGS="-source-paths corpus/eval/program/multi/lib" checks/run-corpus.sh corpus/eval/program/multi
fi
exit $fail
