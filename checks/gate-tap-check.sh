#!/usr/bin/env bash
# checks/gate-tap-check.sh — the gate's TAP: runs checks/gate.sh over a scratch
# items file (LW_ITEMS) of stub rows, one per outcome, checks each line and the
# gate's exit, and has prove parse the output, so the plan count and where the
# directives sit are judged by a TAP parser rather than by eye.
set -uo pipefail
cd "$(dirname "$0")/.."
# an outer gate's row selection must not replace the stub rows
unset LW_GATE_ROWS
command -v prove >/dev/null || { echo "SKIP no prove on PATH (it ships with Perl)"; exit 2; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi; }
gate() {  # gate <items file>: run phase 99 of it; output in $t/out, exit in $t/rc
  LW_ATTEST=0 LW_GATE_J=1 LW_ITEMS="$1" TMPDIR="$t/tmp" checks/gate.sh 99 > "$t/out" 2>/dev/null; echo $? > "$t/rc"
}
mkdir -p "$t/tmp"
# a row's command is eval'd, so a reason with # in it comes from a script
printf '#!/bin/sh\necho "SKIP no widget here (see #4)"\nexit 2\n' > "$t/skip.sh"; chmod +x "$t/skip.sh"
printf '#!/bin/sh\nprintf "%%s\\n" "SKIP no a\\\\b dir"\nexit 2\n' > "$t/skipbs.sh"; chmod +x "$t/skipbs.sh"
printf '#!/bin/sh\necho "SKIPPED is not a reason"\nexit 2\n' > "$t/skipped.sh"; chmod +x "$t/skipped.sh"
printf '#!/bin/sh\necho "SKIP one program"\necho "no such dir: gone" >&2\nexit 2\n' > "$t/skipfirst.sh"; chmod +x "$t/skipfirst.sh"
row() { printf '%s\t99\t%s\tstub\t%s\n' "$1" "$2" "${3:-}"; }
{
  row T.pass  "true"
  row T.skip  "$t/skip.sh"
  row T.todo  "bash -c 'exit 3'" 8a41e9d
  row T.known "false" 1234abc
  row T.bs    "$t/skipbs.sh"
} > "$t/good.tsv"
gate "$t/good.tsv"
check 'the plan line comes first' '[ "$(head -1 "$t/out")" = 1..5 ]'
check 'a passing row is ok' 'grep -qx "ok 1 - T.pass" "$t/out"'
check 'exit 2 with a SKIP line is ok # SKIP, its # escaped' 'grep -qx "ok 2 - T.skip # SKIP no widget here (see \\\\#4)" "$t/out"'
check 'not built with an owning issue is not ok # TODO' 'grep -q "^not ok 3 - T.todo # TODO git-issue:8a41e9d" "$t/out"'
check 'a known failure with an owning issue is not ok # TODO' 'grep -q "^not ok 4 - T.known # TODO git-issue:1234abc" "$t/out"'
check 'a backslash in a reason is escaped' 'grep -qxF "ok 5 - T.bs # SKIP no a\\\\b dir" "$t/out"'
check 'and that gate passes' '[ "$(cat "$t/rc")" = 0 ]'
check 'prove accepts it' 'prove -e cat "$t/out" >/dev/null 2>&1'
{
  row B.fail   "false"
  row B.noskip "bash -c 'echo no reason; exit 2'"
  row B.nb     "bash -c 'exit 3'"
  row B.bonus  "true" 8a41e9d
  row B.none   "no-such-command-anywhere"
  row B.skipped "$t/skipped.sh"
} > "$t/bad.tsv"
gate "$t/bad.tsv"
check 'a failing row is not ok' 'grep -q "^not ok 1 - B.fail (exit 1)" "$t/out"'
check 'exit 2 with no SKIP line is not ok' 'grep -q "^not ok 2 - B.noskip (exit 2, and its last line is not a SKIP line)" "$t/out"'
check 'not built with no owning issue is not ok' 'grep -q "^not ok 3 - B.nb (not built, and no owning issue" "$t/out"'
check 'a TODO row that passes is the bonus ok # TODO' 'grep -q "^ok 4 - B.bonus # TODO git-issue:8a41e9d" "$t/out"'
check 'a missing check script is not built (exit 3)' 'grep -q "^not ok 5 - B.none (not built" "$t/out"'
check 'SKIPPED is not the word SKIP' 'grep -q "^not ok 6 - B.skipped (exit 2, and its last line is not a SKIP line)" "$t/out"'
check 'and that gate fails' '[ "$(cat "$t/rc")" = 1 ]'
prove -e cat "$t/out" > "$t/prove" 2>&1
check 'prove reads every line of it and fails it' 'grep -q "Tests: 6 Failed: 5" "$t/prove"'
check 'prove sees the bonus TODO pass (the gate itself fails on it)' 'grep -q "TODO passed:   4" "$t/prove"'
# each way to fail must fail the gate alone, not only beside the others
alone() {  # alone <what> <command> [issue]
  row S.one "$2" "${3:-}" > "$t/one.tsv"; gate "$t/one.tsv"
  check "$1 alone fails the gate" '[ "$(cat "$t/rc")" = 1 ]'
}
alone 'a stale TODO' "true" 8a41e9d
alone 'a failing row' "false"
alone 'an exit 2 with no SKIP line' "bash -c 'exit 2'"
alone 'a SKIP line that is not the last line' "$t/skipfirst.sh"
alone 'a not-built row with no owning issue' "bash -c 'exit 3'"
# a check run with KEEP=1 prints its kept dir from an EXIT trap, after its SKIP line
printf '#!/bin/sh\ntrap '"'"'[ -n "${KEEP:-}" ] && echo "kept here" >&2'"'"' EXIT\necho "SKIP no browser here"\nexit 2\n' > "$t/keep.sh"; chmod +x "$t/keep.sh"
row S.keep "$t/keep.sh" > "$t/keep.tsv"
KEEP=1 gate "$t/keep.tsv"
check 'KEEP=1 does not turn a skip into a failure' 'grep -qx "ok 1 - S.keep # SKIP no browser here" "$t/out"'
: > "$t/empty.tsv"
gate "$t/empty.tsv"
check 'an empty phase is the plan 1..0, and passes' '[ "$(cat "$t/out")" = 1..0 ] && [ "$(cat "$t/rc")" = 0 ]'
exit $fail
