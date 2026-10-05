#!/usr/bin/env bash
# Numeric representation probes; no oracle MATCH claim (2026-10-03).
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
"$LG" -source-paths "$PWD/src" "$PWD/checks/linear-representation-check.lg" "$t/m.wat" > "$t/log" 2>&1 || { cat "$t/log" >&2; exit 1; }
wasm-tools parse "$t/m.wat" -o "$t/m.wasm"
wasm-tools validate --features=-gc "$t/m.wasm"
export LW_LINEAR_REPRESENTATION_FIXTURE="$t/m.wasm"
(cd host/wazero && go test -run '^TestRepresentationProbes$' -count=1 .)
echo 'PASS linear representation probes validate and execute with GC disabled'
