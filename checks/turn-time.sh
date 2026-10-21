#!/usr/bin/env bash
# checks/turn-time.sh — P4.4: xsofy's turn latency, the emitted lane against the
# stock-Go lane. The first steady-state compute number beside the size and boot
# tables (corpus/xsofy/size-boot.md measures download + init; the gating walks
# compare screens, not time).
#
# Both lanes are the ones lane5.sh builds (same stock cache, same module), served
# with COI, at SEED (424242). In each, checks/browser-boot.mjs --turn-time boots
# to the map, then sends KEYS keys (default 40: the probe's l l j j h k l j,
# repeated), one once the previous turn settled, and records per key the span
# from the keydown on xterm's textarea to the game's `xsofy/stats` event, both
# timestamped inside the page: the game waking on the key plus the turn's
# compute, before drawing. REPS runs per lane (default 3), alternating lanes so
# load drifts hit both; a run's statistic is its median over the counted turns.
#
# Writes corpus/xsofy/turn-time.md and prints it. Exit 0 iff every run counted
# at least KEYS/2 turns in both lanes; 2 when checks/browser-probe.mjs finds no
# Chromium (after the lanes built) or a run times out; 1 on a build failure.
# Env: LG, XSOFY, LETGO, SEED, KEYS, REPS, KEEP=1, LW_LANE5_CACHE, LW_BROWSER_TOOLS.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
. "$(dirname "$0")/env.sh"
XSOFY=${XSOFY:-$LW_ROOT/xsofy}
LETGO=${LETGO:-$LW_ROOT/let-go}
COMMIT=e9789b7d
SEED=${SEED:-424242}
KEYS=${KEYS:-40}
REPS=${REPS:-3}
t=$(mktemp -d); pids=()
cleanup() { for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; [ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"; }
trap cleanup EXIT

# ---- stock lane (lane5.sh's cache) --------------------------------------------------
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
  "$here/host/inject-shell.sh" "$stock.tmp/index.html" "$XSOFY/tools/xsofy-shell.html" >/dev/null || exit 1
  rm -rf "$stock"; command mv "$stock.tmp" "$stock"
fi

# ---- lw lane -------------------------------------------------------------------
"$here/host/build-xsofy-module.sh" "$t/module.wasm" || { echo "FAIL: xsofy main.lg did not compile"; exit 1; }
"$here/host/build-xsofy-serve.sh" "$t/lw" "$t/module.wasm" || { echo "FAIL: build-xsofy-serve.sh"; exit 1; }

browser_skip=$(node "$here/checks/browser-probe.mjs" 2>&1) || true
[ -n "$browser_skip" ] && { echo "SKIP (turn-time: both lanes built; $browser_skip)"; exit 2; }

# ---- runs ------------------------------------------------------------------------
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
ps=$(free_port); python3 "$here/host/coi-serve.py" "$ps" "$stock" >"$t/s.log" 2>&1 & pids+=($!)
pl=$(free_port); python3 "$here/host/coi-serve.py" "$pl" "$t/lw" >"$t/l.log" 2>&1 & pids+=($!)
for p in "$ps" "$pl"; do for _ in $(seq 100); do curl -sf -o /dev/null "http://127.0.0.1:$p/index.html" && break; sleep 0.1; done; done

harness=0
for r in $(seq "$REPS"); do
  for lane in stock lw; do
    url=http://127.0.0.1:$ps; [ "$lane" = lw ] && url=http://127.0.0.1:$pl
    node "$here/checks/browser-boot.mjs" --turn-time "$url" "$SEED" "$KEYS" >"$t/$lane-$r.json" 2>&1 \
      || { harness=1; echo "HARNESS FAIL: $lane run $r: $(grep -ho '"failure":"[^"]*"' "$t/$lane-$r.json")"; }
  done
done

# ---- table -----------------------------------------------------------------------
python3 - "$t" "$here/corpus/xsofy/turn-time.md" "$REPS" "$KEYS" "$SEED" "$XSOFY" "$LG" <<'PY'
import json, sys, os, datetime, subprocess, statistics as st
t, md, reps, keys, seed, xsofy, lg = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6], sys.argv[7]
def load(lane, r):
    try: return json.loads(open(f'{t}/{lane}-{r}.json').read().strip().splitlines()[-1])
    except Exception as e: return {'failure': str(e)}
runs = {lane: [load(lane, r) for r in range(1, reps + 1)] for lane in ('stock', 'lw')}
ok = all(not x.get('failure') and (x.get('turns') or 0) >= keys // 2 for v in runs.values() for x in v)
rev = subprocess.run(['git', '-C', xsofy, 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
lgname = os.path.basename(lg)
today = datetime.date.today().isoformat()
load1 = subprocess.run(['sysctl', '-n', 'vm.loadavg'], capture_output=True, text=True).stdout.split()[1:2]
def fmt(x): return '-' if x is None else f'{x:.1f} ms'
out = [f'# P4.4: xsofy turn latency (measured {today}, checks/turn-time.sh)', '',
       f'xsofy {rev}, lg {lgname}, headless Chromium via `checks/browser-boot.mjs --turn-time`, seed {seed}, '
       f'{keys} keys per run, {reps} runs per lane alternating lanes, load average at the end {" ".join(load1) or "?"}.',
       'A turn = keydown on xterm\'s textarea to the game\'s `xsofy/stats` event, both timestamped in the page: the game',
       'waking on the key plus the turn\'s compute, before the frame is drawn. Keys the game coalesced or ignored are not',
       'counted. Per run the median over its counted turns; the lane row is the median of its runs.', '',
       '| lane | median | mean | p90 | turns counted | runs (median ms) |', '|---|---|---|---|---|---|']
names = {'lw': 'lane 5: lower-wasm (emitted)', 'stock': 'stock Go (lg -w, let-go e9789b7d)'}
summary = {}
for lane in ('lw', 'stock'):
    v = [x for x in runs[lane] if not x.get('failure') and x.get('turns')]
    if not v:
        out.append(f'| {names[lane]} | run failed | - | - | - | ' + '; '.join(x.get('failure', '?') for x in runs[lane]) + ' |'); continue
    med = st.median(x['medianMs'] for x in v); mean = st.median(x['meanMs'] for x in v); p90 = st.median(x['p90Ms'] for x in v)
    summary[lane] = med
    out.append(f"| {names[lane]} | {fmt(med)} | {fmt(mean)} | {fmt(p90)} | {'/'.join(str(x['turns']) for x in v)} of {keys} | {', '.join('%.1f' % x['medianMs'] for x in v)} |")
out.append('')
if 'lw' in summary and 'stock' in summary and summary['lw']:
    out.append(f"Median turn: lower-wasm {summary['lw']:.1f} ms, stock Go {summary['stock']:.1f} ms ({summary['stock']/summary['lw']:.2f}x).")
for lane in ('lw', 'stock'):
    for i, x in enumerate(runs[lane], 1):
        if x.get('failure'): out.append(f'{lane} run {i}: {x["failure"]}')
        else: out.append(f'{lane} run {i} turns: {x.get("turnLog", "")}')
text = '\n'.join(out) + '\n'
open(md, 'w').write(text); print(text)
sys.exit(0 if ok else 2)
PY
r=$?
[ "$harness" = 1 ] && r=2
if [ "$r" = 0 ]; then echo "PASS (turn-time: table written to corpus/xsofy/turn-time.md; every run counted at least $((KEYS/2)) turns in both lanes)"
else echo "HARNESS FAIL (turn-time: a run timed out or counted too few turns; table written to corpus/xsofy/turn-time.md)"; fi
exit "$r"
