#!/usr/bin/env bash
# checks/lane5.sh — P4.2: the emitted lane (lane 5) renders the same screen as
# the stock-Go lane after the same scripted play, at seed 424242.
#
# Lanes:
#   stock  xsofy main.lg bundled by `lg -w -w-shell none` at let-go 4e769212
#          (the backend's ground truth, LETGO_SRC = a `git archive` export of
#          that commit, so the canonical let-go checkout is not touched), then
#          xsofy-shell.html injected by local-scripts/inject-shell.sh: exactly
#          local-scripts/build-bundle.sh's client-shell path. Cached under
#          $LW_LANE5_CACHE keyed by the commit, xsofy's sources and the shell.
#   lw     host/build-xsofy-module.sh's module.wasm in host/build-xsofy-serve.sh's
#          page (the same shell, injected the same way, on the adapter).
# Both are served with COOP/COEP (local-scripts/coi-serve.py): the stock lane's
# key ring needs SharedArrayBuffer; the lw lane does not care (D91).
#
# Walks, each run on both lanes and compared with cmp (document.body.innerText):
#   probe  local-scripts/browser-smoke-playwright/zz-determinism-probe.mjs as
#          is: ?seed=, title, Space, map, 3 s, then l l j j h k l j one key
#          per 400 ms, 2 s, dump.
#   held   checks/browser-boot.mjs --walk: the same boot, then auto-repeat
#          bursts (n keydowns in one task) that let-go's ring coalesces into
#          one read (D98).
# No masking: neither lane has build-info.json, so the shell prints the same
# chrome; the title bar and quest come from xsofy/startup on both.
# Exit 0 iff both walks are byte-identical across the lanes.
# Env: LG, XSOFY, SEED (424242), KEEP=1, LW_LANE5_CACHE.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
ws=$(cd "$here/../.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
XSOFY=${XSOFY:-$HOME/projects-new/3p/xsofy}
LETGO=${LETGO:-$HOME/projects-new/3p/let-go}
COMMIT=4e769212
SEED=${SEED:-424242}
pw=$ws/local-scripts/browser-smoke-playwright
t=$(mktemp -d); pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; [ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"; }
trap cleanup EXIT

# ---- stock lane ------------------------------------------------------------------
cache=${LW_LANE5_CACHE:-${TMPDIR:-/tmp}/lw-lane5-stock}; mkdir -p "$cache"
key=$( { echo "$COMMIT"; shasum "$LG"; cat "$XSOFY/main.lg" "$XSOFY/tools/xsofy-shell.html";
         find "$XSOFY/xsofy" -name '*.lg' -print0 | sort -z | xargs -0 cat; } | md5 -q)
stock=$cache/$key
if [ ! -f "$stock/index.html" ]; then
  echo "building the stock lane (lg -w at $COMMIT)..." >&2
  src=$t/letgo-src; mkdir -p "$src"
  git -C "$LETGO" archive "$COMMIT" | tar -x -C "$src" || { echo "FAIL: git archive $COMMIT"; exit 1; }
  rm -rf "$stock.tmp"; mkdir -p "$stock.tmp"
  if ! (cd "$XSOFY" && LETGO_SRC="$src" "$LG" -w "$stock.tmp" -w-shell none main.lg) >"$t/stock-build.log" 2>&1; then
    echo "FAIL: stock lane build"; tail -20 "$t/stock-build.log"; exit 1
  fi
  "$ws/local-scripts/inject-shell.sh" "$stock.tmp/index.html" "$XSOFY/tools/xsofy-shell.html" >/dev/null || exit 1
  rm -rf "$stock"; command mv "$stock.tmp" "$stock"
fi

# ---- lw lane -------------------------------------------------------------------
"$here/host/build-xsofy-module.sh" "$t/module.wasm" || { echo "FAIL: xsofy main.lg did not compile"; exit 1; }
"$here/host/build-xsofy-serve.sh" "$t/lw" "$t/module.wasm" || { echo "FAIL: build-xsofy-serve.sh"; exit 1; }

# ---- walks ----------------------------------------------------------------------
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
ps=$(free_port); python3 "$ws/local-scripts/coi-serve.py" "$ps" "$stock" >"$t/s.log" 2>&1 & pids+=($!)
pl=$(free_port); python3 "$ws/local-scripts/coi-serve.py" "$pl" "$t/lw" >"$t/l.log" 2>&1 & pids+=($!)
for p in "$ps" "$pl"; do for _ in $(seq 100); do curl -sf -o /dev/null "http://127.0.0.1:$p/index.html" && break; sleep 0.1; done; done

ok=0
for lane in stock lw; do
  dir=$stock; [ "$lane" = lw ] && dir=$t/lw
  port=$(free_port)
  # the probe resolves playwright from its own directory
  (cd "$pw" && node zz-determinism-probe.mjs "$dir" "$port" "$lane" "$SEED" "$t/probe-$lane.txt") >"$t/probe-$lane.json" 2>&1 \
    || { echo "FAIL: probe on $lane"; cat "$t/probe-$lane.json"; }
  url=http://127.0.0.1:$ps; [ "$lane" = lw ] && url=http://127.0.0.1:$pl
  node "$here/checks/browser-boot.mjs" --walk "$url" "$SEED" "$t/held-$lane.txt" >"$t/held-$lane.json" 2>&1 \
    || { echo "FAIL: held walk on $lane"; cat "$t/held-$lane.json"; }
done
for w in probe held; do
  if [ -s "$t/$w-stock.txt" ] && cmp -s "$t/$w-stock.txt" "$t/$w-lw.txt"; then
    echo "$w  IDENTICAL  $(wc -c <"$t/$w-lw.txt" | tr -d ' ') bytes, md5 $(md5 -q "$t/$w-lw.txt")"
    ok=$((ok + 1))
  else
    echo "$w  DIFFER"; diff "$t/$w-stock.txt" "$t/$w-lw.txt" | head -12
    grep -h failure "$t/$w-stock.json" "$t/$w-lw.json" 2>/dev/null
  fi
done
echo "walks: probe = l l j j h k l j (400 ms apart); held = $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("bursts","?"))' "$t/held-lw.json" 2>/dev/null) (one task per burst)"
if [ "$ok" = 2 ]; then echo "PASS (lane 5 byte-identical to the stock-Go lane at seed $SEED, both walks)"; exit 0; fi
echo "FAIL (lane 5)"; exit 1
