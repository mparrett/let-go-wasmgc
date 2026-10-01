#!/usr/bin/env bash
# The match relation for every differential check in this plan.
#
#   checks/oracle.sh <program.lg> [args...]
#
# Runs the program under native lg and under the wasm backend, and declares
# a MATCH only when all three agree:
#   1. stdout, byte for byte;
#   2. exit class: both 0, or both non-zero;
#   3. on non-zero exit, the first line of stderr after normalisation
#      (paths, addresses and "at <file>:<line>" suffixes stripped), so a
#      program that throws must throw the same error, not merely fail.
# Prints MATCH or MISMATCH <which> and exits 0/1. Nothing else counts as
# "matches" anywhere in the plan.
#
# Env: LG (native lg; default = the plan's pinned main build),
#      WASM_RUN (command that compiles+runs an .lg through the backend and
#      behaves like lg on stdout/stderr/exit; unset = NOT IMPLEMENTED, exit 2),
#      KEEP=1 to leave the scratch dir behind.
set -uo pipefail
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
prog=$1; shift
[ -n "${WASM_RUN:-}" ] || { echo "NOT IMPLEMENTED: WASM_RUN unset (backend runner missing)"; exit 2; }
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] || rm -rf "$t"' EXIT
norm() { sed -E -e 's/\x1b\[[0-9;]*m//g' -e 's#(/[^ :]+)+/##g' -e 's/0x[0-9a-f]+/0xADDR/g' -e 's/ at [^ ]+:[0-9]+//g' -e 's/:[0-9]+:[0-9]+$//' | grep -m1 -i 'error' ; }
"$LG" "$prog" "$@" >"$t/n.out" 2>"$t/n.err"; nx=$?
$WASM_RUN "$prog" "$@" >"$t/w.out" 2>"$t/w.err"; wx=$?
if [ "$((nx==0))" != "$((wx==0))" ]; then echo "MISMATCH exit ($nx vs $wx)"; exit 1; fi
if [ $nx -eq 0 ]; then
  if ! cmp -s "$t/n.out" "$t/w.out"; then echo "MISMATCH stdout"; diff "$t/n.out" "$t/w.out" | head -5; exit 1; fi
else
  # lg prints its error report to STDOUT with ANSI colour, file:line:col and a
  # source excerpt; compare the normalised first error line of all output.
  ne=$(cat "$t/n.out" "$t/n.err" | norm); we=$(cat "$t/w.out" "$t/w.err" | norm)
  if [ "$ne" != "$we" ]; then echo "MISMATCH error"; echo "  native: $ne"; echo "  wasm:   $we"; exit 1; fi
fi
echo MATCH
