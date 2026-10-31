# `--target llvm` Polymorphism and Multimethods Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** deftype, defrecord, reify, defprotocol, extend-*, defmulti and
defmethod compile on every target; on `--target llvm` they run with per-type
method tables, C3 ancestry, a Clojure hierarchy and `isa?` multimethods, and
the built-in generic ops dispatch through the same tables.

**Architecture:**
- **Driver.** The shared driver stops refusing these forms. On the llvm lane
  it expands deftype/defrecord/reify itself into an `arch/defstruct`, a
  constructor and a Type registration, so every user type is a static struct
  with a compile-time id.
- **Runtime.** A new runtime namespace, `llvm.poly` (`rt/llvm/poly.lg`), holds:
  - Type objects;
  - the slot registry and method tables (slots of `@lg_types` entries);
  - the resolver and the epoch;
  - the hierarchy;
  - protocols and multimethods.
- **Fast path.** An `arch/dispatch` intrinsic emits the table lookup inline.
- **Build time.** A build-time pass prefills the tables from the program's top-level definitions and emits guarded direct calls where the receiver's type is known (spec §2a).
- **WasmGC.** The lane gets placeholder twins that raise when run.

**Tech Stack:** let-go (pinned lg ff1e6dac), Homebrew LLVM 23, bash; JVM
Clojure (`/opt/homebrew/bin/clojure`) to check `corpus/poly-clj` expectations.

**Spec:** `docs/superpowers/specs/2026-10-08-llvm-polymorphism-design.md`
(sections §1–§6, divergences V1–V6). Builds on
`docs/superpowers/plans/2026-10-07-llvm-target-m1.md` (its Global Constraints
apply) and replaces that plan's Task 10.

## Global Constraints

- **Run env:** `LW_ROOT=$HOME/development LETGO=$HOME/development/let-go LG=<pinned lg ff1e6dac>`; corpus runs use `LW_PAR=1`.
- **Driver load path:** code on it takes no gensyms. In `src/driver.lg`, `src/lower_wasm.lg` and `src/lw_rt.lg`: no destructuring `let`/`fn` params, no `for`, no auto-gensym.
- **Runtime names:** the compiler names runtime vars only through `lw-rt` (`rt-ns`, `rt-sym`, `rt-var`; D213), never a literal `llvm.*`/`wasm.*` var.
- **New runtime files:** each gets a row in its lane's README load-order table (`rt/llvm/README.md`, `rt/wasm/README.md`), and the README's namespace count is updated.
- **Twins:** a twin is a runtime defn with `^{:twin "core/<name>"}` meta (`src/lw_rt.lg:208`).
- **Intrinsics:** a new one is a `^{:intrinsic true}` defn in `rt/llvm/arch.lg`, plus a `case` arm in `ll-intrinsic!` (`src/lower_llvm_rt.lg:266`), plus an entry in `ll-emitted-intrinsics` (`:609`).
- **Error texts** (exact, all catchable):
  - `no implementation of protocol P method m for type T` (native);
  - `no method in multimethod 'f' for dispatch value: v` (native);
  - `Multiple methods in multimethod 'f' match dispatch value: v -> a and b, and neither is preferred` (Clojure);
  - `Multiple implementations of protocol P method m for T: A, B`;
  - `<form> is not supported on the WasmGC target` (`<form>` is `deftype`, `defrecord`, `reify`, `defprotocol`, `extend-type`, `extend-protocol`, `defmulti` or `defmethod`).
- **C3 failure** is a compile error: `lower-llvm: no C3 order for T: supertypes S1, S2 conflict`.
- **Commit messages** cite no commit hashes.
- **Gate rows** for this plan are P12.30 onward in `checks/items.tsv`, each with a `checks/affected.sh` line.
- **Divergences:** each from the spec's list gets a DECISIONS.md entry in the task that implements it, numbered after the file's last entry.
- **Gates before every commit:** a task touching `src/driver.lg`, `src/lower_wasm.lg`, `src/lw_rt.lg` or `rt/wasm/` ends with the GC lane's `corpus/scalar corpus/seqs corpus/wasm` and P7.0. Every task ends with P12.3, P12.20, P12.21 and P12.23 and the llvm lane's `corpus/scalar corpus/seqs corpus/wasm`.
- **Expected-output corpora:** `corpus/poly-clj` programs are compared to a `<prog>.out` file, not to native lg. They use `checks/run-expected.sh` (Task 1).

