#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
"$LG" -source-paths src checks/runtime-var-lookup-check.lg
