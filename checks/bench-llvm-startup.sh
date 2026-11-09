#!/usr/bin/env bash
# Run through checks/quiet.sh. Compare committed lookup with working tree.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export lookup_bench_dir="$t"
git -c core.fsmonitor=false show HEAD:src/lw_rt.lg > "$t/lw_rt.lg"
# Keep identical source/runtime locations despite the baseline module copy.
python3 - "$t/lw_rt.lg" "$PWD/src" <<'PY'
import json, sys
from pathlib import Path
p=Path(sys.argv[1]); s=p.read_text()
a=s.index('(def src-dir '); b=s.index('\n', a)
s=s[:a]+'(def src-dir '+json.dumps(sys.argv[2])+')'+s[b:]
p.write_text(s)
PY
out=${1:-/tmp/llvm-startup-lookup.json}
hyperfine --shell bash --warmup 2 --runs 10 --export-json "$out" \
  --command-name before '"$LG" -source-paths "$lookup_bench_dir:src" src/driver.lg --target llvm --no-rt corpus/scalar/fib.clj "$lookup_bench_dir/before.ll"' \
  --command-name after '"$LG" -source-paths src src/driver.lg --target llvm --no-rt corpus/scalar/fib.clj "$lookup_bench_dir/after.ll"'
