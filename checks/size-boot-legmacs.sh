#!/usr/bin/env bash
# checks/size-boot-legmacs.sh — P6.5, reached as `checks/size-boot.sh --legmacs`:
# the size/boot table for legmacs' main.lg beside xsofy's (corpus/xsofy/size-boot.md).
#
# Lanes:
#   lw     host/build-legmacs-module.sh's module in host/build-legmacs-serve.sh's
#          page: index.html + xsofy-shell-adapter.js + lg-wasm-host.js + let-go's
#          lg-shell-xterm.js + module.wasm; served without COI (D91).
#   stock  `lg -w <dir> main.lg` at let-go 4e769212 with its default xterm shell
#          (index.html with the wasm inline + coi-serviceworker.js), LETGO_SRC a
#          `git archive` of that commit as in lane5.sh, cached under
#          $LW_LEGMACS_STOCK_CACHE; served with COOP/COEP (its key ring needs SAB).
# Both pages load xterm.js + addon-fit from cdn.jsdelivr.net; neither bundle
# counts them. Sizes raw, brotli -q 11, gzip -9; the module alone also as
# emitted and after wasm-opt -O3. Boot = checks/browser-boot.mjs --legmacs-time
# (navigation to the first text in xterm, and to the *scratch* mode line),
# REPS runs per lane (default 5), medians.
#
# Writes corpus/legmacs/size-boot.md and prints it. Exit 0 iff the table is
# written and the lw lane booted in every run. The stock lane's boot is
# measured and reported but does not gate: at let-go 4e769212 it cannot reach
# a first frame (main.lg's os/cwd raises "getwd: not implemented on js" under
# js/wasm), and the table records the failure from the run itself. A module
# that does not compile still gets a table (the stock lane's sizes, the
# backend's first error) and exit 1. Env: LG, LEGMACS, LETGO, REPS, KEEP=1.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
ws=$(cd "$here/../.." && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}
LEGMACS=${LEGMACS:-$HOME/projects-new/3p/legmacs}
LETGO=${LETGO:-$HOME/projects-new/3p/let-go}
COMMIT=4e769212
REPS=${REPS:-5}
t=$(mktemp -d); pids=()
cleanup() { for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; done; [ -n "${KEEP:-}" ] && echo "kept $t" >&2 || rm -rf "$t"; }
trap cleanup EXIT
free_port() { python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
sizes() {  # sizes <file...> -> "raw brotli gzip" summed
  local r=0 b=0 g=0 f
  for f in "$@"; do
    r=$((r + $(wc -c <"$f"))); b=$((b + $(brotli -c -q 11 "$f" | wc -c))); g=$((g + $(gzip -9 -c "$f" | wc -c)))
  done
  echo "$r $b $g"
}

# ---- stock lane ------------------------------------------------------------------
cache=${LW_LEGMACS_STOCK_CACHE:-${TMPDIR:-/tmp}/lw-legmacs-stock}; mkdir -p "$cache"
key=$( { echo "$COMMIT"; shasum "$LG"; cat "$LEGMACS/main.lg"; find "$LEGMACS/legmacs" -name '*.lg' -print0 | sort -z | xargs -0 cat; } | md5 -q)
stock=$cache/$key
if [ ! -f "$stock/index.html" ]; then
  echo "building the stock legmacs lane (lg -w at $COMMIT)..." >&2
  src=$t/letgo-src; mkdir -p "$src"
  git -C "$LETGO" archive "$COMMIT" | tar -x -C "$src" || { echo "FAIL: git archive $COMMIT"; exit 1; }
  rm -rf "$stock.tmp"; mkdir -p "$stock.tmp"
  if (cd "$LEGMACS" && LETGO_SRC="$src" "$here/checks/sem.sh" "$LG" -w "$stock.tmp" main.lg) >"$t/stock-build.log" 2>&1; then
    rm -rf "$stock"; command mv "$stock.tmp" "$stock"
  else
    echo "stock lane: lg -w could not build legmacs" >&2; tail -5 "$t/stock-build.log" >&2; rm -rf "$stock.tmp"
  fi
fi

# ---- lw lane ---------------------------------------------------------------------
lw_ok=1
if LW_LEGMACS_RAW="$t/raw.wasm" "$here/host/build-legmacs-module.sh" "$t/module.wasm" 2>"$t/mod.log"; then
  "$here/host/build-legmacs-serve.sh" "$t/lw" "$t/module.wasm" || exit 1
else
  lw_ok=0
  sed -E 's/\x1b\[[0-9;]*m//g' "$t/mod.log" | grep -m1 -iE 'error|unsupported' | cut -c1-300 >"$t/compile.err"
fi

# ---- sizes -----------------------------------------------------------------------
: >"$t/sizes"
[ -f "$stock/index.html" ] && echo "stock $(sizes "$stock/index.html" "$stock/coi-serviceworker.js")" >>"$t/sizes"
if [ "$lw_ok" = 1 ]; then
  echo "lw $(sizes "$t/lw/index.html" "$t/lw/xsofy-shell-adapter.js" "$t/lw/lg-wasm-host.js" "$t/lw/lg-shell-xterm.js" "$t/lw/module.wasm")" >>"$t/sizes"
  echo "module $(sizes "$t/lw/module.wasm")" >>"$t/sizes"
  echo "raw $(wc -c <"$t/raw.wasm" | tr -d ' ') 0 0" >>"$t/sizes"
fi

# ---- boot ------------------------------------------------------------------------
boot_lane() {  # boot_lane <dir> <label> coi|plain
  local p; p=$(free_port)
  if [ "$3" = coi ]; then python3 "$ws/local-scripts/coi-serve.py" "$p" "$1" >"$t/$2.server.log" 2>&1 & pids+=($!)
  else python3 -m http.server --bind 127.0.0.1 --directory "$1" "$p" >"$t/$2.server.log" 2>&1 & pids+=($!); fi
  for _ in $(seq 100); do curl -sf -o /dev/null "http://127.0.0.1:$p/index.html" && break; sleep 0.1; done
  node "$here/checks/browser-boot.mjs" --legmacs-time "http://127.0.0.1:$p" "$REPS" >"$t/boot-$2.json" 2>&1
}
[ -f "$stock/index.html" ] && boot_lane "$stock" stock coi
[ "$lw_ok" = 1 ] && boot_lane "$t/lw" lw plain

# ---- table -----------------------------------------------------------------------
python3 - "$t" "$here/corpus/legmacs/size-boot.md" "$REPS" "$LEGMACS" "${LW_LEGMACS_MAIN:-}" <<'PY'
import json, sys, datetime, subprocess, os
t, md, reps, legmacs, standin = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], sys.argv[5]
sz = {}
for line in open(f'{t}/sizes'):
    k, *v = line.split(); sz[k] = list(map(int, v))
