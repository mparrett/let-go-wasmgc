# Spec: a native target through LLVM IR, in continuation-passing style

Written 2026-10-07 as a work order for an agent or a person who has not
seen this code before. Read `README.md`, then `docs/READING-GUIDE.md`
(stops 1 to 8 and 11), then `docs/LINEAR-TARGET-SPEC.md` for the shape of
a second target, then this file. The spike behind it is D199, on branch
`spike/llvm-target`.

## Why

1. **Native programs without a wasm engine,** on 64-bit and on 32-bit
   hardware: desktop and server machines, Linux-class 32-bit ARM, and
   microcontrollers (ARM Cortex-M, RISC-V 32). A program becomes a native
   executable, a bare-metal image, or a module run under LLVM's JIT.
2. **Continuations for free.** Lowering in continuation-passing style
   (CPS) makes every call a tail call and every pending computation a
   heap object. That removes stack overflow on deep recursion, makes
   `try` a matter of passing a handler continuation, and makes `go` blocks
   and channels (a named limit since D162) a scheduler over continuations.
3. **A JIT later.** Emitting LLVM IR text keeps the door open to compiling
   at run time through ORC, as `docs/SELF-HOST-SPEC.md` does for wasm.

**The yardstick is jank's `clojure-test-suite`** (`$LETGO/test/clojure-test-suite`,
a submodule pinned at bd610c8 by let-go ff1e6dac). Native lg at the pin
passes all of it: 242 files, 6,311 assertions, 0 failures (let-go's
`TestClojureTestSuite`, 2026-10-07). The target first runs the suite on
64-bit, then on 32-bit; until then, no code may assume the word size.

## Scope

Seven milestones. M1 is the deliverable of this spec; the others are
described so that M1 does not paint them out.

- **M1, the jank suite on the 64-bit host.** The CPS emitter, the runtime
  library and hardware profiles; allocation never frees. Done when the
  suite meets "Acceptance for M1" on the host profile, ahead of time and
  under `lli`. No code assumes a word size: the host profile narrowed to
  31-bit fixnums runs the same rows (decision 14).
- **M2, a mark-sweep collector.** Written fresh, from the standard
  algorithm; roots are taken at function entry (decision 7). Done when
  legmacs boots on the host profile and reaches the WasmGC lane's deftest
  count (316 of 373 as of 2026-10-02), with the suite still green on both
  host profiles.
- **M3, 32-bit: the jank suite on `armv7-virt`.** The bare host, the
  armv7 board files, and the M1 rows under qemu, with the M2 collector.
  From M3 on, `armv7-virt` is the pinned 32-bit profile.
- **M4, `go` blocks and channels.** A scheduler over continuations. Done
  when native lg's `go`/`<!`/`>!`/`chan`/`timeout` tests MATCH.
- **M5, a JIT.** ORC's LLJIT inside the native program, with the emitter
  resident (the native counterpart of SELF-HOST-SPEC stages 3a and 3b).
- **M6, the small profiles.** RISC-V 32 and Cortex-M, which need the
  uniform calling convention (decision 3) and, on Cortex-M, a heap that
  fits in RAM. Done when the M1 corpora MATCH on `rv32-virt` and
  `thumbv7m-mps2` under qemu, run once on demand (decision 14).
- **M7, `call/cc` for let-go programs.** A primitive that hands the
  current continuation to a fn as a callable value. Not scheduled; M1
  keeps it possible (decision 15).

## What exists that this builds on

- **The spike (D199).** `src/lower_llvm.lg` is in the `lower-wasm`
  namespace and loads on demand, as `lower_linear.lg` does. It handles
  integer arithmetic with overflow checks, comparisons, branches, joins,
  calls between program defns, and `println` of scalars, with every value
  an i64 word and the host's tail-call convention hard-coded.
  `corpus/scalar` is 4/5 MATCH, both AOT and under `lli`.
  `host/native/lg_rt.c` is its C host and `checks/native-run.sh` its runner.
- **The seams (D192).** The driver's `--target` flag and `LW_TARGET`;
  `lower-fn` and `session-module` in `src/lower_wasm.lg`, which hand off
  to `llvm-fn` and `llvm-module` under `:llvm`. A new need is met in
  `lower_llvm.lg` or by widening one of these seams, never by a new
  `*target*` conditional elsewhere.
