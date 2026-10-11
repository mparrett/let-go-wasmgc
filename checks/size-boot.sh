#!/usr/bin/env bash
# checks/size-boot.sh — P4.3: bundle size and boot time of the emitted lane
# (lane 5) against the stock-Go lane, measured now on this machine, and the
# TinyGo lane's recorded figures (memory letgo-aot-tinygo-xsofy-lanes,
# 2026-09-20, xsofy 0e2a8b8 × let-go 36b13f79: 2.3 MB, 8725 ms to title,
# 12553 ms to the game screen; not rebuilt here, TinyGo 0.42 + let-go#939).
#
# Bundle = every file the page fetches: stock = index.html (the wasm inline,
# base64 of gzip, as `lg -w` emits it) + coi-serviceworker.js; lw = index.html
# (the same shell injected) + xsofy-shell-adapter.js + lg-wasm-host.js +
# module.wasm. Sizes raw, brotli -q 11 and gzip -9 (GitHub Pages serves gzip
# only). Boot = local-scripts/browser-smoke-playwright/zz-boot-time-probe.mjs
# (navigation to "press any key", then Space to the HUD), REPS runs per lane
# (default 5), medians. Both lanes are built by checks/lane5.sh's caches
# (run it first, or this script builds them the same way).
# Writes the table to corpus/xsofy/size-boot.md and prints it.
# Exit 0 iff both lanes boot to the map in every run and the table is written.
#
# checks/size-boot.sh --legmacs — P6.5: the same table for legmacs, in
# checks/size-boot-legmacs.sh (corpus/legmacs/size-boot.md).
set -uo pipefail
for a in "$@"; do case "$a" in
  --legmacs) exec "$(dirname "$0")/size-boot-legmacs.sh";;
  *) echo "size-boot.sh: unknown arg $a" >&2; exit 2;;
esac; done
here=$(cd "$(dirname "$0")/.." && pwd)
ws=$(cd "$here/../.." && pwd)
. "$(dirname "$0")/env.sh"
XSOFY=${XSOFY:-$LW_ROOT/xsofy}
REPS=${REPS:-5}
pw=${LW_BROWSER_TOOLS:-$ws/local-scripts}/browser-smoke-playwright
t=$(mktemp -d); trap '[ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"' EXIT

# the stock lane: lane5.sh's cache (same key), built by lane5.sh if missing
cache=${LW_LANE5_CACHE:-${TMPDIR:-/tmp}/lw-lane5-stock}
key=$( { echo e9789b7d; shasum "$LG"; cat "$XSOFY/main.lg" "$XSOFY/tools/xsofy-shell.html";
         find "$XSOFY/xsofy" -name '*.lg' -print0 | sort -z | xargs -0 cat; } | md5 -q)
stock=$cache/$key
if [ ! -f "$stock/index.html" ]; then
  echo "stock lane not cached: running checks/lane5.sh to build it" >&2
  "$here/checks/lane5.sh" >"$t/lane5.log" 2>&1
  [ -f "$stock/index.html" ] || { echo "FAIL: no stock lane"; cat "$t/lane5.log"; exit 1; }
fi
"$here/host/build-xsofy-module.sh" "$t/module.wasm" 2>"$t/mod.log" || { cat "$t/mod.log"; echo "FAIL: module"; exit 1; }
"$here/host/build-xsofy-serve.sh" "$t/lw" "$t/module.wasm" || exit 1
raw_module=$(sed -n 's/^module: \([0-9]*\) bytes raw.*/\1/p' "$t/mod.log")

sizes() {  # sizes <file...> -> "raw brotli gzip" summed
  local r=0 b=0 g=0 f
  for f in "$@"; do
    r=$((r + $(wc -c <"$f"))); b=$((b + $(brotli -c -q 11 "$f" | wc -c))); g=$((g + $(gzip -9 -c "$f" | wc -c)))
  done
  echo "$r $b $g"
}
read -r s_raw s_br s_gz <<<"$(sizes "$stock/index.html" "$stock/coi-serviceworker.js")"
read -r l_raw l_br l_gz <<<"$(sizes "$t/lw/index.html" "$t/lw/xsofy-shell-adapter.js" "$t/lw/lg-wasm-host.js" "$t/lw/module.wasm")"
read -r m_raw m_br m_gz <<<"$(sizes "$t/lw/module.wasm")"