def load(f):
    p = f'{t}/boot-{f}.json'
    if not os.path.exists(p): return None
    try: return json.loads(open(p).read().strip().splitlines()[-1])
    except Exception as e: return {'failure': f'{f}: {e}'}
bs, bl = load('stock'), load('lw')
mb = lambda n: f'{n/1e6:.2f} MB' if n >= 1e6 else f'{n/1e3:.0f} KB'
def boot(b, k):
    if b is None: return '-'
    if b.get('failure'): return 'does not boot'
    return f"{b[k]} ms"
lw_ok = bl is not None and not bl.get('failure') and len(bl.get('firstFrameMs', [])) == reps
rev = subprocess.run(['git', '-C', legmacs, 'rev-parse', '--short', 'HEAD'], capture_output=True, text=True).stdout.strip()
today = datetime.date.today().isoformat()
out = [f'# P6.5: legmacs size and boot (measured {today}, checks/size-boot.sh --legmacs)', '',
       f'legmacs {rev} `main.lg`, lg 4e769212 (`lg-4e76921230`), headless Chromium via `checks/browser-boot.mjs --legmacs-time`, '
       f'{reps} runs per lane, medians.',
       'Bundle = every file the page fetches except xterm.js + addon-fit, which both pages load from cdn.jsdelivr.net. Times are',
       'from navigation: boot = first text in xterm, first frame = the *scratch* mode line on screen.', '',
       '| lane | bundle raw | brotli -q 11 | gzip -9 | boot | first frame |', '|---|---|---|---|---|---|']
if standin:
    out[1:1] = [f'**STAND-IN ENTRY ({standin}, LW_LEGMACS_MAIN): the lower-wasm row is NOT legmacs main.lg.**', '']
def row(name, k, b):
    s = sz[k]
    return '| ' + ' | '.join([name, mb(s[0]), mb(s[1]), mb(s[2]), boot(b, 'bootMedian'), boot(b, 'firstFrameMedian')]) + ' |'
out.append(row('lower-wasm (emitted)', 'lw', bl) if 'lw' in sz else '| lower-wasm (emitted) | did not compile | - | - | - | - |')
out.append(row('stock Go (lg -w, let-go 4e769212)', 'stock', bs) if 'stock' in sz else '| stock Go (lg -w, let-go 4e769212) | lg -w could not build legmacs | - | - | - | - |')
out.append('')
if 'module' in sz:
    out.append(f"lower-wasm module alone: {sz['raw'][0]:,} B as emitted, {sz['module'][0]:,} B after `wasm-opt -O3` (served), "
               f"{sz['module'][1]:,} B brotli, {sz['module'][2]:,} B gzip.")
else:
    err = open(f'{t}/compile.err').read().strip() if os.path.exists(f'{t}/compile.err') else '?'
    out.append(f'lower-wasm module: did not compile, so it has no size or boot row yet. Backend: `{err}`')
for name, b in (('lower-wasm', bl), ('stock', bs)):
    if b is None: continue
    if b.get('failure'): out.append(f"{name} boot: {b['failure']}")
    else: out.append(f"Runs (ms) {name}: boot {b.get('bootMs')}, first frame {b.get('firstFrameMs')}.")
if bs is not None and bs.get('failure'):
    out += ['', 'The stock lane builds but does not boot legmacs: under js/wasm let-go\'s `os/cwd` raises "getwd: not implemented on js",',
            'and main.lg calls it to set up the *scratch* buffer, so its boot column is empty and the comparison is bundle size only.',
            'The lower-wasm runtime returns "" for `os/cwd` (D138: no file system in the module).']
text = '\n'.join(out) + '\n'
open(md, 'w').write(text)
print(text)
sys.exit(0 if lw_ok else 1)
PY
r=$?
if [ "$r" = 0 ]; then echo "PASS (table written to corpus/legmacs/size-boot.md; the lw lane booted in every run)"
else echo "FAIL (table written to corpus/legmacs/size-boot.md; the lw lane did not compile or did not boot in every run)"; fi
exit "$r"
