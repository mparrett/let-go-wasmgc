# Polymorphism and multimethods for --target llvm

Written 2026-10-08. Builds on `docs/LLVM-TARGET-SPEC.md` (step 10) and
replaces Task 10 of `docs/superpowers/plans/2026-10-07-llvm-target-m1.md`
("twins that reproduce native dispatch") as the design for deftype,
defrecord, defprotocol, reify, extend-*, defmulti and defmethod.

## Goals

- The shared driver stops refusing `defmulti`, `defmethod`, `deftype`,
  `defrecord`, `defprotocol`, `reify` and `extend-*` on every target.
- On the LLVM lane they work, with Clojure's semantics where Clojure and
  native let-go differ (listed under Divergences), and with dispatch fast
  enough that it does not matter on hot paths.
- The built-in generic operations (count, seq, first/next, nth, get, conj,
  assoc, hash, equiv, invoke, print) become protocol methods in the same
  per-type tables user protocols use, so one dispatch system serves runtime
  types and user types, and a deftype can act as a collection or a function.
- On the WasmGC lane the forms compile, and their defining natives raise a
  catchable placeholder error when they run.

## Non-goals (for now)

- Composition of protocols or traits (a protocol extended to "anything that
  satisfies P1 and P2", mixins). The design keeps room for it: protocol
  resolution is one resolver function, and C3 (below) is the intended order
  for composed method sources.
- Per-protocol epochs (a refinement if an epoch bump inside a hot loop ever
  shows up in a profile).
- The same mechanism on the WasmGC lane.

## 1. Types, type ids and method tables

- **Dispatch id = native type id.** Protocols extend on `(type x)`, and
  native's types are not the runtime's structs: a small vector and a map entry
  share ArrayVector's type, while `Err`, `List` and `Repeat` split by a field.
  So the dispatch id is the native type id that `llvm.core/type-id` computes
  today (0–41), with user types from 42 up. It is computed by a constant
  table from struct id to type id, plus a field test for the few structs that
  split; nil is 0, and a fixnum is Int's id.
- **Type objects.** Each native type, each abstract type and each program
  `deftype`/`defrecord`/`reify` type has a static global Type object. It
  extends today's interned `TypeVal` with its ancestry vector (section 3), a
  pointer to its method table, and that table's epoch. `@lg_types` maps type
  id to Type. `(type x)` returns the Type, unchanged in what it prints.
- **Abstract Types.** `Object`, `Coll`, `Map`, `Vector`, `Sequential`,
  `Associative`, `Counted` and so on (the interfaces section 2 names) are
  Type objects too, with no instances.
- **Types are values.** `(type x)` returns a Type object, which prints by
  name, compares by identity, and can be a hierarchy node.
- **Static deftype and defrecord.** Each top-level `deftype`/`defrecord` form
  (and each `reify` occurrence) is one struct type with a compile-time id in
  `ll-static-types`. A deftype has one field per declared field. A defrecord
  adds an extension map (for keys beyond its fields) and a meta field.
  Re-evaluating the form reuses the type.
- **Method tables.** A type's table is an array of Fn slots.
  - Tables the build prefills (section 2a) are static writable arrays. The
    collector scans their slots as roots (`lg_gc_tables`), since a run-time
    fill can store a heap closure there.
  - A type the build leaves empty gets a GC-heap table on its first dispatch.
  - A table grows (into the heap) on a miss past its length, after a newer
    protocol has added slots.
  - Each Type's table field is in `@lg_gc_globals`.

## 2. Protocols and slots

- **Protocol object.** Holds:
  - its name;
  - its methods (name, global slot number, arities);
  - an impl map, target → {method → Fn}, where a target is a Type, a
    hierarchy keyword or symbol, or nil;
  - a prefer map for `prefer-protocol`.
- **Method dispatchers.** Each method is a Var whose value is a dispatcher
  Fn, so protocol methods are first-class.
- **Slots.** One global slot per method, numbered when the protocol is
  defined; the method's Fn covers all its arities.
- **Built-in protocols.** Runtime protocols with fixed slots, Clojure's names:
  - `ICounted` (count), `ISeqable` (seq), `ISeq` (first, next, more);
  - `IIndexed` (nth), `ILookup` (get), `ICollection` (conj);
  - `IAssociative` (assoc, contains?), `IHash` (hash), `IEquiv` (equiv);
  - `IMeta`/`IWithMeta`, `IFn` (invoke 0–20, apply), `IPrint` (the writer
    behind str/pr/print).

  Each runtime type registers its implementations at startup; a vector's
  count slot is the existing `vcount`.
- **Registration.** `extend-type`, `extend-protocol`, `extend` and the
  inline methods of `deftype`/`defrecord`/`reify` each add [target method Fn]
  to the protocol's impl map and bump the epoch.
- **A protocol call:**
  1. dispatch id;
  2. table from `@lg_types[id]`;
  3. if the table's epoch is current and the slot is filled, call it through
     `lg_invoke<n>` with the receiver first;
  4. else resolve (section 3), fill the slot, call.
- **Queries.** `satisfies?` resolves (so it honors ancestry and the
  hierarchy) and reads the slot. `extends?` and `extenders` read the impl map.

## 2a. Resolution at build time

The program is compiled whole, so most of its polymorphism is known at build
time. The compiler does that work, and the run-time path is kept only for
what changes while the program runs.
- **Prefilled tables.** The build collects every top-level `deftype`/
  `defrecord`/`reify` method, every top-level `extend-type`/
  `extend-protocol`/`extend`, the runtime's built-in implementations and the
  top-level `derive`s. It runs the section 3 resolver over them for each
  (type, slot) a call site can reach, and emits the results as each table's
  initial contents at epoch 0. A program that only defines and extends at the
  top level never misses a table at run time.
- **Direct calls.** When type inference knows a protocol call's receiver
  type, the call is guarded by `epoch == 0` and goes straight to the
  prefilled implementation; otherwise it takes the table path. The guard is
  what keeps `eval`, a nested `extend`, `derive` and `defmethod` correct: any
  of them bumps the epoch, and the guarded calls fall back to the tables.
- **Build-time diagnostics.**
  - A C3 conflict is a compile error.
  - A tie the resolver finds while prefilling is a build warning naming the
    type, protocol and candidates. The slot is left empty, so the call still
    raises at run time, as Clojure does, rather than rejecting a program that
    may never make that call.
- **Shaking.** An implementation no prefilled slot and no run-time
  registration reaches is dropped.
- **Multimethods** stay run-time (their dispatch values are computed when
  called). Their caches start empty.

## 3. Ancestry, hierarchy, resolver, epoch

- **Fixed ancestry by C3.** Each type declares its direct supertypes in
  order: built-in types in the runtime's type table; a deftype the abstract
  Types of the built-in interfaces it implements inline, then Object
  (protocols are not supertypes). The compiler computes each type's C3
  linearization once and stores it as the Type's ancestry vector.
  - The order is deterministic, follows local declaration order, and is
    monotonic.
  - A declaration with no C3 order is a compile error naming the type and
    the conflicting supertypes.
- **Hierarchy (Clojure's).** A global hierarchy
  `{:parents :ancestors :descendants}`, with `:ancestors` kept transitive on
  every `derive`. Functions: `make-hierarchy`, `derive`, `underive`, `isa?`,
  `parents`, `ancestors` and `descendants`, each with an explicit-hierarchy
  arity. Nodes are keywords, symbols and Type objects.
- **`isa?`.**
  - true on equal values;
  - for Type objects, true when the parent is in the child's ancestry
    vector (class inheritance's role in Clojure);
  - true when the parent is in the child's hierarchy ancestors;
  - element-wise on vectors.

  `parents`/`ancestors` of a Type include its fixed ancestry and its
  hierarchy parents.
- **Resolver** for protocol P, method m, type T (nil's Type is Nil):
  1. an impl for T;
  2. T's ancestry vector in order: the first entry with an impl;
  3. T's hierarchy ancestors with an impl:
     - keep the most specific (drop any candidate another candidate `isa?`);
     - one left wins;
     - several are settled by `prefer-protocol`, else raise "Multiple
       implementations of protocol P method m for T: A, B" (catchable);
  4. an impl for Object, unless T is Nil (nil matches only impls extended to
     nil);
  5. none: the sentinel `none`.
- **Caching.** The resolver's result, `none` included, fills the slot. A
  dispatcher reading `none` raises native's "no implementation of protocol P
  method m for type T". A repeated miss and a repeated `satisfies?` on a
  non-implementing type therefore never walk the ancestry again.
- **Epoch.** One global counter, bumped by:
  - `extend*`, `derive`, `underive`, `prefer-protocol`;
  - `defmethod`, `remove-method`, `remove-all-methods`, `prefer-method`.

  A table with a stale epoch is cleared before its slot is filled.
  Multimethod caches check the same epoch. The runtime is single-threaded:
  no locks.

## 4. Multimethods

- **MultiFn object.** Holds:
  - name and dispatch Fn;
  - default dispatch value (`:default`, or the `:default` option);
  - hierarchy (a reference to a hierarchy var, the global one unless
    `:hierarchy` is given);
  - method map, dispatch value → Fn;
  - prefer map, value → set of values it is preferred over;
  - dispatch cache, dispatch value → Fn or `none`, stamped with the epoch.

  Its type implements `IFn`.
- **Clojure's lifecycle.**
  - Re-evaluating `defmulti` keeps the existing MultiFn and its methods.
  - `defmethod`, `remove-method`, `remove-all-methods` and `prefer-method`
    mutate it in place and bump the epoch.
- **A call:**
  1. apply the dispatch Fn to the args to get the dispatch value;
  2. if the cache's epoch is stale, clear the cache;
  3. if the value is cached, call its Fn (or raise on `none`);
  4. else resolve, store, call.
- **Resolver (Clojure's):**
  - an exact method wins;
  - else the candidates are the methods whose key the dispatch value `isa?`
    under the MultiFn's hierarchy;
  - drop dominated candidates;
  - if several remain, consult the prefers (transitive through ancestors);
  - an unsettled tie raises Clojure's "Multiple methods in multimethod 'f'
    match dispatch value: v -> a and b, and neither is preferred";
  - no candidate: the default method;
  - none: native's "no method in multimethod 'f' for dispatch value: v".
- **API.** `methods`, `get-method` (same resolution), `prefers`,
  `remove-method`, `remove-all-methods`, `prefer-method`.
- **Printing.** Runtime types print through their `IPrint` slot. A user type's
  Object `IPrint` uses a matching `print-method` method if one exists, else
  native's default form. `print-method` stays a multimethod on `type`; the
  built-ins never pay for multimethod dispatch.

## 5. Compiler, driver and runtime

- **Driver** (shared):
  - the refusals at `src/driver.lg:562` and `:852` and the head set at `:33`
    go;
  - a pre-pass collects each `deftype`/`defrecord`/`reify` form (`reify`'s
    captured locals become fields): name, fields, inline methods, implemented
    protocols and built-in interfaces;
  - it emits a static type declaration with its direct supertypes; C3 runs
    here.
- **Expansion.** Native's macros stay. They expand to `make-deftype`,
  `defprotocol*`, `extend-type*`, `defmulti*`, `defmethod*` and friends.
- **`rt/llvm/poly.lg`** (new): twins of those natives, plus the registry,
  resolver, hierarchy and multimethods.
  - The `make-deftype` twin returns the static Type.
  - The build-time pass of section 2a runs after the program and the runtime
    are analysed, before module emission.
  - `->T` and `map->T` allocate the static struct.
  - Inline methods compile as ordinary fns with `this` first; field reads are
    struct-field loads.
- **Fast path.** A new emitter intrinsic `arch/dispatch` (slot, argc) emits
  the section 2 sequence inline, with the resolver out of line.
  - The runtime's generic entry points (`count*`, `seq-of`, `nth`, `get-nf`,
    `equiv?`, `hash*`, `write-val`, invoke) use it.
  - `lg_invoke<n>` keeps its direct path for `$Fn`/`$FnV`/`$FnX`; any other
    callee goes to the `IFn` slot (replacing hook slot 5).
- **Staged migration** (corpora green at every step):
  1. Tables, protocols, resolver, hierarchy, multimethods, `poly.lg` and the
     user forms. Built-ins keep their chains, with `kind` as the Object
     fallback. This step alone gets the jank suite past its portability
     shim's `deftype`.
  2. Built-in protocols move one at a time: each runtime type's arm becomes
     a registered impl and leaves `kind`/`ckind`.
  3. `kind`, `ckind` and the hook tier (`seq.lg:80-198`) are deleted.
- **WasmGC lane.** It shares the driver pre-pass. `rt/wasm`'s twins of the
  defining natives raise a catchable "<form> is not supported on the WasmGC
  target" when they run. `rt/wasm` keeps its chains.

## 6. Testing

- **`corpus/poly/`** (oracle MATCH against native lg):
  - deftype fields, construction and inline methods;
  - defrecord as a map (equality, assoc past the fields, printing);
  - protocols on built-in types, nil and Object;
  - `satisfies?`/`extends?`;
  - the caught "no implementation" error;
  - multimethods by exact value and `:default`;
  - `corpus/examples/protocols.lg` comes off the SKIP list.
- **`corpus/poly-clj/`** (hand-written expected output, checked against JVM
  Clojure where the program is plain Clojure):
  - `isa?` dispatch through `derive`;
  - vector dispatch values;
  - `prefer-method`/`prefer-protocol` and the caught tie errors;
  - `derive` after a cached dispatch (the epoch);
  - protocol resolution through `derive`;
  - `defmethod` seen through an earlier reference;
  - C3 order across overlapping built-in interfaces.
- **`corpus/llvm-rt`** (native lg, as P12.23): C3 (with an inconsistent
  case), hierarchy operations, resolver dominance.
- **Compile error.** A deftype whose supertypes have no C3 order fails with
  the named error.
- **Collector.** Extend, derive and dispatch across many types under a small
  heap: the tables are traced and survive collection.
- **WasmGC.** Each defining form raises the placeholder error, caught, and
  the program continues.
- **Gates at every migration step:** P12.3, P12.20, P12.21, P12.23,
  `corpus/scalar`, `corpus/seqs`, `corpus/wasm`.
- **Prefill.** A program that defines and extends only at the top level
  records zero table misses (`llvm.poly/miss-count`); one that extends inside
  a fn records misses only after that call; a guarded direct call switches to
  the new implementation after a run-time `extend` changes it.
- **Build warning.** A top-level tie prints the warning at build time and
  raises the tie error when called.
- **Speed.** A microbenchmark of count, seq, nth, get and = over vectors,
  maps and strings, run before step 2 and after step 3: no more than 10%
  regression in built-in time.
- **Jank suite.** Step 1 takes the LLVM lane off 0/242. Every file still
  failing gets a named cause.

## Divergences from native let-go (each a DECISIONS entry)

1. Multimethods dispatch by `isa?` over a hierarchy (element-wise on
   vectors), with `prefer-method`; native matches the dispatch value exactly.
2. Protocol resolution consults the fixed ancestry and the `derive`
   hierarchy, with `prefer-protocol`; native looks up the exact type, then
   Object.
3. One static type per `deftype`/`defrecord` form; native creates a new
   record type on each evaluation (visible only on redefinition).
4. `defmethod` mutates the MultiFn in place (Clojure); native rebinds the
   var to a new MultiFn, so earlier references miss later methods.
5. C3 linearization orders the fixed ancestry, and is the intended rule for
   protocol/trait composition.
6. On the WasmGC lane the forms compile to placeholders that raise when run.
