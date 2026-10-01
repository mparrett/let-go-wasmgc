#!/usr/bin/env bash
# checks/run-intrinsics-native.sh — P2.1 native half: run the intrinsic and
# pvec test files under native lg with the reference wasm.intrinsics.
# Exit 0 iff every assertion passes AND the number of tests run equals the
# number of deftest forms in the files (guards the run-tests zero-suite trap).
# The eventual P2.1 check is `checks/run-corpus.sh corpus/intrinsics --both`.
set -uo pipefail
cd "$(dirname "$0")/.."
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
expected=$(cat corpus/intrinsics/*_test.lg | grep -c '^(deftest ')
"$LG" -source-paths rt:corpus/intrinsics checks/intrinsics-native-runner.lg "$expected" $(for f in corpus/intrinsics/*_test.lg; do b=${f##*/}; b=${b%.lg}; echo "${b//_/-}"; done) 2>&1 \
  | grep -v '^ir.form-heads catalog loaded'
exit "${PIPESTATUS[0]}"
