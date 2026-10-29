#!/usr/bin/env bash
# checks/lane-coverage.sh — every program corpus the GC lane runs, the llvm
# lane runs too: each dir a GC row in checks/items.tsv passes to
# checks/run-corpus.sh (its globs expanded) is in checks/common-corpora.sh's
# list or is run by an llvm row (WASM_RUN=checks/native-run.sh). Prints each
# dir only the GC lane runs, then `lane-coverage: N gaps`; exits 1 when N > 0.
# Reads the files only; it runs no program.
set -uo pipefail
cd "$(dirname "$0")/.."
python3 - <<'EOF'
import glob, re, sys

def corpus_args(cmd):
    """(lane, dir) for each dir a run-corpus.sh call in cmd names."""
    for seg in re.split(r'&&|\|\||;', cmd):
        toks = seg.split()
        at = [i for i, t in enumerate(toks) if t.endswith('run-corpus.sh')]
        if not at:
            continue
        lane = 'llvm' if 'native-run.sh' in seg else 'gc' if 'WASM_RUN=' not in seg or 'checks/wasm-run.sh' in seg else 'other'
        for t in toks[at[0] + 1:]:
            if t.startswith('corpus'):
                for d in (sorted(glob.glob(t)) if any(c in t for c in '*?[') else [t]):
                    yield lane, d.rstrip('/')

gc, llvm = {}, set()
for line in open('checks/items.tsv'):
    f = line.rstrip('\n').split('\t')
    if len(f) < 3:
        continue
    for lane, d in corpus_args(f[2]):
        if lane == 'gc':
            gc.setdefault(d, []).append(f[0])
        elif lane == 'llvm':
            llvm.add(d)

src = open('checks/common-corpora.sh').read()
body = src.split("<<'EOF'\n", 1)[1].split('\nEOF', 1)[0]
common = {l.split()[0] for l in body.splitlines() if l.strip() and not l.startswith('#')}

gaps = sorted(d for d in gc if d not in common and d not in llvm)
for d in gaps:
    print(f"gc only: {d} ({' '.join(gc[d])})")
print(f"lane-coverage: {len(gaps)} gaps")
sys.exit(1 if gaps else 0)
EOF
