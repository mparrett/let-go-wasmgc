#!/usr/bin/env bash
# checks/llvm-xsofy-check.sh — xsofy on the llvm target (D222): P3.2's world
# dump (corpus/dump-world.lg over the xsofy checkout) compiled once with
# --target llvm, then seeds 1..XSOFY_SEEDS (default 20) at XSOFY_TURNS turns
# (default 60), each byte-identical to native lg's dump. Prints MATCH/DIFF
# per seed and "llvm-xsofy: k/n MATCH"; exits 1 on any DIFF or compile failure.
set -uo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
seeds=${XSOFY_SEEDS:-20}
turns=${XSOFY_TURNS:-60}
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# compile once: native-run.sh keeps its build dir under KEEP, and runs seed 1
KEEP=1 LG_ARGS="-source-paths $XSOFY" checks/native-run.sh corpus/dump-world.lg 1 1 > /dev/null 2> "$t/build.err"
bin=$(sed -n 's/^kept //p' "$t/build.err")/m
if [ ! -x "$bin" ]; then echo "llvm-xsofy: compile failed"; grep -v '^ *at ' "$t/build.err" | head -5; exit 1; fi
ok=0
for seed in $(seq 1 "$seeds"); do
  "$LG" -source-paths "$XSOFY" corpus/dump-world.lg "$seed" "$turns" > "$t/native" 2>/dev/null
  "$bin" corpus/dump-world.lg "$seed" "$turns" > "$t/llvm" 2>/dev/null
  if cmp -s "$t/native" "$t/llvm"; then ok=$((ok + 1)); echo "MATCH seed $seed"; else echo "DIFF seed $seed"; fi
done
rm -rf "$(dirname "$bin")"
echo "llvm-xsofy: $ok/$seeds MATCH"
[ "$ok" = "$seeds" ]
