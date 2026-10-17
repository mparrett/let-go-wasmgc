#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
export LW_EXPECT_LETGO="$LW_ROOT/let-go"
env -u LETGO "$LG" -source-paths src checks/runtime-root-check.lg
env LETGO= "$LG" -source-paths src checks/runtime-root-check.lg
env LW_EXPECT_LETGO="$LETGO" LW_ROOT=/no-such-let-go-root "$LG" -source-paths src checks/runtime-root-check.lg
