#!/usr/bin/env bash
# Focused regressions for the jank compiler/harness boundary; no suite skips.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
bash checks/jank-reader-check.sh
bash checks/runtime-root-check.sh
export WASM_RUN="$PWD/checks/native-run.sh" LW_NATIVE_JIT=orc
export LW_ORC_RUNNER=$(bash checks/build-orc-runner.sh)
export LW_DRIVER_ARGS=--no-rtlib
# Cohesive programs share compiler/runtime startup. The uncaught error stays
# separate because the oracle compares exit status and its first error line.
for group in values calls atoms definitions noncallable-error; do
  bash checks/oracle.sh "checks/fixtures/jank-reader/$group.lg"
done
export NATIVE_RUNNER="$PWD/checks/jank-native.lg" DRIVER_FLAGS='--read-clj --no-rtlib'
bash checks/run-tests.sh checks/fixtures/jank-reader/wrapped_test.cljc
