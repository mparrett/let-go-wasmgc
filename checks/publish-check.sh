#!/usr/bin/env bash
# checks/publish-check.sh [base-ref] — refuse workspace-only material in this
# tree: tracked text files and the messages of the commits since base-ref
# (default: none, every commit reachable from HEAD). The pattern is read from
# PUBLISH_CHECK_TERMS (an extended regex, matched case-insensitively) so this
# file lists nothing itself; locally the workspace sets it, in CI a secret
# does. PUBLISH_CHECK_ALLOW (optional regex) names lines to ignore, matched
# against "<path>:<line>:<text>". Exit 1 with every hit when something
# matches, 2 when the pattern is unset, 0 when clean.
set -uo pipefail
# Scoped to this tree (the script's parent), so it also works when the tree
# is a subdirectory of a larger repository.
cd "$(dirname "$0")/.."
[ -n "${PUBLISH_CHECK_TERMS:-}" ] || { echo "publish-check: PUBLISH_CHECK_TERMS is unset" >&2; exit 2; }
allow=${PUBLISH_CHECK_ALLOW:-'^$'}
base=${1:-}
# --max-columns=0: a ripgrep config may truncate long lines and hide a match.
files=$(git ls-files -z | grep -z -v -E '\.(wasm|png|woff2?)$' | xargs -0 rg -n -i --max-columns=0 -e "$PUBLISH_CHECK_TERMS" 2>/dev/null | rg -v --max-columns=0 -e "$allow")
range=HEAD; [ -n "$base" ] && range="$base..HEAD"
msgs=$(git log --format='%h %s%n%b' "$range" -- . 2>/dev/null | rg -n -i --max-columns=0 -e "$PUBLISH_CHECK_TERMS")
rc=0
if [ -n "$files" ]; then echo "publish-check: files:" >&2; echo "$files" | cut -c1-200 >&2; rc=1; fi
if [ -n "$msgs" ]; then echo "publish-check: commit messages ($range):" >&2; echo "$msgs" | cut -c1-200 >&2; rc=1; fi
[ $rc -eq 0 ] && echo "publish-check: clean ($(git ls-files | wc -l | tr -d ' ') files, messages in $range)"
exit $rc
