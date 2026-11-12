#!/usr/bin/env bash
# checks/lane-coverage.sh — every program corpus the GC lane runs, the llvm
# lane runs too: each dir a GC row in checks/items.tsv passes to
# checks/run-corpus.sh (its globs expanded) is in checks/common-corpora.sh's
# list or is run by an llvm row (WASM_RUN=checks/native-run.sh); and every
# native the GC runtime twins (rt/wasm, `:twin`) has an llvm twin (rt/llvm)
# or is named below as the GC lane's own mechanism. Prints each gap, then
# `lane-coverage: N gaps`; exits 1 when N > 0. Reads the files only; it runs
# no program.
set -uo pipefail
cd "$(dirname "$0")/.."
python3 - <<'EOF'
import glob, os, re, sys

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

# a GC corpus whose behavior the llvm lane has by design another way, and the
# llvm corpus that twins it
twinned = {'corpus/poly-native': 'corpus/poly-clj'}
gaps = sorted(d for d in gc if d not in common and d not in llvm and d not in twinned)
gaps += [f'missing twin: {t}' for t in twinned.values() if not os.path.isdir(t)]
for d in gaps:
    print(f"gc only: {d} ({' '.join(gc[d])})")

def twins(d):
    names = set()
    for f in glob.glob(d + '/*.lg'):
        t = open(f).read()
        names |= set(re.findall(r':twin "([^"]+)"', t))
        for v in re.findall(r':twin \[([^\]]*)\]', t):
            names |= set(re.findall(r'"([^"]+)"', v))
    return names

# the GC lane's own mechanisms, which the llvm lane does another way
lane_own = {
    # the in-module compiler: let-go's IR builder run as a program on WasmGC
    'core/-copy-form-source!', 'ir/form-source-info', 'ir/new-consts', 'ir/new-named-source-info',
    'ir/op-cheap-load?', 'ir/op-infer-facet?', 'ir/op-kws', 'ir/op-lower-facet?', 'ir/op-terminator?',
    # types and protocols built at run time; llvm lowers them statically
    'core/defprotocol*', 'core/extend-type*', 'core/make-deftype', 'core/make-deftype-instance',
    'core/make-protocol-fn', 'core/make-record', 'core/make-record-type',
    # let-go's own lg definition compiles on llvm as program code
    'core/long-array', 'core/integer?', 'core/rational?',
    # lowered by the llvm backend for a protocol named at the call (a call of
    # the protocol's predicate); refused otherwise, corpus/refused/satisfies-value.lg
    'core/satisfies?',
}
missing = sorted(twins('rt/wasm') - twins('rt/llvm') - lane_own)
for n in missing:
    print(f"no llvm twin: {n}")
gaps += missing
print(f"lane-coverage: {len(gaps)} gaps")
sys.exit(1 if gaps else 0)
EOF
