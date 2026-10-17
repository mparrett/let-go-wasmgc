#!/usr/bin/env bash
# checks/local-paths.sh — refuse staged lines that name the machine they were
# written on: a home directory (Users/<name> or home/<name> under the
# root) or a temp root (macOS private tmp, var folders). Generated artifacts
# (logs, census manifests, benchmark JSON) pick these up; write repo-relative
# paths, $LW_ROOT or $TMPDIR instead. Only added lines are checked, so
# files that already carry such paths can still be edited. A pre-commit hook
# (.pre-commit-config.yaml); publish-check covers the rest in CI.
set -uo pipefail
# Bracketed so this file does not match itself.
pat='(/User[s]|/hom[e])/[A-Za-z0-9._-]+/|/private/tm[p]/|/var/folder[s]/'
hits=$(git diff --cached -U0 --no-color --no-ext-diff --diff-filter=ACMR | awk -v pat="$pat" '
  /^\+\+\+ / { f = substr($0, 7); next }
  /^@@/ { split($3, a, ","); n = substr(a[1], 2) + 0; next }
  /^\+/ { if ($0 ~ pat) print f ":" n ": " substr($0, 2, 160); n++ }')
[ -z "$hits" ] && exit 0
echo "local-paths: staged lines name a local directory (use repo-relative paths, \$LW_ROOT or \$TMPDIR):" >&2
echo "$hits" >&2
exit 1
