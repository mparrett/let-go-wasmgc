#!/usr/bin/env bash
# checks/linear-gc.sh <row> — rows P11.0-P11.7, the linear target's M2
# collector (docs/LINEAR-TARGET-SPEC.md, "Milestone 2", D196). Each phase's
# pull request replaces its rows' placeholder with the real check. Exit 0
# pass, 1 fail, 2 the phase is not built yet.
set -uo pipefail
row=${1:?usage: linear-gc.sh <row>}
case $row in
  P11.0|P11.1) phase=0 ;;
  P11.2|P11.3) phase=1 ;;
  P11.4|P11.5) phase=2 ;;
  P11.6|P11.7) phase=3 ;;
  *) echo "linear-gc.sh: unknown row $row" >&2; exit 2 ;;
esac
echo "$row: linear M2 phase $phase is not built yet (docs/LINEAR-TARGET-SPEC.md, D196)"
exit 2