## Review Focus

1. **A protocol extended after the first call on that type** (extend-type
   inside a fn, called mid-loop): later calls see the new impl and earlier
   cached slots never leak. Test: Task 4, `corpus/poly-clj/extend-late.lg`.
2. **A defrecord used as a map**: `assoc` of a non-field key, `dissoc` of a
   field (native returns a plain map), `=` against a map with the same entries
   (false: different type), `(get r :f)`, `keys`, `seq`, `count`, `hash`
   consistent with `=`. Test: Task 5, `corpus/poly/record-map.lg`.
3. **A multimethod whose dispatch fn throws, and one dispatching on nil**
   (`(f nil)` with a `nil` method and with only `:default`): the throw reaches
   the caller's handler; nil dispatch picks the nil method. Test: Task 7,
   `corpus/poly/multi-edge.lg`.
4. **A collection triggering GC with method tables live**: tables allocated
   lazily during a collection-heavy loop over 20 deftypes survive and stay
   correct. Test: Task 4, `corpus/llvm/gc-poly.lg` under `LG_HEAP_BYTES=8388608`.
5. **`(type x)` and `(instance? T x)` for every built-in kind and nil**, and
   `str`/`pr-str` of a Type, match native (`let-go.lang.Type` names). Test:
   Task 2, `corpus/poly/types.lg`.

---

### Task 1: The driver accepts the forms; WasmGC placeholders; the expected-output runner

**Files:**
- Modify: `src/driver.lg:33`, `:562`, `:852`.
- Create: `rt/wasm/poly.lg`, `checks/run-expected.sh`, `corpus/poly-wasm/placeholders.lg`, `corpus/poly-wasm/placeholders.lg.out`.
- Modify: `rt/wasm/README.md`, `checks/items.tsv` (P12.30), `checks/affected.sh`, `DECISIONS.md` (V6).

**Interfaces:**
- Produces: `(checks/run-expected.sh <dir>...)`. For each `*.lg` in a dir it runs `$WASM_RUN` (default `checks/wasm-run.sh`) and compares stdout and the exit status to `<prog>.out`, whose last line is `exit <n>`. It prints `MATCH`/`DIFF <prog>` and a `k/n MATCH` total, and exits 1 on any DIFF.
- Produces: in `wasm.poly`, twins of `core/defprotocol*`, `extend-type*`, `make-protocol-fn`, `make-deftype`, `make-deftype-instance`, `make-record-type`, `make-record`, `defmulti*`, `defmethod*` and `satisfies?`. Each raises the placeholder text naming the user-facing form.

- [ ] **Step 1: Write the test program.** `corpus/poly-wasm/placeholders.lg`: for each of `deftype`, `defrecord`, `defprotocol`, `extend-type`, `defmulti` and `defmethod`, a top-level form inside `(try ... (catch Exception e (println (ex-message e))))`, then `(println "alive")`. `.out` holds the eight-plus lines `deftype is not supported on the WasmGC target` … `alive`, then `exit 0`.
- [ ] **Step 2: Write `checks/run-expected.sh`; run it on the test.** `checks/run-expected.sh corpus/poly-wasm`. Expected: compile failure `lower-wasm: unsupported top-level form deftype` → `DIFF`.
- [ ] **Step 3: Lift the refusals.** Remove `defmulti deftype defprotocol defrecord` from the refusal at `:562` and `:852`, keeping them in `top-level-heads` so `macro-do-expansion` still stops at them. Lower them through the `:else` branch as ordinary forms.
- [ ] **Step 4: Write `rt/wasm/poly.lg` with the placeholder twins; add its README row.**
- [ ] **Step 5: Run the test.** `checks/run-expected.sh corpus/poly-wasm`. Expected: `1/1 MATCH`.
- [ ] **Step 6: Add P12.30 and its `affected.sh` line, the V6 DECISIONS entry, and the gates; commit** "driver: deftype, defrecord, defprotocol, defmulti compile on every target; WasmGC placeholders".

