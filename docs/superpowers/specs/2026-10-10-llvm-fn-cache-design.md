# The llvm target's function cache: one entry per lowered function, written as it is lowered

Written 2026-10-10. It extends D221 (the runtime compile cache) and covers
its part 3 (partial invalidation). It applies to `--target llvm` only. The
GC and linear lanes keep D181's snapshot unchanged.

## Why

An llvm compile of xsofy's world dump takes about 76 s, and native lg
loads the same program in 0.45 s. The runtime comes from the D221 snapshot
(warm, about 3 s). Nearly all of the rest is analysis and lowering of about
1,037 functions that no cache holds: xsofy's own namespaces (793 `defn`
forms in the checkout) and the let-go stdlib namespaces it reaches (set,
walk and others), with their closures. That work is redone on every compile,
even when nothing changed. An edit to one runtime file also rebuilds the
whole runtime library (a cold build takes about 140 s).

## The constraint that shapes it

let-go, like Clojure, is a meta-circular live coding environment. A namespace is not a fixed unit that is read and then compiled: its forms are expanded and evaluated
one at a time. A macro defined on line 40 changes what line 41 means. A
top-level form can run code that registers templates or defines vars, and a
later form can redefine a var or a macro. So the cache cannot key a
namespace by its text, or build it in a batch after loading. It is
populated as compilation goes, one function at a time, and an entry is
replaced when a redefinition changes what a function is.

## Where this is going

The longer aim is let-go compiled in let-go, a JIT behind a live REPL and
image (the llvm spec's M5), and, given a top level, a tree shake that
drops whatever the program does not reach, the REPL and the compiler
services included. This cache is the first compiler service built with
that in mind. An in-image compiler needs the same thing it does: lowering
one function at a time, as forms are evaluated, and redoing exactly what a
redefinition invalidates. So the cache must work in an image, not only in
the AOT driver:
- **The core has no files and no driver in it.** The keys, traces,
  entries, verification and invalidation live in `lower-llvm-cache`
  (with the funnel). Storage is a protocol with two implementations, which
  are the core's only side effects:
  - the file store below, for the AOT driver;
  - an in-memory map, for an image or a test.
- **Entries are data an in-image JIT can take.** Units are D225 items,
  not text with meaning only to the driver. Handing an entry's items to
  ORC is M5's work, but nothing here prevents it.
- **A REPL redefinition is an in-session rewrite** (Rewrites, below),
  with no special case. The meta corpus below is the same test a REPL
  would need.
- **Written to be compiled by this backend.** The core namespaces use
  only what `--target llvm` lowers today, so a later step can compile the
  compiler. The plan names any feature it has to avoid.
- **Shakeable.** No runtime namespace requires the cache or the funnel,
  so a module whose top level does not reach the compiler services links
  none of them. D221's shake already follows references from `_main`.
  That stays a property to keep, checked when the compiler is first
  compiled into an image, not something this spec builds.

## Model

**One entry per lowered function**, meaning a defn's arity, a library
namespace's init, or a generated dispatch defn. Its closures, try regions
and wrappers belong to its entry.

**Key: what the function is, plus what lowering it looked at.**
- *The resolved expanded form.* This is the function's source after
  macroexpansion, with every symbol replaced by what it resolves to at that
  moment: a var by its qualified name, a local by its De Bruijn index, a
  class by its name. Expansion still runs on every compile, natively, so
  macro definitions, redefinitions and aliases are all captured by the
  form itself. Its hash is the entry's *form hash*.
- *Locals are normalized in the hash.* Expansion numbers its gensyms
  from a counter that lowering also takes from. A hit takes none, so every
  later expansion's gensym names shift. If the hash saw those names, one
  hit would make every later function miss. So the hash names a local by
  its De Bruijn index (the number of binders between the use and its
  binder), never by its symbol. Indices rather than binding order make a
  subform hash the same wherever it sits: a closure keeps its hash when
  code is added before it, and equal closures in two functions share one. This is only for hashing: the lowered output keeps its names,
  and structural naming of output stays backburnered (Not in scope).
- *The compiler key, for what cannot be traced.* This covers:
  - the lg binary's hash (let-go's IR passes run inside it);
  - the target, the resolved profile, and the compile options (`no-eval`,
    `runtime-compile`, `*checked*`, `*box*` and the rest);
  - a hash of the compiler's non-function definitions (its `def` tables,
    such as `value-substs` and `ll-leaf-vars`) and of its macros.

  Runtime sources leave the key, because runtime functions are now
  entries like any other. Compiler functions leave it too: they are traced
  (next item). A change to the key starts an empty store, and that is
  rare: an lg rebuild, a new profile, or an edit to a table or a macro of
  the compiler.
