#!/usr/bin/env bash
# host/build-xsofy-module.sh <out.wasm> — xsofy's real entry (main.lg)
# compiled by the backend (P4.1), then wasm-opt -O3: the module the browser
# lane serves as module.wasm. Shared by checks/browser-boot.sh --xsofy,
# checks/lane5.sh and checks/size-boot.sh.
#
# Cached: the compile takes ~80 s, so the result is kept under
# $LW_XSOFY_CACHE (default ${TMPDIR:-/tmp}/lw-xsofy-module) keyed by an md5
# of everything that can change it: the lg binary, src/, the runtime sources
# (LW_RT_DIR when set, D104), xsofy's sources and wasm-opt's flags.
# Prints "cache hit|built <key>" and the raw/optimised sizes on stderr.
# Env: LG, XSOFY, LW_RT_DIR, LW_NO_OPT=1 (serve the unoptimised module),
# LW_XSOFY_RAW=<path> (also copy the unoptimised module there).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: build-xsofy-module.sh <out.wasm>}
. "$(dirname "$0")/../checks/env.sh"
XSOFY=${XSOFY:-$LW_ROOT/xsofy}
OPT=/opt/homebrew/opt/binaryen/bin/wasm-opt
optflags=(-O3 --enable-gc --enable-reference-types --enable-exception-handling --enable-bulk-memory
          --enable-tail-call --enable-multivalue)
cache=${LW_XSOFY_CACHE:-${TMPDIR:-/tmp}/lw-xsofy-module}; mkdir -p "$cache"
key=$( { shasum "$LG"; echo "${optflags[*]} ${LW_NO_OPT:-}";
         cat "$here"/src/*.lg "${LW_RT_DIR:-$here/rt/wasm}"/*.lg "${LW_RT_DIR:-$here/rt/wasm}"/README.md;
         cat "$XSOFY/main.lg"; find "$XSOFY/xsofy" -name '*.lg' -print0 | sort -z | xargs -0 cat; } | md5 -q)
if [ -f "$cache/$key.wasm" ]; then
  echo "cache hit $key" >&2
else
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  if ! "$here/checks/sem.sh" "$LG" -source-paths "$here/src:$XSOFY" "$here/src/driver.lg" \
         -source-paths "$XSOFY" "$XSOFY/main.lg" "$t/m.wat" >"$t/drv.log" 2>&1; then
    grep -v 'catalog' "$t/drv.log" >&2; exit 1
  fi
  wasm-tools parse "$t/m.wat" -o "$t/raw.wasm"
  if [ -n "${LW_NO_OPT:-}" ]; then command cp "$t/raw.wasm" "$t/m.wasm"; else "$OPT" "${optflags[@]}" "$t/raw.wasm" -o "$t/m.wasm"; fi
  command cp "$t/raw.wasm" "$cache/$key.raw.wasm"
  command cp "$t/m.wasm" "$cache/$key.wasm.tmp$$" && command mv -f "$cache/$key.wasm.tmp$$" "$cache/$key.wasm"
  echo "built $key" >&2
fi
command cp "$cache/$key.wasm" "$out"
[ -n "${LW_XSOFY_RAW:-}" ] && command cp "$cache/$key.raw.wasm" "$LW_XSOFY_RAW"
echo "module: $(wc -c <"$cache/$key.raw.wasm" | tr -d ' ') bytes raw, $(wc -c <"$out" | tr -d ' ') bytes served" >&2