- **The analysis.** `analyze-fn`, the driver's boxing fixpoint, `ty`,
  `src-of`, `rt-target` and the twin table are target-neutral and shared.
  The emitter reads the indexed RPN IR through `ir/blocks`,
  `ir/block-insts`, `ir/block-params`, `ir/block-term`, `ir/op`,
  `ir/refs` and `ir/aux`; it does not use the structured tree that `walk`
  lowers for wasm.
- **The runtime.** `rt/wasm/*.lg` is written against the 43 intrinsics of
  `rt/wasm/intrinsics.lg` and runs under native lg through their reference
  implementation (`checks/run-intrinsics-native.sh`). Each intrinsic needs
  an LLVM form; that list is the M1 checklist, as the instruction census
  was for the linear target.
- **The handwritten WAT.** About 700 lines in `src/lower_wasm.lg`
  (`print-runtime`, `exn-runtime`, `fn-runtime`, `bframe-runtime`,
  `$rt_invoke<n>`, the box helpers) have no IR source. Their native forms
  are C in `host/native/`, or LLVM IR text in `lower_llvm.lg`.
- **The host ABI** (`host/ABI.md`). The native hosts implement the same
  imports as C functions; `sleep` and `read_key` block.
- **Tools on the development machine** (2026-10-07): the LLVM project only,
  from Homebrew: `llvm` 23.1.2 (`llc`, `opt`, `clang`, `lli`, `llvm-link`,
  `llvm-ar`) and `lld` 23.1.2 (a separate formula); compiler-rt's builtins
  for a bare board are built from source by `checks/build-builtins.sh`,
  since Homebrew's LLVM ships them for Darwin only. Also `cmake` and
  `ninja` for that build, `qemu-system-arm` (machines `virt` and
  `mps2-an385`) and `qemu-system-riscv32` (`virt`).

## Design decisions (made; do not reopen without a note in DECISIONS.md)

1. **Lower the IR directly.** No wasm text, no rendering of the GC
   instruction stream. `lower_llvm.lg` emits LLVM IR text from the same
   analysed IR the wasm emitter consumes.

2. **Hardware profiles are EDN files.** A profile describes one hardware
   and host combination. It is data, not code: the driver reads it with
   the EDN reader, nothing in it is evaluated, and its bytes are part of
   the runtime-library and module cache keys. Profiles live in
   `targets/<name>.edn` and are selected with `--profile <name or path>`
   or `LW_PROFILE`; without one, the driver uses the host profile for the
   machine it runs on. Fields:

   ```clojure
   {:name        "armv7-virt"
    :triple      "armv7-none-eabihf"   ; LLVM target triple
    :cpu         "cortex-a7"           ; optional, passed to llc
    :features    "+strict-align"       ; optional, passed to llc
    :cflags      ["-mcpu=cortex-a7" "-mfloat-abi=hard" "-mno-unaligned-access"]
                                       ; clang flags: host C, board assembly, builtins
    :word-bits   32                    ; pointer and boxed-word width
    :fixnum-bits 31                    ; signed; at most (dec word-bits), the default
    :tail-calls  :tailcc               ; :tailcc or :uniform (decision 3)
    :float       :hard                 ; :hard, or :soft for no FPU
    :host        :bare                 ; :posix or :bare (decision 11)
    :board       "armv7-virt"          ; :bare only: host/native/boards/<board>/
    :heap        {:bytes 805306368}    ; :bare only: the heap's size
    :run         ["qemu-system-arm" "-M" "virt" "-cpu" "cortex-a7" "-m" "1024M"
                  "-nographic" "-monitor" "none"
                  "-semihosting-config" "enable=on,target=native" "-kernel"]}
   ```

   The first profiles are `host` (generated from the build machine:
   aarch64-apple-darwin on the development machine), `armv7-virt`
   (Cortex-A7, bare, under `qemu-system-arm -M virt`; the pinned 32-bit
   profile, decision 14), `rv32-virt`
   (RV32IMAC, bare, under `qemu-system-riscv32 -M virt`) and
   `thumbv7m-mps2` (Cortex-M3, bare, under `qemu-system-arm -M
   mps2-an385`). An armv7 Linux profile is possible but not scheduled; its
   userland needs an emulated Linux to run on the development machine.

