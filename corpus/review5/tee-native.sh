#!/usr/bin/env bash
# oracle.sh's LG: native lg, with stdout/stderr also kept in $R5_OUT.native.*
"$HOME/projects-new/3p/lg-bin/lg-4e76921230" "$@" >"$R5_OUT.native.out" 2>"$R5_OUT.native.err"; x=$?
cat "$R5_OUT.native.out"; cat "$R5_OUT.native.err" >&2; exit $x
