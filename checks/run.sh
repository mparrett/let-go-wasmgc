#!/usr/bin/env bash
# checks/run.sh <item-id> — run one item's check from items.tsv. Exit 0 =
# that item is done; 1 = failing; 2 = the check script itself does not exist
# yet (the implementer builds the check with the feature; the reviewer runs
# this, never the implementer's own ad-hoc command).
set -uo pipefail
. "$(dirname "$0")/env.sh"
cd "$(dirname "$0")/.."
id=${1:?item id}
line=$(awk -F'\t' -v id="$id" '$1==id{print; exit}' checks/items.tsv)
[ -n "$line" ] || { echo "unknown item $id"; exit 2; }
cmd=$(printf '%s' "$line" | cut -f3)
echo "== $id: $(printf '%s' "$line" | cut -f4)"
echo "-- $cmd"
set -- $cmd
# a shell builtin (e.g. the P1.0 row's leading `test -x`) is a real command too
case "$(type -t "$1" 2>/dev/null)" in file|builtin) ;; *) [ -x "$1" ] || { echo "NOT IMPLEMENTED: $1 missing"; exit 2; } ;; esac
eval "$cmd"; rc=$?
# P5.4: a green run attests the row's current inputs (checks/attest.sh); the
# gate then skips it until an input moves. LW_ATTEST=0 disables.
[ $rc = 0 ] && [ "${LW_ATTEST:-1}" != 0 ] && checks/attest.sh record "$id" 2>/dev/null
exit $rc
