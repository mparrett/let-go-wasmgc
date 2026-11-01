# LLVM user-defined types

## Problem and evidence

The objective is complete jank compatibility and a pure Clojure numeric tower
built with deftype. The current driver/deftype-forms transforms fieldful types
into maps and fieldless types into keywords. ORC baseline 86941 proves wrong
map?/keyword?, equality, type, instance?, and generic get behavior; evidence is
in docs/benchmarks/jank-orc-2026-10-17-deftype. Native behavior comes from pinned
let-go e9789b7d53 pkg/vm/deftype.go, not the dirty sibling working copy.

Native DTypeInstance is a fresh identity object even with zero fields. It has
a DType pointer, field storage, metadata, identity equality/hash, and named
field access. with-meta creates a fresh instance sharing field storage.
Generic get does not expose fields. Printing defaults to #<Name field=value>.
Mutable fields and protocol implementations are required parts of user types,
not reasons to preserve the tagged-map approximation.

## Selected direction

Use a generic GC-traced UserInstance with a type reference, field storage,
metadata, and an allocation identity token stable across moving GC. A user
type is a real TypeVal with a descriptor for field names and mutability;
extend TypeVal with an optional descriptor reference, null for builtins.
Update both native runtime allocation and LLVM static TypeVal initializers
when changing that layout. Reuse TypeVal ancestry and protocol table slots.
The runtime kind of an instance must not imply a static builtin type ID:
type-of returns its descriptor's TypeVal directly. Builtin numeric fast paths
remain unchanged.

Compiler identities use existing namespace-qualified symbols plus field order,
not gensyms or process addresses. Runtime allocation tokens are separate from
compiler identities: they only supply stable identity hashing for instances.
Do not compare native and ORC hash numbers, which are inherently unrelated;
verify stability, equality laws, collision handling, and map-key behavior.

Alternatives considered: retaining tagged maps fails the observed semantics;
a distinct LLVM struct for every source type can optimize fixed field access
but complicates dynamic definitions and cache interfaces. Start with generic
instances and constant field indices, then specialize only with measurements.

## Compiler and runtime integration

- Generate a real type value and constructors in driver/deftype-forms for LLVM.
  Keep defrecord separate: records require associative semantics and structural
  equality, so they cannot silently become deftype instances.
- Preserve native source evaluation used for macro expansion and symbol
  resolution. Do not bind compiler-visible type vars to runtime-dialect arrays
  accidentally; distinguish compiler oracle objects from emitted initialization.
- Constructors allocate fresh instances. Field accesses in methods use constant
  slots; dot/.- access lowers through the core dot builtin with a runtime twin.
  Follow pinned arity, missing-field and mutable-field behavior.
- Dispatch protocol methods by type object identity. Fieldful and fieldless
  types use the same dispatch rule. Account for cross-namespace implementations,
  multiple arities, extension and type redefinition: an old instance must not
  acquire a new type merely because the source name was reused.
- Integrate type-name, printing, metadata, hash/equality, instance?, isa?, and
  collection predicates. User instances are not maps, callable maps, or seqs.
- Trace descriptors, fields, metadata, protocol closures and type roots through
  GC. Include schema/layout changes in runtime snapshots and durable caches.

## Delivery and proof

Implement in vertical steps: identity/construction and type integration;
fields/metadata/printing/hash; protocol dispatch and mutable fields; source
loading/redefinition and cache restoration. These are milestones within the
full requirement, not substitutes for it. Consolidate differential cases in
checks/fixtures/jank-reader/definitions.lg and runtime cases in existing groups.
Use check properties for retained instance versions, field updates and aliasing;
compare observable semantics to the pinned oracle and independent invariants.

Run actual jank users of types (reduce, num/number predicates and protocol
cases) after each relevant step. BigInt, Ratio and BigDecimal integration
remains separate required work; passing constructors alone does not implement
the numeric tower. Benchmark constructor/field/protocol costs after correctness,
including a small machine-integer workload to guard unrelated regressions.
