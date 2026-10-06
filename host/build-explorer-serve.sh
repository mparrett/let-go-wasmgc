#!/usr/bin/env bash
# host/build-explorer-serve.sh <dir> — the eval/compile explorer (D194):
# build the compiler host corpus/emit/host/host.lg with LW_EXPORT_RT=1
# LW_RUNTIME_COMPILE=1, as checks/emit-linked.sh does and sharing its cache
# ($LW_EMIT_HOST_DIR, default $TMPDIR/lw-emit-host, keyed by a hash of src/,
# rt/ and the host program), wasm-opt -O3 it (the optimized host still links
# compiled code, D193), and lay out <dir> with explorer.html +
# lg-wasm-host.js + explorer.wasm so `python3 -m http.server 8263 -d <dir>`
# serves http://localhost:8263/explorer.html. JSPI needs no COI. It also
# builds the host with no flags and with LW_EXPORT_RT=1 alone, and writes
# sizes.json (the optimized bytes of all three and what each flag adds) for
# the page's header. Every build and its wasm-opt output is cached in the
# same directory: the first run takes about 3 minutes per variant on a
# quiet machine, later runs a few seconds.
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
# variant <name> [VAR=1 ...]: corpus/emit/host/host.lg built with those
# flags into $hd/<name>.wasm, and wasm-opt -O3 of it into <name>.opt.wasm,
# each built once per key. "host" (both flags) is the served module and
# the one checks/emit-linked.sh shares; the other two only measure what
# each flag adds (sizes.json).
variant() {
  local n=$1; shift
  if [ ! -f "$hd/$n.wasm" ]; then
    mkdir -p "$hd"
    # only the variant's own flags: a caller's exported LW_EXPORT_RT or
    # LW_RUNTIME_COMPILE must not reach the other variants (the driver
    # treats anything but "1" as off)
    env -u LW_EXPORT_RT -u LW_RUNTIME_COMPILE "$@" LW_RTLIB_DIR="$hd/rtlib" \
      "$here/checks/sem.sh" "$LG" -source-paths "$here/src" "$here/src/driver.lg" corpus/emit/host/host.lg "$hd/$n.wat" >"$hd/$n.build.log" 2>&1 \
      || { echo "$n build failed:" >&2; tail -20 "$hd/$n.build.log" >&2; exit 1; }
    wasm-tools parse "$hd/$n.wat" -o "$hd/$n.wasm.tmp" && wasm-tools validate "$hd/$n.wasm.tmp" \
      || { echo "$n module invalid" >&2; exit 1; }
    command mv -f "$hd/$n.wasm.tmp" "$hd/$n.wasm"
  fi
  if [ -z "${LW_NO_OPT:-}" ] && [ ! -f "$hd/$n.opt.wasm" ]; then
    "$OPT" -O3 --enable-gc --enable-reference-types --enable-exception-handling --enable-bulk-memory --enable-tail-call --enable-multivalue "$hd/$n.wasm" -o "$hd/$n.opt.wasm.tmp" 2>/dev/null
    command mv -f "$hd/$n.opt.wasm.tmp" "$hd/$n.opt.wasm"
  fi
}
variant host LW_EXPORT_RT=1 LW_RUNTIME_COMPILE=1
# the flags are in the cache names: host-default and host-export, the names
# before this, could hold modules built with an exported flag
variant host-rt0-rc0
variant host-rt1-rc0 LW_EXPORT_RT=1
if [ -n "${LW_NO_OPT:-}" ]; then sfx=wasm stage=raw ver=""; else sfx=opt.wasm stage="wasm-opt -O3" ver=$("$OPT" --version | head -1 | sed 's/^wasm-opt version //' | tr -d '"\\' | sed 's/[[:space:]]*$//'); fi
command cp "$hd/host.$sfx" "$t/explorer.wasm"
sz() { wc -c <"$hd/$1.$sfx" | tr -d ' '; }
d=$(sz host-rt0-rc0) e=$(sz host-rt1-rc0) b=$(sz host)
br=$(brotli -c "$t/explorer.wasm" | wc -c | tr -d ' ')
cat >"$t/sizes.json" <<JSON
{"date": "$(date +%F)", "key": "$key", "stage": "$stage", "binaryen": "$ver", "raw": $(wc -c <"$hd/host.wasm" | tr -d ' '),
 "default": $d, "export_rt": $e, "both": $b,
 "evaluator_and_runtime": $d, "kept_for_linking": $((e - d)), "compiler": $((b - e)),
 "served": $b, "served_brotli": $br}
JSON
mkdir -p "$out"; command cp "$here/host/explorer.html" "$here/host/lg-wasm-host.js" "$t/explorer.wasm" "$t/sizes.json" "$out/"
echo "explorer host ($key): raw $(wc -c <"$hd/host.wasm" | tr -d ' ') B, served $b B ($stage), brotli $br B; default $d, export-only $e -> $out" >&2
