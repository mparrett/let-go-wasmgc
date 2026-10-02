#!/usr/bin/env bash
# corpus/review5/run.sh <prog.lg>... : checks/oracle.sh verdict per program,
# both sides' stdout/stderr kept under results/<group>-<name>.{native,wasm}.{out,err}
# and the verdict in results/<group>-<name>.verdict.
# Env: LW_TREE = the lower-wasm tree whose checks/src/rt to use (default: the
# frozen copy this review ran on; set LW_TREE=<live dev/lower-wasm> to rerun on HEAD),
# LG_ARGS as oracle.sh, R5_PAR programs at once (default 3).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
W=${LW_TREE:-/private/tmp/claude-501/-Users-matt-projects-new-3p-joint-xsofy/fca6f592-886f-4b90-9538-46a9d7127210/scratchpad/ws/dev/lower-wasm}
export W here
mkdir -p "$here/results"
one() {
  p=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
  b=$(basename "$(dirname "$p")")-$(basename "$p" .lg)
  export R5_OUT=$here/results/$b
  v=$(cd "$W" && WASM_RUN="$here/tee-wasm.sh" LG="$here/tee-native.sh" checks/sem.sh checks/oracle.sh "$p" 2>&1)
  printf '%s\n' "$v" >"$here/results/$b.verdict"
  printf '%-44s %s\n' "$b" "$(printf '%s' "$v" | tail -n +1 | grep -m1 -E 'MATCH|MISMATCH|NOT IMPL' )"
}
export -f one
printf '%s\0' "$@" | xargs -0 -n1 -P "${R5_PAR:-3}" bash -c 'one "$0"'