### Task 2: Type objects, dispatch ids and C3 ancestry

**Files:**
- Create: `rt/llvm/poly.lg` (Type part), `src/lower_llvm_poly.lg` (C3 and the type table), `corpus/llvm-rt/c3_test.lg`, `corpus/poly/types.lg`.
- Modify: `rt/llvm/core.lg` (`type-of`, `type-name`, TypeVal at `:46`/`:148`/`:198`), `rt/llvm/README.md`, `src/lower_llvm_rt.lg` (`ll-static-types` `:20`), `src/lower_llvm.lg` (module globals).

**Interfaces:**
- Produces: `(c3 type supers-of) -> vector`, in `lower_llvm_poly.lg`. `supers-of` maps a type name to its ordered direct supertypes. The result is the type followed by its linearization. It throws the C3 text on conflict.
- Produces: `TypeVal` (`rt/llvm/core.lg:46`) extended to `[:ref :i64 :ref [:mut :ref] [:mut :i64]]`, with fields name Bytes, type id, ancestry PVec of Types (nearest first, excluding self), table (an array of slots, or nil), and table epoch. The spec's Type object is this struct.
- Produces: the dispatch id is the native type id (spec §1), not the struct's header id: `llvm.core/type-id`'s numbering (0–41), with abstract types and user types after it.
  - It is computed as `(llvm.poly/dispatch-id x) -> i64`: a constant table from struct id to type id, plus `type-id`'s field tests for the structs that split (`PVec` by `vpkind`, `Err`, `List`, `TypeVal`/Repeat, MetaNamed).
  - Tests check it against `type-id` for every kind.
- Produces: `@lg_types`, the Type objects as static globals indexed by type id, replacing `Globals` field 1's 42-slot node. Abstract Types (`Object`, `Coll`, `Sequential`, `Associative`, `Counted`, `Indexed`, `Seqable`, `Seq`, `Map`, `Set`, `Vector`, `List`, `Fn`, `Named`, `Number`) take ids after the native ones. `(llvm.poly/type-of-id id) -> Type`.
- Produces: the runtime's supertype table in `lower_llvm_poly.lg`, `ll-builtin-supers`, a map from runtime struct name to its ordered abstract supers. For example, `"$PVec"` maps to `["Vector" "Associative" "Indexed" "Counted" "Sequential" "Coll" "Object"]`.

- [ ] **Step 1: Write `corpus/llvm-rt/c3_test.lg`.** Deftests:
  - `c3-diamond`: `{:A [:B :C] :B [:D] :C [:D] :D []}` gives `[:A :B :C :D]`;
  - `c3-python-classic`: the O/A/B/C/D/E/K1/K2/K3/Z example gives `[:Z :K1 :K2 :K3 :D :A :B :C :E :O]`;
  - `c3-conflict`: `{:X [:A :B] :Y [:B :A] :Z [:X :Y]}` throws the C3 text naming Z.

  Expected: FAIL (no `c3`).
- [ ] **Step 2: Implement `c3`.** Run `TEST_DIR=corpus/llvm-rt checks/run-intrinsics-native.sh`. Expected: PASS.
- [ ] **Step 3: Write `corpus/poly/types.lg`.** For nil, 1, 1.5, a big int, "s", \c, :k, 'k, a list, a vector, a map, a set, a lazy seq, a fn, an atom and a Type, print `(type x)` and `(str (type x))`. Print `(instance? T x)` for matching and non-matching pairs. Print `(= (type 1) (type 2))`.

  Run `WASM_RUN=checks/native-run.sh checks/run-corpus.sh corpus/poly`. Expected: MISMATCH or compile error.
