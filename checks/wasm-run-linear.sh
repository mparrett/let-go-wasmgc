#!/usr/bin/env bash
# Linear target and GC-disabled Go runner (2026-10-03).
set -euo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$here/checks/env.sh"
prog=${1:?usage: wasm-run-linear.sh <prog.lg> [args...]}; shift
sp=""
read -r -a lgargs <<<"${LG_ARGS:-}"
for ((i=0;i<${#lgargs[@]};i++)); do
 [ "${lgargs[$i]}" != -source-paths ] || sp=${lgargs[$((i+1))]:-}
done
t=$(mktemp -d)
trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
drv=("$LG" -source-paths "$here/src${sp:+:$sp}" "$here/src/driver.lg")
[ -z "$sp" ] || drv+=(-source-paths "$sp")
drv+=(--target linear)
key=""
if [ -n "${LW_MODULE_CACHE:-}" ]; then
 mkdir -p "$LW_MODULE_CACHE"
 key=$( { cat "$prog"; echo "$sp"; echo "target=linear eval=${LW_NO_EVAL:-0} table=${LW_NO_PROGRAM_TABLE:-0}"; cat "$here"/src/*.lg "${LW_RT_DIR:-$here/rt/wasm}"/*.lg;
  if [ -n "$sp" ]; then
   IFS=: read -r -a roots <<<"$sp"
   for r in "${roots[@]}"; do find "$r" -name '*.lg' -not -path '*/worktrees/*' -print0 | sort -z | xargs -0 cat; done
  fi
 } | md5 -q)
fi
if [ -n "$key" ] && [ -f "$LW_MODULE_CACHE/$key.wasm" ]; then
 cp "$LW_MODULE_CACHE/$key.wasm" "$t/m.wasm"
else
 if ! "${drv[@]}" "$prog" "$t/m.wat" > "$t/compile.log" 2>&1; then cat "$t/compile.log" >&2; exit 1; fi
 wasm-tools parse "$t/m.wat" -o "$t/m.wasm"
 wasm-tools validate --features=-gc "$t/m.wasm"
 if [ -n "$key" ]; then cp "$t/m.wasm" "$LW_MODULE_CACHE/$key.wasm.tmp$$"; mv "$LW_MODULE_CACHE/$key.wasm.tmp$$" "$LW_MODULE_CACHE/$key.wasm"; fi
fi
cache=${LW_WAZERO_CACHE:-${TMPDIR:-/tmp}/lw-wazero-runner}
mkdir -p "$cache"
runnerkey=$( { cat "$here"/host/wazero/{main.go,go.mod,go.sum}; go version; } | md5 -q)
runner=$cache/$runnerkey
if [ ! -x "$runner" ]; then
 (cd "$here/host/wazero" && go build -o "$runner.tmp$$" .)
 mv "$runner.tmp$$" "$runner"
fi
"$runner" "$t/m.wasm" "$prog" "$@"
