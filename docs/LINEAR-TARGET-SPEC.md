# Spec: a linear-memory target beside WasmGC

Written 2026-10-03 as a work order for an agent or a person who has not
seen this code before. Read `README.md`, then `docs/READING-GUIDE.md`
(stops 2, 3, 4, 5, 8 and 11 are the ones this touches), then this file.
Everything here is about adding a second output format; the WasmGC target
stays the default and its output must not change.

## Why

Two reasons, and both are needed to judge trade-offs below.

1. **Runtimes without WasmGC.** Pure-Go engines (wazero) and many embedded
   or server hosts run core wasm with linear memory only. A linear-memory
   module runs there unchanged.
2. **Browsers without JSPI.** The hosts suspend blocking imports (`sleep`,
   `read_key`) through JSPI. Binaryen's Asyncify is the usual fallback, but
   it spills locals to linear memory and cannot handle GC references in
   locals: `wasm-opt --asyncify` on these modules fails with
   `canMakeZero(type)`. A linear-memory module has only numeric locals, so
   Asyncify works on it, and a loader can feature-detect JSPI and pick the
   artifact, as the LiteRT-LM web runtime does since its 0.14.0.

So the target is worth having even though Safari 27 and Firefox 153 bring
JSPI; reason 1 does not expire.

## Scope

Three milestones. Milestone 1 is the deliverable of this spec; 2 and 3 are
described so that 1 does not paint them out.

- **M1, leaking allocator.** `--target linear` produces a module that
  bump-allocates and never frees. Done when `corpus/scalar/` gives MATCH
  under a wazero runner through `checks/oracle.sh`, and the WasmGC output
  is byte-identical to before for every program in `corpus/scalar/` and
  `corpus/eval/`.
- **M2, precise collector** (design and phases: Milestone 2 below, D196). A non-moving mark-sweep collector with a shadow
  stack for roots, modelled on the two collectors in
  [wallisp](https://github.com/mparrett/wallisp): `engines/bytecode_gc.c`
  (non-moving mark-sweep over a uniform cell heap, mark bits plus an
  explicit mark stack, free-list sweep; `mark` and `gc` near its line 530)
  and `engines/lisp_gc.c` (the `R_save` shadow stack with a strict push/pop
  protocol around every call, and the notes on keeping it balanced under
  tail-call elimination). Both are freestanding C compiled to wasm with
  linear memory, so their shape transfers directly; what changes is that
  our heap has many object kinds and sizes, hence size-class free lists
  below. Done
  when legmacs boots under the wazero runner and its deftest suite reaches
  the same count as the WasmGC lane (316 of 373 as of 2026-10-02).
- **M3, Asyncify artifact.** `wasm-opt --asyncify` over the M1/M2 module,
  a JS host implementing the unwind/rewind protocol for `sleep` and
  `read_key`, and feature detection in the demo pages that loads it when
  `WebAssembly.Suspending` is absent.

## What exists that this builds on

- `src/lower_wasm.lg` emits WAT from let-go's structured IR. The GC
  representation is concentrated in a few functions:
  `coerce` (i64 vs boxed value, inline hybrid `ref.i31`/`$Int` box, D41),
  `box-wrapper` and `unbox-fn` (runtime box helpers),
  `rec-group` and `fnv-types` (the type section, D25/D52/D150),
  `closure-wat` (closure allocation and arity dispatch),
  `emit-intrinsic` (intrinsic var to instruction),
  `tail-call-wat` (tail calls through `return_call` and `$rt_invoke<n>`),
  `try-wat` (exception regions, D31), and
  `rt-target` (which runtime defn a native call routes to, D58).
- GC instruction census of the emitter and the runtime's raw WAT (as of
  2026-10-03): `ref.cast` 82, `struct.get` 74, `ref.null` 56, `ref.test`
  47, `struct.new` 41, `array.len` 27, `ref.i31` 20, `ref.is_null` 19,
  `ref.as_non_null` 13, `array.new_default` 12, `array.set` 10,
  `array.copy` 9, `i31.get_s` 8, `array.get_u` 8, `ref.func` 7,
  `return_call_ref` 5, `ref.eq` 5, `struct.set` 4, `call_ref` 4,
  `array.new_data` 3, `array.new` 2, `array.get` 2, `array.new_fixed` 1.
  Every one of these needs a linear form; the list is the checklist.
