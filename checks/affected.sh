#!/usr/bin/env bash
# checks/affected.sh [--all] [<path>...]  — which items.tsv rows a change touches.
#
# With no args: paths = `git diff --name-only HEAD` (staged and unstaged) +
# untracked files under dev/lower-wasm (what an implementer is about to hand
# over). Runs under macOS bash 3.2; advisory only (D106), gates stay full. With paths:
# those. Prints the item ids whose check reads at least one of the paths,
# one per line, in items.tsv order; --all prints the id → inputs table.
#
# The map is a static table (below), not derived: every check script names
# its inputs in its header, and the table is the one place that has to move
# when a check grows a new input. Tokens are dir prefixes under dev/lower-wasm
# (`src/` = the backend, `rt/` = the runtime, `corpus/<x>/` = that corpus,
# `checks/<name>` = the script itself, `host/`), plus `xsofy`/`legmacs`
# for the external corpora (census, world-parity, native-twins).
#
# Rule of thumb the table encodes (measured 2026-10-01, perf-report.md):
#   src/ change    -> every oracle row + census (30 min fresh) + bench-fib
#   rt/ change     -> oracle rows that run programs (the runtime is linked in),
#                     native tier, review2, twins; NOT census, NOT refuse,
#                     NOT bench-fib (fib reaches no runtime: 1.3 KB shaken)
#   corpus/x/ only -> the rows that read corpus/x (no rtlib rebuild happens
#                     either way: the key hashes rt/ + src/ only)
#   checks/ only   -> the rows whose command names that script
set -uo pipefail
cd "$(dirname "$0")/.."
# id<TAB>space-separated input prefixes. "oracle" expands to the compile+run
# path: src/ rt/ checks/oracle.sh checks/wasm-run.sh src/run.mjs.
table() { cat <<'EOF'
P0.1	checks/run-corpus.sh checks/sem.sh checks/gate.sh checks/census.sh checks/census.lg checks/census-summary.py checks/run-intrinsics-native.sh checks/intrinsics-native-runner.lg checks/run.sh corpus/scalar/
P1.0	oracle corpus/scalar/
P1.1	oracle corpus/scalar/ corpus/opmatrix/ corpus/typed/ checks/run-corpus.sh
P1.2	oracle corpus/control/ checks/run-corpus.sh
P1.3	oracle corpus/closure/ checks/run-corpus.sh
P1.4	src/ checks/wasm-run.sh checks/refuse.sh corpus/refused/
P1.5	src/ checks/census.sh checks/census.lg checks/census-summary.py xsofy legmacs
P1.6	src/ checks/census.sh checks/census.lg checks/census-summary.py xsofy legmacs oracle corpus/census/switch/
P1.7	oracle corpus/review/ checks/run-corpus.sh checks/refuse.sh
P1.8	oracle checks/env.sh checks/sem.sh checks/macro-error-determinism.sh checks/native-msg-check.lg checks/fixtures/macro-error-bare.lg
P1.9	oracle corpus/consts/ checks/run-corpus.sh
P1.10	oracle src/driver.lg corpus/reader-ns/ checks/run-corpus.sh checks/native-run.sh
P1.GATE	src/ checks/bench-fib.sh checks/bench-fib.mjs checks/bench-fib-probe.lg corpus/scalar/fib.clj
P2.1	oracle corpus/wasm/ checks/run-corpus.sh
P2.2	oracle corpus/hash/ checks/hash-parity.sh checks/wasm-hash.sh
P2.3	oracle corpus/core-tests.txt checks/run-tests.sh checks/run-tests.skip src/testshim.lg
P2.4	oracle corpus/maporder/ checks/map-order.sh checks/run-tests.sh
P2.5	oracle corpus/seqs/ checks/run-corpus.sh
P2.6	oracle corpus/core-tests.txt checks/run-tests.sh
P2.7	oracle checks/run-roundtrip.sh
P2.9	rt/ corpus/intrinsics/ checks/run-intrinsics-native.sh checks/intrinsics-native-runner.lg
P2.8	rt/ corpus/natives/ checks/native-twins.sh tools/
P2.10	rt/ corpus/review2/ checks/run-review2.sh
P2.11	oracle corpus/wasm/ checks/run-corpus.sh
P2.12	oracle corpus/wasm/pending/variadic/ corpus/refused/ checks/refuse.sh
P3.0	rt/ corpus/intrinsics/ corpus/edn/ checks/run-intrinsics-native.sh
P3.1	rt/ corpus/natives/ checks/native-twins.sh tools/
P3.2	oracle corpus/dump-world.lg checks/world-parity.sh xsofy
P4.0	oracle host/ corpus/host/ checks/browser-boot.sh checks/browser-boot.mjs
P4.1	oracle host/ corpus/host/ checks/browser-boot.sh checks/browser-boot.mjs xsofy
P4.2	oracle host/ checks/lane5.sh xsofy
P4.3	oracle host/ checks/size-boot.sh xsofy
P2.14	oracle corpus/core-tests.txt checks/run-tests.sh checks/run-tests.skip src/testshim.lg
P5.0	corpus/quality/
P5.1	oracle corpus/core-tests.txt checks/run-tests.sh checks/run-tests.skip src/testshim.lg
P5.2	oracle corpus/core-tests.txt checks/run-tests.sh checks/run-tests.skip src/testshim.lg
P5.3	oracle corpus/wasm/gaps/ checks/run-corpus.sh
P5.4	checks/attest.sh checks/gate.sh checks/run.sh checks/affected.sh checks/items.tsv
P5.5	checks/affected.sh
P5.R	corpus/review3/
P5.6	oracle corpus/review3/fix-regex/ checks/run-corpus.sh
P5.7	oracle corpus/review3/fix-twins/ checks/run-corpus.sh
P5.8	oracle corpus/review3/fix-natives/ checks/run-corpus.sh
P5.9	oracle corpus/review3/fix-meta/ checks/run-corpus.sh
P5.10	oracle corpus/review3/ checks/run-tests.sh checks/run-tests.skip src/testshim.lg
P5.11	oracle corpus/review3/counter.txt checks/run-tests.sh src/testshim.lg
P5.12	oracle corpus/review3/fix-scope/ checks/run-corpus.sh
P6.0	rt/ corpus/natives/ checks/native-twins.sh tools/ legmacs
P6.1	oracle src/ checks/census.sh checks/census.lg checks/census-summary.py corpus/wasm/dynvars/ corpus/wasm/arity/ corpus/wasm/nsinit/ checks/run-corpus.sh legmacs
P6.2	oracle corpus/legmacs-tests.txt checks/run-tests.sh checks/run-tests.skip src/testshim.lg legmacs
P6.3	oracle checks/legmacs-parity.sh corpus/legmacs/ legmacs
P6.4	oracle host/ checks/browser-boot.sh checks/browser-boot.mjs legmacs
P6.5	oracle host/ checks/size-boot.sh legmacs
P6.R	corpus/review4/
P6.6	oracle corpus/review4/fix-traps/ checks/run-corpus.sh
P6.7	oracle corpus/review4/fix-twins/ checks/run-corpus.sh rt/ corpus/natives/ checks/native-twins.sh tools/ legmacs
P6.8	oracle corpus/review4/fix-backend/ checks/run-corpus.sh
P7.0	oracle corpus/eval/ checks/run-corpus.sh
P7.1	oracle corpus/legmacs-eval-tests.txt checks/run-tests.sh checks/run-tests.skip src/testshim.lg legmacs
P7.2	oracle checks/legmacs-parity.sh corpus/legmacs/ legmacs
P7.3	oracle corpus/eval-buffer/ checks/run-corpus.sh legmacs
P7.4	oracle host/ checks/size-boot.sh legmacs xsofy
P7.5	oracle host/ checks/eval-hosts.sh checks/browser-boot.mjs legmacs
P7.6	oracle src/ host/ checks/eval-optout.sh legmacs
P7.R	corpus/review5/
P7.7	oracle corpus/review5/fix-eval/ checks/run-corpus.sh
P7.8	oracle corpus/review5/fix-rt/ checks/run-corpus.sh
P7.9	oracle corpus/review5/fix-backend/ checks/run-corpus.sh
P7.10	rt/ corpus/eval/ corpus/review5/fix-eval/ checks/eval-native.sh checks/oracle.sh checks/env.sh
P8.0	src/ rt/ checks/gc-byte-identity.sh corpus/scalar/ corpus/eval/
P8.1	src/ rt/ checks/target-check.sh checks/linear-refuse-check.lg checks/fixtures/linear-target.lg checks/wasm-run.sh corpus/refused/linear/
P8.2	src/ rt/ checks/linear-layout-check.sh checks/linear-layout-check.lg
P8.3	src/ rt/ host/wazero/ checks/linear-representation-check.sh checks/linear-representation-check.lg
P8.6	oracle host/wazero/ checks/wasm-run-linear.sh checks/run-corpus.sh corpus/scalar/
P8.7	oracle host/wazero/ checks/wasm-run-linear.sh checks/run-corpus.sh corpus/opmatrix/ corpus/typed/
P8.8	oracle host/wazero/ checks/wasm-run-linear.sh checks/run-corpus.sh corpus/control/
P8.9	oracle host/wazero/ checks/wasm-run-linear.sh checks/run-corpus.sh corpus/closure/
P8.10	oracle host/wazero/ checks/wasm-run-linear.sh checks/run-corpus.sh corpus/seqs/
P8.4	src/ rt/ host/wazero/ checks/linear-host-check.sh checks/linear-host-check.lg
P8.5	src/ rt/ host/wazero/ checks/wasm-run-linear.sh checks/oracle.sh corpus/scalar/fib.clj
P8.12	src/ rt/ host/wazero/ checks/wasm-run-linear.sh checks/linear-runner-abi-check.sh checks/fixtures/linear-argv.lg checks/fixtures/linear-large-host.lg checks/oracle.sh
P8.11	src/ rt/ checks/linear-division-check.sh checks/fixtures/linear-float-division.lg corpus/refused/linear/integer-division.lg corpus/refused/linear/first-class-division.lg
P8.13	oracle host/wazero/ checks/wasm-run-linear.sh checks/run-corpus.sh corpus/linear-numeric/
P11.0	src/ rt/ host/wazero/ checks/linear-gc.sh checks/wasm-run-linear.sh
P12.1	oracle src/lower_llvm.lg src/lower_llvm_profile.lg host/native/ targets/ checks/native-run.sh checks/profile-field.lg corpus/llvm-scalar/
P12.2	src/driver.lg src/lower_wasm.lg src/lower_llvm.lg src/lower_llvm_profile.lg targets/ corpus/llvm-profile/ checks/llvm-profile-check.sh checks/profile-field.lg
P12.3	oracle src/lower_llvm.lg src/lower_llvm_profile.lg host/native/ targets/ checks/native-run.sh checks/llvm-word-check.sh checks/profile-field.lg corpus/llvm-scalar/ corpus/llvm/ corpus/llvm-profile/
P12.4	oracle src/driver.lg checks/run-tests.sh checks/jank-suite.sh checks/jank-native.lg checks/native-test-runner.lg corpus/jank-harness/
P12.23	rt/llvm/ corpus/llvm-rt/ checks/run-intrinsics-native.sh checks/intrinsics-native-runner.lg src/lower_llvm_poly.lg src/lower_llvm_ir.lg
P12.30	rt/wasm/poly.lg src/driver.lg corpus/poly-wasm/ checks/run-expected.sh
P12.31	oracle src/lower_llvm.lg src/lower_llvm_rt.lg src/lower_llvm_poly.lg rt/llvm/ host/native/ checks/native-run.sh corpus/poly/
P12.32	src/lower_llvm.lg src/lower_llvm_rt.lg src/lower_llvm_poly.lg rt/llvm/ host/native/ checks/native-run.sh checks/run-expected.sh corpus/poly-clj/
P12.37	src/ rt/llvm/ host/native/ checks/native-run.sh checks/llvm-rtlib-check.sh corpus/scalar/fib.clj corpus/poly/ corpus/llvm/
P12.38	src/ rt/llvm/ host/native/ checks/native-run.sh checks/llvm-xsofy-check.sh corpus/dump-world.lg xsofy
P12.39	src/lower_llvm.lg src/lower_llvm_rt.lg src/lower_llvm_ir.lg src/lower_llvm_refcheck.lg checks/llvm-refs-check.sh corpus/llvm/ corpus/poly/ corpus/control/
P12.40	src/ checks/llvm-funnel-lint.lg checks/llvm-funnel-check.sh
P12.20	oracle checks/llvm-armv7-check.sh src/lower_llvm.lg src/lower_llvm_profile.lg host/native/ targets/ checks/native-run.sh checks/build-builtins.sh checks/profile-field.lg corpus/llvm/ corpus/llvm-scalar/
P12.21	src/lower_llvm.lg src/lower_llvm_profile.lg host/native/ targets/ checks/native-run.sh checks/build-builtins.sh checks/llvm-oom-check.sh corpus/scalar/fib.clj
P11.1	src/ rt/ host/wazero/ checks/linear-gc.sh checks/wasm-run-linear.sh
P11.2	src/ rt/ host/wazero/ checks/linear-gc.sh checks/wasm-run-linear.sh corpus/linear-gc/
P11.3	src/ rt/ host/wazero/ checks/linear-gc.sh checks/wasm-run-linear.sh
P11.4	src/ rt/ host/wazero/ checks/linear-gc.sh checks/wasm-run-linear.sh corpus/linear-gc/
P11.5	src/ rt/ host/wazero/ checks/linear-gc.sh checks/wasm-run-linear.sh corpus/linear-gc/
P11.6	src/ rt/ host/wazero/ checks/linear-gc.sh checks/wasm-run-linear.sh legmacs
P11.7	src/ rt/ host/wazero/ checks/linear-gc.sh checks/wasm-run-linear.sh corpus/linear-gc/
P9.0	src/ rt/ checks/rtlib-cold-warm.sh corpus/eval/program/apply-update-warm-cache.lg
P9.1	src/ rt/ checks/gensym-load.sh checks/fixtures/gensym-probe.lg checks/env.sh
P9.2	src/ rt/ checks/rtlib-cold-warm.sh checks/fixtures/warm-gensym/
P10.0	src/ rt/ corpus/scalar/ corpus/eval/ checks/fixtures/warm-gensym/ legmacs checks/wasmbin-roundtrip.sh checks/sem.sh checks/env.sh
P10.1	rt/ corpus/scalar/ corpus/opmatrix/ corpus/typed/ corpus/emit/ checks/emit-native.sh checks/emit-run.mjs checks/oracle.sh checks/env.sh
P10.2	src/ rt/ corpus/scalar/ corpus/opmatrix/ corpus/typed/ corpus/emit/ host/node-host.mjs host/lg-wasm-host.js checks/emit-linked.sh checks/oracle.sh checks/env.sh
P10.3	src/ rt/ corpus/emit/host/ host/explorer.html host/build-explorer-serve.sh host/lg-wasm-host.js checks/explorer-page-check.mjs checks/sem.sh checks/env.sh
P7.11	oracle corpus/eval/program/multi/ checks/run-corpus.sh
P10.6	oracle checks/ir-pipeline.sh checks/fixtures/ir-pipeline/ checks/env.sh
EOF
}
# BSD sed has no \b: the token is always first in column 2, so match it there.
expand() { awk -F'\t' 'BEGIN{OFS="\t"} {sub(/^oracle /, "src/ rt/ checks/oracle.sh checks/wasm-run.sh ", $2); print}'; }
if [ "${1:-}" = --all ]; then table | expand; exit 0; fi
# bash 3.2 (macOS /bin/bash) has no mapfile. --relative keeps paths relative to
# this dir wherever the checkout sits (a worktree, a copy inside another repo);
# --no-renames lists both ends of a rename; `diff HEAD` covers staged and
# unstaged tracked changes, ls-files --others the new untracked files.
paths=()
if [ $# -gt 0 ]; then paths=("$@"); else
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "affected.sh: not in a git checkout; pass paths explicitly" >&2; exit 2; }
  while IFS= read -r p; do [ -n "$p" ] && paths+=("$p"); done < <({ git diff --name-only --relative --no-renames HEAD -- . ; git ls-files --others --exclude-standard -- . ; } | sort -u)
fi
[ ${#paths[@]} -gt 0 ] || { echo "no changes" >&2; exit 0; }
# a path matches a token when the token is a prefix of it (dirs end in /),
# or equals it; the external corpora match on their checkout paths.
table | expand | while IFS=$'\t' read -r id inputs; do
  hit=0
  for tok in $inputs; do
    for p in "${paths[@]}"; do
      case $p in "$tok"*) hit=1 ;; esac
      case $tok in xsofy|legmacs) case $p in *"/3p/$tok/"*) hit=1 ;; esac ;; esac
      [ $hit = 1 ] && break 2
    done
  done
  [ $hit = 1 ] && echo "$id"
done
# the loop above exits with the LAST row's hit test; the script's own status is "ran"
exit 0
