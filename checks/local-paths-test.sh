#!/usr/bin/env bash
# checks/local-paths-test.sh — checks/local-paths.sh refuses a staged line
# that names a home or temp directory, and passes clean lines, removed
# lines and binary files. Runs in a scratch repository.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
cd "$t" && git init -q . && git config user.email t@t && git config user.name t
fail=0
expect() { # expect <rc> <label>
  "$here/checks/local-paths.sh" >/dev/null 2>&1; rc=$?
  [ "$rc" = "$1" ] || { echo "FAIL $2: exit $rc, want $1"; fail=1; }
  git reset -q 2>/dev/null; git checkout -q -- . 2>/dev/null; git clean -qfd
}
h='/Use''rs/someone/dev/x.lg'
printf 'clean\n' > a.txt; git add a.txt; git commit -qm a
printf 'ok line\n' > b.txt; git add b.txt;                                expect 0 clean
printf 'see %s\n' "$h" > b.txt; git add b.txt;                            expect 1 macos-home
printf 'see /ho''me/someone/x\n' > b.txt; git add b.txt;                  expect 1 linux-home
printf 'log /priv''ate/var/fold''ers/ab/xyz/T/f\n' > b.txt; git add b.txt; expect 1 var-folders
printf 'out /priv''ate/t''mp/x/y\n' > b.txt; git add b.txt;               expect 1 private-tmp
printf 'see %s\n' "$h" > a.txt; git commit -qam dirty
printf 'clean\n' > a.txt; git add a.txt;                                  expect 0 removed-line
printf 'bin\0%s\n' "$h" > c.bin; git add c.bin;                           expect 0 binary
printf 'see %s\n' "$h" > b.txt                                           # unstaged
expect 0 unstaged
[ $fail = 0 ] && echo "local-paths-test: ok"
exit $fail