- `rt/wasm/*.lg` is the runtime, compiled by the same backend, so it
  follows the representation switch for free except for the raw-WAT
  intrinsics in `rt/wasm/intrinsics.lg` (`^{:intrinsic true :wasm "..."}`),
  which need a linear twin each.
- The host ABI (`host/ABI.md`) already passes strings across the boundary
  as `ptr`+`len` in a linear-memory copy area; inside the module strings
  are GC byte arrays. The imports do not change for this target. Only the
  copy step inside the module changes: a linear string is already bytes in
  memory, so `print_str` and friends pass its address directly.
- `checks/oracle.sh` is the match relation; `checks/wasm-run.sh` is the
  WasmGC runner it compares against native lg. `checks/env.sh` resolves
  the sibling checkouts and the pinned lg.
- The driver is `src/driver.lg`; its `-main` reads `-source-paths` from
  its argument vector and the rest from environment variables
  (`LW_NO_EVAL`, `LW_NO_PROGRAM_TABLE`). The compiled runtime library is
  cached under `LW_RTLIB_DIR` with a key covering the sources read.

## Design decisions (made; do not reopen without a note in DECISIONS.md)

1. **Value representation: tagged i32.** Low bit 1 is a fixnum (31-bit
   signed, mirroring D41's `ref.i31` range so the canonical-form rule and
   every hash stay the same); low bit 0 is a pointer to a heap object, with
   0 as `nil`. Ints outside 31 bits are a heap `$Int` holding an i64,
   exactly as D41 boxes them. Floats are heap objects. Booleans are two
   static heap objects at fixed addresses (D22's singletons).
2. **Object header.** Every heap object starts with `kind:i32` (the same
   kind numbers `wasm.seq/kind` returns, see `rt/wasm/README.md`) and
   `size:i32` in bytes, header included; fields follow 4-byte aligned.
   Arrays add `len:i32`. Casts (`ref.cast`, `ref.test`, `br_on_cast`)
   become a load of `kind` and a compare; a failed cast raises the same
   named error the GC lane raises, never a trap.
3. **Allocation.** One `global $heap_top`; `alloc(size)` bumps, grows with
   `memory.grow` on demand, and never frees in M1. The copy area the hosts
   use for crossing the boundary stays where `host/ABI.md` puts it; the
   heap starts after it.
4. **Functions.** `call_ref`/`return_call_ref` become `call_indirect` /
   `return_call_indirect` through one table of every function that is ever
   taken as a value; a closure's code slots hold table indices. Tail calls
   keep using the tail-call proposal; exceptions keep using `try_table`
   and `throw_ref`. Both are enabled in the wazero fork behind
   `experimental.CoreFeaturesTailCall` and
   `experimental.CoreFeaturesExceptionHandling`, which the Go runner sets.
5. **One emitter, two representations.** The switch is a dynamic var in
   `lower_wasm.lg` (`*target*`, `:gc` or `:linear`) consulted by a small
   representation layer: the functions listed above dispatch on it, and
   every raw instruction string in the emitter goes through that layer
   rather than being spelled twice. No second emitter file. The cost is
   that the GC path is edited; the guard is the byte-identity check in the
   acceptance list.
6. **Driver switch.** `--target linear` on the driver command line and
   `LW_TARGET=linear` in the environment mean the same thing; the flag
   wins. The target is part of the rtlib cache key, so the two targets
   never share a cached runtime library.
7. **Runner.** A small Go program, `host/wazero/main.go`, built against
   the wazero fork that implements tail calls and exception handling. It
   provides the imports in `host/ABI.md` over the module's linear memory
   (`sleep` sleeps, `read_key` reads stdin, `size` reports the terminal),
   runs `_main`, and exits with the module's status so that
   `checks/oracle.sh` can treat it like `lg`. `checks/wasm-run-linear.sh`
   wraps driver, `wasm-tools parse` and this runner. Why Go and not the
   JS hosts: the point of M1 is to prove the module runs without GC and
   without JSPI; node would prove neither.

## Milestone 1 work, in order

1. **Driver and cache key.** Accept `--target`, thread it to the emitter
   as `*target*`, add it to the rtlib key. With `--target gc` (the default)
   outputs are byte-identical to today; add this as a check before any
   emitter change (see acceptance 1) so later steps are measured against
   it.
2. **Type section.** Under `:linear`, `rec-group` emits no GC types: one
   memory, the function table, the func types `$Code<n>` with `i32` in
   place of `(ref null eq)`, and the globals (`$heap_top`, the singleton
   addresses).
3. **Representation layer.** Introduce the layer and route the GC path
   through it first with no behaviour change (acceptance 1 again), then add
   the linear forms: `coerce`, box/unbox, `struct.new`/`get`/`set`,
   `array.*`, `ref.cast`/`ref.test`/`br_on_cast`, `ref.null`/`is_null`/
   `as_non_null`/`eq`, `ref.func` and `call_ref` via the table.
4. **Intrinsic twins.** Each raw-WAT intrinsic in `rt/wasm/intrinsics.lg`
   gets its linear form, selected by the same layer; the native reference
   implementation is unchanged, so `checks/run-intrinsics-native.sh` stays
   the first test of any change there.
5. **Runner.** `host/wazero/main.go`, `checks/wasm-run-linear.sh`, and the
   oracle wiring: `WASM_RUN=checks/wasm-run-linear.sh checks/oracle.sh
   corpus/scalar/fib.clj` prints MATCH.
6. **Corpus.** `checks/run-corpus.sh corpus/scalar` under the linear
   runner, then `corpus/opmatrix` and `corpus/typed` (row P1.1's set),
   then `corpus/control`, `corpus/closure`, `corpus/seqs`. Record each
   directory's result in STATUS.md as rows `P8.0` onward in
   `checks/items.tsv`, following the existing row format: the exact
   command whose exit 0 means done.

## Acceptance for milestone 1

1. **GC output unchanged.** A check that compiles every program in
   `corpus/scalar/` and `corpus/eval/*/` with the default target before and
   after the change set and compares the `.wasm` bytes; identical. Keep it
   as a row so later linear work keeps being measured.
2. `WASM_RUN=checks/wasm-run-linear.sh checks/run-corpus.sh corpus/scalar`
   reports MATCH for every program.
3. `checks/run-corpus.sh corpus/opmatrix corpus/typed` under the linear
   runner, MATCH for every program (these are the integer edge cases:
   overflow, shifts, division by zero errors, the D16 quirks).
4. Gates 1 and 7 still green with `LW_ATTEST=0` (the GC lane).
5. A note in `DECISIONS.md` with the next number recording what was built
   and any deviation from the decisions above, and one line per limit met
   (an op refused under linear, a corpus directory not yet matching).
6. `README.md` gains a paragraph on the target and the runner, with the
   wazero fork and the two feature flags named, and the prerequisites
   section lists Go.

## Milestone 2: precise collector (D196)

Added 2026-10-06, after M1 and D195. "M2" here is always the linear
target's milestone; the self-host course uses M0/M1/M2 for something else
(the compiler compiling itself), so say "linear M2" where both could be
meant. Read wallisp's two collectors first (links above); the protocol
notes in `lisp_gc.c`'s header are the part that is easy to get wrong.

### What M1 already gives the collector

M1 is not a second emitter: `linear-module` in `src/lower_linear.lg`
rewrites the shaken GC module text. Everything the collector needs to be
precise is known at that point.

- **Object maps.** Every heap object starts with a 12-byte header: `kind`,
  `size` in bytes (header included), and a layout id. Each layout comes
  from a GC struct or array type (`repr-layouts`), so the rewriter knows
  which fields held references before they became `i32`.
- **Local roots.** The rewriter sees which locals and params had ref types
  in the GC text, and every function signature (`:functions`).
- **Tags.** A value with the low bit set is a fixnum and 0 is `nil`
  (decision 1), so "is this a pointer" is a tag test plus a range check.
- **Allocation is always a call.** `struct.new` and the array allocators
  lower to calls of `$lin_new_*`, which call `$lin_alloc`. No instruction
  allocates on its own, so a collection can only start inside a call.
- **Immortal statics.** Booleans, string constants and the named error
  objects live in data segments below `131072`, and the static area is a
  compile error past that (`lower_linear.lg`, "linear static area
  exhausted"). The heap is `[131072, $heap_top)`.
- **No re-entry from the host.** The runner calls `lw run`, then
  `lw report` or `lw trap` after it returns; no import calls back into the
  module.

### Decisions (a deviation goes in DECISIONS.md with the next number)

1. **Algorithm.** Non-moving mark-sweep, as the M2 bullet above says.
   Objects never move, so a stale copy of a pointer can keep garbage alive
   but can never point at the wrong object, and address-based identity
   stays stable.
2. **Shadow frames for locals.** A global `$lin_shadow_sp` points into a shadow
   stack region of linear memory. A function with ref-typed params or
   locals that makes any call gets a frame: on entry it moves `$lin_shadow_sp` by
   one slot per such local, zeroes the slots and stores its ref params;
   every `local.set`/`local.tee` of a ref local also stores to its slot.
   The callee owns its frame (callers push nothing). Phase 1 frames every
   such function; phase 3 narrows to functions that can reach `$lin_alloc`
   (a `call_indirect` counts as reaching it) and to locals live across a
   call.
3. **Operand-stack values.** In `(call $f (call $g) (call $h))`, `$g`'s
   result sits on the operand stack, invisible to the collector, while
   `$h` may allocate. Phase 1 moves every ref-typed argument that is not a
   `local.get`, `global.get` or constant (call results, block results, a
   catch's payload) into a fresh framed local, uniformly. Phase 3 narrows
   this to arguments followed by a sibling that contains a call. As of
   2026-10-06 (main 38accbc), `corpus/linear-gc/seq-pipeline.clj`'s module has 119 call
   results held across a later sibling call among 6,689 call sites, and
   fib 8 of 153; the count is an upper bound, since it includes `i64`
   results.
4. **Stack pointer discipline.** A framed function restores `$lin_shadow_sp`
   before every `return` and before `return_call`/`return_call_indirect`
   (its arguments are already on the operand stack, and nothing allocates
   between the restore and the call). A `throw` unwinds frames without
   running their restores, so every `try_table` handler resets `$lin_shadow_sp`
   to its own function's frame top, saved in a local on entry, and
   `lw run`'s handler resets it to the base.
5. **No local writes inside `try_table` bodies.** The runner's wazero pin
   (`0ec6142a`, as of 2026-10-06) predates wazero/wazero#2504: a caught
   exception reverts locals written inside the body to their values at
   block entry. Today every `try_table` body is a single call, so frames
   must not change that: slot stores stay outside `try_table` bodies until
   the pin includes that fix. Row P11.3 checks it.
6. **Tracing.** The rewriter emits a layout table as a data segment: for
   each layout id, its size and the offsets of its reference fields; for
   arrays, whether elements are references. `funcref` fields (closure code
   slots hold table indices), `i64`, `f64`, `i8` and non-reference `i32`
   fields are never traced, so `repr-field-type` keeps the GC field type
   alongside the `i32` it maps to. A traced value is followed only if it
   is untagged, non-zero and in `[131072, $heap_top)`; statics are never
   marked or swept, and phase 0 checks they hold no heap pointers.
7. **Heap blocks.** Every block, live or free, starts with the header, so
   the sweep walks the heap by `size`. The mark bit is bit 31 of the size
   word, cleared by the sweep. Free blocks get kind 0, adjacent free blocks
   coalesce during the sweep, and free lists are segregated by size in
   8-byte steps up to 512 bytes with one first-fit list above that.
8. **Roots.** The shadow stack between its base and `$lin_shadow_sp`, every
   ref-typed global (the var table, constants and runtime globals are all
   globals after `lin_init`), and nothing else. The mark stack is explicit
   (lazy-seq chains are deep) and lives above `$heap_top`, outside the
   heap, grown with `memory.grow` when needed.
9. **When to collect.** `$lin_alloc` tries the free lists, then bumps
   within the current memory, then collects once the bytes allocated since
   the last collection pass a threshold (1 MiB to start, then the live size
   after the last collection, at least 1 MiB), and only then grows memory.
   Phase 2 tunes these numbers against the gate budget and records them.
10. **Testing modes.** Three build flags, read by the driver like
    `LW_NO_EVAL`: `LW_GC_VERIFY=1` marks and checks every traced pointer
    lands on a valid header but frees nothing; `LW_GC_STRESS=1` collects
    at every allocation; `LW_GC_POISON=1` fills freed blocks with a fixed
    pattern and kind. Stress turns a missing root into a deterministic
    corpus failure, which is why phase 1 runs it before anything is freed.
11. **The GC target never moves.** `checks/gate.sh 11` also runs P8.0, so
    every phase's gate includes GC byte identity.

### Phases and rows

Each phase is its own pull request; its rows exit 2 until it lands
(`checks/linear-gc.sh` is the placeholder they share). Run them with
`checks/gate.sh 11`.

| Phase | Builds | Rows |
|---|---|---|
| 0 | Layout table, root enumeration, decision 10's verify mode; no frames, nothing freed | P11.0: the gate-8 corpus directories MATCH with `LW_GC_VERIFY=1`, collecting at program exit, zero bad pointers. P11.1: no static object holds a heap pointer. |
| 1 | Shadow frames, operand-stack spills, decision 4's restores | P11.2: the gate-8 corpus MATCHes with verify and stress together. P11.3: no `try_table` body writes a local. |
| 2 | Sweep, free lists, coalescing, the trigger | P11.4: the gate-8 corpus MATCHes with stress and poison. P11.5: `corpus/linear-gc/alloc-loop.lg`'s peak RSS at 10x the iterations is under 2x its peak RSS at 1x (bounded, not growing with run length). |
| 3 | Narrowed frames and spills; legmacs | P11.6: legmacs boots under the runner and its deftest count matches the GC lane's. P11.7: the gate-8 corpus still MATCHes under stress after narrowing. |

Measure startup, fib 35 and `corpus/linear-gc/seq-pipeline.clj` against the WasmGC
lane at the end of phases 2 and 3, dated, in the phase's DECISIONS.md
entry. As of 2026-10-06 under the wazero runner (D195), fib 35 takes about
95 ms of CPU and the allocating programs reach 0.3 to 0.9 GiB peak RSS,
because M1 never frees.

## Milestone 3 outline (Asyncify artifact)

- `wasm-opt --asyncify --pass-arg=asyncify-imports@env.sleep,term.read_key`
  over the linear module; measure size and speed against the JSPI module.
- A JS host mode beside the JSPI one in `host/lg-wasm-host.js` that drives
  `asyncify_start_unwind` / `asyncify_stop_unwind` /
  `asyncify_start_rewind` / `asyncify_stop_rewind` for the two blocking
  imports; Emscripten's Asyncify runtime is the reference for the
  protocol.
- Feature detection in `host/pages-index.html` and the demo pages: JSPI
  present loads the WasmGC module, otherwise the Asyncify linear module.
  The landing page's browser note changes accordingly.

## Rules for whoever builds this

- Work on a branch of this repository and open a pull request; CI runs the
  publish check on it. Do not push to `main`.
- `src/` changes are the risky part: keep the GC byte-identity check green
  after every emitter commit, not only at the end.
- Native lg is the oracle for everything. When native and linear disagree,
  the backend is wrong until a `FINDINGS.md` entry shows native is.
- Named limits are fine; silent divergence is not. An op the linear target
  does not handle is a compile error naming the op, pinned in
  `corpus/refused`, exactly as the GC lane does.
- Dates on every number.
