# Pinned sorted-map oracle caveat

During preparation of consolidated custom-comparator regressions, the pinned
binary `$LW_ROOT/lg-bin/lg-e9789b7d53` produced this result:

```clojure
(let [m (sorted-map-by < 3 :c 1 :a 2 :b)]
  (println m (hash m))
  (println (assoc m 4 :d 2 :replacement))
  (println (dissoc m 1))
  (println m (hash m) (hash {1 :a 2 :b 3 :c})))
```

```text
{1 :a, 2 :b, 3 :c} 3884163183
{1 :a, 2 :replacement, 3 :c, 4 :d}
{2 :b, 3 :c}
{1 :a, 2 :b, 2 :b, 3 :c} 3884163183 3884163183
```

The original map acquires a duplicate entry after these operations. Its hash
was cached before the operations, so this probe alone does not identify which
operation mutates it. A larger probe that first hashes after updates shows
different hashes from the equal hash-map. Direct fresh ascending/descending
maps both hash to 3884163183, confirming that ordering alone is not the cause.

Do not implement order-dependent hashing to match the contaminated oracle.
Use fresh native collections for independent differential operations, and
verify persistence against explicit expected values. Investigate and report
the pinned native defect separately; no external issue has been posted.
