# Leaves as direct calls on the llvm target

Written 2026-11-06. It applies to `--target llvm` only (src/lower_llvm*.lg)
and sits inside the CPS design kept on 2026-10-10: optimize within CPS
(leaves, fewer continuations), no direct-call redesign.

## Why

Every call from one let-go fn to another is a CPS call: the caller
allocates a continuation frame with `lg_alloc`, stores its live values in
it, and tail-calls the callee, which resumes the frame when it returns. Only
intrinsics, primitive ops and `println` are emitted inline (`ll-call-plan*`).

That cost lands on small pure fns, the commonest kind. Measured 2026-11-06
on llvm.xxhash: `r64` calls `r32`, which calls `r16`, and each call
allocates a frame, so every 8-byte read costs several heap allocations, and
LLVM cannot inline or optimize across a `musttail` call into a heap frame.
XXH3 over 25 MB takes 2.9 s on llvm against 1 ms natively (zeebo/xxh3 is
assembly), about 8.5 MB/s, or 27 MB/s on a quieter machine. The let-go
compiler built through llvm spends 2.9 s of every run fingerprinting its own
binary for the runtime-library cache key, and the rest of its compile is
the same kind of code.

## Goals, non-goals, anti-goals

Goals:
- A fn that does nothing a continuation is needed for compiles to a plain
  LLVM function, and a call to it is a direct `call`, so LLVM can inline it
  and run its usual optimizations.
- Programs run faster with no change to their source; xxh3 is the first
  measure, the llvm-built compiler's compile time the second.

Non-goals:
- The GC lane and the linear lane.
- Fns that raise catchably, sit on a call-graph cycle, or call a non-leaf:
  they stay CPS.
- Replacing hot runtime fns with C (see Approaches).

Anti-goals, which would make this a failure even if it were faster:
- A program's behavior changes: output, exit, error text, or a raise caught
  differently. The oracle (checks/oracle.sh) is the judge, as for every row.
- A collection runs while a caller holds heap values the collector does not
  see.
- The C stack grows without bound in a loop.

## Constraints (from the lowering as it is)

