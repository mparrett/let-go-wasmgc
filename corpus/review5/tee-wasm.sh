#!/usr/bin/env bash
# oracle.sh's WASM_RUN: $W/checks/wasm-run.sh, outputs kept in $R5_OUT.wasm.* (300 s cap)
. "$(dirname "$0")/../../checks/env.sh"
LG=$LW_ROOT/lg-bin/lg-e9789b7d53 gtimeout 300 "$W/checks/wasm-run.sh" "$@" >"$R5_OUT.wasm.out" 2>"$R5_OUT.wasm.err"; x=$?
echo "exit $x" >>"$R5_OUT.wasm.err"
cat "$R5_OUT.wasm.out"; cat "$R5_OUT.wasm.err" >&2; exit $x
