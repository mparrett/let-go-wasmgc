# LLVM sorted comparator implementation plan

**Goal:** Compile and execute sorted-map-by/sorted-set-by with the pinned
let-go comparator semantics, unblocking jank eq/not_eq.

**Architecture:** Store a comparator reference on SMap/SSet. Null selects the
existing default comparator hook; a custom callable uses an adapter for native
boolean/numeric result normalization and hash fallback. Keep the existing
array representation and its documented comparator call-trace limitation.

**Tech stack:** let-go runtime dialect, LLVM ORC, pinned native oracle.

## Current verification

Custom comparator implementation and source mappings are in place. The native
core group passes 16 tests / 14,165 assertions including 150 generated operation
sequences (seed 20261017), checking every retained map/set version against an
independent hash-map model. The consolidated values ORC run matches after
replacing long coercion with the existing saturating float helper; the earlier
run correctly exposed mismatches on infinity/overflow. Review found no new
correctness defect. A callable-map/reverse-numeric case was added afterward
and is included in the pending two-pass small-heap cache check. Actual jank
eq/not_eq is also pending. No full-suite claim is made.

## Implementation and verification

- [ ] Extend `checks/fixtures/jank-reader/values.lg` after its current two-pass
  cache check finishes. Use one block covering ascending/descending numeric
  and boolean comparators, interleaved maps/sets, updates/removals/lookups,
  equality and hash, metadata and empty, comparator-equivalent keys, fractional
  floats, NaN, infinities, out-of-range floats, invalid
  arguments/results and thrown comparator errors. Run the fixture through
  `checks/oracle.sh` with `LW_NATIVE_JIT=orc`, `WASM_RUN=checks/native-run.sh`,
  and `LW_DRIVER_ARGS=--no-rtlib`; require the expected missing-constructor
  compile failure before implementing.
  Baseline scratch group `/tmp/llvm-sorted-comparator-regressions.lg` already
  produces native exit 0 vs ORC exit 1 (missing constructors). Before merging
  it into values.lg, isolate native collections per operation: the pinned
  binary mutates some retained sorted maps during updates/deletion. See
  `docs/benchmarks/jank-orc-2026-10-16-unicode/sorted-oracle-observation.md`.
  Test backend persistence with explicit expected values, not a contaminated
  native instance. Preserve the independent bug reproducer.
- [ ] Add comparator fields and accessors to `rt/llvm/sorted.lg`. Every
  SMap/SSet constructor must preserve the field. Search accepts it explicitly;
  default ordering continues through the installed core hook. Ensure `empty`
  drops metadata but retains custom ordering, matching the pin.
- [ ] Add callable validation/result normalization and error-to-hash fallback
  at the core/extension boundary. Reuse the sort adapter where safe, without
  changing sort's error propagation. Do not reuse the raw `fptosi` float branch:
  pinned `vm.ToInt` maps NaN to zero and saturates infinities/out-of-range
  floats; guard these before conversion. Core depends on sorted, so sorted must
  not require core. Keep custom adapters as GC-visible runtime references.
- [ ] Add variadic constructors to `rt/llvm/ext.lg`, matching native validation
  order/messages. Route `empty-v` through comparator-preserving constructors.
  Wire mappings at the LLVM-only `ext-twins` conditional with `ns-var` lookup
  for the new extension functions (literal Var references also resolve when
  loading Wasm). Do not break the shared
  `src/lw_rt.lg` loader by naming absent functions in `src/lw_ext.lg`.
- [ ] Run the existing consolidated fixture again, then actual jank eq/not_eq.
  A harness exit zero with bar zero is insufficient: inspect tests, assertions,
  failures/errors, skips, and the first failure in results.tsv.
- [ ] Extend an existing native runtime test group with a seeded `check`
  property for comparator-preserving collection operations if its conversion
  helpers support these kinds. Avoid a parallel test framework or per-case files.
- [ ] Run small-heap GC/reference checks, gensym/snapshot guards and source-keyed
  cache creation/restoration. Inspect all SMap/SSet allocations for layout
  consistency. Seek review of comparator normalization, error fallback, GC
  rooting and cross-target mapping before claiming completion.
- [ ] Archive exact targeted results and source hashes, update LLVM-JANK.md and
  chit. Keep the full objective active until the full census proves it.
