#!/usr/bin/env bash
# Time each prog (built by build.sh into $OUT) on four lanes and record peak RSS. Usage: bench.sh [prog...]
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); W=${LW_SRC:-$here/../..}
P=${OUT:-${TMPDIR:-/tmp}/runtime-lanes}
LGV=${LGV:?set LGV to the lg binary for the vm lane and lg compile (the 2026-10-05 runs used dbaf59cb)}
# The wazero runner is the binary checks/wasm-run-linear.sh builds and caches;
# run that once first.
RUNNER=$(ls -t "${LW_WAZERO_CACHE:-${TMPDIR:-/tmp}/lw-wazero-runner}"/* | head -1)
RUNS=${RUNS:-5}
mkdir -p "$P/results"
progs=("$@"); [ ${#progs[@]} -gt 0 ] || progs=(empty fib tak loop10m vec-conj map-assoc seq-pipeline str-build)
for n in "${progs[@]}"; do
  src=$here/progs/$n.clj
  cmds=(); names=()
  names+=(vm);      cmds+=("$LGV $src")
  names+=(aot);     cmds+=("$P/aot/$n")
  [ -f "$P/mods/$n.linear.wasm" ] && { names+=(wazevo); cmds+=("$RUNNER $P/mods/$n.linear.wasm $src"); }
  [ -f "$P/mods/$n.gc.wasm" ] && { names+=(node-gc); cmds+=("node $W/src/run.mjs $P/mods/$n.gc.wasm $src"); }
  echo "== $n"
  for i in "${!cmds[@]}"; do
    out=$( { /usr/bin/time -l ${cmds[$i]} >/dev/null; } 2>&1 )
    rc=$?
    rss=$(echo "$out" | awk '/maximum resident set size/{printf "%.0f", $1/1048576}')
    printf '%-8s rc=%s peak=%sMiB\n' "${names[$i]}" "$rc" "$rss"
  done
  hf=(hyperfine -N --warmup 1 --runs "$RUNS" --export-json "$P/results/$n.json")
  for i in "${!cmds[@]}"; do hf+=(-n "${names[$i]}" "${cmds[$i]}"); done
  "${hf[@]}" 2>&1 | grep -E '^Benchmark|Time \(mean|User:|Range' | sed 's/^ *//'
done