- [ ] **Step 4: Emit the Type objects and `@lg_types`, and run C3 per type at module build.** Make `type-of` return the Type for the value's dispatch id, keeping native's printed names. Twin `core/instance?`: the id is equal, or the type is in the ancestry.
- [ ] **Step 5: Run `corpus/poly/types.lg`.** Expected: MATCH.
- [ ] **Step 6: Add P12.31 (`corpus/poly` on llvm) and the V5 DECISIONS entry (with the native-type-id dispatch); run the gates; commit** "llvm target: Type objects, dispatch ids, C3 ancestry".

### Task 3: The hierarchy

**Files:**
- Modify: `rt/llvm/poly.lg` (hierarchy part).
- Create: `corpus/poly/hierarchy.lg` (keywords only, oracle), `corpus/poly-clj/hierarchy-types.lg` and `.out`, `corpus/llvm-rt/hierarchy_test.lg`.

**Interfaces:**
- Produces twins of `core/make-hierarchy`, `derive` (2 and 3 args), `underive`, `isa?` (2 and 3), `parents`, `ancestors`, `descendants` (1 and 2) and `register-type-parent!`.
  - The global hierarchy is a runtime global map `{:parents :ancestors :descendants}`, with `:ancestors` and `:descendants` kept transitive.
  - `derive`/`underive` bump the epoch.
- Produces: `(llvm.poly/epoch) -> i64` and `(llvm.poly/bump-epoch!)`.
- `isa?` semantics are the spec's §3: equality; then the Type ancestry; then the hierarchy ancestors; element-wise on equal-length vectors.

- [ ] **Step 1: Write the tests.**
  - `hierarchy.lg` prints `isa?`, `parents`, `ancestors` and `descendants` over a keyword diamond, before and after `underive`, and with an explicit `(make-hierarchy)`.
  - `hierarchy-types.lg` covers `(derive (type []) ::coll-like)`, `(isa? (type []) ::coll-like)`, `(isa? (type []) Object-type)` through ancestry, and `(isa? [::a ::b] [::p ::q])` element-wise. Its `.out` is checked with JVM Clojure, using `clojure.lang.PersistentVector` in place of `(type [])`.

  Run both corpora. Expected: FAIL (no twins).
- [ ] **Step 2: Implement the hierarchy and the epoch; run the tests.** Expected: `corpus/poly` MATCH, `checks/run-expected.sh corpus/poly-clj` MATCH, and llvm-rt PASS.
- [ ] **Step 3: Add P12.32 (`checks/run-expected.sh corpus/poly-clj` with `WASM_RUN=checks/native-run.sh`); run the gates; commit** "llvm target: the hierarchy (derive, isa?, types as nodes)".

### Task 4: Protocols, method tables, the resolver, `arch/dispatch`

**Files:**
- Modify: `rt/llvm/poly.lg` (protocols), `rt/llvm/arch.lg` (`dispatch`), `src/lower_llvm_rt.lg` (`ll-intrinsic!` arm, `ll-emitted-intrinsics`), `src/lower_llvm.lg` (`@lg_gc_globals` gets each Type's table field), `host/native/gc.c` (`lg_gc_tables`: static tables' slots scanned as roots, used from Task 6).
- Create:
  - oracle programs `corpus/poly/protocol.lg`, `corpus/poly/protocol-builtin.lg`;
  - expected-output programs `corpus/poly-clj/extend-late.lg`, `corpus/poly-clj/protocol-hierarchy.lg`, `corpus/poly-clj/prefer-protocol.lg`;
  - `corpus/llvm/gc-poly.lg`.

**Interfaces:**
- Produces: `(arch/defstruct Protocol [:ref :ref :ref :ref])`, with fields name Bytes, methods (a vector of `{:name :slot}`), impls (a map from target to a map from method keyword to Fn), and prefers (a map). `none` is a unique runtime sentinel object.
- Produces twins of:
  - `core/defprotocol*` (name, method syms), which assigns slots from the global slot counter;
  - `extend-type*` (protocol, target, impl map), where a target is a Type, a keyword or symbol, or nil, and which bumps the epoch;
  - `make-protocol-fn` (protocol, sym), which returns a dispatcher Fn of any arity;
  - `satisfies?`, `extends?` and `extenders`;
  - `prefer-protocol` (protocol, a, b), a new var in core's namespace on llvm only.
