#!/usr/bin/env bash
# checks/subject-lint-cases.sh — cases for subject-lint (Conventional Commits 1.0.0). Exit 0 iff all pass.
#   checks/subject-lint-cases.sh
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
fail=0
# case <name> <expect: ok|FAIL> <must-print regex or -> ; message on stdin
case_() {
  local name=$1 want=$2 must=$3 out rc got=ok bad=""
  cat >"$t/$name.txt"
  out=$(python3 "$here/subject-lint.py" "$t/$name.txt" 2>&1); rc=$?
  [ $rc -ne 0 ] && got=FAIL
  [ "$got" = "$want" ] || bad="exit $got, want $want"
  [ "$must" = - ] || grep -qE "$must" <<<"$out" || bad="$bad; missing /$must/"
  if [ -n "$bad" ]; then echo "FAIL $name: $bad"; sed 's/^/    /' <<<"$out"; fail=1; else echo "ok   $name"; fi
}

echo "fix(twin-manifest): read lw_rt's extra-twins routes written with rt-sym" | case_ scoped ok -
echo "feat: per-program run limits in run-corpus" | case_ unscoped ok -
echo "feat(driver)!: read programs in user first" | case_ breaking-bang ok -
printf 'refactor(checks): one limit wrapper\n\nThe runners call checks/limit.sh.\n\nBREAKING CHANGE: LW_LIMIT_RUN replaces the TIMEOUT files.\n' | case_ breaking-footer ok -
printf 'fix(corpus): reader-ns budget row\n\nRefs: #b2edfcf\n' | case_ trailer ok -

echo "twin-manifest: read lw_rt's extra-twins routes" | case_ area-only FAIL 'type'
echo "Fix(driver): capitalised type" | case_ capital-type FAIL 'type'
echo "fix(driver) read without colon" | case_ no-colon FAIL 'type'
echo "fix(driver):no space" | case_ no-space FAIL 'space'
echo "fix(driver): " | case_ empty-description FAIL 'description'
printf 'fix(driver): a subject\nbody without a blank line\n' | case_ no-blank-line FAIL 'blank line'
echo "fix(): empty scope" | case_ empty-scope FAIL 'scope'
echo "fix(driver): a subject that ends with a period." | case_ period ok 'warning .*period'
printf "Merge branch 'main' into workflow-state\n" | case_ git-merge ok 'written by git'
printf 'Revert "feat(sem): a table of running slots"\n\nThis reverts commit e9e51c6.\n' | case_ git-revert ok 'written by git'
echo "fixup! feat(checks): per-issue workflow state" | case_ git-fixup ok 'written by git'
echo "Merged the branch by hand" | case_ merged-by-hand FAIL 'type'

exit $fail
