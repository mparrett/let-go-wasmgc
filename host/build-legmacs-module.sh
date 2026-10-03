#!/usr/bin/env bash
# host/build-legmacs-module.sh <out.wasm> — legmacs' real entry (main.lg)
# compiled by the backend (P6.4), then wasm-opt -O3: the module the browser
# lane serves as module.wasm. Shared by checks/browser-boot.sh --legmacs and
# checks/size-boot.sh --legmacs. Same shape as build-xsofy-module.sh.
#
# Cached under $LW_LEGMACS_CACHE (default ${TMPDIR:-/tmp}/lw-legmacs-module),
# keyed by an md5 of the lg binary, src/, the runtime sources (LW_RT_DIR when
# set), legmacs' sources and wasm-opt's flags. A failed compile is not
# cached. Prints "cache hit|built <key>" and the raw/optimised sizes on
# stderr; on a failed compile, the driver's output (minus catalog lines) on
# stderr and exit 1. Env: LG, LEGMACS, LW_RT_DIR, LW_NO_OPT=1, LW_NO_EVAL=1,
# LW_LEGMACS_RAW=<path> (also copy the unoptimised module there),
# LW_LEGMACS_MAIN=<file.lg> (compile this entry instead of main.lg, still
# against the legmacs source root: a diagnostic stand-in for exercising the
# host while main.lg does not compile; checks never set it).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: build-legmacs-module.sh <out.wasm>}
. "$(dirname "$0")/../checks/env.sh"
LEGMACS=${LEGMACS:-$LW_ROOT/legmacs}
entry=${LW_LEGMACS_MAIN:-$LEGMACS/main.lg}
OPT=/opt/homebrew/opt/binaryen/bin/wasm-opt
optflags=(-O3 --enable-gc --enable-reference-types --enable-exception-handling --enable-bulk-memory
          --enable-tail-call --enable-multivalue)
cache=${LW_LEGMACS_CACHE:-${TMPDIR:-/tmp}/lw-legmacs-module}; mkdir -p "$cache"
# LW_NO_EVAL=1 (P7.6, no evaluator) is a different module: in the key, and
# only when set, so the default build keeps its key
key=$( { shasum "$LG"; echo "${optflags[*]} ${LW_NO_OPT:-}"; [ -n "${LW_NO_EVAL:-}" ] && echo "no-eval=$LW_NO_EVAL";
         cat "$here"/src/*.lg "$here"/src/*.mjs "${LW_RT_DIR:-$here/rt/wasm}"/*.lg "${LW_RT_DIR:-$here/rt/wasm}"/README.md;
         cat "$entry"; find "$LEGMACS/legmacs" -name '*.lg' -print0 | sort -z | xargs -0 cat; } | md5 -q)
if [ -f "$cache/$key.wasm" ]; then
  echo "cache hit $key" >&2
else
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  if ! "$here/checks/sem.sh" "$LG" -source-paths "$here/src:$LEGMACS" "$here/src/driver.lg" \
         -source-paths "$LEGMACS" "$entry" "$t/m.wat" >"$t/drv.log" 2>&1; then
    grep -v 'catalog' "$t/drv.log" >&2; exit 1
  fi
  wasm-tools parse "$t/m.wat" -o "$t/raw.wasm"
  if [ -n "${LW_NO_OPT:-}" ]; then command cp "$t/raw.wasm" "$t/m.wasm"; else "$OPT" "${optflags[@]}" "$t/raw.wasm" -o "$t/m.wasm"; fi
  command cp "$t/raw.wasm" "$cache/$key.raw.wasm"
  command cp "$t/m.wasm" "$cache/$key.wasm.tmp$$" && command mv -f "$cache/$key.wasm.tmp$$" "$cache/$key.wasm"
  echo "built $key" >&2
fi
command cp "$cache/$key.wasm" "$out"
[ -n "${LW_LEGMACS_RAW:-}" ] && command cp "$cache/$key.raw.wasm" "$LW_LEGMACS_RAW"
echo "module: $(wc -c <"$cache/$key.raw.wasm" | tr -d ' ') bytes raw, $(wc -c <"$out" | tr -d ' ') bytes served" >&2
