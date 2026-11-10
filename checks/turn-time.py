#!/usr/bin/env python3
"""turn-time — P4.4's table: read the per-run JSON that checks/turn-time.sh left
in its temp dir and write corpus/xsofy/turn-time.md.

  turn-time.py TMPDIR MD REPS KEYS SEED XSOFY LG COMMIT

Exit 0 iff every run in both lanes counted at least KEYS/2 turns.
"""
import json, sys, os, datetime, subprocess, statistics as st
t, md, reps, keys, seed, xsofy, lg, commit = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5], sys.argv[6], sys.argv[7], sys.argv[8]
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
names = {'lw': 'lane 5: lower-wasm (emitted)', 'stock': f'stock Go (lg -w, let-go {commit})'}
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
sys.exit(0 if ok else 1)