- Produces: `(llvm.poly/resolve proto slot type) -> Fn | none`, which follows spec §3 steps 1–5. It is written over plain data (impl maps, ancestry vectors, the hierarchy map), so Task 6's build-time pass can run the same function under native lg.
- Produces: `llvm.poly/miss-count`, a runtime counter of table misses, read by `(llvm.poly/misses)`.
- Produces: `(arch/dispatch slot argc recv & args)`. It emits:
  1. the id;
  2. the table load from `@lg_types[id]`;
  3. the epoch compare;
  4. the slot load;
  5. on a miss (or `none`), a call to `llvm.poly/dispatch-miss` (slot, recv), which returns the Fn or raises;
  6. `lg_invoke<argc+1>` on the Fn.

- [ ] **Step 1: Write the tests.**
  - `protocol.lg` (oracle): a protocol extended to `(type {})`, to `nil`, and through `extend-protocol` over `(type 0)`, `(type "")` and `(type true)`; `satisfies?` both ways; a caught "no implementation" error; protocol fns passed to `map`.
  - `protocol-builtin.lg`: `corpus/examples/protocols.lg`'s protocol half.
  - The `poly-clj` programs:
    - `extend-late` calls `(p x)` in a loop that extends P to `x`'s type at iteration 3. It prints the caught error at 1–2 and the impl result from 3 on.
    - `protocol-hierarchy`: `(derive ::rec-like ::shape)`, `(derive RecType ::shape)`, P extended to `::shape`. A call on a RecType resolves through `derive`. Then `derive` to a second parent with its own impl: a caught tie error. After `prefer-protocol`, the preferred impl.
    - `prefer-protocol`: ancestry before hierarchy, e.g. P on `Coll` and on a derived keyword parent of `(type [])` gives the `Coll` impl.
  - `gc-poly.lg`: 20 `deftype`s, each extending one protocol, dispatched over a 200k-iteration loop allocating vectors. It prints a checksum. Run it with `LG_HEAP_BYTES=8388608`.

  Run all of them. Expected: FAIL.
- [ ] **Step 2: Implement the protocol registry, `resolve`, `dispatch-miss`, the tables (lazy, grown, cleared on a stale epoch, holding `none`) and the dispatcher Fns.**
- [ ] **Step 3: Implement the `arch/dispatch` intrinsic and route dispatcher Fns through it; run the tests.** Expected: MATCH everywhere; `gc-poly` matches native lg.
- [ ] **Step 4: Add the V2 DECISIONS entry; take `protocols.lg` off `corpus/examples/SKIP` if its multimethod half also passes after Task 7 (note it there); run the gates; commit** "llvm target: protocols through per-type method tables".

### Task 5: deftype, defrecord, reify as static types

**Files:**
- Modify: `src/driver.lg` (the llvm-lane expansion, at the `process!` cond `:811-863` and `index!` `:562`), `rt/llvm/poly.lg` (`register-type!` and record helpers).
- Create: `src/lower_llvm_types.lg` (the expansion, loaded by the llvm lane only), `corpus/poly/deftype.lg`, `corpus/poly/defrecord.lg`, `corpus/poly/record-map.lg`, `corpus/poly/reify.lg`.

**Interfaces:**
- Consumes: `arch/defstruct` program decls (`driver.lg:369`, `:821`, `:917`), `c3`, the Type table, and `extend-type*`.
- Produces the expansions:
  - `(deftype T [f..] P (m [this a] body)..)` becomes `(do (arch/defstruct T [:ref..]) (def T (llvm.poly/register-type! T "T" [<interface names>])) (defn ->T [f..] (arch/new T f..)) (extend-type* P T {:m (fn [this a] body')})..)`. In `body'`, a field `f` becomes `(arch/get T i this)`. A `^:mutable` field under `set!` becomes `(arch/set! T i this v)`.
  - `defrecord` is the same, with two extra fields (the extmap and meta). It adds `map->R`, and its impls of `ILookup`, `IAssociative`, `ICounted`, `ISeqable`, `IEquiv`, `IHash` and `IPrint` are generated in `llvm.poly` as record helpers taking the field keyword vector.
  - `reify` gets one type `reify__<form-index>`. Its captured locals become fields, and the form becomes `(->reify__N locals..)`.
