#!/usr/bin/env bash
# Target selection and cache isolation (2026-10-03). No oracle claims here.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
driver=("$LG" -source-paths "$PWD/src" "$PWD/src/driver.lg" --no-rt)
prog=checks/fixtures/linear-target.lg
env -u LW_TARGET "${driver[@]}" "$prog" "$t/default.wat"
LW_TARGET=linear "${driver[@]}" --target gc "$prog" "$t/flag.wat"
LW_TARGET=gc "${driver[@]}" "$prog" "$t/env.wat"
cmp "$t/default.wat" "$t/flag.wat"
cmp "$t/default.wat" "$t/env.wat"
LW_TARGET=linear "${driver[@]}" "$prog" "$t/linear-env.wat"
LW_TARGET=gc "${driver[@]}" --target linear "$prog" "$t/linear-flag.wat"
cmp "$t/linear-env.wat" "$t/linear-flag.wat"
wasm-tools parse "$t/linear-env.wat" -o "$t/linear.wasm"
wasm-tools validate --features=-gc "$t/linear.wasm"
fixture=corpus/refused/linear/array-fill.wat
wasm-tools parse "$fixture" -o "$t/gc-fixture.wasm"
wasm-tools validate "$t/gc-fixture.wasm"
if "$LG" -source-paths "$PWD/src" "$PWD/checks/linear-refuse-check.lg" "$fixture" "$t/refused.wat" > "$t/refused.log" 2>&1; then exit 1; fi
grep -q 'lower-wasm: unsupported op array.fill under linear' "$t/refused.log"
fixture=corpus/refused/linear/flat-ref-null.wat
wasm-tools parse "$fixture" -o "$t/flat-gc.wasm"
wasm-tools validate "$t/flat-gc.wasm"
if "$LG" -source-paths "$PWD/src" "$PWD/checks/linear-refuse-check.lg" "$fixture" "$t/flat.wat" > "$t/flat.log" 2>&1; then exit 1; fi
grep -q 'lower-wasm: unsupported op ref.null (flat instruction) under linear' "$t/flat.log"
for bad in '' invalid; do
  if env -u LW_TARGET "${driver[@]}" --target $bad > "$t/log" 2>&1; then exit 1; fi
  grep -Eq 'lower-wasm: (--target needs gc, linear or llvm|unsupported target invalid)' "$t/log"
done
cat > "$t/key.lg" <<'LG'
(require '[lower-wasm :as lw])
(let [gc (binding [lw/*target* :gc] (lw/rtlib-key))
      linear (binding [lw/*target* :linear] (lw/rtlib-key))]
  (when (= gc linear) (throw (ex-info "target cache keys collide" {}))))
LG
"$LG" -source-paths "$PWD/src" "$t/key.lg"
echo 'PASS target precedence, validation, named refusal and runtime cache keys'
