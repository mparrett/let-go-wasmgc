#!/usr/bin/env python3
"""census-summary.py <corpus> <raw.tsv> <bad-dir> <out.tsv> <out-summary.md> <fallbacks 0|1>

Merges census.lg's per-unit TSV with the wasm-tools validation failures
(<bad-dir>/u<idx> holds the first error line), writes the final TSV and the
markdown summary, prints the bucket table, and exits 0 iff the P1.5 (and,
with fallbacks=1, P1.6) conditions hold. Stdlib only.
"""
import collections
import datetime
import os
import re
import sys

corpus, raw, bad_dir, out_tsv, out_md, fb = sys.argv[1:7]
fallbacks = fb == "1"

with open(raw) as fh:
    header = fh.readline().rstrip("\n").split("\t")
    rows = [dict(zip(header, line.rstrip("\n").split("\t"))) for line in fh if line.strip()]

for r in rows:
    p = os.path.join(bad_dir, "u" + r["idx"])
    if os.path.exists(p):
        with open(p) as fh:
            r["detail"] = fh.read().strip()[:160]
        r["bucket"] = "invalid-wat"

with open(out_tsv, "w") as fh:
    fh.write("\t".join(header) + "\n")
    for r in rows:
        fh.write("\t".join(r[h] for h in header) + "\n")

COMPILES = {"ok", "unbound-var", "phase2-const"}
n = len(rows)
buckets = collections.Counter(r["bucket"] for r in rows)


def norm(b):
    # like failures count together: strip unit names, node ids, numbers
    b = re.sub(r'"u\d+_[^"]*"', '"<fn>"', b)
    return re.sub(r"\d+", "N", b)


heads = collections.OrderedDict()
for r in rows:
    if r["bucket"] in COMPILES:
        continue
    h = norm(r["bucket"])
    heads.setdefault(h, []).append(r)
top = sorted(heads.items(), key=lambda kv: -len(kv[1]))[:15]

unbound = collections.Counter()
for r in rows:
    for v in filter(None, r["externs"].split(",")):
        unbound[v] += 1
p2_units = [r for r in rows if r["phase2"]]
p2_kinds = collections.Counter(k for r in p2_units for k in r["phase2"].split(","))
p2_units_by_kind = collections.Counter(k for r in p2_units for k in set(r["phase2"].split(",")))

ops = sum(c for b, c in buckets.items() if b.startswith("unsupported op"))
invalid = buckets.get("invalid-wat", 0)
gotos = buckets.get("goto fallback", 0)
trees = sum(c for b, c in buckets.items() if b.startswith("unsupported tree node"))
compiled = sum(c for b, c in buckets.items() if b in COMPILES)
must = {"legmacs": [("legmacs/buffer.lg", "row-col-of")], "xsofy": [("xsofy/fov.lg", "reveal-line")]}.get(corpus, [])
named = []
for f, nm in must:
    hit = [r for r in rows if r["file"] == f and r["name"] == nm]
    named.append((f, nm, hit[0]["bucket"] if hit else "MISSING"))

L = []
L.append(f"# Backend census: {corpus} ({datetime.date.today().isoformat()})\n")
L.append("Each top-level fn unit (one row per arity) lowered alone by lower-wasm and its "
         "module validated with wasm-tools; nothing is run. Regenerate with "
         f"`checks/census.sh {corpus}`; per-unit rows in `{corpus}.tsv`.\n")
L.append(f"**{compiled}/{n} units compile** ({100.0 * compiled / max(n, 1):.1f}%): "
         f"ok {buckets.get('ok', 0)}, unbound-var {buckets.get('unbound-var', 0)}, "
         f"phase2-const {buckets.get('phase2-const', 0)}. "
         f"unsupported op: {ops}; invalid-wat: {invalid}; goto fallback: {gotos}; unsupported tree node: {trees}.\n")
L.append("| bucket | units |\n|---|---:|")
for b, c in sorted(buckets.items(), key=lambda kv: (-kv[1], kv[0])):
    L.append(f"| `{b}` | {c} |")
L.append("")
L.append("`unbound-var` = compiles; reaches at least one var outside the corpus with no wasm "
         "definition yet (a run-time `TypeError: nil is not a function `). `phase2-const` = "
         "compiles, no unbound var, at least one Phase-2 constant placeholder. Units reaching "
         "only the corpus's own vars count as ok: a whole-program compile makes those direct calls.\n")
L.append(f"## Top error heads ({len(heads)} distinct)\n")
L.append("| n | head | example | detail |\n|---:|---|---|---|")
for h, rs in top:
    ex = rs[0]
    d = ex["detail"].replace("|", "\\|")[:120]
    L.append(f"| {len(rs)} | `{h}` | {ex['file']} {ex['name']} ({ex['arity']}) | {d} |")
L.append("")
L.append(f"## Phase-2 constant placeholders: {len(p2_units)} units\n")
L.append("Units (any bucket) holding at least one placeholder, by kind (sites in parentheses):\n")
L.append("| kind | units | sites |\n|---|---:|---:|")
for k, c in p2_units_by_kind.most_common():
    L.append(f"| {k} | {c} | {p2_kinds[k]} |")
L.append("")
L.append(f"## Unbound vars: {len(unbound)} distinct (top 25 by units)\n")
L.append("| var | units |\n|---|---:|")
for v, c in unbound.most_common(25):
    L.append(f"| `{v}` | {c} |")
L.append("")
if named:
    L.append("## P1.6 named fns\n")
    for f, nm, b in named:
        L.append(f"- {f} `{nm}`: {b}")
    L.append("")
with open(out_md, "w") as fh:
    fh.write("\n".join(L))

print(f"{corpus}: {compiled}/{n} compile; unsupported-op {ops}, invalid-wat {invalid}, "
      f"goto {gotos}, tree-node {trees}; phase2-placeholder units {len(p2_units)}")
for b, c in sorted(buckets.items(), key=lambda kv: (-kv[1], kv[0])):
    print(f"  {c:5d}  {b}")
for f, nm, b in named:
    print(f"  named: {f} {nm}: {b}")

ok = ops == 0 and invalid == 0
if fallbacks:
    ok = ok and gotos == 0 and trees == 0 and all(b in COMPILES for _, _, b in named)
sys.exit(0 if ok else 1)
