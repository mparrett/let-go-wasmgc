#!/usr/bin/env bash
# checks/eval-hosts.sh — P7.5: the in-module evaluator is reachable the same
# way from every host.
#   1. corpus/host/eval-hello.lg (eval of read code, a defn made by eval,
#      a closure, an eval error's message) through the backend: its stdout
#      under host/node-host.mjs AND in host/index.html (headless Chromium,
#      checks/browser-boot.mjs --run, served with COI by
#      local-scripts/coi-serve.py) must equal native lg's, byte for byte.
#   2. legmacs' real module (host/build-legmacs-module.sh, cached) under
#      node-host with the keys a manual test-drive uses: type
#      (defn f [x] (* x 2)) C-x C-e, (f 21) C-x C-e, then C-x C-c. The echo
#      area must show "=> 42" (and "=> #'legmacs.main/f"), as native legmacs
#      does on a 100x30 pty with the same keys (host/pty-run.py; native is
#      killed after the quit prompt, exit 124 is fine). Presence, not a
#      byte-identical dump: P7.2's parity script 6 is the byte-identical one.
# Exit 0 iff all three hold. Env: LG, LEGMACS, KEEP=1; harness self-test:
# LW_EVAL_PROG=<other program> and LW_EVAL_SKIP_LEGMACS=1.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
ws=$(cd "$here/../.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
LEGMACS=${LEGMACS:-$HOME/projects-new/3p/legmacs}
t=$(mktemp -d); pids=()
cleanup() { for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; [ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"; }
trap cleanup EXIT
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
ok=1

# ---- 1. eval-hello under node-host and the browser ------------------------
prog=${LW_EVAL_PROG:-$here/corpus/host/eval-hello.lg}
"$LG" "$prog" >"$t/expected" 2>&1 || { echo "FAIL: eval-hello.lg fails natively"; cat "$t/expected"; exit 1; }
if ! "$here/checks/sem.sh" "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$prog" "$t/eval.wat" >"$t/compile.log" 2>&1; then
  echo "FAIL: eval-hello.lg did not compile (backend)"; grep -v catalog "$t/compile.log" | head -20; exit 1
fi
wasm-tools parse "$t/eval.wat" -o "$t/eval.wasm" || exit 1
node "$here/host/node-host.mjs" "$t/eval.wasm" >"$t/node.out" 2>&1; rc=$?
if [ "$rc" = 0 ] && cmp -s "$t/node.out" "$t/expected"; then
  echo "node-host  PASS  eval-hello == native ($(wc -l <"$t/expected" | tr -d ' ') lines)"
else
  ok=0; echo "node-host  FAIL  exit $rc"; diff "$t/expected" "$t/node.out" | head -12
fi
mkdir -p "$t/www"; command cp "$here"/host/index.html "$here"/host/lg-wasm-host.js "$t/www/"; command cp "$t/eval.wasm" "$t/www/eval.wasm"
px=$(free_port); python3 "$ws/local-scripts/coi-serve.py" "$px" "$t/www" >"$t/server.log" 2>&1 & pids+=($!)
for _ in $(seq 100); do curl -sf -o /dev/null "http://127.0.0.1:$px/index.html" && break; sleep 0.1; done
if node "$here/checks/browser-boot.mjs" --run "http://127.0.0.1:$px" eval.wasm "$t/expected" >"$t/browser.json" 2>"$t/browser.err"; then
  echo "browser    PASS  eval-hello == native in Chromium ($(python3 -c 'import json,sys; print(round(json.load(open(sys.argv[1]))["totalMs"]))' "$t/browser.json") ms)"
else
  ok=0; echo "browser    FAIL"; head -c 900 "$t/browser.json"; echo; head -5 "$t/browser.err"
fi

# ---- 2. legmacs C-x C-e under node-host -----------------------------------
keys=$'(defn f [x] (* x 2))\x18\x05(f 21)\x18\x05\x18\x03'
if [ -n "${LW_EVAL_SKIP_LEGMACS:-}" ]; then echo "legmacs    SKIPPED (LW_EVAL_SKIP_LEGMACS)"; [ "$ok" = 1 ] && exit 0 || exit 1; fi
if ! "$here/host/build-legmacs-module.sh" "$t/legmacs.wasm" 2>"$t/lm.log"; then
  echo "legmacs    FAIL  main.lg did not compile (backend)"; tail -5 "$t/lm.log"; exit 1
fi
timeout 120 node "$here/host/node-host.mjs" "$t/legmacs.wasm" --keys "$keys" --size 100x30 >"$t/lm.node" 2>&1; rn=$?
timeout 180 python3 "$here/host/pty-run.py" 100 30 "$keys" "$LG" -source-paths "$LEGMACS" "$LEGMACS/main.lg" >"$t/lm.native" 2>&1; rv=$?
has() { tr -d '\033' <"$1" | grep -a -q -- "$2"; }
if has "$t/lm.native" "=> 42"; then :; else echo "legmacs    FAIL  native legmacs did not echo => 42 (exit $rv); the harness is wrong, not the module"; ok=0; fi
if has "$t/lm.node" "=> 42" && has "$t/lm.node" "=> #'legmacs.main/f"; then
  echo "legmacs    PASS  C-x C-e under node-host echoes => #'legmacs.main/f and => 42 (node exit $rn, native exit $rv)"
else
  ok=0; echo "legmacs    FAIL  node-host exit $rn; echo lines seen:"; tr -d '\033' <"$t/lm.node" | grep -a -o "=> [^|]\{0,60\}\|Eval error[^|]\{0,80\}" | head -5
fi
[ "$ok" = 1 ] && { echo "PASS (eval reachable from node-host, the browser and legmacs C-x C-e)"; exit 0; }
echo "FAIL (eval-hosts)"; exit 1
