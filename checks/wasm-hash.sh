#!/usr/bin/env bash
# checks/wasm-hash.sh <edn> <kind> — the P2.2 hook (D18): print the decimal
# uint32 hash the BACKEND computes for (read-string edn), kind "pvector" via
# with-meta (D79: always PersistentVector). Prints LIMIT for a row whose
# read-string is a named limit in the runtime (bigint/ratio/bigdec, D15).
#
# Compiling one module per row would cost ~10 s × 201, so the hook batches:
# on first use it emits ONE program covering every row of vectors.tsv, runs it
# through checks/wasm-run.sh, caches the answers keyed by the table + tree
# hash, and answers each call from the cache.
set -uo pipefail
cd "$(dirname "$0")/.."
edn=$1; kind=${2:-}
tsv=corpus/hash/vectors.tsv
key=$( (cat "$tsv"; cat src/*.lg rt/wasm/*.lg) | md5 -q)
cache=${TMPDIR:-/tmp}/lw-wasm-hash-$key.tsv
if [ ! -s "$cache" ]; then
  prog=$(mktemp -d)/hashes.lg
  python3 - "$tsv" > "$prog" <<'PY'
import sys
rows=[l.rstrip("\n").split("\t") for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
def lit(s): return '"'+s.replace("\\","\\\\").replace('"','\\"')+'"'
print("(def rows [")
for i,(kind,edn,_h) in enumerate(rows):
    print(f"  [{i} {lit(kind)} {lit(edn)}]")
print("])")
print('''(doseq [[i kind edn] rows]
  (let [r (try (let [v (read-string edn)
                     v (if (= kind "pvector") (with-meta v {:pv true}) v)]
                 (str (hash v)))
               (catch Exception e (if (clojure.string/includes? (str (ex-message e)) "lower-wasm:") "LIMIT" (str "ERR " (ex-message e)))))]
    (println (str i "\\t" kind "\\t" r))))''')
PY
  checks/sem.sh checks/wasm-run.sh "$prog" > "$cache.tmp" 2>"$cache.err" && command mv "$cache.tmp" "$cache" || { echo "ERR compile/run failed: $(head -1 "$cache.err")"; exit 1; }
fi
python3 - "$tsv" "$cache" "$edn" "$kind" <<'PY'
import sys
tsv,cache,edn,kind=sys.argv[1:]
rows=[l.rstrip("\n").split("\t") for l in open(tsv) if l.strip() and not l.startswith("#")]
ans={l.split("\t")[0]:l.rstrip("\n").split("\t")[2] for l in open(cache) if "\t" in l}
for i,(k,e,_h) in enumerate(rows):
    if k==kind and e==edn:
        print(ans.get(str(i),"ERR missing")); sys.exit(0)
print("ERR row not in table"); sys.exit(1)
PY