3. **CPS, with the tail-call convention chosen by the profile.** Every
   lowered function takes its continuation `k`, never returns a value, and
   ends in a `musttail` call. A call whose result is used later allocates
   a continuation record `[code, k, saved...]`; a call whose result is
   returned directly passes `k` through. LLVM guarantees `musttail` only
   on some targets and conventions (cross-compiled with `llc` from LLVM 23,
   2026-10-07; not yet run on hardware or qemu):

   | targets | `tailcc`, differing prototypes | one prototype, C convention |
   |---|---|---|
   | x86-64, aarch64, i686, armv7, thumbv7m | yes | yes |
   | riscv32, wasm32 (with `+tail-call`) | no | yes |
   | mips32 (both endians), powerpc32 | no | no |

   `:tailcc` is the spike's convention: `tailcc void (ptr %k, args...)`,
   each argument in its own LLVM type. `:uniform` gives every CPS function
   the prototype `void (ptr %k, ptr %args)`: the caller writes arguments
   into a per-thread argument buffer (a global, single-threaded until M4)
   and the callee reads them first thing. Targets with neither (MIPS,
   PowerPC 32) are a named limit; a trampoline strategy, where each
   function returns its successor to a loop in `lg_run`, would cover them
   and is not scheduled.

4. **Pieces, joins and continuation functions.** A block is cut after each
   call that needs a continuation; `[b n]` is block b's piece n. Each piece
   after a cut, the fn's entry, and each block with other than one
   predecessor is an LLVM function of its own. A one-predecessor block is a
   basic block of the function that reaches it, so no code is duplicated.
   Values cross into a function as arguments (joins) or as saved slots
   (continuations), per a liveness pass over pieces. A fn-level `recur`
   that branches back to the entry block gets the entry's body moved into
   a join function, so the entry can be re-entered.

5. **Leaf functions stay direct.** A function whose calls reach only
   leaves (intrinsics, primitive ops, C helpers, other leaves; a fixpoint
   over the call graph) compiles as an ordinary `fastcc` function returning
   its value, called with a plain `call`. Most runtime helpers (hashing,
   string building, collection internals) are leaves, so this keeps the
   number of continuations close to the number of user-level calls. A leaf
   never triggers a collection (decision 7).

6. **Values: let-go's numbers are fixed, the word is the profile's.**
   - An `:int` is always an LLVM `i64`, on every profile, because let-go's
     integers are 64-bit (native lg is Go's int64, and the oracle compares
     against it). On 32-bit profiles LLVM legalizes i64 arithmetic into
     register pairs and calls compiler-rt's builtins (`__aeabi_ldivmod` and
     the like), which bare profiles link from `checks/build-builtins.sh`.
   - A `:float` is always an LLVM `double`; with `:float :soft` LLVM calls
     compiler-rt's soft-float routines.
   - A `:bool` is an `i1` inside a function and a word where it is stored.
   - A boxed value is a word of `:word-bits`. Low bit 1 is a fixnum
     (`v << 1 | 1`); 0 is `nil`, 2 is `false`, 4 is `true`; anything else
     points at a heap object. Integers outside the profile's fixnum range
     are heap `Int` objects holding an i64, as D41 boxes them. Floats are
     always heap objects.
   - Every heap object starts with a header word holding its kind (the
     numbers `wasm.seq/kind` returns) and its size; arrays add a length.
   - Continuation records, closure environments and heap objects are LLVM
     struct types, and sizes come from the `getelementptr` size idiom, so
     field offsets and alignment follow the profile triple's data layout.
     Nothing in the emitter assumes 8-byte words or 8-byte alignment.

7. **Collection at function entry.** In M2, every CPS function begins with
   a check of the allocation budget, reserving what its body allocates
   (bodies are loop-free in CPS, since loop heads are join functions, so
   the amount is bounded). A collection runs only there, and its roots are
   that function's arguments (or its argument buffer, under `:uniform`),
   the globals and the var table: nothing else is live, because every call
   is a tail call. No stack maps, no shadow stack, no conservative scan. A
   variable-size allocation is a CPS call, so it is an entry point too. A
   leaf that exhausts the budget grows the heap where the host can
   (`:posix`), or fails with a named out-of-memory error (`:bare`); the
   collection waits for the next entry check. The heap is non-moving, so
   `host/ABI.md`'s pointer-and-length imports get object payloads directly
   (D176). LLVM's `gc "statepoint-example"` strategy is the named fallback
   if a collection is ever needed in the middle of a function.

