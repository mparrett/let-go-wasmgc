#!/usr/bin/env bash
# corpus/review4/run.sh <prog.lg>... — review4's batch driver.
# Verdict per program is checks/oracle.sh (the match relation), run against a
# frozen copy of src/ rt/ checks/ (LW_TREE, default: the snapshot taken from
# joint 86f9fb1 + uncommitted P6.1 diff at the start of the review) so implementers' live edits
# cannot move results. Each side has a time limit; a timeout prints
# "error: TIMEOUT <side>" so a one-sided hang is a MISMATCH.
# Results: $OUT/<name>.verdict (+ .n.out/.w.out for MISMATCHes).
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${LW_TREE:=/private/tmp/claude-501/-Users-matt-projects-new-3p-joint-xsofy/fca6f592-886f-4b90-9538-46a9d7127210/scratchpad/ws/dev/lower-wasm}"
: "${OUT:=$here/results}"; mkdir -p "$OUT"
LGBIN=$HOME/projects-new/3p/lg-bin/lg-4e76921230
w=$(mktemp -d); trap 'rm -rf "$w"' EXIT
cat >"$w/lg" <<X
#!/usr/bin/env bash
timeout ${NTIME:-120} "$LGBIN" "\$@"; rc=\$?; [ \$rc -eq 124 ] && echo "error: TIMEOUT native" >&2; exit \$rc
X
cat >"$w/wr" <<X
#!/usr/bin/env bash
LG=$LGBIN timeout ${WTIME:-300} "$LW_TREE/checks/wasm-run.sh" "\$@"; rc=\$?; [ \$rc -eq 124 ] && echo "error: TIMEOUT wasm" >&2; exit \$rc
X
chmod +x "$w/lg" "$w/wr"
export w OUT LW_TREE LW_MODULE_CACHE=${LW_MODULE_CACHE:-$OUT/.modcache}
one() {
  f=$1; b=$(basename "$f" .lg)
  v=$(cd "$(dirname "$f")" && LG="$w/lg" WASM_RUN="$w/wr" "$LW_TREE/checks/oracle.sh" "$f" 2>&1)
  printf '%s\n' "$v" >"$OUT/$b.verdict"
  if [ "$(head -1 <<<"$v")" != MATCH ]; then
    (cd "$(dirname "$f")" && "$w/lg" "$f" >"$OUT/$b.n.out" 2>&1; "$w/wr" "$f" >"$OUT/$b.w.out" 2>&1)
  fi
  echo "$(head -1 <<<"$v") $b"
}
export -f one
printf '%s\0' "$@" | xargs -0 -n1 -P "${PAR:-3}" "$LW_TREE/checks/sem.sh" bash -c 'one "$1"' _
