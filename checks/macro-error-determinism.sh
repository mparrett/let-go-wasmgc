#!/usr/bin/env bash
# P1.8 (D184): formatter preservation and a bare macro-error native oracle.
# Inputs: src/, rt/, checks/native-msg-check.lg, checks/fixtures/macro-error-bare.lg,
# checks/env.sh, checks/sem.sh, checks/oracle.sh, checks/wasm-run.sh, src/run.mjs.
set -euo pipefail
. "$(dirname "$0")/env.sh"
cd "$(dirname "$0")/.."
checks/sem.sh "$LG" checks/native-msg-check.lg
WASM_RUN=checks/wasm-run.sh checks/sem.sh checks/oracle.sh checks/fixtures/macro-error-bare.lg
