# Literal allocation and regex identity

Run 17733: consolidated values fixture MATCH through ORC without a runtime
library cache after preserving map/set construction and regex literal origins.

Run 65530: added retained loop versions, exposing incorrect reuse of sets,
vectors, and lists across iterations. `loop-native.out` and `loop-before.out`
preserve the differential failure. Map allocations were already fresh.

Run 20872: the expanded fixture MATCH after excluding allocation-sensitive
collection calls from LLVM LICM hoisting. This protects identity and NaN set
equality without changing the existing non-LLVM predicate.

Actual jank eq/not_eq run 58569 MATCH: 2/2 deftests, 142 assertions, no skips.
The harness supplied --test --read-clj and used the runtime-cache path; the
outer LW_DRIVER_ARGS=--no-rtlib was replaced by the harness. Runtime-cache
creation/restoration run 43282 completed MATCH twice. The load-time gensym
counter remains 1133 and the runtime snapshot round-trips (722883 bytes). No full-suite or isolated
performance improvement is claimed. The manifest records sources for those runs.
