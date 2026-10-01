#!/usr/bin/env bash
# checks/gate.sh <phase> — every item of the phase must exit 0 (not 2).
set -uo pipefail
cd "$(dirname "$0")/.."
ph=${1:?phase}; fail=0
for id in $(awk -F'\t' -v p="$ph" '$1 !~ /^#/ && $2==p && $1 !~ /GATE/{print $1}' checks/items.tsv); do
  if checks/run.sh "$id" >/dev/null 2>&1; then echo "ok   $id"; else echo "FAIL $id (exit $?)"; fail=1; fi
done
exit $fail
