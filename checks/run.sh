#!/usr/bin/env bash
# checks/run.sh <item-id> — run one item's check from items.tsv. Exit 0 =
# that item is done; 1 = failing; 2 = the check script itself does not exist
# yet (the implementer builds the check with the feature; the reviewer runs
# this, never the implementer's own ad-hoc command).
set -uo pipefail
cd "$(dirname "$0")/.."
id=${1:?item id}
line=$(awk -F'\t' -v id="$id" '$1==id{print; exit}' checks/items.tsv)
[ -n "$line" ] || { echo "unknown item $id"; exit 2; }
cmd=$(printf '%s' "$line" | cut -f3)
echo "== $id: $(printf '%s' "$line" | cut -f4)"
echo "-- $cmd"
set -- $cmd
[ -x "$1" ] || [ "$(type -t "$1" 2>/dev/null)" = file ] || { echo "NOT IMPLEMENTED: $1 missing"; exit 2; }
eval "$cmd"
