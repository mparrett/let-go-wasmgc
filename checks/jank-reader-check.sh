#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
sed 's/^(ns driver$/(ns reader-check-driver/' src/driver.lg > "$t/reader_check_driver.lg"
"$LG" -source-paths "src:$t:checks/fixtures/jank-reader" checks/jank-reader-check.lg
