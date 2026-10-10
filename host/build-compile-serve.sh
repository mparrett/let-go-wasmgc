#!/usr/bin/env bash
# host/build-compile-serve.sh <dir> — the browser self-compilation demo
# (D206): build corpus/host/compile.lg against the renamed copy of src/
# exactly as checks/self-compile-module.sh builds the P12.4 and P12.5
# fixtures (LW_HOST_FS=1 LW_HOST_ASM=1, lw-rt's D209 snapshot, let-go's
# pkg/rt/core and ir/ at the pinned commit, the shared rtlib cache), wasm-opt
# -O3 it, build host/wat-asm (host/build-wat-asm.sh), and lay out <dir> with
# compile.html + compile-worker.js + lg-wasm-host.js + compile.wasm +
# rt-snapshot.edn + wat-asm.wasm + sizes.json, so `python3 -m http.server
# 8264 -d <dir>` serves http://localhost:8264/compile.html. JSPI needs no COI.
# The module and its wasm-opt output are cached under $LW_COMPILE_HOST_DIR
# (default $TMPDIR/lw-compile-host) by a hash of src/, rt/, the module script
# and the program; the first build takes minutes (the P12 rows' build times
# in STATUS.md, plus wasm-opt), later runs a few seconds.
# Env: LG, LETGO (env.sh), LW_NO_OPT=1, LW_SELF_COMPILE_CACHE (the rtlib dir).
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
out=${1:?usage: build-compile-serve.sh <dir>}
. "$root/checks/env.sh"
OPT=$WASM_OPT
prog=$root/corpus/host/compile.lg
key=$( { git -C "$root" ls-files -s src rt checks/self-compile-module.sh corpus/host/compile.lg
         git -C "$root" diff HEAD -- src rt checks/self-compile-module.sh corpus/host/compile.lg; } | shasum | cut -c1-12)
hd=${LW_COMPILE_HOST_DIR:-${TMPDIR:-/tmp}/lw-compile-host}/$key
if [ ! -f "$hd/compile.wasm" ] || [ ! -f "$hd/rt-snapshot.edn" ]; then
  t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
  . "$root/checks/self-compile-module.sh"
  sc_setup || exit 1
  sc_build "$prog" || exit 1
  mkdir -p "$hd"
  command cp "$t/m.wasm" "$hd/compile.wasm.tmp"; command mv -f "$hd/compile.wasm.tmp" "$hd/compile.wasm"
  command cp "$t/rt-snapshot.edn" "$hd/rt-snapshot.edn"
  echo "$build" >"$hd/build-seconds"
fi
if [ -z "${LW_NO_OPT:-}" ] && [ ! -f "$hd/compile.opt.wasm" ]; then
  "$OPT" -O3 --enable-gc --enable-reference-types --enable-exception-handling --enable-bulk-memory --enable-tail-call --enable-multivalue \
    "$hd/compile.wasm" -o "$hd/compile.opt.wasm.tmp" 2>/dev/null
  command mv -f "$hd/compile.opt.wasm.tmp" "$hd/compile.opt.wasm"
fi
"$root/host/build-wat-asm.sh" "$hd/wat-asm.wasm"
if [ -n "${LW_NO_OPT:-}" ]; then served=$hd/compile.wasm stage=raw; else served=$hd/compile.opt.wasm stage="wasm-opt -O3"; fi
sz() { wc -c <"$1" | tr -d ' '; }
br() { brotli -c "$1" | wc -c | tr -d ' '; }
letgo_commit=$(sed -n 's/^(def letgo-commit "\([0-9a-f]*\)")$/\1/p' "$root/src/lw_rt.lg")
mkdir -p "$out"
cat >"$out/sizes.json" <<JSON
{"date": "$(date +%F)", "key": "$key", "stage": "$stage", "letgo": "$letgo_commit", "build_seconds": $(cat "$hd/build-seconds" 2>/dev/null || echo null),
 "compiler_raw": $(sz "$hd/compile.wasm"), "compiler": $(sz "$served"), "compiler_brotli": $(br "$served"),
 "snapshot": $(sz "$hd/rt-snapshot.edn"), "snapshot_brotli": $(br "$hd/rt-snapshot.edn"),
 "assembler": $(sz "$hd/wat-asm.wasm"), "assembler_brotli": $(br "$hd/wat-asm.wasm")}
JSON
command cp "$root/host/compile.html" "$root/host/compile-worker.js" "$root/host/lg-wasm-host.js" "$hd/rt-snapshot.edn" "$hd/wat-asm.wasm" "$out/"
command cp "$served" "$out/compile.wasm"
echo "compile host ($key): raw $(sz "$hd/compile.wasm") B, served $(sz "$served") B ($stage), brotli $(br "$served") B; snapshot $(sz "$hd/rt-snapshot.edn") B; wat-asm $(sz "$hd/wat-asm.wasm") B -> $out" >&2