- **Raising is a tail call.** A catchable raise is `lg_throw`, which loads
  the innermost handler frame and tail-calls its code with that frame's
  continuation (`ll-function!`'s prelude, D235). Called from inside a direct
  call, the leaf's native frame would never be popped, so a loop that raises
  would grow the stack. A leaf must not raise catchably. A trap (`arch/trap`,
  an out-of-range `bget`) aborts the process, which is safe from any depth.
- **The collector's roots are a CPS fn's params.** Each CPS fn checks
  `lg_gc_pending` on entry and collects with its params as roots; "nothing
  else is live, since every call is a tail call" (`ll-gc-check`). Across a
  direct call the caller keeps heap words in registers, so a leaf must not
  collect: it has no entry check. It may allocate: `lg_alloc` never collects
  (it sets `lg_gc_pending` past a threshold and aborts when out of memory,
  host/native/gc.c), and every heap value live across the direct call, the
  leaf's result included, is stored in the caller's continuation frame
  before the caller's next CPS call, whose callee's entry check is the only
  place a collection runs.
- **Traps differ under --test.** Outside --test an index check or cast that
  fails calls `lg_trap`, which aborts. Under --test (`*trap-throws*`) it
  calls `lg_trapk`, a catchable raise through `%k`, which a leaf cannot
  make.
- **Every generated fn is `tailcc` returning void** (`ll-fn`). A leaf is a
  new kind of item: `fastcc` (or the default convention) returning its value.
- **The fn cache keys units by text and callee signatures.** A leaf changes
  how its callers are emitted, so leafness is part of a fn's signature.

## Approaches

1. **Direct-call leaves within CPS (recommended).** Classify fns as leaves
   by a fixpoint over the call graph; emit each leaf once as a direct-call
   function; emit calls to leaves as direct calls. Everything else stays
   CPS. Stays inside the 2026-10-10 decision, helps every program, and gives
   LLVM straight-line code to optimize where it matters most.
2. **C for hot runtime fns.** Port xxh3 (and later others) to the native
   host and call it through an intrinsic. Fast for that fn (a port is
   written and set aside in the spike tree), but it leaves every other
   program, and the compiler itself, exactly as slow, and each port is a
   second implementation to keep in step.
3. **A direct-call calling convention for all fns.** Declined on 2026-10-10.

## Design (approach 1)

### Which fns are leaves

A fn arity is a leaf when every instruction in its body is one of:
- a primitive op or intrinsic whose emission cannot raise catchably:
  wrapping i64 arithmetic (`arch/i64-*`), bit ops, comparisons, float
  arithmetic, allocation and boxing, and `bget`/`aget`/field reads and
  writes and checked casts outside --test (their failure aborts there;
  under --test they raise catchably, so a fn using them is not a leaf in a
  --test build);
- a constant (an int, a float, a boolean, nil, a static keyword or a
  constant global built at startup);
- a call to another leaf, with matching arity;
- control flow within the fn (branches, loops, `recur`).

Excluded: any call through `ll-call-plan` (a non-leaf fn, a fn value, a var
read through the table), checked arithmetic that raises ArithmeticException,
integer division or remainder whose zero case raises, `throw`, `try`,
closures, dynamic var reads or bindings, and the GC lane's stand-ins. The
classification runs after type inference, so a param typed `:int` reads
unboxed.

Leaves are found by a fixpoint: start from fns whose bodies call nothing,
add any fn whose calls all reach leaves, repeat until nothing changes. The
leaves form an acyclic graph: a fn on any call-graph cycle, mutual tail
recursion included, stays CPS, so a leaf never needs more C stack than the
depth of that graph. A fn's own `recur` is a loop inside it, not a call.

Leafness is computed once per program, after analysis and before lowering,
over every analysed fn (the program's and the runtime's), and again in the
driver's boxing loop when a signature changes. The runtime library's
leafness is computed when that library is built and stored with its
signatures in the cached library, so a compile that restores it gets its
leaves without recomputing them.

### How a leaf is emitted

- One LLVM function per leaf arity, named apart from its CPS entry
  (`<name>.leaf`), `internal fastcc`, params in their analysed
  representations (`i64`, `double`, `i1`, or the boxed word), returning its
  representation, with no `%k` and no GC entry check.
- Its CPS entry stays for every use that needs a fn value or an unknown
  callee (apply, a fn stored in a collection, a call through a var the
  table rebinds): a thin CPS function that calls `<name>.leaf` directly and
  returns to `%k`. So a leaf's identity as a value does not change.
- A call from any fn to a known leaf (resolved var, matching arity) emits
  `call fastcc <ret> @"<name>.leaf"(args)` inline and binds the result, with
  no continuation frame and no cut in the caller's pieces (`ll-cuts`).

### Signatures and the fn cache

Leafness is recorded in the fn's signature (`:leaf true` on the arity),
which the driver's `*sigs*` entries and the analysis cache's callee
interfaces (`analysis-interfaces`) both carry, so `ll-call-plan` sees it and
a fn that stops being a leaf invalidates its callers' cached analysis and
lowering.

## Follow-ups, after leaves land

Each starts only after leaves are in and measured, and is judged by the
same acceptance as leaves: behavior unchanged, then time.

1. **Known continuations (contification).** A CPS fn returns by loading the
   code pointer from its continuation frame and tail-calling through it, an
   indirect call LLVM cannot see through and the CPU cannot predict as a
   return. When every call to a fn passes the same continuation (a helper
   called from one site, or from sites that all resume the same code), the
   lowering can tail-call that continuation's code directly instead of
   through `%k`, or fold the fn into its caller's pieces. It needs a
   whole-program view of each fn's call sites, which the leaf fixpoint's
   call graph already provides.
2. **Inlining before lowering.** When a callee is inlined at the IR level,
   its call and continuation disappear. let-go's IR has an inline pass
   (ir.passes.inline, gated by its `*enable-inline*` and fed a registry of
   callee IR that let-go's pipeline.lg builds); this repo's driver builds no
   such registry, so the llvm lane inlines nothing across fns today. The
   first step is to measure: count the CPS calls left in the compiler's own
   module before and after enabling it for small non-leaf callees.

## Acceptance

- **Behavior:** every corpus row passes as before (a full row run on a quiet
  machine), including P13.9 and the llvm corpora; P12.37 meets its bound.
- **A guard:** a corpus case per leaf property: a leaf that would raise if
  wrongly classified (checked `+`) stays CPS and its raise is caught; a leaf
  called in a loop of a million iterations runs in constant C stack.
- **Speed, measured with hyperfine on a quiet machine:** XXH3 of 25 MB on
  llvm, recorded before and after, with a target of under 100 ms (about
  250 MB/s, within two orders of magnitude of zeebo's assembly), recorded
  with the result rather than gating it (behavior is the gate); the
  llvm-built compiler's compile of corpus/scalar/fib.clj, before and after;
  the llvm benchmarks rows, none slower.

## Decided

- Approach 1, within CPS (the 2026-10-10 decision, and the owner's
  direction on 2026-11-06 that the optimizers should close the gap).
- Leaves never collect, never raise catchably and never sit on a call-graph
  cycle; they may allocate (from host/native/gc.c: allocation never
  collects).

## Settled while writing (my calls)

- Leafness is computed after analysis over the whole program and runtime,
  rerun by the boxing loop, carried in signatures and the analysis cache's
  interfaces, and stored with the cached runtime library.
- Under --test, ops that trap catchably are not leaf ops; test builds have
  fewer leaves and the same behavior.
- No call-graph cycles among leaves, so leaf recursion depth needs no limit.
- The xxh3 time is a recorded target, not a gate.

## Left to the builder

- The exact op allowlist, kept as one table beside `ll-call-plan*`.
- Whether `fastcc` or the default convention, measured.

## Risks

- **A misclassified leaf** collects or raises: the GC then misses roots,
  or the stack leaks. The allowlist is closed (an op not on it is not a
  leaf), and the corpus guard above checks both failure modes.
- **Deep recursion in a leaf** cannot happen: a fn on a call-graph cycle is
  not a leaf.
- **Code size:** a leaf has two entries (direct and CPS). The shake drops
  the CPS entry when nothing takes the fn as a value.
