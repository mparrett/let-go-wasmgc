#!/usr/bin/env bash
# host/build-repl-serve.sh <dir> — the let-go REPL demo (round 3): compile
# corpus/host/repl.lg through the backend, wasm-opt -O3, and lay out <dir>
# with repl.html + lg-wasm-host.js + repl.wasm so `python3 -m http.server
# 8262 -d <dir>` serves http://localhost:8262/repl.html. JSPI needs no COI.
# Env: LG, LW_NO_OPT=1. Prints raw/opt/brotli sizes.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: build-repl-serve.sh <dir>}
. "$(dirname "$0")/../checks/env.sh"
OPT=/opt/homebrew/opt/binaryen/bin/wasm-opt
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
"$here/checks/sem.sh" "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$here/corpus/host/repl.lg" "$t/repl.wat" >"$t/drv.log" 2>&1 || { grep -v catalog "$t/drv.log" >&2; exit 1; }
wasm-tools parse "$t/repl.wat" -o "$t/raw.wasm"
if [ -n "${LW_NO_OPT:-}" ]; then command cp "$t/raw.wasm" "$t/repl.wasm"; else
  "$OPT" -O3 --enable-gc --enable-reference-types --enable-exception-handling --enable-bulk-memory --enable-tail-call --enable-multivalue "$t/raw.wasm" -o "$t/repl.wasm" 2>/dev/null; fi
mkdir -p "$out"; command cp "$here/host/repl.html" "$here/host/lg-wasm-host.js" "$t/repl.wasm" "$out/"
echo "repl module: raw $(wc -c <"$t/raw.wasm" | tr -d ' ') B, served $(wc -c <"$t/repl.wasm" | tr -d ' ') B, brotli $(brotli -c "$t/repl.wasm" | wc -c | tr -d ' ') B -> $out" >&2
