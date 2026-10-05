#!/usr/bin/env bash
# checks/browser-boot.sh — P4.0: the browser host boots an emitted module.
#
# Builds corpus/host/hello.lg through the backend and host/keys-probe.wat,
# serves host/ + both modules twice (local-scripts/coi-serve.py with COOP/COEP,
# and plain `python3 -m http.server` without), and drives host/index.html in
# headless Chromium (checks/browser-boot.mjs):
#   hello: stdout must equal native lg's for the same program, byte for byte;
#   keys:  a, b, q pressed must be echoed by term.read_key.
# Then runs both modules under host/node-host.mjs and under wasmtime (the
# module merged with host/wasmtime-adapter.wat), and prints one table.
#
# Exit 0 iff hello and keys pass in the browser UNDER COI. The no-COI row is
# reported either way (JSPI needs no SharedArrayBuffer, so it is expected to
# pass too; that is the COI finding in host/ABI.md). node and wasmtime rows
# are informational. Env: LG, KEEP=1.
#
# checks/browser-boot.sh --xsofy-shell — P4.1 host half: the same two modules
# in the REAL xsofy/tools/xsofy-shell.html (host/build-xsofy-serve.sh injects
# it unchanged with local-scripts/inject-shell.sh, on host/xsofy-shell-adapter.js),
# served without COI (D91). Asserts: the shell boots (ready mode 'worker',
# Fairfax HD loaded, xterm attached, #status hidden); hello's stdout and the
# xterm buffer both equal native lg's output; keys-probe prints the size the
# shell passed to setSize; five 'j' keydowns in one task reach the host and
# read back as ONE key (D98); 'q' ends the program. Plus node-host: the same
# burst is one read with --coalesce and five without (node-host's default is
# unchanged). Exit 0 iff all hold. Needs network: the shell loads xterm from
# cdn.jsdelivr.net. Env as above, plus XSOFY (the checkout whose shell is used).
#
# checks/browser-boot.sh --xsofy — P4.1 backend half. (1) corpus/host/
# term-demo.lg through the backend under host/node-host.mjs (100x30, keys
# a b j j q) must print the same bytes as native lg on a 100x30
# pseudo-terminal (host/pty-run.py): the D97 term intrinsics. (2) xsofy's
# real main.lg compiled by the backend (host/build-xsofy-module.sh, cached)
# served as module.wasm in the real shell (host/build-xsofy-serve.sh, plain
# http.server, no COI: D91) must reach the title card and, after Space, the
# map screen in headless Chromium (checks/browser-boot.mjs --xsofy, the
# detection of zz-boot-time-probe.mjs), with ?seed= honoured and the shell's
# xsofy/startup + xsofy/stats events received. Prints time-to-title and
# time-to-map. Exit 0 iff (1) and (2) hold. Env: LG, XSOFY, SEED (424242).
#
# checks/browser-boot.sh --legmacs — P6.4. legmacs' real main.lg compiled by
# the backend (host/build-legmacs-module.sh, cached) served as module.wasm in
# let-go's stock xterm shell on the lower-wasm host (host/build-legmacs-serve.sh,
# plain http.server, no COI: D91), driven by checks/browser-boot.mjs --legmacs:
# boots to the *scratch* mode line, echoes typed keys on buffer line 5, and
# redraws the frame for a smaller viewport with no key pressed (the host's
# wake on resize). Prints bootMs / firstFrameMs / echoMs / resizeMs. Exit 0
# iff all hold; a module that does not compile is exit 1 with the driver's
# first error. Env: LG, LEGMACS, LETGO, LW_LEGMACS_MAIN (build-legmacs-module.sh:
# a diagnostic stand-in entry; the row never sets it).
set -uo pipefail
mode=default
case "${1:-}" in --xsofy-shell) mode=xsofy-shell ;; --xsofy) mode=xsofy ;; --legmacs) mode=legmacs ;; "") ;; *) echo "usage: browser-boot.sh [--xsofy-shell|--xsofy|--legmacs]"; exit 2 ;; esac
here=$(cd "$(dirname "$0")/.." && pwd)
ws=$(cd "$here/../.." && pwd)
. "$(dirname "$0")/env.sh"
MERGE=$WASM_MERGE
t=$(mktemp -d); pids=()
cleanup() { for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; [ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"; }
trap cleanup EXIT

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

# ---- --xsofy -------------------------------------------------------------------
if [ "$mode" = xsofy ]; then
  ok=1
  if ! "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$here/corpus/host/term-demo.lg" "$t/td.wat" >"$t/td.log" 2>&1; then
    echo "FAIL: term-demo.lg did not compile"; grep -v catalog "$t/td.log"; exit 1
  fi
  wasm-tools parse "$t/td.wat" -o "$t/td.wasm" || exit 1
  node "$here/host/node-host.mjs" "$t/td.wasm" --keys abjjq --size 100x30 >"$t/td.node" 2>&1; tn=$?
  python3 "$here/host/pty-run.py" 100 30 abjjq "$LG" "$here/corpus/host/term-demo.lg" >"$t/td.native"; tv=$?
  if [ "$tn" = 0 ] && [ "$tv" = 0 ] && cmp -s "$t/td.node" "$t/td.native"; then
    echo "term-demo PASS  node-host == native lg on a 100x30 pty ($(wc -c <"$t/td.native" | tr -d ' ') bytes, keys abjjq)"
  else
    ok=0; echo "term-demo FAIL  node-host exit $tn, native exit $tv"; cmp "$t/td.node" "$t/td.native" | head -2
  fi
  "$here/host/build-xsofy-module.sh" "$t/module.wasm" || { echo "FAIL: xsofy main.lg did not compile"; exit 1; }
  "$here/host/build-xsofy-serve.sh" "$t/xs" "$t/module.wasm" || { echo "FAIL: build-xsofy-serve.sh"; exit 1; }
  px=$(free_port); python3 -m http.server --bind 127.0.0.1 --directory "$t/xs" "$px" >"$t/xs.server.log" 2>&1 & pids+=($!)
  for _ in $(seq 100); do curl -sf -o /dev/null "http://127.0.0.1:$px/index.html" && break; sleep 0.1; done
  node "$here/checks/browser-boot.mjs" --xsofy "http://127.0.0.1:$px" "${SEED:-424242}" >"$t/game.json"
  python3 - "$t/game.json" <<'EOF2'
import json, sys
try: r = json.load(open(sys.argv[1]))
except Exception as e: r = {'pass': False, 'failure': f'no result from browser-boot.mjs ({e})'}
keep = ('titleMs', 'mapMs', 'titleSeed', 'startup', 'stats', 'readyMode', 'coi', 'jspi', 'running', 'error', 'errors', 'bad', 'failure', 'text')
print(f"xsofy     {'PASS' if r.get('pass') else 'FAIL'}  " + json.dumps({k: r[k] for k in keep if k in r})[:900])
if r.get('titleMs') is not None:
    print(f"timing: time-to-title {r['titleMs']} ms, time-to-map {r.get('mapMs', '-')} ms (seed {r['seed']}, from navigation)")
sys.exit(0 if r.get('pass') else 1)
EOF2
  [ $? = 0 ] || ok=0
  if [ "$ok" = 1 ]; then echo "PASS (xsofy: term-demo matches native; the emitted xsofy reaches the title and the map in the real shell)"; exit 0; fi
  echo "FAIL (xsofy)"; exit 1
fi

# ---- --legmacs -----------------------------------------------------------------
if [ "$mode" = legmacs ]; then
  [ -n "${LW_LEGMACS_MAIN:-}" ] && echo "NOTE: entry overridden by LW_LEGMACS_MAIN=$LW_LEGMACS_MAIN (diagnostic, not P6.4)"
  if ! "$here/host/build-legmacs-module.sh" "$t/module.wasm" 2>"$t/mod.log"; then
    echo "FAIL: legmacs main.lg did not compile (backend)"
    sed -E 's/\x1b\[[0-9;]*m//g' "$t/mod.log" | grep -m1 -iE 'error|unsupported' | cut -c1-500 | sed 's/^/  /'
    exit 1
  fi
  sed -n 's/^module: /module: /p' "$t/mod.log"
  "$here/host/build-legmacs-serve.sh" "$t/lm" "$t/module.wasm" || { echo "FAIL: build-legmacs-serve.sh"; exit 1; }
  px=$(free_port); python3 -m http.server --bind 127.0.0.1 --directory "$t/lm" "$px" >"$t/lm.server.log" 2>&1 & pids+=($!)
  for _ in $(seq 100); do curl -sf -o /dev/null "http://127.0.0.1:$px/index.html" && break; sleep 0.1; done
  node "$here/checks/browser-boot.mjs" --legmacs "http://127.0.0.1:$px" >"$t/lm.json"
  python3 - "$t/lm.json" <<'EOF3'
import json, sys
try: r = json.load(open(sys.argv[1]))
except Exception as e: r = {'pass': False, 'failure': f'no result from browser-boot.mjs ({e})'}
for k in ('boot', 'echo', 'resize'):
    part = r.get(k) or {'pass': False, 'missing': True}
    print(f"{k:<7}{'PASS' if part.get('pass') else 'FAIL'}  " + json.dumps({x: y for x, y in part.items() if x != 'pass'})[:400])
for k in ('failure', 'screen', 'lgw', 'errors', 'bad'):
    if r.get(k): print('   ', k, json.dumps(r[k])[:600])
ms = lambda k: '-' if r.get(k) is None else f"{r[k]}"
print(f"timing (ms from navigation): bootMs {ms('bootMs')}, firstFrameMs {ms('firstFrameMs')}; "
      f"echoMs {ms('echoMs')} (median of {r.get('echoAllMs')}), resizeMs {ms('resizeMs')}; "
      f"readyMode {r.get('readyMode')}, jspi {r.get('jspi')}, coi {r.get('coi')}, host size {r.get('hostSize')}")
sys.exit(0 if r.get('pass') else 1)
EOF3
  if [ $? = 0 ]; then echo "PASS (legmacs: boots to the mode line, echoes keys, redraws on resize)"; exit 0; fi
  echo "FAIL (legmacs)"; exit 1
fi

# ---- build -------------------------------------------------------------------
www=$t/www; mkdir -p "$www"
cp "$here/host/index.html" "$here/host/lg-wasm-host.js" "$www/"
if ! "$LG" -source-paths "$here/src" "$here/src/driver.lg" "$here/corpus/host/hello.lg" "$t/hello.wat" >"$t/drv.log" 2>&1; then
  echo "FAIL: hello.lg did not compile"; cat "$t/drv.log"; exit 1
fi
wasm-tools parse "$t/hello.wat" -o "$www/hello.wasm" || exit 1
wasm-tools parse "$here/host/keys-probe.wat" -o "$www/keys.wasm" || exit 1
"$LG" "$here/corpus/host/hello.lg" >"$t/native.out" 2>"$t/native.err" || { echo "FAIL: native lg exited non-zero"; cat "$t/native.err"; exit 1; }
keys_expected=$'size 80 24\nready\nkey 97\nkey 98\nkey 113\npending 0\nbye'

# ---- --xsofy-shell -------------------------------------------------------------
if [ "$mode" = xsofy-shell ]; then
  xs=$t/xs
  "$here/host/build-xsofy-serve.sh" "$xs" "$www/hello.wasm" "$www/keys.wasm" || { echo "FAIL: build-xsofy-serve.sh"; exit 1; }
  px=$(free_port); python3 -m http.server --bind 127.0.0.1 --directory "$xs" "$px" >"$t/xs.server.log" 2>&1 & pids+=($!)
  for _ in $(seq 100); do curl -sf -o /dev/null "http://127.0.0.1:$px/index.html" && break; sleep 0.1; done
  node "$here/checks/browser-boot.mjs" --xsofy-shell "http://127.0.0.1:$px" "$t/native.out" >"$t/xs.json"
  # the same burst under node-host: one j read with --coalesce, five without
  node "$here/host/node-host.mjs" "$www/keys.wasm" --keys ajjjjjbq --coalesce >"$t/node-co.out" 2>&1
  node "$here/host/node-host.mjs" "$www/keys.wasm" --keys ajjjjjbq >"$t/node-raw.out" 2>&1
  python3 - "$t" <<'EOF'
import json, sys
t = sys.argv[1]
try: r = json.load(open(f'{t}/xs.json'))
except Exception as e: r = {'failure': f'no result from browser-boot.mjs ({e})'}
def n106(f): return open(f'{t}/{f}').read().split('\n').count('key 106')
co, raw = n106('node-co.out'), n106('node-raw.out')
ok = True
for k in ('boot', 'hello', 'size', 'held', 'quit'):
    part = r.get(k) or {'pass': False, 'missing': True}
    ok &= bool(part.get('pass'))
    print(f"{k:<6}{'PASS' if part.get('pass') else 'FAIL'}  " + json.dumps({x: y for x, y in part.items() if x != 'pass'})[:300])
node_ok = co == 1 and raw == 5
ok &= node_ok
print(f"{'node':<6}{'PASS' if node_ok else 'FAIL'}  burst ajjjjjbq: {co} j read with --coalesce, {raw} without")
h = r.get('hello', {})
def ms(x): return '-' if x is None else f'{x:.0f}'
print(f"timing (page ms): main start {ms(h.get('mainStartMs'))}, first output to shell {ms(h.get('shellFirstOutputMs'))}, "
      f"first paint in xterm {ms(h.get('visibleMs'))}, host run total {ms(h.get('totalMs'))}")
for x in ('failure', 'keysStdout'):
    if r.get(x): print('   ', x, json.dumps(r[x]))
open(f'{t}/xs.ok', 'w').write('1' if ok and not r.get('failure') else '0')
EOF
  if [ "$(cat "$t/xs.ok")" = 1 ]; then echo "PASS (xsofy-shell: boots, hello MATCHes native in xterm, held key = one read, q quits)"; exit 0; fi
  echo "FAIL (xsofy-shell)"; exit 1
fi

# ---- browser, with and without COI -----------------------------------------
# servers start in this shell (not in a $(...) subshell) so cleanup can kill them
pc=$(free_port); python3 "${LW_BROWSER_TOOLS:-$ws/local-scripts}/coi-serve.py" "$pc" "$www" >"$t/coi.server.log" 2>&1 & pids+=($!)
pp=$(free_port); python3 -m http.server --bind 127.0.0.1 --directory "$www" "$pp" >"$t/plain.server.log" 2>&1 & pids+=($!)
wait_up() {
  for _ in $(seq 100); do curl -sf -o /dev/null "http://127.0.0.1:$1/index.html" && return 0; sleep 0.1; done
  echo "FAIL: server on $1 did not start"; cat "$t"/*.server.log; exit 1
}
wait_up "$pc"; wait_up "$pp"
node "$here/checks/browser-boot.mjs" "http://127.0.0.1:$pc" coi "$t/native.out" >"$t/coi.json"
node "$here/checks/browser-boot.mjs" "http://127.0.0.1:$pp" no-coi "$t/native.out" >"$t/plain.json"

# ---- node and wasmtime ---------------------------------------------------------
host_row() {  # host_row <name> <hello-out> <hello-exit> <keys-out>
  local h=FAIL k=FAIL
  [ "$3" = 0 ] && cmp -s "$2" "$t/native.out" && h=PASS
  [ "$(cat "$4")" = "$keys_expected" ] && k=PASS
  printf '%s\t%s\t%s\n' "$1" "$h" "$k"
}
LG_HOST_TIMING=1 node "$here/host/node-host.mjs" "$www/hello.wasm" </dev/null >"$t/node-hello.out" 2>"$t/node-hello.err"; nx=$?
node "$here/host/node-host.mjs" "$www/keys.wasm" --keys abq >"$t/node-keys.out" 2>&1
host_row node "$t/node-hello.out" "$nx" "$t/node-keys.out" >"$t/rows.tsv"

feat=(--enable-gc --enable-reference-types --enable-exception-handling --enable-tail-call --enable-multivalue
      --enable-bulk-memory --enable-nontrapping-float-to-int --enable-sign-ext --enable-mutable-globals --disable-compact-imports)
wasm-tools parse "$here/host/wasmtime-adapter.wat" -o "$t/adapter.wasm"
grep -v '(export "memory"' "$here/host/wasmtime-adapter.wat" | wasm-tools parse -o "$t/adapter-term.wasm" -
wt_run() {  # wt_run <module> <out>; keys a b q on stdin
  "$MERGE" "${feat[@]}" --rename-export-conflicts "$1" main "$t/adapter.wasm" env "$t/adapter-term.wasm" term -o "$1.wt" 2>/dev/null || return 1
  printf 'abq' | wasmtime run -W gc=y,exceptions=y,function-references=y,tail-call=y,max-wasm-stack=268435456 \
    --invoke 'lw main' "$1.wt" 2>"$2.err" | grep -v '^<null anyref>$' >"$2"
  return "${PIPESTATUS[1]}"
}
wt_run "$www/hello.wasm" "$t/wt-hello.out"; wx=$?
wt_run "$www/keys.wasm" "$t/wt-keys.out"
host_row wasmtime "$t/wt-hello.out" "$wx" "$t/wt-keys.out" >>"$t/rows.tsv"

# ---- report --------------------------------------------------------------------
python3 - "$t" <<'EOF'
import json, sys
t = sys.argv[1]
def ms(x): return '-' if x is None else f'{x:.1f}'
print(f"{'host':<16}{'COI':<6}{'SAB':<6}{'JSPI':<6}{'hello':<7}{'keys':<6}{'first-out ms':>13}{'total ms':>10}{'page-done ms':>14}")
def load(f):
    try: return json.load(open(f'{t}/{f}.json'))
    except Exception as e: return {'label': f, 'failure': f'no result from browser-boot.mjs ({e})'}
for f in ('coi', 'plain'):
    r = load(f)
    h, k = r.get('hello', {}), r.get('keys', {})
    print(f"{'chromium/'+r['label']:<16}{str(r.get('coi','?')):<6}{str(r.get('sab','?')):<6}{str(r.get('jspi','?')):<6}"
          f"{('PASS' if h.get('pass') else 'FAIL'):<7}{('PASS' if k.get('pass') else 'FAIL'):<6}"
          f"{ms(h.get('firstOutputMs')):>13}{ms(h.get('totalMs')):>10}{ms(h.get('pageDoneMs')):>14}")
    for x in ('failure',):
        if r.get(x): print('   ', x, r[x])
    for part in (h, k):
        if part and not part.get('pass'): print('   ', json.dumps(part)[:400])
timing = open(f'{t}/node-hello.err').read().strip()
for line in open(f'{t}/rows.tsv'):
    name, h, k = line.rstrip('\n').split('\t')
    extra = timing.replace('timing ', '') if name == 'node' else 'no JSPI: sleep/read_key block the thread'
    print(f"{name:<16}{'-':<6}{'-':<6}{('yes' if name=='node' else 'no'):<6}{h:<7}{k:<6}  {extra}")
EOF
coi_ok=$(python3 -c '
import json, sys
try: r = json.load(open(sys.argv[1]))
except Exception: r = {}
print(int(bool(r.get("hello", {}).get("pass")) and bool(r.get("keys", {}).get("pass")) and r.get("coi") is True))' "$t/coi.json")
if [ "$coi_ok" = 1 ]; then echo "PASS (browser under COI: hello MATCHes native lg, keys echoed)"; exit 0; fi
echo "FAIL (browser under COI)"; exit 1
