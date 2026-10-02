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
P6.0	rt/ corpus/natives/ checks/native-twins.sh tools/ legmacs
P6.1	src/ checks/census.sh checks/census.lg checks/census-summary.py legmacs
P6.2	oracle corpus/legmacs-tests.txt checks/run-tests.sh checks/run-tests.skip src/testshim.lg legmacs
P6.3	oracle checks/legmacs-parity.sh corpus/legmacs/ legmacs
P6.4	oracle host/ checks/browser-boot.sh checks/browser-boot.mjs legmacs
P6.5	oracle host/ checks/size-boot.sh legmacs
P6.R	corpus/review4/
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
