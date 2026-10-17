# Deftype representation baseline

Mutable field verification uses the existing `definitions.lg` fixture and
native `core_test.lg` property group. It adds no performance benchmark.

- Runtime mutation and metadata-alias properties pass. Newly stored references
  also survive allocation pressure in the ORC differential with a 1 MiB heap.
- The original annotated-field baseline failed with `unresolved symbol x`.
  Lexical rewriting passed the uncached consolidated definitions fixture.
- A macro introducing `__lw_field_receiver` reproduced a receiver-capture
  failure (`UserInstance: cast failure`; native result `42`). The revised
  rewrite chooses its receiver after ordinary macro expansion. Verification
  includes delayed closure reads and foreign-namespace macros in the same
  fixture; both cache creation and restoration pass the ORC differential.
- The compiler identity and snapshot check passes after removing a new
  destructuring binding. No expected counter was changed.

Reproduce the consolidated ORC check with:

```sh
WASM_RUN=checks/native-run.sh LW_NATIVE_JIT=orc LW_LL_CHECK_REFS=1 \
  bash checks/oracle.sh checks/fixtures/jank-reader/definitions.lg
```

Use `LW_DRIVER_ARGS=--no-rtlib` for uncached compilation and
`LG_HEAP_BYTES=1048576` for the small-heap variant. Detailed command output
remains in the bench-baton logs; temporary probes are consolidated into the
fixture rather than retained as separate test sources.

Run 86941 fails the ORC differential with --no-rtlib. The baseline probes
fieldful and fieldless constructors, identity, type, instance?, map?/keyword?,
and generic get. Native creates distinct non-map objects with their declared
type; the current driver generates tagged maps or keywords instead.

This is a compiler representation defect, not a request to change the oracle.
The temporary probe will be consolidated into the existing definitions group
as the replacement is implemented. Field access and protocol behavior need
additional cases in that same group.


