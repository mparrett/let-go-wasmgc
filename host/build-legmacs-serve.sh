#!/usr/bin/env bash
# host/build-legmacs-serve.sh <out-dir> [module.wasm ...] — a directory that
# serves legmacs on the lower-wasm host (P6.4): index.html = host/legmacs.html
# (let-go's host.html frame + xterm CDN tags), xsofy-shell-adapter.js,
# lg-wasm-host.js, and let-go's stock lg-shell-xterm.js taken unchanged from
# the pinned commit with `git show` (the let-go checkout is not touched).
# Open <out-dir>/index.html?module=<name>.wasm (default module.wasm) through
# any static server; no COOP/COEP needed (D91). Env: LETGO (default the
# canonical checkout), LG_COMMIT (default ff1e6dac, the pinned lg).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$(dirname "$0")/../checks/env.sh"
LETGO=${LETGO:-$LW_ROOT/let-go}
LG_COMMIT=${LG_COMMIT:-ff1e6dac}
out=${1:?usage: build-legmacs-serve.sh <out-dir> [module.wasm ...]}; shift
mkdir -p "$out"
command cp "$here/legmacs.html" "$out/index.html"
command cp "$here/xsofy-shell-adapter.js" "$here/lg-wasm-host.js" "$out/"
git -C "$LETGO" show "$LG_COMMIT:pkg/rt/wasm/lg-shell-xterm.js" >"$out/lg-shell-xterm.js"
for m in "$@"; do command cp "$m" "$out/"; done
