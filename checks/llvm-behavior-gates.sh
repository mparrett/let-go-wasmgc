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
# a serial check takes one slot of the machine-wide pool (checks/sem.sh), as
# run-corpus.sh's programs each do, so this gate shares the machine with
# other agents' builds instead of oversubscribing it
slot() { checks/sem.sh "$@"; }
row P12.3a llvm checks/run-corpus.sh corpus/llvm-scalar corpus/llvm
row P12.3b llvm LW_PROFILE=host-aarch64-darwin-fix31 checks/run-corpus.sh corpus/llvm-scalar corpus/llvm
row P12.3c slot checks/llvm-word-check.sh
row P12.20 slot checks/llvm-armv7-check.sh
row P12.21 slot checks/llvm-oom-check.sh
row P12.23 env TEST_DIR=corpus/llvm-rt checks/run-intrinsics-native.sh
row llvm-corpora llvm checks/run-corpus.sh corpus/scalar corpus/seqs corpus/wasm corpus/consts
# the GC lane's common program corpora, refusals and twin coverage, on llvm
row P13.9 checks/common-corpora.sh llvm
row P13.10 env LW_LANE=llvm bash -c 'checks/refuse.sh corpus/refused && checks/refuse.sh corpus/review/refused'
row P13.11 bash -c "RT=rt/llvm checks/native-twins.sh corpus/natives/natives-shared.txt --exclude term/ && RT=rt/llvm checks/native-twins.sh corpus/natives/natives-xsofy.txt --exclude term/ && RT=rt/llvm checks/native-twins.sh corpus/natives/natives-legmacs.txt --exclude term/ --skip corpus/natives/SKIP-legmacs"
row P13.12 llvm checks/run-tests.sh --corpus corpus/core-tests.txt --bar 273
row P13.13 env WASM_RUN=checks/native-run.sh LETGO_TEST=$LW_ROOT/legmacs/test SRC_PATHS=$LW_ROOT/legmacs:$LW_ROOT/legmacs/test bash -c 'checks/run-tests.sh --corpus corpus/legmacs-tests.txt && checks/run-tests.sh --corpus corpus/legmacs-eval-tests.txt'
row P13.14 env LW_LANE=llvm checks/legmacs-parity.sh 6
row P13.15 checks/lane-coverage.sh
row P1.10 checks/run-corpus.sh corpus/reader-ns
row P1.10-llvm llvm checks/run-corpus.sh corpus/reader-ns
row P12.30 slot checks/run-expected.sh corpus/poly-wasm
row P12.31 llvm checks/run-corpus.sh corpus/poly
row P12.32 slot env WASM_RUN=checks/native-run.sh checks/run-expected.sh corpus/poly-clj
row P12.37 checks/llvm-rtlib-check.sh   # slots its own compiles; its timed one runs under checks/quiet.sh
row P12.38 slot checks/llvm-xsofy-check.sh
row P12.39 slot checks/llvm-refs-check.sh
# P12.40: lowering reads the session only through questions
row P12.40 slot checks/llvm-funnel-check.sh
row LLVM.RTLIB.REUSE slot bash checks/llvm-rtlib-reuse-check.sh
row LLVM.ANALYSIS.REUSE slot bash checks/llvm-analysis-reuse-check.sh
row LLVM.ORC slot bash checks/llvm-orc-check.sh
row LLVM.JANK.ADAPTER slot bash checks/jank-llvm-check.sh
row LLVM.RUNTIME.LOOKUP slot env LW_TARGET=llvm bash checks/runtime-var-lookup-check.sh
row LLVM.CACHE.PACKAGING slot bash checks/self-compile-deps-check.sh
if [ "${GC_LANE:-1}" = 1 ]; then
  row gc-corpora checks/run-corpus.sh corpus/scalar corpus/seqs corpus/wasm
  row P7.0 checks/run-corpus.sh corpus/eval/*/
  row P7.11 env LG_ARGS="-source-paths corpus/eval/program/multi/lib" checks/run-corpus.sh corpus/eval/program/multi
fi
exit $fail
