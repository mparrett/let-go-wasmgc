#!/usr/bin/env bash
# checks/publish-check-push.sh — the pre-push hook (.pre-commit-config.yaml):
# checks/publish-check.sh over the commits being pushed. The pattern is the
# repository secret CI uses; without PUBLISH_CHECK_TERMS set locally this
# says so and lets the push go, and CI still runs the check.
set -uo pipefail
cd "$(dirname "$0")/.."
if [ -z "${PUBLISH_CHECK_TERMS:-}" ]; then
  echo "publish-check: PUBLISH_CHECK_TERMS unset, skipped (CI runs it)"
  exit 0
fi
# prek and pre-commit name the remote's old tip; a new branch has none, and
# is checked against main as CI does.
base=${PRE_COMMIT_FROM_REF:-}
case "$base" in ""|0000000000000000000000000000000000000000) base=origin/main ;; esac
exec checks/publish-check.sh "$base"