- `register-type!` returns the Type for the struct's static id and records its interfaces for C3.
- Native's printed forms: `#<T f=v ...>` for a deftype and `#R{:f v}` for a record (check against native lg).

- [ ] **Step 1: Write the tests.**
  - `deftype.lg`: fields, `->T`, an inline protocol method using fields, `^:mutable` with `set!`, `(type x)` and `instance?`, printing, identity equality.
  - `defrecord.lg`: `->R`, `map->R`, field access by keyword, an inline method, printing.
  - `record-map.lg`: Review Focus 2.
  - `reify.lg`: `reify` of a protocol capturing a local, and `Object`'s `toString` through `str`.
  - `checks/llvm-c3-error-check.sh`: compiles a deftype whose implemented interfaces have no C3 order and expects exit 1 with `lower-llvm: no C3 order for` in the log (P12.36).

  Run the oracle on llvm. Expected: FAIL.
- [ ] **Step 2: Implement the expansion and the record helpers; run the tests.** Expected: MATCH.
- [ ] **Step 3: Add the V3 DECISIONS entry; run the gates (driver touched); commit** "llvm target: deftype, defrecord, reify as static types".

### Task 6: Build-time resolution: prefilled tables, guarded direct calls, build warnings

**Files:**
- Create: `src/lower_llvm_prefill.lg` (the build-time pass).
- Modify: `src/lower_llvm.lg` (emits the tables as static writable arrays, `lg_gc_tables`, and the direct-call guard at protocol call sites with a known receiver type), `src/lower_llvm_rt.lg` (`arch/dispatch` lowering), `host/native/gc.c`.
- Create: `corpus/poly/prefill.lg`, `corpus/poly-clj/prefill-runtime-extend.lg`, `corpus/poly-clj/prefill-direct.lg`, `checks/llvm-prefill-warn-check.sh`.

**Interfaces:**
- Consumes: Task 4's `resolve` (run under native lg over the build's data), Task 3's hierarchy, Task 5's static types, and the top-level `extend-type*`/`deftype` registrations the driver collected.
- Produces: `(ll-prefill program-facts) -> {[type-id slot] fn-var}`, where `program-facts` holds:
  - `:impls`, a map from protocol to a map from target to a map from method to fn var;
  - `:derives`, a sequence of `[child parent]` from top-level `derive`s;
  - `:reachable`, the set of `[type-id slot]` pairs call sites can reach;
  - each type's C3 ancestry.

  A tie yields no entry and a build warning on stderr: `lower-llvm: warning: protocol P method m for T: multiple implementations A, B`.
- Tables start at epoch 0. A run-time `extend*`/`derive`/`underive`/`prefer-protocol` bumps the global epoch to ≥ 1.
- A direct call is emitted as `epoch == 0 ? call impl : table path` when inference gives the receiver's type.

- [ ] **Step 1: Write the tests.**
  - `prefill.lg` (oracle, plus a check): top-level deftypes and `extend-protocol` over built-in types, called in a loop. At the end it prints `(llvm.poly/misses)` under a reader conditional that native lg skips. Run through `checks/run-expected.sh` with the expected count `0`.
  - `prefill-runtime-extend`: a protocol extended to a type inside a fn called mid-loop. Misses are 0 before that call and positive after it, and the results switch to the new impl.
  - `prefill-direct`: a call on a receiver whose type inference knows, before and after a run-time `extend` that replaces its implementation, prints the old then the new result.
  - `checks/llvm-prefill-warn-check.sh`: compiles a program with a top-level tie. It expects the warning in the build log and the tie error, caught, at run time.

  Expected: FAIL.
- [ ] **Step 2: Implement `ll-prefill` and the table emission (static arrays, `lg_gc_tables` scanned by `lg_gc`); run `prefill.lg` and `gc-poly.lg`.** Expected: misses 0; `gc-poly` still MATCH under the small heap.
- [ ] **Step 3: Implement the guarded direct calls and the warning; run the rest.** Expected: MATCH, warn-check exit 0.
- [ ] **Step 4: Add P12.35 (the prefill corpora and the warn check); run the gates; commit** "llvm target: protocol tables prefilled at build time, guarded direct calls".

