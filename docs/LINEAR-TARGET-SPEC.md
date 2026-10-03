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
- **M2, precise collector.** A non-moving mark-sweep collector with a shadow
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

## Milestone 2 outline (precise collector)

- Read wallisp's two files first (links above); the protocol notes in
  `lisp_gc.c`'s header are the part that is easy to get wrong.
- Shadow stack: a region of linear memory with `global $sp`; every
  function that holds a pointer across a call pushes it on entry and pops
  on exit; the emitter knows which locals are pointers because the kind
  table does. Pointer-typed arguments are pushed by the caller or callee,
  pick one and record it. Tail calls pop before `return_call`.
- Mark from the shadow stack, the globals and the var table; sweep into
  size-class free lists; `alloc` tries the lists first and collects when
  `memory.grow` would be needed, with a growth policy that keeps the
  oracle's timings within the gate budget.
- Done when legmacs boots and its suite matches the GC lane's count, and
  when a long-running corpus program's memory stays bounded (add one that
  allocates in a loop for a few seconds).

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
