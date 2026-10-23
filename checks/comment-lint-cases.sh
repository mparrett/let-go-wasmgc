#!/usr/bin/env bash
# checks/comment-lint-cases.sh — cases for comment-lint's style rules. Exit 0 iff all pass.
#   checks/comment-lint-cases.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
# case <name> <expect: ok|FAIL> <must-print regex or -> <must-not-print regex or -> ; text on stdin
case_() {
  local name=$1 want=$2 must=$3 mustnot=$4 out rc
  cat >"$t/$name.md"
  out=$(python3 "$here/comment-lint.py" "$t/$name.md" 2>&1); rc=$?
  local got=ok; [ $rc -ne 0 ] && got=FAIL
  local bad=""
  [ "$got" = "$want" ] || bad="exit $got, want $want"
  [ "$must" = - ] || grep -qE "$must" <<<"$out" || bad="$bad; missing /$must/"
  [ "$mustnot" = - ] || ! grep -qE "$mustnot" <<<"$out" || bad="$bad; printed /$mustnot/"
  if [ -n "$bad" ]; then echo "FAIL $name: $bad"; sed 's/^/    /' <<<"$out"; fail=1; else echo "ok   $name"; fi
}

# a tight comment longer than any word budget: every sentence a fact, no filler
for i in $(seq 1 24); do echo "Row P$i.$i passes on the rebased head with the base's counts. Its log names $i programs."; done \
  | case_ tight-long ok - '^(ERROR|warning) '

echo "Fixed by #58. P6.0 passes on its head, with MISSING 0." \
  | case_ clean ok - '^(ERROR|warning) '

echo "I basically wanted to note that the fix actually works, owing to the fact that #57 moved the server." \
  | case_ needless ok 'warning needless .*(basically|actually|the fact that)' -

echo "The server was moved into the repo by #57. The probe is run by every browser row." \
  | case_ passive ok 'warning passive' -

echo "The old row was not very often green, and the README did not remember wasmtime." \
  | case_ negative ok 'warning negative' -

echo "The probe runs first, and it launches Chromium. The rows skip, and they print the reason. The gate counts exit 2, and it never reads green." \
  | case_ loose ok 'warning loose' -

printf 'First I ran the gate on the branch.\nThen I checked P6.0 against main.\nAfter that I looked at the log.\n' \
  | case_ narration ok 'warning narration' -

echo "To give some context, the browser rows used a server outside the repo. Fixed by #57." \
  | case_ context-opener ok 'warning opener' -

printf 'P4.0 fails on the wasmtime lane:\n\n```\nwasmtime  -  -  no  FAIL  FAIL  no JSPI: sleep/read_key block the thread and every other word in this very long code line does not count toward any sentence at all here\n```\n' \
  | case_ code-not-prose ok - '^(ERROR|warning) '

echo "Why did you skip wasmtime here? You forgot the README line." \
  | case_ personal ok 'warning personal' -

echo "Generated with a tool. Fixed by #58." \
  | case_ footer-still-error FAIL 'ERROR   footer' -

exit $fail
