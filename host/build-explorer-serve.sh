#!/usr/bin/env bash
# host/build-explorer-serve.sh <dir> — the eval/compile explorer (D194):
# build the compiler host corpus/emit/host/host.lg with LW_EXPORT_RT=1
# LW_RUNTIME_COMPILE=1, as checks/emit-linked.sh does and sharing its cache
# ($LW_EMIT_HOST_DIR, default $TMPDIR/lw-emit-host, keyed by a hash of src/,
# rt/ and the host program), wasm-opt -O3 it (the optimized host still links
# compiled code, D193), and lay out <dir> with explorer.html +
# lg-wasm-host.js + explorer.wasm so `python3 -m http.server 8263 -d <dir>`
# serves http://localhost:8263/explorer.html. JSPI needs no COI. The
# optimized module is cached as host.opt.wasm in the same directory.
# Env: LG, LW_NO_OPT=1. Prints raw/opt/brotli sizes.
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: build-explorer-serve.sh <dir>}
. "$here/checks/env.sh"
OPT=$WASM_OPT
cd "$here"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
key=$( { git ls-files -s src rt corpus/emit/host; git diff HEAD -- src rt corpus/emit/host; } | shasum | cut -c1-12)
hd=${LW_EMIT_HOST_DIR:-${TMPDIR:-/tmp}/lw-emit-host}/$key
if [ ! -f "$hd/host.wasm" ]; then
  mkdir -p "$hd"
  LW_EXPORT_RT=1 LW_RUNTIME_COMPILE=1 LW_RTLIB_DIR="$hd/rtlib" \
    "$here/checks/sem.sh" "$LG" -source-paths "$here/src" "$here/src/driver.lg" corpus/emit/host/host.lg "$hd/host.wat" >"$hd/build.log" 2>&1 \
    || { echo "host build failed:" >&2; tail -20 "$hd/build.log" >&2; exit 1; }
  wasm-tools parse "$hd/host.wat" -o "$hd/host.wasm.tmp" && wasm-tools validate "$hd/host.wasm.tmp" \
    || { echo "host module invalid" >&2; exit 1; }
  command mv -f "$hd/host.wasm.tmp" "$hd/host.wasm"
fi
# the optimized module is cached beside the host too (wasm-opt takes about 50 s)
if [ -n "${LW_NO_OPT:-}" ]; then command cp "$hd/host.wasm" "$t/explorer.wasm"; else
  if [ ! -f "$hd/host.opt.wasm" ]; then
    "$OPT" -O3 --enable-gc --enable-reference-types --enable-exception-handling --enable-bulk-memory --enable-tail-call --enable-multivalue "$hd/host.wasm" -o "$hd/host.opt.wasm.tmp" 2>/dev/null
    command mv -f "$hd/host.opt.wasm.tmp" "$hd/host.opt.wasm"
  fi
  command cp "$hd/host.opt.wasm" "$t/explorer.wasm"; fi
mkdir -p "$out"; command cp "$here/host/explorer.html" "$here/host/lg-wasm-host.js" "$t/explorer.wasm" "$out/"
echo "explorer host ($key): raw $(wc -c <"$hd/host.wasm" | tr -d ' ') B, served $(wc -c <"$t/explorer.wasm" | tr -d ' ') B, brotli $(brotli -c "$t/explorer.wasm" | wc -c | tr -d ' ') B -> $out" >&2
