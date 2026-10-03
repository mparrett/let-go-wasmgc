#!/usr/bin/env bash
# Target selection and cache isolation (2026-10-03). No oracle claims here.
set -euo pipefail
cd "$(dirname "$0")/.."
. checks/env.sh
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
driver=("$LG" -source-paths "$PWD/src" "$PWD/src/driver.lg" --no-rt)
prog=corpus/refused/linear/null.lg
env -u LW_TARGET "${driver[@]}" "$prog" "$t/default.wat"
LW_TARGET=linear "${driver[@]}" --target gc "$prog" "$t/flag.wat"
LW_TARGET=gc "${driver[@]}" "$prog" "$t/env.wat"
cmp "$t/default.wat" "$t/flag.wat"
cmp "$t/default.wat" "$t/env.wat"
for mode in env flag; do
  if [ "$mode" = env ]; then
    if LW_TARGET=linear "${driver[@]}" "$prog" "$t/refused.wat" > "$t/log" 2>&1; then exit 1; fi
  else
    if LW_TARGET=gc "${driver[@]}" --target linear "$prog" "$t/refused.wat" > "$t/log" 2>&1; then exit 1; fi
  fi
  grep -q 'lower-wasm: unsupported op ref.null under linear' "$t/log"
done
for bad in '' invalid; do
  if env -u LW_TARGET "${driver[@]}" --target $bad > "$t/log" 2>&1; then exit 1; fi
  grep -Eq 'lower-wasm: (--target needs gc or linear|unsupported target invalid)' "$t/log"
done
cat > "$t/key.lg" <<'LG'
(require '[lower-wasm :as lw])
(let [gc (binding [lw/*target* :gc] (lw/rtlib-key))
      linear (binding [lw/*target* :linear] (lw/rtlib-key))]
  (when (= gc linear) (throw (ex-info "target cache keys collide" {}))))
LG
"$LG" -source-paths "$PWD/src" "$t/key.lg"
echo 'PASS target precedence, validation, named refusal and runtime cache keys'
