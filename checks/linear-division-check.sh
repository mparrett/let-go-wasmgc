#!/usr/bin/env bash
# Unsupported integer division must be refused, typed floats compile (2026-10-03).
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
driver=("$LG" -source-paths "$PWD/src" "$PWD/src/driver.lg" --no-rt --target linear)
if "${driver[@]}" corpus/refused/linear/integer-division.lg "$t/refused.wat" > "$t/refused.log" 2>&1; then exit 1; fi
grep -q 'lower-wasm: unsupported op :div under linear (Ratio/BigInt result)' "$t/refused.log"
if "$LG" -source-paths "$PWD/src" "$PWD/src/driver.lg" --target linear corpus/refused/linear/first-class-division.lg "$t/first-class.wat" > "$t/first-class.log" 2>&1; then exit 1; fi
grep -q 'lower-wasm: unsupported op :div under linear (Ratio/BigInt result)' "$t/first-class.log"
"${driver[@]}" checks/fixtures/linear-float-division.lg "$t/float.wat" > "$t/float.log" 2>&1 || { cat "$t/float.log" >&2; exit 1; }
wasm-tools parse "$t/float.wat" -o "$t/float.wasm"
wasm-tools validate --features=-gc "$t/float.wasm"
echo 'PASS named integer division refusal and typed floating division compilation'