The first implementation adds a GC-traced UserInstance, a descriptor slot in
TypeVal, a separate runtime allocation counter, real constructors, and dynamic
type-of/type-name handling. Native core run 88356 passes 16 tests / 14,174
assertions. ORC run 87202 exposed preprocessing target selection: lw/*target*
is bound later, so the branch now uses the selected lw-rt runtime target.

Run 92624 matches ordinary type and earlier definition outputs but ends in a
known native oracle discrepancy: `(deftype ShadowedType [ShadowedType])` causes
native constructor field shadowing and an expected-DType error. LLVM qualifies
the type reference and succeeds. This case was removed from differential
coverage; the correct qualified reference is retained.

Review identified compiler-side native object preservation. Temporary macro
baseline 56822 fails before the fix (native exit 0, ORC exit 1). The driver now
evaluates the original declaration natively and marks the emitted constructor
so process! does not overwrite its native constructor root. Consolidated
verification 55932 and native core invariants 12219 are pending.

This is an incomplete user-type implementation. Field/protocol integration,
metadata, printing, hashing, redefinition and cache/GC proof remain required.


Run 55932 MATCH: the consolidated definitions fixture includes real user type
identity and a macro constructing a native instance and reading its field.
Native core run 12219 passes 16 tests / 14,181 assertions, including seven
new user-type invariants within the existing predicates/type group.

Malformed declaration baseline failed with a generic native-compile error.
Moving preprocessing under the existing ::native handler fixes it: run 15506
MATCH. Captured invalid-declaration outputs preserve its diagnostic and the
preceding print. Runtime field access is the next failing case under test.


Field access verification completed: run 14959 MATCH for the consolidated
ORC definitions fixture; run 88440 passes 16 native core tests / 14,184
assertions. The dot twin supports native raw member lookup then leading-hyphen
fallback, with the native missing-field diagnostic. Other receiver methods
and protocol dispatch are not yet implemented by that twin.

Metadata/printing/hash work is now under test. The consolidated definitions
fixture includes metadata copies, nil metadata, printing and distinct map keys.
The existing native metadata group has one check property (seed 20261018,
100 generated vectors of 1–12 values) retaining original and copied instances
against an independent index-to-key lookup model. Baseline 13229 fails ORC execution; baseline 45255 fails the generated
property and shrinks its counterexample to [[0]] (metadata copies alias the
original). The failure log is preserved. Runtime changes now allocate a fresh
metadata copy sharing field storage, print the default deftype form, and hash
the stable allocation token through fmix32. ORC run 95752 and native core run
59003 completed: the ORC differential matches, and all 16 native core tests
pass with 14,185 assertions, including the generated identity and map-key
property. GC and cache verification remain outstanding.

Protocol baseline 50056 fails with native exit 0 and ORC exit 1. Switching
LLVM deftype dispatch to type identity and constant field slots gives MATCH
in run 58114 for fieldful, fieldless, and metadata-copied instances.

Review found that generated dispatchers overwrite native methods used during
macro expansion, and source field names can shadow the receiver. Extended
baseline 36599 reproduces the native-instance cast failure during macro
expansion. Generated dispatchers now preserve native method roots, and their
field bindings retain a deterministic receiver symbol distinct from source
bindings. Run 59979 MATCH verifies these fixes. Multiple arities, cross-namespace
coverage, extensions and type redefinition remain unfinished.

The hash property now captures hashes before metadata copying and map
allocation, and generates nil, scalar, and map metadata with varied fields.
Native verification run 4221 passes all 16 tests and 14,185 assertions. The active ORC collector is
nonmoving mark/sweep; a small-heap run will establish survival across
collection, not relocation.

Further review extended hygiene to all source symbols, including free body
references and generated argument names. Baseline 64486 fails when a generated
receiver captures a global referenced by FreeSymbolProbe. The fix chooses all
generated locals against the complete source symbol set. Native record
declarations and both constructors are also preserved for macros using mixed
record/type protocols. Scoped source review found no further blocking defect;
ORC verification 47897 MATCH confirms the expanded definitions fixture.

Small-heap runtime-cache run 97112 MATCH twice with a 1 MiB heap, then passes
the gensym counter (1133) and 722,883-byte snapshot round-trip checks.
The appended definitions case retains instances, metadata copies, saved
hashes, and an identity-keyed map across 10,000 temporary instance allocations.
Traced rerun 9472 MATCH records 6,848 collections total, including 5,927 between
the preceding output and the allocation-loop result. See gc-trace.log,
gc-trace-command.sh, gc-cache.log and gc-cache-source-manifest.json.
This proves joint survival across nonmoving collection. Globals independently
retain type descriptors, and locals independently retain the map keys; this
does not isolate each tracing edge. The timings include shared load.

Multiple-arity baseline 35824 fails because nested arity clauses are treated as
one parameter vector. The driver now records all declared signatures, indexes
implementations by type and arity, and emits distinct foreign helpers per
arity. The consolidated fixture also calls methods defined in another
namespace and invokes one through a macro. Verification 78508 exposed a
separate foreign-global ownership defect: declarations were stored as bare
symbols and resolved in the final namespace, as were top-level bodies.

The driver now captures declaration Vars immediately and groups each foreign
top-level block into a helper compiled in its owner namespace. Global conflict
checks use Var identity, and the runtime registry includes every captured
namespace. Helper construction is eager and retains source-call diagnostics.
Run 75165 MATCH covers arities and foreign implementations. Cached ORC run
56459 MATCH additionally covers a six-argument protocol call, same-named
globals in separate namespaces and runtime eval lookup. Scoped review found
no further blocking defect. Gensym check 50161 remains at 1133 and the snapshot
round-trip passes. Existing regression run 24968 passes four of nine files:
both namespace-reader cases, floating-call type naming, and definitions before
an ns form. Five evaluator cases fail at llvm.eval/core-table*; run 21269
reproduces the same failure in the frozen pre-user-type compiler, establishing
that this is an existing gap. The unchanged library types fixture (run 35889)
executes its protocol calls but fails on symbol of a Var; its printed record
instance? result also disagrees. It is not an end-to-end pass.

### Var conversion and interned Vars

ORC run 88635 matches pinned bytecode for the consolidated definitions fixture. It covers public namespace spelling in `symbol`, ordinary-symbol collisions with interned Var names, live dereference and metadata, root updates, and watch notification. Outputs are archived as `var-symbol-*`; the manifest records the changed runtime inputs and fixture. Native core properties pass 16 tests / 14,185 assertions (95701), and the gensym/snapshot guard passes at counter 1133 (61237).

The uncached compiler path remains unresolved: run 38527 fails before execution with a missing signature for `lw-ext/posix-ranges` while lowering `regex-parse`. Cached verification does not establish that this path works.

### Namespace creation and intern

The runtime now implements `create-ns`. Programs referencing `intern` register their compiled namespace names, including empty namespaces, without installing the evaluator table. Namespace-sensitive top-level code starts in `user` and executes namespace transitions in source order. LLVM reads of `*ns*` call the runtime getter.

Final uncached ORC calls run 23826 matches bytecode, covering initial/current namespace state, foreign and empty namespaces, and interned values. Actual jank intern run 95884 matches; its outputs are archived here. Cached definitions run 37484 matched namespace creation, error handling, and existing definitions before the final initial-namespace correction. Identifier/snapshot verification 45299 passed before that final correction.

Uncached definitions now expose the evaluator failure precisely: `llvm.eval/core-table*` cannot materialize `core/bit-not` as a function value (24737). This remains open. The final namespace source manifest accompanies the final calls and jank results.
