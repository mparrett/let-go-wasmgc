#!/usr/bin/env bash
# Allocator-owned host buffers survive length growth and shrinkage (2026-10-03).
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
"$LG" -source-paths "$PWD/src" checks/linear-host-check.lg "$t/m.wat"
wasm-tools parse "$t/m.wat" -o "$t/m.wasm"
wasm-tools validate --features=-gc "$t/m.wasm"
export LW_LINEAR_HOST_FIXTURE="$t/m.wasm"
(cd host/wazero && go test -run '^TestGrowingHostBuffer$' -count=1 .)