free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
(cd "$pw" && node zz-boot-time-probe.mjs "$stock" "$(free_port)" stock "$REPS") >"$t/boot-stock.json" 2>&1
(cd "$pw" && node zz-boot-time-probe.mjs "$t/lw" "$(free_port)" lw "$REPS") >"$t/boot-lw.json" 2>&1

python3 - "$t" "$here/corpus/xsofy/size-boot.md" "$s_raw" "$s_br" "$s_gz" "$l_raw" "$l_br" "$l_gz" "$m_raw" "$m_br" "$m_gz" "$raw_module" "$REPS" <<'EOF'
import json, sys, datetime, subprocess
t, md = sys.argv[1], sys.argv[2]
s_raw, s_br, s_gz, l_raw, l_br, l_gz, m_raw, m_br, m_gz, raw_module, reps = map(int, sys.argv[3:14])
def load(f):
    try: return json.loads(open(f'{t}/{f}').read().strip().splitlines()[-1])
    except Exception as e: return {'failure': f'{f}: {e}'}
bs, bl = load('boot-stock.json'), load('boot-lw.json')
ok = all('titleMedian' in b and len(b.get('screenMs', [])) == reps for b in (bs, bl))
mb = lambda n: f'{n/1e6:.2f} MB' if n >= 1e6 else f'{n/1e3:.0f} KB'
ms = lambda b, k: f"{b[k]} ms" if k in b else 'FAIL'
xs = subprocess.run(['git', '-C', __import__('os').environ['XSOFY'], 'rev-parse', '--short', 'HEAD'],
                    capture_output=True, text=True).stdout.strip()
today = datetime.date.today().isoformat()
rows = [
  ('lane 5: lower-wasm (emitted)', mb(l_raw), mb(l_br), mb(l_gz), ms(bl, 'titleMedian'), ms(bl, 'screenMedian')),
  ('stock Go (lg -w, let-go e9789b7d)', mb(s_raw), mb(s_br), mb(s_gz), ms(bs, 'titleMedian'), ms(bs, 'screenMedian')),
  ('TinyGo (recorded 2026-09-20, not re-run)', '2.3 MB', '1.27 MB (floor build)', '1.70 MB (floor build)', '8725 ms', '12553 ms'),
]
out = [f'# P4.3: lane 5 size and boot (measured {today}, checks/size-boot.sh)', '',
       f'xsofy {xs}, lg e9789b7d (`lg-e9789b7d53`), headless Chromium via zz-boot-time-probe.mjs, {reps} runs per lane, medians.',
       'Bundle = every file the page fetches (shell included in both). Boot times are from navigation; the title card itself',
       'animates for part of the time-to-title on every lane.', '',
       '| lane | bundle raw | brotli -q 11 | gzip -9 | time-to-title | time-to-map |', '|---|---|---|---|---|---|']
out += ['| ' + ' | '.join(r) + ' |' for r in rows]
out += ['', f'Lane 5 module alone: {raw_module:,} B as emitted, {m_raw:,} B after `wasm-opt -O3` (served), '
        f'{m_br:,} B brotli, {m_gz:,} B gzip.',
        f"Runs (ms): lane 5 title {bl.get('titleMs')}, map {bl.get('screenMs')}; stock title {bs.get('titleMs')}, map {bs.get('screenMs')}.",
        'TinyGo row: memory `letgo-aot-tinygo-xsofy-lanes` (xsofy 0e2a8b8 × let-go 36b13f79, another day and load); its 2.3 MB is',
        'the raw bundle, its compressed figures are the 2026-09-20 footprint audit\'s floor build (wasm-opt -Oz, external wasm).']
for b in (bs, bl):
    if 'failure' in b: out.append(f"FAILURE: {b['failure']}")
text = '\n'.join(out) + '\n'
open(md, 'w').write(text)
print(text)
sys.exit(0 if ok else 1)
EOF
r=$?
[ "$r" = 0 ] && echo "PASS (table written to corpus/xsofy/size-boot.md)" || { echo "FAIL (a lane did not boot in every run)"; cat "$t"/boot-*.json; }
exit "$r"
