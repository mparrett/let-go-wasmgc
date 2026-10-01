#!/usr/bin/env bash
# checks/wasm-run.sh <prog.lg> — compile a program through the lower-wasm
# backend and run it under node, behaving like `lg <prog.lg>` on stdout and
# exit status (DECISIONS D12). This is oracle.sh's WASM_RUN.
#
# A compile failure (driver error, unsupported op, invalid WAT) exits 1 with
# the tool output on stderr, so the oracle reports it as a MISMATCH rather
# than a match. Env: LG (default the plan's pinned main build), KEEP=1.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
prog=${1:?usage: wasm-run.sh <prog.lg>}
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
if ! "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$prog" "$t/m.wat" >"$t/drv.log" 2>&1; then
  cat "$t/drv.log" >&2; exit 1
fi
wasm-tools parse "$t/m.wat" -o "$t/m.wasm" || exit 1
node "$here/src/run.mjs" "$t/m.wasm"
