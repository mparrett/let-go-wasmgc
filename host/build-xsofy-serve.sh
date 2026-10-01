#!/usr/bin/env bash
# host/build-xsofy-serve.sh <out-dir> [module.wasm ...] — a directory that
# serves xsofy/tools/xsofy-shell.html (copied unchanged) on the lower-wasm
# host: index.html = host/xsofy.html with the shell injected by the
# workspace's own local-scripts/inject-shell.sh (before </body>, sentinel
# wrapped), plus xsofy-shell-adapter.js, lg-wasm-host.js and the modules.
# Open <out-dir>/index.html?module=<name>.wasm through any static server;
# the JSPI lane needs no COOP/COEP (D91). Env: XSOFY (default the canonical
# checkout).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
ws=$(cd "$here/../../.." && pwd)
XSOFY=${XSOFY:-$ws/xsofy}
out=${1:?usage: build-xsofy-serve.sh <out-dir> [module.wasm ...]}; shift
mkdir -p "$out"
command cp "$here/xsofy.html" "$out/index.html"
command cp "$here/xsofy-shell-adapter.js" "$here/lg-wasm-host.js" "$out/"
for m in "$@"; do command cp "$m" "$out/"; done
"$ws/local-scripts/inject-shell.sh" "$out/index.html" "$XSOFY/tools/xsofy-shell.html" >/dev/null
