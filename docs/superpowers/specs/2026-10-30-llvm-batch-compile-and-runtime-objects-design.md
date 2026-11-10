# The llvm target's per-program cost: a cheap runtime restore, and the runtime compiled once

Written 2026-10-30. It applies to `--target llvm` only and sits beside the
function cache (2026-10-10-llvm-fn-cache-design.md), which removes analysis
and lowering from a warm compile but keeps three costs on every compile: the
runtime restore, module assembly (shake and render), and clang. This design
is about those three. The fn-cache spec names "per-namespace object files" as
the next lever once lowering is cached; the runtime object below is that
lever, applied to the runtime first.

## Why

P13.9 (the common corpora on the llvm lane) compiles and runs 271 programs,
three at a time, and took 62 minutes on 2026-10-30 at a load of 10 to 15.
Most corpus programs are small, so nearly all of that is cost every program
pays whatever it contains. Measured that day on `corpus/scalar/fib.clj`:

| step | pinned lg | lg + reader fix |
|---|---|---|
| driver compile (`lg … driver.lg --target llvm`) | 9.8 s | 4.3 s |
| clang (host C and the program's IR, `-O2`) | 3.05 s | 2.7–3.0 s |
| running the binary | 0.9 s | 0.9 s |
| total | 14.7 s | 9.2–9.4 s |

The reader fix is nooga/let-go's linear duplicate-key check (branch
`fix/reader-linear-duplicate-keys`, in review); the pinned reader compared
every key of the 75 MB runtime snapshot's maps pairwise.

With the fix, what is left does not depend on the program:
- **The driver compile is fixed overhead.** Loading the driver alone takes
  0.5–1.2 s; compiling `(println 1)` takes 5.3–6.4 s and `fib` 4.3–5.1 s. A
  Go profile of a warm `fib` compile puts about 25% of samples in reading
  the snapshot (12% in its strings, the cached IR text), about 36% in
  garbage collection, mostly marking what the read built, and about 40%
  under compiling and running the driver's own source, which contains the
  restore. Lowering `fib` itself does not show.
- **The module is the runtime.** `fib`'s module is 3.80 MB of runtime
  functions, 0.03 MB of helpers and 0.01 MB of program, so clang's 3.2 s at
  `-O2` is spent on the runtime. Caching the host C objects saves nothing:
  clang already overlaps them with the module (measured, and dropped).

