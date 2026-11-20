#!/usr/bin/env bash
# checks/llvm-xxh3-bench.sh [runs] [outdir] — XXH3-64 of 25 MB on the llvm
# target: builds checks/fixtures/compute/xxh-25mb.lg (the runtime's own
# llvm.xxhash over a 25 MB buffer) with the driver's default cached runtime
# library, as a native executable, then times it with hyperfine under
# checks/quiet.sh, so the run holds the bench baton and every slot. The build
# is not timed. Prints the module's leaf-fn count, one in-program run (hash,
# nanoseconds) and hyperfine's summary. runs defaults to 5.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
runs=${1:-5}
out=${2:-$(mktemp -d)}
mkdir -p "$out"
llvm=${LLVM_BIN:-/opt/homebrew/opt/llvm/bin}
fixbits=$("$LG" -source-paths src checks/profile-field.lg host fixnum-bits)
"$LG" -source-paths src:rt src/driver.lg --target llvm checks/fixtures/compute/xxh-25mb.lg "$out/xxh.ll"
"$llvm/clang" -O2 -w "-DLG_FIXNUM_BITS=$fixbits" host/native/rt.c host/native/gc.c host/native/posix.c "$out/xxh.ll" -o "$out/xxh"
echo "leaf fns in the module: $(grep -c '^define.*\.leaf' "$out/xxh.ll" || true)"
"$out/xxh"
checks/quiet.sh hyperfine --warmup 1 --runs "$runs" --export-json "$out/hyperfine.json" "$out/xxh"
echo "artifacts: $out"
