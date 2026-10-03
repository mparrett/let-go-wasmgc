#!/usr/bin/env bash
# host/build-pages.sh <out-dir> — the static demo site: index.html (the
# landing page host/pages-index.html) plus the three demos in their own
# directories, each produced by its serve script:
#   repl/     host/build-repl-serve.sh        (compiles corpus/host/repl.lg)
#   xsofy/    host/build-xsofy-serve.sh       (module from build-xsofy-module.sh)
#   legmacs/  host/build-legmacs-serve.sh     (module from build-legmacs-module.sh)
# Any static server serves the result; the JSPI lane needs no COOP/COEP (D91).
# The xsofy and legmacs serve scripts read the xsofy checkout and the let-go
# checkout (XSOFY, LETGO); see each script's header. Env: LG, LW_NO_OPT=1.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build-pages.sh <out-dir>}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
mkdir -p "$out"
command cp "$here/pages-index.html" "$out/index.html"
"$here/build-repl-serve.sh" "$out/repl"
"$here/build-xsofy-module.sh" "$t/xsofy.wasm"
"$here/build-xsofy-serve.sh" "$out/xsofy" "$t/xsofy.wasm"
command mv -f "$out/xsofy/xsofy.wasm" "$out/xsofy/module.wasm"
"$here/build-legmacs-module.sh" "$t/legmacs.wasm"
"$here/build-legmacs-serve.sh" "$out/legmacs" "$t/legmacs.wasm"
command mv -f "$out/legmacs/legmacs.wasm" "$out/legmacs/module.wasm"
touch "$out/.nojekyll"
echo "site: $out ($(du -sh "$out" | cut -f1))" >&2
