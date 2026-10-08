#!/usr/bin/env bash
# checks/wasm-run.sh <prog.lg> [args...] — compile a program through the
# lower-wasm backend and run it under node, behaving like `lg <prog.lg> args`
# on stdout and exit status (DECISIONS D12). This is oracle.sh's WASM_RUN.
#
# A compile failure (driver error, unsupported op, invalid WAT) exits 1 with
# the tool output on stderr, so the oracle reports it as a MISMATCH rather
# than a match.
#
# Env: LG (default the plan's pinned main build), KEEP=1, LG_ARGS (the same
# native-lg args oracle.sh passes; its `-source-paths <dirs>` names the
# library roots a multi-namespace program requires from, P3.2),
# LW_MODULE_CACHE=<dir> (reuse the compiled module of an unchanged program:
# keyed by the program, its source roots, src/ and rt/; args are run-time).
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/env.sh"
prog=${1:?usage: wasm-run.sh <prog.lg> [args...]}; shift
sp=""
read -r -a lgargs <<<"${LG_ARGS:-}"
for ((i = 0; i < ${#lgargs[@]}; i++)); do
  [ "${lgargs[$i]}" = -source-paths ] && sp=${lgargs[$((i + 1))]:-}
done
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
drv=("$LG" -source-paths "$here/src${sp:+:$sp}" "$here/src/driver.lg")
[ -n "$sp" ] && drv+=(-source-paths "$sp")
# LW_DRIVER_ARGS: extra driver flags (checks/run-tests.sh passes --test etc.)
read -r -a dargs <<<"${LW_DRIVER_ARGS:-}"; drv+=(${dargs[@]+"${dargs[@]}"})
key=""
if [ -n "${LW_MODULE_CACHE:-}" ]; then
  mkdir -p "$LW_MODULE_CACHE"
  key=$( { cat "$prog"; echo "$sp"; echo "target=${LW_TARGET:-gc} ${LW_DRIVER_ARGS:-}"; cat "$here"/src/*.lg "$here"/src/*.mjs "${LW_RT_DIR:-$here/rt/wasm}"/*.lg;
           [ -n "$sp" ] && IFS=: read -r -a roots <<<"$sp" && for r in "${roots[@]}"; do find "$r" -name '*.lg' -not -path '*/worktrees/*' -print0 | sort -z | xargs -0 cat; done; } | md5 -q)
fi
if [ -n "$key" ] && [ -f "$LW_MODULE_CACHE/$key.wasm" ]; then
  cp "$LW_MODULE_CACHE/$key.wasm" "$t/m.wasm"
else
  if ! "${drv[@]}" "$prog" "$t/m.wat" >"$t/drv.log" 2>&1; then
    cat "$t/drv.log" >&2; exit 1
  fi
  wasm-tools parse "$t/m.wat" -o "$t/m.wasm" || exit 1
  [ -n "$key" ] && command cp "$t/m.wasm" "$LW_MODULE_CACHE/$key.wasm.tmp$$" && command mv -f "$LW_MODULE_CACHE/$key.wasm.tmp$$" "$LW_MODULE_CACHE/$key.wasm"
fi
node "$here/src/run.mjs" "$t/m.wasm" "$prog" "$@"
