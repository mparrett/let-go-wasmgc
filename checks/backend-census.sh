#!/usr/bin/env bash
# checks/backend-census.sh [max-limits] — rows P12.1/P12.2: the backend's own
# units through checks/census.lg (as the xsofy/legmacs census, each unit
# lowered alone), counting the units that do not compile ("other ..." buckets;
# none since 2026-10-09: the `binding` sites became calls in P12.1/P12.2,
# and census.lg boxes float-tainted params as analyze-fn does).
# Prints each such row and the count; exit 0 iff count <= max-limits
# (default 0). File order matters: lower_linear.lg has no ns form and must
# follow lower_wasm.lg. ~4 min, one lg process. KEEP=1 keeps the TSV.
#
# Env: LG (env.sh).
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"
max=${1:-0}
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
mkdir -p "$t/wat"
if ! ( cd "$root" && LG_SOURCE_PATHS="$root:$root/src" "$LG" checks/census.lg "$root" backend "$t/backend.tsv" "$t/wat" \
      src/lw_rt.lg src/lw_ext.lg src/lower_wasm.lg src/lower_linear.lg src/driver.lg src/testshim.lg ) >"$t/log" 2>&1; then
  echo "census.lg failed:"; tail -5 "$t/log"; exit 1
fi
awk -F'\t' 'NR>1 && $5 !~ /^(ok|unbound-var|phase2-const)$/ {print "  " $2 " " $3 " (" $4 "): " substr($5,1,90)}' "$t/backend.tsv" > "$t/limits"
n=$(wc -l <"$t/limits" | tr -d ' ')
total=$(( $(wc -l <"$t/backend.tsv" | tr -d ' ') - 1 ))
cat "$t/limits"
echo "backend census: $total units, $n do not compile (max $max)"
[ "$n" -le "$max" ]
