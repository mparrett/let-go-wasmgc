#!/usr/bin/env bash
# Run through checks/quiet.sh: compare the committed driver, reuse disabled,
# and reuse enabled. Synthetic multi-round workload plus single-round fib.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
reuse_bench_dir=$(mktemp -d)
trap 'rm -rf "$reuse_bench_dir"' EXIT
export reuse_bench_dir
git -c core.fsmonitor=false show HEAD:src/driver.lg > "$reuse_bench_dir/baseline.lg"
python3 - "$reuse_bench_dir/many.lg" <<'PY'
import sys
from pathlib import Path
defs = [f'(defn stable-{i} [x] (loop [n x acc 0] (if (< n 1) acc (recur (dec n) (+ acc n)))))' for i in range(100)]
defs += ['(defn add-one [x] (+ x 1))', '(defn invoke [f x] (f x))', '(println (invoke add-one 41))']
defs += [f'(println (stable-{i} 10))' for i in range(100)]
Path(sys.argv[1]).write_text('\n'.join(defs) + '\n')
PY
out=${1:-/tmp/llvm-analysis-reuse-benchmark}
mkdir -p "$out"
export LW_LL_ANALYSIS_STATS=0
# Surface compiler errors before Hyperfine suppresses command output.
"$LG" -source-paths src "$reuse_bench_dir/baseline.lg" --target llvm --no-rt \
  "$reuse_bench_dir/many.lg" "$reuse_bench_dir/base.ll" > "$reuse_bench_dir/preflight.log" 2>&1 \
  || { cat "$reuse_bench_dir/preflight.log"; exit 1; }
hyperfine --shell bash --warmup 1 --runs 5 --export-json "$out/multi-round.json" \
  --command-name baseline '"$LG" -source-paths src "$reuse_bench_dir/baseline.lg" --target llvm --no-rt "$reuse_bench_dir/many.lg" "$reuse_bench_dir/base.ll"' \
  --command-name disabled 'LW_LL_ANALYSIS_REUSE=0 "$LG" -source-paths src src/driver.lg --target llvm --no-rt "$reuse_bench_dir/many.lg" "$reuse_bench_dir/off.ll"' \
  --command-name enabled 'LW_LL_ANALYSIS_REUSE=1 "$LG" -source-paths src src/driver.lg --target llvm --no-rt "$reuse_bench_dir/many.lg" "$reuse_bench_dir/on.ll"'
hyperfine --shell bash --warmup 1 --runs 5 --export-json "$out/single-round.json" \
  --command-name baseline '"$LG" -source-paths src "$reuse_bench_dir/baseline.lg" --target llvm --no-rt corpus/scalar/fib.clj "$reuse_bench_dir/base.ll"' \
  --command-name disabled 'LW_LL_ANALYSIS_REUSE=0 "$LG" -source-paths src src/driver.lg --target llvm --no-rt corpus/scalar/fib.clj "$reuse_bench_dir/off.ll"' \
  --command-name enabled 'LW_LL_ANALYSIS_REUSE=1 "$LG" -source-paths src src/driver.lg --target llvm --no-rt corpus/scalar/fib.clj "$reuse_bench_dir/on.ll"'
LW_LL_ANALYSIS_REUSE=1 LW_LL_ANALYSIS_STATS=1 "$LG" -source-paths src src/driver.lg \
  --target llvm --no-rt "$reuse_bench_dir/many.lg" "$reuse_bench_dir/on.ll"
