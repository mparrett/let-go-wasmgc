# LLVM literal allocation and identity

Jank eq/not_eq execute fully but fail on distinct NaN-containing sets and
distinct regex literals. Diagnostic values are archived in
`docs/benchmarks/jank-orc-2026-10-16-sorted/equality-diagnostics.log`.

Pinned native probes establish that nonempty map/set literals allocate on
each function invocation, empty metadata-free literals are shared, and a
regex literal is shared across calls to its own function. Aliases of the same
set or regex remain equal. Quoted collections remain constants.

The IR builder currently folds literal-only maps/sets into constants, and
the runtime pool interns them by contents. Preserve nonempty LLVM map/set
literal construction through the builder's existing constructor-call path,
including metadata handling. Keep the original path for empty metadata-free
collections and sorted input values; keep the Wasm lane unchanged. This also
fixes observable nonempty-map identity, beyond the NaN set symptom.

Regex source objects remain distinct through IR CSE, but LLVM replaces them
with structurally identical symbol stand-ins before pooling. Add an optional
origin discriminator to const-global!: LLVM regex uses function name plus
the originating IR node (`src-of`), preserving aliases and repeated reads of
one site. This uses existing deterministic compiler identifiers, not new
gensyms or process addresses. The regex initializer continues to create one
MetaNamed wrapper per global. Other constant keys remain unchanged.

Rejected alternatives: removing runtime identity equality would break aliases;
allocating regexes at each read would break same-site repeated calls; disabling
all constant caching would unnecessarily affect immutable scalar reuse.

Verify the consolidated values group (allocations, aliases, empty literals,
same regex site versus distinct sites), actual jank eq/not_eq, source snapshot
and cache restoration, and unchanged Wasm loading. Review origin propagation
through block arguments and function specialization. Do not infer full-suite
compatibility from these targeted cases.

Loop regression confirmed a second allocation boundary: LICM independently
hoists total-pure-call? constructors even with unique CSE call keys. Keep
allocation-sensitive collection calls (including collection projections that
can allocate sequence wrappers) and constantly closures at their evaluation
sites in LLVM. Retain the existing non-LLVM predicate and read-only scalar
optimizations. The consolidated fixture retains three loop iterations and
compares set/map/vector/list identities and NaN-sensitive equality. Baseline
run 65530 reused sets, vectors, and lists; maps were already fresh because
array-map is not in the pinned total-pure-builtins registry.