### Task 7: Multimethods

**Files:**
- Modify: `rt/llvm/poly.lg` (multimethods).
- Create:
  - oracle programs `corpus/poly/multimethod.lg`, `corpus/poly/multi-edge.lg`;
  - expected-output programs `corpus/poly-clj/multi-isa.lg`, `corpus/poly-clj/multi-vector.lg`, `corpus/poly-clj/multi-prefer.lg`, `corpus/poly-clj/multi-inplace.lg`.

**Interfaces:**
- Produces: `(arch/defstruct MultiFn [:ref :ref :ref :ref :ref :ref :ref :i64])`, with fields name, dispatch Fn, default value, hierarchy var (or nil for global), methods map, prefers map, cache map, and cache epoch. Its type implements `IFn` through `extend-type*` at startup.
- Produces twins of:
  - `core/defmulti*` (name, dispatch Fn, default): keeps an existing MultiFn when the var is already bound to one;
  - `defmethod*` (mf, value, Fn): mutates in place, bumps the epoch, returns mf, so native's `(set! name ...)` expansion still works;
  - `remove-method`, `remove-all-methods`, `prefer-method`, `prefers`, `methods` and `get-method`.

  The `:hierarchy` option is read from the `defmulti` form by the llvm expansion in `src/lower_llvm_types.lg`, since native's macro drops it.
- Produces the resolver per spec §4. Its cache maps a dispatch value to an Fn or `none`, and is cleared on a stale epoch.

- [ ] **Step 1: Write the tests.**
  - `multimethod.lg` (oracle): exact dispatch on keywords, numbers and vectors; `:default`; a caught "no method" error; `methods`; `remove-method`.
  - `multi-edge.lg`: Review Focus 3.
  - `multi-isa`: `derive` chains, with the method on the ancestor chosen; dominance picks the most specific.
  - `multi-vector`: `[::circle ::square]` against `[::shape ::shape]`.
  - `multi-prefer`: a tie caught with Clojure's text, then resolved by `prefer-method`.
  - `multi-inplace`: a MultiFn captured in a closure before a `defmethod` sees the new method.

  Check the `poly-clj` `.out` files with JVM Clojure. Run. Expected: FAIL.
- [ ] **Step 2: Implement; run the tests.** Expected: MATCH. Take `corpus/examples/protocols.lg` off SKIP and confirm it MATCHes.
- [ ] **Step 3: Add the V1 and V4 DECISIONS entries; run the gates; commit** "llvm target: isa? multimethods with prefer-method and a dispatch cache".

### Task 8: Built-in protocols, part 1: printing and invoke

**Files:**
- Modify: `rt/llvm/poly.lg` (the built-in protocols `IPrint` and `IFn` at fixed slots 0 and 1), `rt/llvm/str.lg` (`write-val` `:537`), `rt/llvm/seq.lg` (invoke0/1/2 `:138`, hook slot 5), `src/lower_llvm.lg` (`lg_invoke<n>` fallback `:1407`).
- Create: `corpus/poly/print-method.lg`, `corpus/poly/ifn-type.lg`.

**Interfaces:**
- Built-in protocol slots are fixed, in this order: `IPrint` 0, `IFn` 1, `ICounted` 2, `ISeqable` 3, `ISeq` 4 (first), 5 (next), 6 (more), `IIndexed` 7, `ILookup` 8, `ICollection` 9, `IAssociative` 10 (assoc), 11 (contains?), `IHash` 12, `IEquiv` 13, `IMeta` 14, `IWithMeta` 15. User protocols start at 16.
- `write-val` dispatches slot 0 for every value whose kind is foreign. Object's `IPrint` consults `print-method`'s MultiFn, then falls back to native's default form.
- `lg_invoke<n>`'s path for a value that isn't an Fn tail-calls slot 1 instead of `invoke-args`'s hook.

