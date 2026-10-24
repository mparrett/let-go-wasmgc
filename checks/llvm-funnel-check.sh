#!/usr/bin/env bash
# checks/llvm-funnel-check.sh — row P12.40: lowering reads session state
# only through questions (checks/llvm-funnel-lint.lg). First a self-test on
# a planted read (reported) and the same read inside a defquestion (not),
# then the lint over the files lowering runs from. Exits 1 on any violation.
set -uo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
lint() { "$LG" checks/llvm-funnel-lint.lg "$@"; }
printf '(defn f [v] (get @*sigs* v))\n' > "$t/bad.lg"
printf '(lc/defquestion q-sig [v] [:sig v] (get @*sigs* v))\n(defn g [v] (swap! *sigs* assoc v 1) (q-sig v))\n' > "$t/good.lg"
lint "$t/bad.lg" > "$t/bad.out"
if ! grep -q 'funnel: .*bad.lg f reads \*sigs\*' "$t/bad.out"; then echo "llvm-funnel: self-test failed (a planted read was not reported)"; exit 1; fi
if ! lint "$t/good.lg" > "$t/good.out"; then echo "llvm-funnel: self-test failed (a question or a write was reported)"; cat "$t/good.out"; exit 1; fi
# lw_rt.lg and lw_ext.lg are the data layer behind lw-rt's questions; the
# lowering files may reach their tables only through those questions
lint src/lower_wasm.lg src/lower_llvm.lg src/lower_llvm_rt.lg src/lower_llvm_poly.lg
