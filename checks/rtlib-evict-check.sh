#!/usr/bin/env bash
# D231: the eval and no-eval runtime libraries coexist in one cache
# directory, and each build evicts only its own variant's stale files.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
LW_RTLIB_DIR="$t/cache" "$LG" -source-paths src checks/rtlib-evict-check.lg