- *The compiler functions that ran.* Lowering a function runs some of the
  compiler's functions in `lower-wasm`, `lower-llvm*`, `lw-rt` and
  `lw-ext`. The trace records each one that ran, with a hash of its source
  form, so a compiler edit invalidates only the entries whose lowering ran
  the edited function. An edit to `ll-closure!` re-lowers the functions
  that make closures, and leaves the rest. Recording is a wrapper put on
  each compiler function's var when the llvm target loads; the GC lane
  installs none. Plan 1 checks that let-go calls through the var, so a
  wrapper sees every call, including calls between compiler functions.
  It also times the wrappers' cost.
- *A trace of the lookups lowering made,* recorded as it ran, each as a
  pair of the question and a hash of its answer:
  - a callee's signature;
  - whether a var is a var-table global, a thunk def, a rooted native, a
    twin or a stdlib alias;
  - a program type's declaration;
  - `*box-params*`;
  - `*program-file*` (for `*file*`);
  - test mode (`*stub-libs*`);
  - whatever else a lowering asks the session for.

**Lookup is a verifying trace,** as in Shake and Salsa. Just before
analysing a function, the compiler takes the stored entries for its form
hash. For each one, it checks that each compiler function it records still
has the same source hash, then re-asks every recorded question through the same
function lowering would use, and compares the answers. An entry whose
answers all match is a hit. Re-asking can analyse what a question names (a
callee's signature), which is exactly what lowering would have done.

**Every miss is filled.** A miss compiles the form that should have been
there and puts it in the cache: the function is lowered as today, and its
entry is written at once, with the trace and what the lowering added. This
holds at every level. A function whose entry is missing gets one. A
question re-asked during verification that names something not yet in the
session gets that thing compiled and cached as well, such as a callee
never seen before. The store is filled by demand as compilation goes,
never in a separate build step.

**What an entry holds.** It holds what the function's analysis and
lowering added to the session, less what nested builds added (each nested
build is its own entry):
- the signature entry and analysis info;
- the lowered units;
- regions and module items;
- constants and strings;
- var and module globals;
- environment and program type declarations;
- the `*fn-values*` llvm keys;
- `*elem*` and `*externs*` entries;
- failures and stubs;
- the two counters (merged with `max`, as D181 does).

A hit merges the entry into the session and marks the function done.
Today's runtime snapshot is the special case: every runtime function's
entry, merged from an empty session.

**Rewrites in a session.** A function lowered again in the same compile
(after a redefinition, or in a round of the driver's boxing fixpoint) gets
a new form hash or a new trace answer, so it gets a new entry.
- **Removal comes first.** The session tracks, for each function, the
  additions its current entry merged in, and the reverse index maps each
  question to the functions that asked it.
- **The invalidated set.** Invalidating a function means the function
  itself, plus every function whose trace asked about an interface that
  changed. That repeats until nothing more changes, since a dependent
  lowered again may change its own signature.
- **Subtract, then lower.** First, each invalidated function's additions
  are subtracted from the session: its units, regions, globals, constants
  and `*fn-values*` keys. Then each is lowered again (or matched against
  the store). Without the subtraction, D225's one-global-per-name check
  would fail on the function's own earlier globals.
- **Shared additions survive.** An addition two entries share, such as a
  content-named constant or an environment type, stays until no entry in
  the session holds it, so the session counts holders.

**Order and cycles.** Analysis already runs callees first. Within a
recursive cycle, a question asked about a member that is still being
analysed records the answer it got (`:busy`, the default boxed signature).
A later compile that reaches the cycle in another order gets other answers,
so it misses and lowers again: correct, just not reused.

## Names stay valid across compiles

A cached unit is pasted into a module it was not lowered for, so every
module symbol it names must mean the same thing there.
- Constants, fn values, var globals and lifted closures are already
  content-named (D221, D225, `<fname>__fn<nid>`).
- **Type ids are not.** Program types and closure environments take ids
  from one counter in first-use order (`ll-next-id!`). Instructions that
  store a program type's or an environment's id instead load it from an
  internal constant global named for the type (`lg_tid_<name>`, the shape
  `lower_llvm_rt.lg` already uses for static types). Module assembly
  assigns the numbers and emits the constants. LLVM folds a load from an
  internal constant, so this costs nothing at run time. No global
  initializer names a program or environment id today. The plan's first
  task checks this, and makes any it finds a reference to the constant.
- Lowering consumes gensyms, so a hit takes fewer of them and later local
  names differ. That is acceptable because acceptance is behavior. A
  gensym-derived name in a *module* symbol would collide across compiles,
  and D225's one-global-per-name check fails such a compile loudly. The
  plan audits for gensym-derived module symbols.

## Recording every lookup

Missing a lookup is this design's one dangerous failure: a missed input
means a stale hit and wrong code. Two defenses:
1. **One funnel.** The questions lowering asks go through named functions
   in a new namespace, `lower-llvm-cache`, which records each into the
   function being built (the shape of `lower-llvm-ir/with-refs`). Today
   they are about 100 direct reads across `lower_wasm.lg`, `lower_llvm.lg`
   and `lower_llvm_rt.lg` (`@*sigs*`, `callee-sig`, `rt-target`,
   `*rooted-natives*`, `*thunk-def-vars*`, `var-globals`,
   `@*prog-decls*` and others). They move to the funnel, and a direct read
   of a session atom from lowering code is a bug.
2. **A check mode, as a gate row.** Under `LW_LL_CHECK_CACHE=1`, every hit
   is also lowered fresh, in a scratch copy of the session that is thrown
   away afterwards, so the fresh lowering's globals never meet the merged
   entry's.
   - **What is compared.** The two entries are compared as data, after one
     normalization: gensym-derived local names, which differ between any
     two lowerings, are renamed in order of first appearance (D186's
     normalized body diff). Module symbols are compared as they are, since
     they are content-named and must agree.
   - **A difference is a missed lookup, and it is filled like any miss.**
     The fresh entry is the correct one. It replaces the stale entry in the
     session, by the removal under Rewrites, and in the store, so the
     module is built from correct code and the store repairs itself.
   - **It is still reported,** naming the function and the first
     differing field. Replacing the entry fixes this compile but not the
     trace: the input it failed to record could change in a later compile,
     and the trace would accept the entry again. So the compile succeeds,
     the report goes to stderr, and the gate row fails on any report until
     that input is added to the funnel.
   - **Why it exists.** It compares the cache's own records, not a
     module's bytes. It is how an input the funnel missed shows up before
     it ships, in the spirit of P12.39's reference check.

## Store

- **One store serves every compile unit.** No entry is keyed by the
  program being compiled. A function's entry is found by its form hash and
  checked by its trace, whichever program reached it. So `main.lg` and the
  world dump share xsofy's library entries, every program shares the
  runtime's, and a test build shares the entries of the code it tests.
  Program-specific inputs (rooted natives, `*file*`, test mode) are
  answers in the trace, so they select among an entry's traces rather than
  splitting the store.
- Entries live under `LW_RTLIB_DIR` (default `src/.rtlib`), in
  `fncache-<compiler key>/`. Since compiler functions are traced rather
  than keyed, editing the compiler keeps the store: each entry is checked
  against the compiler as it now stands. There is one file per namespace, holding that
  namespace's entries keyed by form hash. Each form hash keeps at most 4
  traces, newest first, so alternating between two programs or two
  variants still hits.
- A write goes to a temp file and is renamed into place, as now.
- **Entries are written while the compile runs, not only at its end.**
  A namespace's file is rewritten once its last function this compile
  reaches is lowered, and otherwise after every 50 new entries. A compile
  that fails or is interrupted therefore keeps most of what it lowered.
- A store for another compiler key is deleted when a new one is made, as
  `load-rtlib!` deletes old libraries now.
- **The runtime snapshot stays as a fast path.** `load-rtlib!` restores
  it when the runtime sources match. Otherwise `build-rtlib!` builds it
  through the function cache, so a runtime edit lowers only the functions
  whose form or trace changed.

## Acceptance

Behavior and bounds, measured with hyperfine where a time is claimed:
- **Behavior.** Each program in P12.37's list, plus xsofy's world dump
  (seeds 1–20), behaves the same compiled with no cache, with a cold
  cache, and with a warm cache, and the same as native lg.
- **Speed.** The bound is set after measuring, in the first plan's first
  task. That task times with hyperfine the parts of an xsofy compile that
  a full hit still runs:
  - reading;
  - restoring the runtime snapshot (`rtlib`, 3.8 s on 2026-10-28, most
    of it parsing the 78 MB snapshot); meeting the goal below may need a
    faster EDN reader in let-go itself;
  - native loading and expansion;
  - resolving and hashing forms;
  - re-asking traces;
  - merging entries;
  - module assembly, the shake (0.85 s) and the text (0.4 s) included;
  - clang.

  The bound is their sum plus a margin, written into this spec before any
  cache code. Today's 76 s is the baseline, and native lg loads the same
  program in 0.45 s. The goal is the whole compile under 1 s, or at least
  native lg's time; the restore, the shake and the text are paid on every
  hit, so the bound names each one's share of it.
- **Partial rebuilds, on a copy of xsofy:**
  - a comment-only edit lowers 0 functions;
  - a body edit that keeps the signature lowers at most 8 (that function
    and its closures);
  - an edit that changes a signature also lowers the functions whose trace
    asked about it, and the dumps still match native.
- **Partial rebuilds of the runtime.** D221's part 3
  (`LLVM_RTLIB_PARTIAL=1` in `checks/llvm-rtlib-check.sh`) passes: a
  comment-only edit lowers 0 functions, and a one-function body edit lowers
  at most 8. Both are reported by the `rtlib-llvm: N reused, M rebuilt`
  line.
- **Meta environment.** A new corpus, `corpus/llvm/fncache/`, has programs
  that each change meaning mid-compile:
  - a macro redefined between two uses;
  - a def redefined;
  - a top-level form that registers values a later function reads;
  - a library namespace whose macro is used by a dependent.

  Each MATCHes native cold and warm. It also MATCHes after its library's
  macro is edited between two compiles, without clearing the store.
- **Check mode.** The check-mode row compiles the llvm, poly, control
  and fncache corpora and xsofy's dump warm, with `LW_LL_CHECK_CACHE=1`.
  It fails on any report. A planted missed lookup is reported, and the
  module built in the same run behaves correctly, because the fresh entry
  replaced the stale one.

## Not in scope

- The GC and linear lanes.
- Caching macroexpansion, or the reading of sources.
- Caching clang's output. Per-namespace object files are the next lever
  once lowering is cached.
- De Bruijn or path-based naming of locals *in the output* (backburnered,
  in let-go). Normalizing locals *in the form hash* is in scope and
  required (Model).
- Sharing a store between machines or lg builds.

## Risks

- **The funnel misses a lookup.** The check mode is the defense, and it is
  a gate row, not an option.
- **Analysis inside let-go's IR passes reads state the funnel does not
  see,** such as var metadata the IR build consults. The resolved expanded
  form covers name resolution, and the lg binary hash covers the passes.
  Any other read is found by the check mode and moved into the form or the
  trace.
- **Store size.** About 4 traces for each of a few thousand functions. The
  plan measures it, and adds a bound if it passes 100 MB.

## Delivery: three plans, in order

1. **Groundwork, with no cache.**
   - The lookup funnel (`lower-llvm-cache`), with every session read
     moved behind it.
   - Tracing which compiler functions ran: the var wrappers, the check
     that they see calls between compiler functions, and their cost.
   - The `lg_tid_<name>` constants for program and environment ids.
   - The timing in Acceptance, which sets the speed bound.

   It is checked by unchanged behavior on the existing gate rows
   (`checks/llvm-behavior-gates.sh`). It is useful on its own, since it
   makes lowering's inputs explicit.
2. **The cache for program and stdlib library functions:** the entry
   delta, the form hash, verifying traces, the store, in-session
   invalidation, the check mode, `corpus/llvm/fncache/` and the xsofy rows.
3. **The runtime through the cache:** `build-rtlib!` builds through the
   function cache, and D221 part 3 is enabled.
