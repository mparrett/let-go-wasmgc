#!/usr/bin/env bash
# checks/ir-pipeline.sh — row P10.6: let-go's IR pipeline carried as a
# program. checks/fixtures/ir-pipeline/main.lg requires ir.build, ir.dump and
# ir.passes.pipeline with let-go's pkg/rt/core/ir (at the pinned commit, exported
# with git archive) as a library source path, so
# the driver indexes the IR tree as it does any -source-paths library (its
# defs, deftypes, defrecords and protocols included), builds and optimizes
# five defn forms and prints their text dumps. The module's output must equal
# native lg's exactly. LW_PROGRAM_TABLE=1 because ir.data's init interns its
# accessors into `ir` through resolve, which reads the program table
# (src/driver.lg).
# Prints MATCH or MISMATCH (with the first lines of the diff), the module
# size and the wall time. Exit 0 iff MATCH; 2 without a let-go checkout.
#
# Env: LG, LETGO (env.sh), LW_RTLIB_DIR.
set -uo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/checks/env.sh"
export LG
# The IR tree at the commit the pinned lg was built from (src/lw_rt.lg's
# letgo-commit; both move on a pin bump), not the checkout's working tree:
# the module must carry the same pipeline the native oracle runs.
letgo_commit=e9789b7d
prog=$root/checks/fixtures/ir-pipeline/main.lg
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
# Only ir/ is exported: pkg/rt/core also holds string.lg and the other
# embedded libraries, which the driver would index as program libraries in
# place of the runtime's own namespaces.
if ! git -C "$LETGO" archive "$letgo_commit" pkg/rt/core/ir 2>"$t/git.err" | tar -x -C "$t"; then
  echo "SKIP ir-pipeline (cannot read pkg/rt/core/ir at let-go $letgo_commit from $LETGO; set LETGO)"; exit 2
fi
core=$t/pkg/rt/core
if ! "$LG" "$prog" >"$t/native.txt" 2>&1; then
  echo "native run failed:"; tail -5 "$t/native.txt"; exit 1
fi
start=$(date +%s)
LW_PROGRAM_TABLE=1 LG_ARGS="-source-paths $core" KEEP=1 \
  bash "$root/checks/wasm-run.sh" "$prog" >"$t/module.txt" 2>"$t/module.err"
rc=$?
kept=$(sed -n 's/^kept //p' "$t/module.err" | tail -1)
size=""
[ -n "$kept" ] && [ -f "$kept/m.wasm" ] && size=$(wc -c <"$kept/m.wasm" | tr -d ' ')
[ -n "$kept" ] && command rm -rf "$kept"
secs=$(( $(date +%s) - start ))
if [ $rc -ne 0 ]; then
  echo "MISMATCH: module run exited $rc"; grep -v '^kept ' "$t/module.err" | tail -8; exit 1
fi
# A fn-template constant (an inner fn's IR, built for a closure) prints its
# aux through the host: natively the Go vm.Consts struct and the reader's
# source-info table, in the module wasm.ir's placeholders (its header names
# both). The IR itself is in the dump's other lines, so that aux is replaced
# on both sides.
for f in native module; do
  sed -E 's/(= Const ; \{:kind :fn-template ).*(\} : \?\?)?$/\1<host-printed aux>/' "$t/$f.txt" >"$t/$f.norm"
done
if cmp -s "$t/native.norm" "$t/module.norm"; then
  echo "MATCH ir-pipeline ($(wc -l <"$t/native.txt" | tr -d ' ') lines; module ${size:-?} bytes; ${secs}s)"
else
  echo "MISMATCH ir-pipeline (module ${size:-?} bytes; ${secs}s):"
  diff "$t/native.norm" "$t/module.norm" | head -120
  exit 1
fi
