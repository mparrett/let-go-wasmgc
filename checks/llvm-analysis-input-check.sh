#!/usr/bin/env bash
# Exercise the driver's real input extraction and mutable-IR eligibility.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
sed 's/^(ns driver$/(ns analysis-check-driver/' src/driver.lg > "$t/analysis_check_driver.lg"
"$LG" -source-paths "src:$t" checks/llvm-analysis-input-check.lg