8. **The fixnum range is parameterized.** The runtime stops hard-coding
   i31. Three intrinsics replace `wasm/i31`, `wasm/i31?` and
   `wasm/i31-get`: `wasm/fix`, `wasm/fix?` and `wasm/fix-get`, plus two
   constants, `wasm/fix-min` and `wasm/fix-max`. Under `--target gc` and
   `--target linear` they lower exactly as the i31 forms do today, with
   bounds -2^30 and 2^30-1. Under `--target llvm` the bounds come from the
   profile's `:fixnum-bits`, a signed width as in D41 (N bits holds
   -2^(N-1) to 2^(N-1)-1): 63 on the 64-bit host profile by default,
   31 on the 32-bit profiles, which is D41's range. A profile may
   narrow it, which is how a 64-bit build is compared with D41's range
   under the oracle. D41's canonical-form rule holds per build: an int
   inside the build's range is never a heap `Int`. The places that spell
   the range today are `rt/wasm/seq.lg:98` (`box-int`),
   `rt/wasm/intrinsics.lg:304` (the reference bounds), `coerce` and the two
   box helpers in `src/lower_wasm.lg` (lines 200, 3094 and 3144), and
   `rt/wasm/emit.lg:854`.

9. **Exceptions are a handler register.** A global `lg_handler` points at
   the innermost handler frame `[handler code, saved k, prior frame,
   binding depth]`. `try` pushes a frame and runs the body with a
   continuation that pops it before continuing; `throw` pops the frame,
   unwinds dynamic bindings to its depth, and calls its handler code with
   the exception value. `finally` is a frame whose code runs the finally
   region, then rethrows the original value, so a raw runtime error keeps
   its uncaught message (D31). The lifted try regions the IR already
   produces are reused as they are. A throw from CPS code calls the handler
   directly. A leaf (decision 5) cannot, since it must return to its
   caller, so a throw from a leaf stores the exception in `lg_pending` and
   returns a sentinel; a leaf that calls another leaf passes the sentinel
   straight back, and the first CPS caller to see it calls the handler.
   That is one compare per leaf call, on every profile. There is no
   `setjmp` or `longjmp` anywhere: control moves only by calling
   continuations, and this target does not use Cheney on the MTA.

10. **Closures.** A fn value is a heap object `[header, info, code per
    arity 0 to 4, env...]`, mirroring `$Fn` (D52); variadic and higher
    arities extend it as `$FnV` and `$FnX` do (D83, D150). A call through
    a value goes to `lg_invoke<n>`, which checks the arity and tail-calls
    the code with the closure as `%self`. The code slots hold function
    pointers; there is no function table.

