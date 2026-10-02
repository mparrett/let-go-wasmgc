#!/usr/bin/env bash
# checks/hash-parity.sh [--self] [vectors.tsv] — item P2.2.
#
# Default: for each row of corpus/hash/vectors.tsv (kind, edn, hash from
# let-go's vm.HashValue), ask the wasm runtime for the hash via
#   checks/wasm-hash.sh <edn> <kind>
# which must print the decimal uint32 hash of (read-string edn) and nothing
# else. kind is passed because one EDN text can name two runtime types:
# "pvector" rows are PersistentVectors (what a vector with metadata becomes),
# and [] hashes differently as a PersistentVector than as an ArrayVector.
#
# --self: recompute every row through native lg's `hash` builtin, in ONE lg
# process, and compare with the Go table. This proves the table is what lg
# itself computes, and is the falsification path for the table's format.
#
# Exit: 0 = every row matches; 1 = at least one miss; 2 = hook missing.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
LG=${LG:-$HOME/projects-new/3p/lg-bin/lg-4e76921230}

self=0
if [ "${1:-}" = --self ]; then self=1; shift; fi
tsv=${1:-$here/../corpus/hash/vectors.tsv}
[ -r "$tsv" ] || { echo "no vectors file: $tsv"; exit 2; }
tsv=$(cd "$(dirname "$tsv")" && pwd)/$(basename "$tsv")

if [ "$self" = 1 ]; then
  # lg prints one MISS line per mismatch and a final "ROWS <n> MISSES <m>".
  out=$("$LG" -e "
(require '[clojure.string :as str])
(let [rows (->> (str/split-lines (slurp \"$tsv\"))
                (remove #(or (str/blank? %) (str/starts-with? % \"#\")))
                (map #(str/split % #\"\t\")))
      misses (atom 0)]
  (doseq [[kind edn want] rows]
    (let [v (read-string edn)
          v (if (= kind \"pvector\") (with-meta v {:pv true}) v)
          got (hash v)]
      (when (not= got (parse-long want))
        (swap! misses inc)
        (println \"MISS\" kind edn \"want\" want \"got\" got))))
  (println \"ROWS\" (count rows) \"MISSES\" @misses))
" 2>&1)
  printf '%s\n' "$out" | grep -v '^nil$'
  summary=$(printf '%s\n' "$out" | grep '^ROWS ')
  [ -n "$summary" ] || { echo "FAIL: lg did not finish"; exit 1; }
  set -- $summary
  [ "$4" = 0 ] && { echo "OK: lg hash == vm.HashValue on all $2 rows"; exit 0; }
  echo "FAIL: $4 of $2 rows differ"; exit 1
fi

hook=${WASM_HASH:-$here/wasm-hash.sh}  # override to test the loop
[ -x "$hook" ] || { echo "NOT IMPLEMENTED: $hook missing"; exit 2; }
rows=0 misses=0 limits=0
while IFS=$'\t' read -r kind edn want; do
  case $kind in ''|'#'*) continue ;; esac
  rows=$((rows + 1))
  got=$("$hook" "$edn" "$kind" 2>&1)
  # LIMIT = the runtime names this kind a Phase-2 limit (bigint/ratio/bigdec, D15): skipped, reported, not a miss.
  if [ "$got" = LIMIT ]; then limits=$((limits + 1)); echo "LIMIT $kind ${edn:0:60}"; continue; fi
  if [ "$got" != "$want" ]; then
    misses=$((misses + 1))
    echo "MISS $kind ${edn:0:80} want $want got ${got:0:80}"
  fi
done < "$tsv"
echo "ROWS $rows MISSES $misses LIMITS $limits"
[ "$misses" = 0 ]
