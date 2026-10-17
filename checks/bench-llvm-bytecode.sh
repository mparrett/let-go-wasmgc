#!/usr/bin/env bash
# Fresh-process startup and compilation, excluding recursive fib execution.
# Run through checks/quiet.sh. Both engines use the same pinned LG.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
bench_dir=$(mktemp -d)
trap 'rm -rf "$bench_dir"' EXIT
export fib_compare_dir="$bench_dir"
export fib_compare_llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
out=${1:-/tmp/llvm-bytecode-comparison.json}
# -c evaluates top-level calls. Remove only the invocation on BOTH paths.
python3 - "$bench_dir/definitions.lg" <<'PY'
from pathlib import Path
import sys
s=Path('corpus/scalar/fib.clj').read_text()
assert s.count('(println (fib 35))') == 1
Path(sys.argv[1]).write_text(s.replace('(println (fib 35))', ''))
PY
sed 's/^(ns driver$/(ns startup-benchmark-driver/' src/driver.lg > "$bench_dir/startup_benchmark_driver.lg"
"$LG" -source-paths src src/driver.lg --target llvm --no-rt "$bench_dir/definitions.lg" "$bench_dir/definitions.ll"
export fib_compare_fixbits=$("$LG" -source-paths src checks/profile-field.lg host fixnum-bits)
hyperfine --shell bash --warmup 3 --runs 20 --export-json "$out" \
  --command-name bytecode-startup '"$LG" -e nil' \
  --command-name llvm-startup 'LW_TARGET=llvm "$LG" -source-paths "src:$fib_compare_dir" -e "(require (quote startup-benchmark-driver)) (require (quote lower-llvm))"' \
  --command-name bytecode-startup-and-compile '"$LG" -c "$fib_compare_dir/definitions.lgb" "$fib_compare_dir/definitions.lg"' \
  --command-name llvm-startup-and-emit-ir '"$LG" -source-paths src src/driver.lg --target llvm --no-rt "$fib_compare_dir/definitions.lg" "$fib_compare_dir/definitions.ll"' \
  --command-name llvm-machine-code-and-link '"$fib_compare_llvm/clang" -O2 -w "-DLG_FIXNUM_BITS=$fib_compare_fixbits" host/native/rt.c host/native/gc.c host/native/posix.c "$fib_compare_dir/definitions.ll" -o "$fib_compare_dir/definitions.bin"'