- [ ] **Step 1: Write the tests.**
  - `print-method.lg`: `(defmethod print-method RecType ...)` used by `pr-str`, `str` and `println`.
  - `ifn-type.lg`: a deftype implementing `IFn`'s invoke called as a function, passed to `map`, and used with `apply` on 6 args.

  Expected: FAIL.
- [ ] **Step 2: Implement; run the tests.** Expected: MATCH.
- [ ] **Step 3: Run the gates; commit** "llvm target: printing and invoke through built-in protocols".

### Task 9: Built-in protocols, part 2: collections, then retire the kind chains

**Files:**
- Modify:
  - `rt/llvm/seq.lg`: `count*` `:666`, `seq-of` `:462`, `s-first`/`s-next`/`s-more` `:555`, `nth` `:726`, `conj` `:769`, `equiv?` `:1048`, `hash*` `:1188`, and `kind` `:219`;
  - `rt/llvm/core.lg`: `get-nf` `:660`, `ckind` `:69`, `type-name` `:148`;
  - `rt/llvm/poly.lg`: registrations.
- Create: `corpus/poly/collection-type.lg`, `checks/llvm-dispatch-bench.sh`, `corpus/perf/dispatch-bench.lg`.

**Interfaces:**
- Each runtime type registers its existing arm's code as its impl of slots 2–15 at startup (`llvm.poly/install-builtins!`, called from `llvm.core/install!`).
- The generic entry point becomes `(arch/dispatch <slot> ...)`, with the old arm left as Object's impl until step 4.
- `checks/llvm-dispatch-bench.sh` prints ns/op for count, seq, nth, get and = over a vector, a map and a string, and exits 1 when any regresses by more than 10% against the numbers in `corpus/perf/dispatch-bench.baseline`.

- [ ] **Step 1: Capture the baseline before any change.** Run `checks/llvm-dispatch-bench.sh --capture`, which writes the baseline file. Commit it with the script.
- [ ] **Step 2: Write `collection-type.lg`.** A deftype implementing `ICounted`, `ISeqable`, `ISeq`, `IIndexed` and `ILookup`, used with `count`, `seq`, `map`, `reduce`, `nth`, `get`, `into` and destructuring. Expected: FAIL.
- [ ] **Step 3: Move the protocols one at a time.** For each of `ICounted`, `ISeqable`/`ISeq`, `IIndexed`, `ILookup`, `ICollection`/`IAssociative`, `IHash`/`IEquiv` and `IMeta`/`IWithMeta`: register the impls, switch its entry point to `arch/dispatch`, run the llvm corpora and P12.23, and commit "llvm runtime: <protocol> through the method table".
- [ ] **Step 4: Delete `kind`, `ckind` and the hook tier** (`seq.lg:80-198`, `set-kind-hooks!`). Each caller that remains either dispatches or tests one type with `arch/is?`. Expected: the llvm corpora, `corpus/poly` and `poly-clj`, and P12.23 all pass; `grep -n "(kind\|(sq/kind\|ckind" rt/llvm` prints nothing.
- [ ] **Step 4b: Prefill the built-in slots.** Task 6's pass includes the runtime's registrations from `install-builtins!` as build-time facts. Expected: `prefill.lg`'s misses stay 0 with built-in calls in its loop.
- [ ] **Step 5: Run `checks/llvm-dispatch-bench.sh`.** Expected: exit 0 (no regression over 10%).
- [ ] **Step 6: Add P12.33 (the bench) and P12.34 (`collection-type`); run the gates; commit** "llvm runtime: the kind chains are gone; built-ins dispatch through method tables".

### Task 10: The jank suite past the shim

**Files:** `corpus/jank/baseline.tsv`, `STATUS.md`.

- [ ] **Step 1: Run** `WASM_RUN=checks/native-run.sh checks/jank-suite.sh`. Expected: more than 0/242 files agree, and every file still failing has a first-error line.
- [ ] **Step 2: Group the failures by cause** in STATUS.md (polymorphism causes are fixed here; others are listed for the M1 plan's Task 11). Update the baseline; commit "jank suite: the llvm lane past the portability shim".