The same costs are paid by every user compile, not only by the corpus rows,
and they are the floor under the compile-time goal (the whole compile under
1 s, or native lg's time).

## Goals, non-goals, anti-goals

Goals:
- A small program's compile, build and run is dominated by its own size, not
  by the runtime's.
- P13.9 and the other corpus rows get faster as a consequence; their
  verdicts do not change.
- Every user compile gets the same benefit; nothing here is test-only.

Non-goals:
- The GC and linear lanes.
- Caching lowering (the fn cache's job) or macroexpansion.
- The bare-board (`host bare`) and JIT (`LW_NATIVE_JIT`) paths, except that
  they keep working as they do now.

Anti-goals, which would make this a failure even if it were faster:
- A program's behavior depends on what was compiled before it in the same
  process.
- A runtime edit, a compiler change or an lg change leaves a stale runtime
  object linked.
- Programs run measurably slower without anyone deciding that trade.

## Constraints

- **Programs are evaluated in the host.** The driver `eval`s each program's
  top-level forms in the lg process (`src/driver.lg:720`, `:1250`), so a
  program's namespaces, var redefinitions, `defmethod`s and protocol
  extensions live in the host image. A session (`new-session`,
  `with-session*`) scopes only lowering's state. The driver also keeps
  module-level atoms (loaded libraries, defns).
- **Runtime functions are internal.** 2,769 of `fib`'s 3,155 functions are
  `define internal`, so the whole module optimizes as one unit and the shake
  drops what is unreached. A runtime compiled separately needs a visible
  symbol for every runtime function a program may call.
- **Some state is module-wide.** The type table is built fresh for each
  module's types (`ll-tinfo-globals`); var globals, constants and strings
  are interned per module; the init chain runs only live vars' inits; the
  static keyword table (`ll-intern-statics-sym`) covers the module's
  keywords.
- **Behavior is the oracle** (checks/oracle.sh against native lg), never
  bytes or IR.

## Part 1: a cheap runtime restore

### Approaches

1. **Batch compile in one process.** `driver.lg --batch <manifest>` compiles
   many programs, each in a fresh session, restoring the snapshot once and
   compiling the driver once. By the profile above it would save most of
   each compile's 4.3 s, an estimate the work would measure first. The cost is isolation: since programs are evaluated in the host,
   each program's namespaces and its changes to shared vars, multimethods
   and protocols must be undone before the next, and the driver's own atoms
   reset. Undoing a `defmethod` on a core multimethod or an
   `extend-protocol` on a core type needs host support that let-go does not
   have (a namespace-registry snapshot and restore), so a complete version
   is a let-go change.
2. **Make the restore cheap instead.** Keep one compile per process and cut
   what the restore costs:
   - keep the cached IR text out of the EDN: units store an offset into a
     sidecar text file, read only for units the shake keeps;
   - read the index part of the snapshot only (signatures, globals, the
     shake's def/ref graph), which is a small fraction of 75 MB.

   It saves less per compile than batching (the driver still loads, about
   0.5–1.2 s), needs no isolation, and helps every compile, including a
   user's single compile, which batching does not.
3. **Both:** 2 first, then 1 for the corpus rows if 2 leaves enough on the
   table.

**Chosen: 2, without batching** (owner, 2026-10-30). It removes most of
the restore with no new correctness risk and serves a user's single
compile as well as the corpus; batching's isolation would have needed a
let-go change for less general gain.

## Part 2: the runtime compiled once

### Approaches

1. **A native runtime object, no link-time optimization.** Build the
   runtime once per snapshot key into `runtime.o`; a program's module holds
   its own functions and declarations of the runtime symbols it names;
   clang compiles only that module and links. Fastest build; programs lose
   inlining across the runtime boundary, so tight loops through runtime
   calls may run slower.
2. **The runtime as optimized bitcode, linked with ThinLTO.** Build the
   runtime once into bitcode with a ThinLTO summary, and link programs with
   `-flto=thin` and a ThinLTO cache directory. Cross-module inlining is
   kept, and the cache keeps the runtime's backend work from repeating. It
   costs more per link than 1 and its gain depends on the cache hit rate,
   which needs measuring.
3. **Per-namespace objects** (the fn-cache spec's next lever): objects for
   the runtime and for each library namespace, xsofy's included. It is the
   general form of 1 or 2, and needs the fn cache's entries to know what a
   namespace's object contains.

**Recommended: a spike measuring 1 and 2 on P12.37's programs, then build
whichever meets the bounds below,** with 3 as the later generalization once
the fn cache's plan 2 lands. 1 is the simplest to make correct; 2 is the one
most likely to keep programs' speed.

### What has to change, either way

- **Linkage.** Runtime functions a program can call become visible (hidden
  visibility in a shared build, or plain external); functions only the
  runtime calls stay internal to `runtime.o`.
- **The shake.** It stops at the runtime boundary: it keeps program units
  and records which runtime symbols they name. Unused runtime code is
  dropped by the linker (`-ffunction-sections` with `--gc-sections`, or
  `-dead_strip` on macOS), which is the shake's job moved to link time.
- **Stable ids.** Runtime type ids, var globals, constants and static
  keywords are fixed by the runtime build and live in `runtime.o`; a
  program's types take ids after the runtime's, its constants and keywords
  intern into the runtime's tables at init, and its var globals stay in its
  own module.
- **Init.** The runtime's init chain lives in `runtime.o` and runs whole, or
  stays live-only through a registration the linker can drop; which one is
  decided by measuring startup.
- **Keys.** `runtime.o` (or its bitcode) is keyed like the snapshot (the
  lowering source, the runtime sources, the lg binary) plus clang's version,
  its flags and the hardware profile; a key mismatch rebuilds it, never
  links an old one.

## Acceptance

Behavior and bounds; times measured with hyperfine on a quiet machine
(`checks/quiet.sh`). The lg is the pin in `checks/env.sh` (today
`lg-e9789b7d53`), moved to a let-go build with the reader fix once that
merges; until then, measurements use e9789b7d53 plus the fix alone, and say
so. The first task re-measures the table in Why on a quiet machine: the
figures above were taken at a load of 10 to 15.
- **Behavior.** Every corpus row passes as before, and P12.37's programs
  behave the same with and without the cache, with and without the runtime
  object. The sidecar text and part 2's object are each covered by a
  check that a planted stale entry or object is rebuilt, not used.
- **Restore (part 1).** The warm restore's share of a `(println 1)`
  compile is set by measuring first, then bounded; the target is the driver
  compile of a small program under 2 s.
- **Build (part 2).** clang's step for `fib.clj` under 1 s, and the
  program's run time within 10% of today's on the llvm benchmarks rows.
- **P13.9.** Its time recorded before and after each part, from the
  per-row seconds `checks/workflow.mk rows` prints (#83's branch until it
  merges).

## Decided

- No batch mode (owner, 2026-10-30): part 1 is the cheap restore
  (approach 2) only, so no isolation work and no let-go registry change.
- A program may run at most 10% slower than today on the llvm benchmarks
  rows (owner, 2026-10-30); that is the spike's pass line between part 2's
  approaches 1 and 2.
- Part 1 before part 2, and part 2 starts with a spike that measures
  approaches 1 and 2. (My recommendation.)

## Open, for the owner

- P13.9's target time.
- Where part 1 falls against fn-cache plan 1, which is in flight and was
  set to finish first. Part 1 touches the same restore path, but not the
  funnel or the traces.

## Settled while writing (my calls)

- The pin is `checks/env.sh`'s, and moves to a let-go with the reader fix
  (owner's decision, 2026-10-30); the reader fix is the let-go side of the
  restore's cost, so this design needs no other let-go reader work.
- Part 1's sidecar lives beside the snapshot in the runtime cache directory
  (`LW_RTLIB_DIR`), keyed with it, and is separate from the fn cache's
  store, so the two formats cannot collide.

## Left to the builder

- The sidecar format and how a unit names its text.
- The linker flags per host, and the visibility split between runtime
  functions.

## Risks

- **Lost inlining (part 2).** Measured by the spike and bounded in
  Acceptance before anything ships.
- **Startup (part 2).** Running the whole runtime's init chain may cost
  more than today's live-only chain; measured before choosing.
