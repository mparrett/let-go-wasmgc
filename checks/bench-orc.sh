#!/usr/bin/env bash
# Measure execution setup for pre-emitted Fibonacci IR (no recursive call),
# then the full source-to-run path. Run under checks/quiet.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
export orc_bench_dir="$t" orc_bench_llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
export LW_ORC_RUNNER=$(bash checks/build-orc-runner.sh)
export LW_ORC_CACHE_DIR="$t/cache" LW_ORC_OPT_LEVEL=2 LW_ORC_STATS=0
out=${1:-/tmp/llvm-orc-benchmark}
mkdir -p "$out"
python3 - "$t/definitions.lg" <<'PY'
from pathlib import Path
import sys
s=Path('corpus/scalar/fib.clj').read_text()
assert s.count('(println (fib 35))') == 1
Path(sys.argv[1]).write_text(s.replace('(println (fib 35))', ''))
PY
"$LG" -source-paths src src/driver.lg --target llvm --no-rt "$t/definitions.lg" "$t/m.ll"
fixbits=$("$LG" -source-paths src checks/profile-field.lg host fixnum-bits)
for c in rt gc posix; do
  "$orc_bench_llvm/clang" -O2 -w "-DLG_FIXNUM_BITS=$fixbits" -emit-llvm -c "host/native/$c.c" -o "$t/$c.bc"
done
"$orc_bench_llvm/llvm-link" "$t/m.ll" "$t/rt.bc" "$t/gc.bc" "$t/posix.bc" -o "$t/all.bc"
"$LW_ORC_RUNNER" "$t/all.bc" "$t/definitions.lg"
hyperfine --shell bash --warmup 2 --runs 10 --export-json "$out/executor.json" \
  --command-name lli '"$orc_bench_llvm/lli" -O2 "$orc_bench_dir/all.bc" "$orc_bench_dir/definitions.lg"' \
  --command-name orc-uncached 'LW_ORC_CACHE=0 "$LW_ORC_RUNNER" "$orc_bench_dir/all.bc" "$orc_bench_dir/definitions.lg"' \
  --command-name orc-cached '"$LW_ORC_RUNNER" "$orc_bench_dir/all.bc" "$orc_bench_dir/definitions.lg"'
export LW_DRIVER_ARGS=--no-rt
hyperfine --shell bash --warmup 2 --runs 10 --export-json "$out/source-to-run.json" \
  --command-name aot 'env -u LW_NATIVE_JIT bash checks/native-run.sh "$orc_bench_dir/definitions.lg"' \
  --command-name lli 'LW_NATIVE_JIT=lli bash checks/native-run.sh "$orc_bench_dir/definitions.lg"' \
  --command-name orc-cached 'LW_NATIVE_JIT=orc bash checks/native-run.sh "$orc_bench_dir/definitions.lg"'
LW_ORC_STATS=1 "$LW_ORC_RUNNER" "$t/all.bc" "$t/definitions.lg"
