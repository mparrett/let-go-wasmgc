#!/usr/bin/env bash
# Classify leaf fns (fns the llvm lowering may call directly) over IR built
# by the driver's analysis, checks/llvm-leaf-check.lg.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
sed 's/^(ns driver$/(ns leaf-check-driver/' src/driver.lg > "$t/leaf_check_driver.lg"
LW_TARGET=llvm "$LG" -source-paths "src:$t" checks/llvm-leaf-check.lg
