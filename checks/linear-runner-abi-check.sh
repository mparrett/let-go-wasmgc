#!/usr/bin/env bash
# Native-oracle host ABI checks for argv and large buffers (2026-10-03).
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
export WASM_RUN=checks/wasm-run-linear.sh
LG_ARGS="-source-paths $PWD/corpus/typed" checks/oracle.sh checks/fixtures/linear-argv.lg extra
export LW_LINEAR_HOST_VALUE
LW_LINEAR_HOST_VALUE=$(python3 -c "print('Z' * 70000, end='')")
checks/oracle.sh checks/fixtures/linear-large-host.lg "$LW_LINEAR_HOST_VALUE"
