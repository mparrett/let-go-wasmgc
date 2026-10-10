#!/usr/bin/env bash
# oracle.sh's LG: native lg, with stdout/stderr also kept in $R5_OUT.native.*
. "$(dirname "$0")/../../checks/env.sh"
"$LW_ROOT/lg-bin/lg-e9789b7d53" "$@" >"$R5_OUT.native.out" 2>"$R5_OUT.native.err"; x=$?
cat "$R5_OUT.native.out"; cat "$R5_OUT.native.err" >&2; exit $x
