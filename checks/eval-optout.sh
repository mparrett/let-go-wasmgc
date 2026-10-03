#!/usr/bin/env bash
# checks/eval-optout.sh — P7.6: LW_NO_EVAL=1 builds a module without the
# in-module evaluator (rt/wasm/eval.lg) and without the program table, even
# when the program calls eval; without the flag nothing changes.
#   1. corpus/host/eval-hello.lg: unflagged it MATCHes native lg
#      (checks/oracle.sh); flagged it exits non-zero at its first eval with
#      the pre-Phase-7 named error (D139) and prints nothing before it.
#   2. corpus/host/hello.lg (no eval): the wasm-opt -O3 modules built with
#      and without the flag are byte-identical.
#   3. legmacs main.lg both ways (host/build-legmacs-module.sh, which keys
#      its cache on the flag): a raw / wasm-opt / brotli table; the flagged
#      module boots under host/node-host.mjs (the *scratch* mode line shows),
#      and C-x C-e of a form echoes an "Eval error" instead of trapping.
# Exit 0 iff all hold. Env: LG, LEGMACS, KEEP=1.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/env.sh"
LEGMACS=${LEGMACS:-$LW_ROOT/legmacs}
OPT=/opt/homebrew/opt/binaryen/bin/wasm-opt
optflags=(-O3 --enable-gc --enable-reference-types --enable-exception-handling --enable-bulk-memory
          --enable-tail-call --enable-multivalue)
named="lower-wasm: core/eval has no twin"
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT
ok=1
cd "$here"

# ---- 1. eval-hello both ways ----------------------------------------------
prog=corpus/host/eval-hello.lg
r=$(WASM_RUN=checks/wasm-run.sh checks/oracle.sh "$prog" 2>&1 | head -3)
if [ "$(echo "$r" | head -1)" = MATCH ]; then echo "eval-hello  unflagged  PASS  MATCH native"
else ok=0; echo "eval-hello  unflagged  FAIL  $r"; fi
LW_NO_EVAL=1 checks/wasm-run.sh "$prog" >"$t/ne.out" 2>"$t/ne.err"; rc=$?
if [ "$rc" != 0 ] && grep -qF "$named" "$t/ne.out" "$t/ne.err" && ! grep -qv "$named" "$t/ne.out"; then
  echo "eval-hello  LW_NO_EVAL PASS  exit $rc at the first eval: $named"
else
  ok=0; echo "eval-hello  LW_NO_EVAL FAIL  exit $rc"; head -3 "$t/ne.out" "$t/ne.err"
fi

# ---- 2. an eval-free program is byte-identical ----------------------------
build() { # build <out-prefix> <prog> [env...]: compile, parse, wasm-opt
  local out=$1 p=$2; shift 2
  env "$@" checks/sem.sh "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$p" "$out.wat" >"$out.log" 2>&1 &&
    wasm-tools parse "$out.wat" -o "$out.raw.wasm" && "$OPT" "${optflags[@]}" "$out.raw.wasm" -o "$out.wasm"
}
if build "$t/h0" corpus/host/hello.lg LW_NO_EVAL= && build "$t/h1" corpus/host/hello.lg LW_NO_EVAL=1; then
  if cmp -s "$t/h0.wasm" "$t/h1.wasm"; then echo "hello       PASS  wasm-opt modules byte-identical ($(wc -c <"$t/h0.wasm" | tr -d ' ') B, md5 $(md5 -q "$t/h0.wasm"))"
  else ok=0; echo "hello       FAIL  modules differ: $(md5 -q "$t/h0.wasm") vs $(md5 -q "$t/h1.wasm")"; fi
else ok=0; echo "hello       FAIL  did not build"; tail -5 "$t"/h*.log; fi

# ---- 3. legmacs both ways -------------------------------------------------
for v in on off; do
  flag=""; [ "$v" = off ] && flag=1
  if ! LW_NO_EVAL=$flag LW_LEGMACS_RAW="$t/lm-$v.raw.wasm" host/build-legmacs-module.sh "$t/lm-$v.wasm" 2>"$t/lm-$v.log"; then
    ok=0; echo "legmacs     FAIL  eval-$v build failed"; tail -5 "$t/lm-$v.log"
  fi
done
if [ -f "$t/lm-on.wasm" ] && [ -f "$t/lm-off.wasm" ]; then
  printf '\n| legmacs main.lg | raw | wasm-opt -O3 | brotli |\n|---|---|---|---|\n'
  for v in on off; do
    label=$([ "$v" = on ] && echo "evaluator (default)" || echo "LW_NO_EVAL=1")
    printf '| %s | %s | %s | %s |\n' "$label" "$(wc -c <"$t/lm-$v.raw.wasm" | tr -d ' ')" \
      "$(wc -c <"$t/lm-$v.wasm" | tr -d ' ')" "$(brotli -c "$t/lm-$v.wasm" | wc -c | tr -d ' ')"
  done
  echo
  keys=$'(+ 1 2)\x18\x05\x18\x03'
  timeout 120 node host/node-host.mjs "$t/lm-off.wasm" --keys "$keys" --size 100x30 >"$t/lm.node" 2>&1; rn=$?
  has() { tr -d '\033' <"$t/lm.node" | grep -a -q -- "$1"; }
  if has "*scratch*" && has "Eval error" && ! has "RuntimeError" && ! has "unreachable"; then
    echo "legmacs     PASS  LW_NO_EVAL module boots under node-host; C-x C-e echoes an Eval error (node exit $rn)"
  else
    ok=0; echo "legmacs     FAIL  node exit $rn; seen:"
    tr -d '\033' <"$t/lm.node" | grep -a -o "Eval error[^|]\{0,80\}\|RuntimeError[^|]\{0,80\}\|=> [^|]\{0,40\}" | head -5
  fi
fi
[ "$ok" = 1 ] && { echo "PASS (LW_NO_EVAL opts the evaluator out; eval-free modules unchanged)"; exit 0; }
echo "FAIL (eval-optout)"; exit 1
