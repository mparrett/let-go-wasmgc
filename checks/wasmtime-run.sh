#!/usr/bin/env bash
# checks/wasmtime-run.sh <prog.lg> [args...] — compile a program through the
# lower-wasm backend and run it under wasmtime, behaving like `lg <prog.lg>
# args` on stdout and exit status: oracle.sh's WASM_RUN for the wasmtime host
# lane (D232). The compile is checks/wasm-run.sh's (LW_WASM_OUT), so the two
# runners share the driver flags, the limits and LW_MODULE_CACHE; the merged
# module is cached beside the program's under the same key.
#
# The program module is merged with host/wasmtime-adapter.wat by binaryen's
# wasm-merge, once as "env" and once (minus its memory and _start exports) as
# "term"; the adapter's _start calls `lw main`, so wasmtime runs the result as
# a WASI command with the lg path as argv[0] (--argv0 $LG, as node's hosts
# report os/args), the process environment (-S inherit-env=y, for os/getenv)
# and the cwd preopened (--dir ., for slurp). Flags: GC, exceptions, function
# references, tail calls, and a 256 MB wasm stack (ABI.md's depth table).
#
#   checks/wasmtime-run.sh --probe        print the wasmtime found, or SKIP
#   checks/wasmtime-run.sh --wasm m.wasm [args...]   run a built module
#
# wasmtime is taken from $WASMTIME, else PATH, else ~/.wasmtime/bin (the
# installer's default). Without one every form prints `SKIP (wasmtime: …)`
# naming the binary and exits 2; with LW_REQUIRE_WASMTIME=1 that is a FAIL,
# exit 1, for a machine where the lane is expected (D227's pattern).
# Env: LG, LG_ARGS, LW_MODULE_CACHE, LW_DRIVER_ARGS (as wasm-run.sh), KEEP=1.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/env.sh"
wt=${WASMTIME:-$(command -v wasmtime || true)}
[ -n "$wt" ] || { [ -x "$HOME/.wasmtime/bin/wasmtime" ] && wt=$HOME/.wasmtime/bin/wasmtime; }
if [ -z "$wt" ] || [ ! -x "$wt" ]; then
  why="no wasmtime binary on PATH or in ~/.wasmtime/bin (set WASMTIME)"
  [ -n "${LW_REQUIRE_WASMTIME:-}" ] && { echo "FAIL (LW_REQUIRE_WASMTIME is set: $why)"; exit 1; }
  echo "SKIP (wasmtime: $why)"; exit 2
fi
if [ "${1:-}" = --probe ]; then echo "wasmtime $("$wt" --version | awk '{print $2}') at $wt"; exit 0; fi
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
if [ "${1:-}" = --wasm ]; then
  cp "${2:?usage: wasmtime-run.sh --wasm <module.wasm> [args...]}" "$t/m.wasm"; shift 2
else
  prog=${1:?usage: wasmtime-run.sh <prog.lg> [args...]}; shift
  LW_WASM_OUT=$t/m.wasm "$here/checks/wasm-run.sh" "$prog" || exit $?
  set -- "$prog" "$@"
fi
# the merged module is deterministic in the program module and the adapter
key=""
if [ -n "${LW_MODULE_CACHE:-}" ]; then
  key=$(cat "$t/m.wasm" "$here/host/wasmtime-adapter.wat" | md5 -q)
fi
if [ -n "$key" ] && [ -f "$LW_MODULE_CACHE/$key.wt.wasm" ]; then
  cp "$LW_MODULE_CACHE/$key.wt.wasm" "$t/m.wt.wasm"
else
  feat=(--enable-gc --enable-reference-types --enable-exception-handling --enable-tail-call --enable-multivalue
        --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals --disable-compact-imports)
  wasm-tools parse "$here/host/wasmtime-adapter.wat" -o "$t/env.wasm" || exit 1
  grep -v -e '(export "memory"' -e '(export "_start")' "$here/host/wasmtime-adapter.wat" | wasm-tools parse -o "$t/term.wasm" - || exit 1
  # --no-validation: binaryen 133 refuses the adapter's import of `lw main`
  # ("(ref (exact $f)) is not a subtype of (ref $f)", an exact reference
  # failing its own supertype), so its check is skipped and wasm-tools
  # validates the merged module instead.
  if ! "$here/checks/limit.sh" compile "$WASM_MERGE" "${feat[@]}" --no-validation --rename-export-conflicts \
         "$t/m.wasm" main "$t/env.wasm" env "$t/term.wasm" term -o "$t/m.wt.wasm" 2>"$t/merge.err"; then
    cat "$t/merge.err" >&2; exit 1
  fi
  wasm-tools validate "$t/m.wt.wasm" || exit 1
  [ -n "$key" ] && command cp "$t/m.wt.wasm" "$LW_MODULE_CACHE/$key.wt.wasm.tmp$$" && command mv -f "$LW_MODULE_CACHE/$key.wt.wasm.tmp$$" "$LW_MODULE_CACHE/$key.wt.wasm"
fi
"$here/checks/limit.sh" run "$wt" run -W gc=y,exceptions=y,function-references=y,tail-call=y,max-wasm-stack=268435456 \
  -S inherit-env=y --dir . --argv0 "$LG" "$t/m.wt.wasm" "$@"
