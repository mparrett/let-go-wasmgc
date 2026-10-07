#!/usr/bin/env bash
# ndiff.sh <group-name>: rerun native for probes/<group>/<name>.lg and diff with results/<group>-<name>.wasm.out
here=$(cd "$(dirname "$0")" && pwd); b=$1; g=${b%%-*}; n=${b#*-}
. "$(dirname "$0")/../../checks/env.sh"
"$LW_ROOT/lg-bin/lg-ff1e6dac76" ${LG_ARGS:-} "$here/probes/$g/$n.lg" >"$here/results/$b.native.out" 2>"$here/results/$b.native.err"
diff "$here/results/$b.native.out" "$here/results/$b.wasm.out"; grep -v '^exit 0$' "$here/results/$b.wasm.err" | tail -3
