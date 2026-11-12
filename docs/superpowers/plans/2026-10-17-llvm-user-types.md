# LLVM User Types Implementation Plan

> Execute sequentially with the executing-plans workflow. Preserve the current
> working tree and the paused function-cache design. Keep tests consolidated.

**Goal:** Replace LLVM deftype stand-ins with native-compatible user types,
providing the foundation for the Clojure BigInt and Ratio implementation.

**Architecture:** GC-traced generic instances refer to real TypeVal descriptors.
Compiler type identities use qualified source symbols; runtime identity hashes
use stable allocation tokens. Records retain their separate semantics.

**Tech stack:** Pinned let-go Clojure runtime dialect, LLVM IR, ORC, existing GC.

- [x] Capture native and ORC representation baseline (run 86941).
- [ ] Extend the existing definitions fixture with the baseline, field access,
  constructor errors, metadata, same-named types in two namespaces, and aliases.
- [x] Add UserInstance and optional TypeVal descriptor layout in rt/llvm/core.lg;
  update static TypeVal initialization in src/lower_llvm_rt.lg. Integrate kind,
  type-of, type-name, instance?, and predicates. Verify native runtime groups.
- [x] Implement LLVM constructor/type initialization in src/driver.lg. Preserve
  compiler-side native type objects and namespace ownership during indexing.
  Keep defrecord behavior separate. Verify the consolidated ORC differential.
- [x] Add field-slot access, dot twin, metadata, printer, and stable identity
  hashing; test retained aliases across collection. Extend existing groups with
  seeded check properties rather than creating a file per behavior.
- [ ] Replace keyword/map protocol dispatch for LLVM deftypes with type identity
  and field slots. Cover library/program cross-namespace methods and arities.
- [ ] Implement mutable fields, extensions and redefinition while retaining
  old-instance dispatch. Verify error behavior against the pinned source.
- [ ] Verify constructor and protocol users in actual jank tests, including
  compatibility definitions introduced through in-ns and imported helpers.
- [ ] Verify fresh/restored runtime caches, small-heap GC, gensym/snapshot and
  complete native runtime tests. Freeze sources for another full jank census.
- [ ] Measure warm constructor/field/protocol costs against pinned bytecode;
  record cold compile and cache restoration separately. Continue the numeric
  tower plan; do not mark the whole goal complete at this milestone.

The identity census is complete; its archived evidence is in
docs/benchmarks/jank-orc-2026-10-17-identity-integrated. A newer census uses
the independent frozen /tmp/jank-runtime-integrated-20261017 snapshot and
excludes mutable field storage changes.

Mutable field implementation now uses a shared, GC-traced reference array.
The runtime `set-field!` primitive mutates that array and returns the assigned
value; metadata copies share it while retaining separate identity hashes.
Uncached ORC definitions, seeded native mutation properties, and small-heap
collection survival for newly stored references pass.

Field metadata normalization and lexical rewriting are implemented using the
pinned core `-dt-rewrite` with an LLVM field-slot emitter in the declaration
namespace. Uncached definitions pass. Review reproduced receiver capture by
a macro-introduced binding; the revision expands ordinary macros before
selecting the receiver name. Cached verification passes that regression,
delayed closure reads, and foreign-namespace mutation; restoration from the
newly built cache also passes.
Evidence is summarized in the existing deftype README; regression cases stay
in definitions.lg rather than separate benchmark or probe files.

Protocol implementations must belong to the runtime type descriptor,
not the current value of its source Var. The pinned native probe creates an
instance, redefines the same type name, then extends the saved old type:
the old and new instances keep their respective implementations, and the
extension changes only the old instance's result. Descriptor method installation
and dynamic lookup now preserve this behavior, with generated update/isolation
properties and the expanded definitions fixture passing. Native probing also establishes
that a saved constructor follows the latest source type Var; do not change it
to capture an old descriptor.

Static builtin descriptors now expose their method-table slots as GC roots,
derived from retained `lg_type.*` globals after shaking. Native compiler-side
extensions and type-alias invalidation are implemented. Nil methods use a
GC-traced table in UserGlobals and participate in the existing generated
isolation property. The definitions fixture passes with a 1 MiB heap, covering
nil aliases, builtin/nil table survival, and macro calls before and after an
extension. Top-level macro expansions are retained in source order so later
extensions cannot change earlier compiled expressions. Broader extension
forms and inheritance remain unfinished.

Latest checkpoint: native core run 4221 passes 16 tests / 14,185 assertions
with generated metadata and retained hash checks. ORC definitions run 47897
matches fieldful/fieldless protocol dispatch, metadata copies, macro-time
method calls, mixed record/type constructors, and generated-name hygiene.
Protocol and GC/cache plan items remain open for their broader requirements.

Collection checkpoint: run 97112 MATCH twice with a 1 MiB heap and runtime
cache enabled; gensym counter 1133 and snapshot round-trip pass. Traced run
9472 MATCH records 6,848 collections, including 5,927 around the retained
instance allocation loop. ORC uses nonmoving mark/sweep, so this establishes
collection survival, not relocation or isolated tracing-edge coverage.

Protocol checkpoint: runs 75165 and 56459 MATCH multiple declared arities,
cross-namespace implementations, six-argument calls and macro-time methods.
The foreign-global failure required capturing declaration Vars and compiling
foreign top-level blocks in their lexical namespace; runtime eval now sees
those namespaces too. The library protocol regression remains in run 24968.