11. **Hosts.** `host/native/posix.c` implements `host/ABI.md` over C
    stdio, `malloc`, `nanosleep`, `getenv` and the process arguments.
    `host/native/bare.c` implements it with no OS: output through ARM or
    RISC-V semihosting (`SYS_WRITE0`, `SYS_WRITEC`), exit status through
    `SYS_EXIT_EXTENDED` (so qemu exits with the program's status), a static
    heap of `:heap :bytes`, `getenv` and `os/args` empty, `sleep` a
    busy-wait on the cycle counter, and `read_key` end of input. Each bare
    profile adds its startup code (vector table or `_start`, stack, `.bss`
    clearing) and linker script under `host/native/boards/`. Both hosts
    are written for any word size (`intptr_t`, no 8-byte assumptions).

12. **Runner.** `checks/native-run.sh` reads the profile. For a `:posix`
    profile it builds the `.ll` and the posix host with clang. For a
    `:bare` profile it compiles the `.ll` with `llc` for `:triple`, `:cpu`
    and `:features`, links it with clang and lld (`-nostdlib`, the board's
    `start.S` and `link.ld`, the bare host, compiler-rt's builtins), and
    runs the image with `:run`. The LLVM project is the only toolchain. With
    `LW_NATIVE_JIT=1` on the host profile it links the module with the
    host's bitcode and runs it under `lli`. It behaves like `lg` on stdout
    and exit status, so `checks/oracle.sh` uses it through `WASM_RUN`.

13. **Acceptance is behaviour.** Every claim for this target is an oracle
    MATCH against native lg. This target adds no byte-identity checks of
    its own. The WasmGC lane keeps its existing ones (row P8.0 and
    `checks/gc-byte-identity.sh`), and every change set must keep them
    green, because the seams in decision 1 are shared.

14. **One pinned 32-bit profile, from M3.** In M1 the gate runs the host
    profile and the host profile narrowed to 31-bit fixnums
    (`host-*-fix31`), which needs no emulator and catches code that assumes
    a fixnum fits a 64-bit word. From M3 the gate runs the host and
    `armv7-virt`. `armv7-virt` is there to keep the target honest about
    word size, i64 legalization and the bare host; it is not a claim that
    every profile works all the time. `rv32-virt` and `thumbv7m-mps2` have
    rows of their own that run on demand (`checks/gate.sh` skips them unless
    `LW_ALL_PROFILES=1`), and a milestone that claims them runs them once.
    A change that breaks a profile the gate does not run is found when that
    profile is next run, not before; that is the accepted cost.

15. **Continuations stay re-enterable.** M1 does not expose `call/cc`
    (M7), but it must not rule it out. A continuation record is never
    mutated or reused after it is allocated, so calling the same
    continuation twice is safe. Dynamic state that a continuation depends
    on lives where a reified continuation can capture it: the handler
    register (decision 9) and the dynamic-binding stack are heap
    structures reachable from a pointer, not C-stack state, so M7 can save
    both with `k` and restore them on re-entry. Native lg has no
    `call/cc`, so M7 cannot be checked by the oracle. Its tests are a
    corpus with expected output written by hand, and the spec for M7 must
    name that exception to decision 13.

## Milestone 1 work, in order

1. **Profiles.** The EDN reader in the driver, `--profile` and
   `LW_PROFILE`, the host profiles (and their `-fix31` variants), the
   profile in the cache keys, and `checks/native-run.sh` driven by it.
2. **Word-size-generic emitter.** Replace the spike's i64-everywhere
   values with decision 6's types; continuation records as struct types.
   The spike's `corpus/scalar` results must hold on the host profile and
   its `-fix31` variant.
3. **The suite harness, early.** `checks/jank-suite.sh` runs the suite's
   `core_test` and `string_test` files the way `checks/run-tests.sh
   --corpus` runs let-go's core tests: native lg's `run-tests` report
   against the backend's `--test` build, deftest by deftest. Both sides
   read `.cljc` files with `:clj` reader conditionals and load let-go's
   portability shim (`$LETGO/test/compat/clojure/core-test/portability.lg`)
   ahead of the suite's own. It prints `files MATCH M/F` and
   `deftests N/T`, and classifies each failing deftest's cause, with D15
   (Ratio, BigInt, BigDecimal) as its own column. It runs under any
   `WASM_RUN`, so the WasmGC lane's score is recorded once as a reference.
   A ratchet file (`corpus/jank/baseline.tsv`) records the passing
   deftests; the gate row fails when one that passed stops passing.
4. **Fixnum parameter.** Decision 8 for the existing targets first, with
   no behaviour change: P8.0 green, `checks/run-intrinsics-native.sh`
   green.
5. **Emitter completion for program code.** Boxed constants (strings as
   heap byte arrays, keywords and symbols interned at startup), the var
   table, `:def` and `:set-var`, closures (decision 10), calls through
   values, fn-level `recur` (decision 4), `=` beyond two ints through the
   runtime's `equiv?`.
6. **Intrinsics.** An LLVM form for each of the 43 intrinsics: struct and
   array allocation, field and element access, kind tests and casts
   against the header, fixnum and float boxing, byte arrays, host calls.
   A failed cast raises the same named error the GC lane raises, never a
   crash.
7. **Leaf classification** (decision 5), then the runtime library: drop
   the driver's `:llvm` forcing of `--no-rt`, compile `rt/wasm/*.lg`
   through the emitter, and port the handwritten WAT helpers to C or LLVM
   text.
8. **Exceptions** (decision 9).
9. **Host ABI.** Every import in `host/ABI.md` in `posix.c`.
10. **The refused top-level forms.** `src/driver.lg` refuses `defmulti`,
    `deftype`, `defprotocol` and `defrecord` (line 834) although let-go's
    IR builds them. Seven suite files use them (2 multimethods, 5 types,
    records or protocols). Lifting the refusal is front-end and runtime
    work shared by every target, so the WasmGC lane gains them too; the
    GC byte guard holds because no program in its set used these forms.
11. **The suite to its bar.** Work the harness's failures down by cause
    until "Acceptance for M1" holds, recording each gate-12 row in
    `checks/items.tsv`.

The D15 question (implement Ratio, BigInt and BigDecimal, or count those
deftests as named exceptions) is decided after step 3's first full run
on the WasmGC lane and step 11's first full run on this target, from the
measured count. The decision is a DECISIONS.md entry; until it is made,
D15-caused failures are reported, not counted against the bar.

## Acceptance for milestone 1

1. **WasmGC lane unchanged.** P8.0 and `checks/gc-byte-identity.sh` pass
   after every step; `checks/gensym-load.sh` (P9.1) passes.
2. **The jank suite.** On the host profile, every `core_test` and
   `string_test` deftest that native lg passes MATCHes, except those whose
   only failure cause is D15 (pending the decision above), ahead of time
   and under `lli`. The same holds on the `-fix31` host profile.
3. **The repo's corpora.** `corpus/scalar`, the selected
   `corpus/opmatrix` (D177's exclusions), `corpus/typed`,
   `corpus/control`, `corpus/closure` and `corpus/seqs` MATCH on the host
   profile and its `-fix31` variant.
4. **Deep recursion.** A non-tail recursion ten million deep finishes
   without a stack overflow, and ten million mutual tail calls through fn
   values run in constant C stack.
5. **The convention is checked, not assumed.** `checks/native-run.sh`
   refuses a profile whose `:tail-calls` its triple cannot honour: `llc`
   reports "failed to perform tail call elimination" or "Unsupported
   calling convention", and the runner names the profile and the field.

## Milestone 2: the collector

- **Algorithm.** Non-moving mark-sweep over size-segregated pages: a mark
  bit in each header, an explicit mark stack, precise tracing by kind from
  a layout table the emitter generates from its struct types (reference
  fields only; raw i64 and double fields skipped), sweeping each page into
  its size class's free list, and a growth-based trigger (collect when
  bytes allocated since the last collection exceed the live size). Page
  and size-class sizes come from the profile, so a Cortex-M heap of tens of
  kilobytes and a desktop heap of gigabytes use the same code.
- **Roots.** As decision 7: the arguments of the function at whose entry
  the collection runs, the globals, the var table, the interned keywords
  and symbols, and `lg_handler`'s frames.
- **Where it lives.** The collector is written in let-go (for example
  `rt/native/gc.lg`) against a small set of raw-memory intrinsics (word
  and byte loads and stores, address arithmetic, page allocation, copy and
  fill), with a reference implementation over a byte array, so it is
  tested under native lg before it is compiled. A compile-time check
  rejects any allocation inside collector code.
- **Done** when legmacs boots on the host profile and its deftests reach
  the WasmGC lane's count, with peak memory recorded against native lg, and
  the jank suite still passes its ratchet on both host profiles.

## Milestone 3: 32-bit on `armv7-virt`

`targets/armv7-virt.edn`, `host/native/bare.c` (decision 11) and the
armv7 board files, then the M1 acceptance rows under `qemu-system-arm`.
Done when acceptance items 2 to 4 of M1 hold on `armv7-virt`, a bare
profile with a small `:heap :bytes` reports `error: out of memory` and
exits 1 on exhaustion, and `armv7-virt` replaces `-fix31` as the gate's
second profile (decision 14).

## Milestone 6: the small profiles

The `:uniform` convention (decision 3), then `rv32-virt` and
`thumbv7m-mps2`. Cortex-M3 has no FPU, so `thumbv7m-mps2` uses
`:float :soft`; its `:heap :bytes` is limited by the board's RAM (4 MB on
`mps2-an385`), so it needs M2's collector. Done when the M1 acceptance
corpora MATCH on both, run once on demand.

## Named limits

- Ratio and BigInt results remain named errors (D15), as on the other
  targets.
- Until M2, every continuation leaks: fib(35) peaks near 490 MB on the host
  against native lg's 19 MB (spike, 2026-10-07), so the bare profiles run
  only small programs before M2.
- MIPS and PowerPC 32 have no profile: LLVM gives no guaranteed tail call
  on them under any convention (decision 3).
- LLVM's wasm32 backend accepts the `:uniform` convention with
  `+tail-call`: 10 million mutual tail calls through a function table ran
  under node 26, linked by `zig cc -target wasm32-wasi` (2026-10-07). A
  wasm32 profile is possible but not scheduled. Decision 9 uses no
  `setjmp`, which matters here: zig 0.16's wasi-libc `setjmp` fails in the
  LLVM backend ("undefined tag symbol cannot be weak"). It would not
  exercise i64 legalization (wasm has native i64), which is why
  `armv7-virt` is the pinned 32-bit profile.
- Until M5, run-time compilation (`LW_RUNTIME_COMPILE`, `rt/wasm/emit.lg`)
  is a named compile refusal under this target; `eval` works through the
  evaluator.
- Performance against the WasmGC lane under V8 is unmeasured; the spike's
  10 to 20× over native lg's bytecode VM is not that comparison. A fib and
  an allocation-heavy benchmark against both are rows of gate 12.
