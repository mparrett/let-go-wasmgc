# LLVM sorted collection comparators

## Evidence and scope

After fixing imported assertion routing, jank `core_test/not_eq.cljc` reaches
`clojure.core-test.eq/tests` and fails compilation at `core/sorted-map-by`.
The same helper uses `sorted-set-by`. Native reports one test and 71 passing
assertions. Evidence is in `/tmp/jank-imported-assertions/results.tsv` and the
archived imported-assertions benchmark directory.

The pinned oracle is let-go e9789b7d53. `pkg/rt/lang.go`'s `fnComparator`,
`CoreSortedMapBy`, and `CoreSortedSetBy`, plus `pkg/vm/sorted_map.go` and
`sorted_set.go`, define the behavior. Read them with `git show` at the pin;
the sibling working tree is not the oracle.

## Design

Retain a comparator reference in each LLVM SMap/SSet, using null for default
ordering. Preserve it through updates, metadata changes, and empty. Extend
the existing sorted search path to dispatch through that reference. Normalize
custom comparator results using the existing sort comparator behavior:
boolean true means less; false queries the reverse direction; numeric results
are converted as the pinned native engine does and reduced to their sign.
Comparator errors use hash ordering, as native tree insert/find/delete do.
Constructor argument validation must match the native error messages.
Float result conversion must guard NaN (zero) and saturate infinities and
out-of-range floats before LLVM integer conversion; raw `fptosi` is unsafe.

This extends the existing immutable sorted arrays. It retains binary-search
lookup and O(n) insertion. A persistent balanced tree is the alternative for
O(log n) updates and matching native comparator call traces; it is a larger
representation change. A process-global comparator is rejected because two
collections with different orderings must coexist and survive GC/cache use.

The existing array representation already differs from the native tree for
inconsistent comparisons and mixed incomparable keys. Do not claim matching
comparator invocation traces or resolve that limitation by suppressing tests.

## Verification and consolidation

Extend the existing values differential fixture with a single operation group:
construct ascending/descending map and set values, update/remove/lookup, compare
across orderings, preserve comparator through metadata and empty, exercise
equivalent keys, validate arguments, and exercise error fallback. Use `check`
with reproducible seeds and shrinking for generated operation sequences where
the native and runtime representations can be compared directly.

Observe the missing-constructor failure before implementation. Then verify
the consolidated group under ORC, small-heap GC, cache creation/restoration,
and actual jank eq/not_eq. Changes to SMap/SSet layouts require checking every
constructor and the source-keyed runtime cache. Keep Wasm mappings functional:
the shared lw_rt mapping must not resolve a missing Wasm extension function.

No full-suite score can be inferred from these targeted results.
