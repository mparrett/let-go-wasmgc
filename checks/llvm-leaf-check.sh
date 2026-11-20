#!/usr/bin/env bash
# Classify leaf fns (fns the llvm lowering may call directly) over IR built
# by the driver's analysis, their record in signatures and in the cached
# runtime library (built here, in its own directory), and the direct-call
# function each leaf is emitted as, in the module the driver makes of
# corpus/llvm/leaves.lg and checks/fixtures/llvm-arch-leaves.lg (which also
# runs against native lg); checks/llvm-leaf-check.lg.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
arch=checks/fixtures/llvm-arch-leaves.lg
for p in corpus/llvm/leaves.lg "$arch"; do
  "$LG" -source-paths src src/driver.lg --target llvm "$p" "$t/$(basename "$p" .lg).ll"
done
LG_ARGS="-source-paths rt" WASM_RUN=checks/native-run.sh checks/oracle.sh "$arch"
sed 's/^(ns driver$/(ns leaf-check-driver/' src/driver.lg > "$t/leaf_check_driver.lg"
LW_LEAF_MODULES="$t/leaves.ll $t/llvm-arch-leaves.ll" LW_TARGET=llvm LW_RTLIB_DIR="$t/rtlib" \
  "$LG" -source-paths "src:$t" checks/llvm-leaf-check.lg
