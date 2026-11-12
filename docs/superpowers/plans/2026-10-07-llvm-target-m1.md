# `--target llvm` Milestone 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** jank's `clojure-test-suite` runs under `--target llvm` on the 64-bit host and MATCHes native lg deftest by deftest (D15-caused failures reported separately until decided), ahead of time and under `lli`, with no code assuming the word size.

**Architecture:** `src/lower_llvm.lg` (in the `lower-wasm` namespace, loaded on demand) lowers the analysed indexed RPN IR: blocks are cut at continuation calls, pieces and joins become `musttail` functions, one-predecessor blocks stay basic blocks. A hardware profile (EDN) fixes word size, fixnum width, tail-call convention and host. A C host in `host/native/` implements `host/ABI.md`. The suite harness compares native lg's `run-tests` report with the backend's `--test` build per deftest.

**Tech Stack:** let-go (pinned lg ff1e6dac), Homebrew LLVM 23 (`llc`, `opt`, `clang`, `lli`, `llvm-link`), wasm-tools and binaryen (for the WasmGC guards), bash checks.

**Spec:** `docs/LLVM-TARGET-SPEC.md` (decisions referenced as S1–S15; M1 work steps as W1–W11). Decisions D206, D207.

## Global Constraints

- Run env for every command: `LW_ROOT=$HOME/development LETGO=$HOME/development/let-go LG=<pinned lg ff1e6dac>`. The pinned lg: `git -C $LETGO archive ff1e6dac | tar -x -C <dir> && (cd <dir> && go build -ldflags="-s -w -X main.commit=ff1e6dac76" -o <dir>/lg-ff1e6dac76 .)`.
- Suite location: `$LETGO/test/clojure-test-suite/test/clojure/{core_test,string_test}/*.cljc` (submodule at bd610c8, the commit ff1e6dac records). Native lg at the pin passes 242 files, 6,311 assertions.
- Acceptance is behaviour: oracle MATCH (`WASM_RUN=checks/native-run.sh checks/oracle.sh <prog>` prints `MATCH`) or the harness's per-deftest agreement. No byte-identity checks for this target (S13).
- A task that touches `src/driver.lg`, `src/lower_wasm.lg`, `src/lw_rt.lg`, `src/lw_ext.lg` or `rt/` ends with `checks/gc-byte-identity.sh` (P8.0, about 20 min cold) exiting 0 and `checks/gensym-load.sh` (P9.1) printing `OK gensym counter after load: 1130`. Tasks that touch only `src/lower_llvm*.lg`, `host/native/`, `targets/`, `corpus/` or new `checks/` scripts skip P8.0: the GC build never loads those files.
- New logic goes in `src/lower_llvm*.lg`, `host/native/`, `targets/`, or the seams named in S1/D192 (`target-args`, the session map, `lower-fn`, `session-module`, the rtlib key). No new `*target*` conditionals elsewhere. Task 10's front-end work is the stated exception and is target-neutral.
- Code on the driver's load path takes no gensyms: no destructuring `let`/`fn` params, no `for`, no auto-gensym in additions to `src/driver.lg` or `src/lower_wasm.lg` (D192, D196).
- `:int` is LLVM `i64` and `:float` is `double` on every profile; only the boxed word follows `:word-bits` (S6). Nothing in `lower_llvm*.lg` or `host/native/` may hard-code 8-byte words or alignment.
- Boxed words: low bit 1 fixnum `v << 1 | 1`; `0` nil; `2` false; `4` true; otherwise a pointer to an object whose first word is the header (S6).
- No `setjmp`/`longjmp` anywhere (S9). Continuation records are never written after their initialising stores (S15).
- Gate 12 rows live in `checks/items.tsv` (`id<TAB>phase<TAB>command<TAB>done-when`), each with a line in `checks/affected.sh`'s table.
- Every host row also runs on the `-fix31` host profile (S14).

## Review Focus

1. **Integers at the fixnum edges** (±2^30, ±2^31, ±2^62, MinInt64, MaxInt64) through params, continuation records, collections and `=`/`hash` must print and compare as native lg does on both host profiles. Test: Task 3, `corpus/llvm/fixnum-edges.lg`; Task 7 adds the collection line.
2. **Deep recursion**: non-tail recursion 10,000,000 deep and 10,000,000 mutual tail calls through fn values finish without a C stack overflow. Test: Task 5, `corpus/llvm/deep.lg`.
3. **A throw from a leaf inside a runtime higher-order call** (`(map #(nth [] %) [1])` realised under a user `try`) reaches the user's handler with native's message, and dynamic bindings are unwound. Test: Task 8, `corpus/llvm/leaf-throw.lg`.
4. **`.cljc` reader conditionals** (`#?(:clj … :cljs … :default …)` and `#?@` splicing) select the same branch on both sides of the harness. Test: Task 4, fixture `corpus/jank-harness/conditionals.cljc`.
5. **`thrown?` with an exception class** (`Exception`, `ArithmeticException`, `ClassCastException`, `IllegalArgumentException`, `ExceptionInfo`) matches as native's class test does. Test: Task 8, `corpus/llvm/thrown-classes.lg`.

---

### Task 0: Land the spike as the baseline

**Files:** (git only) branch `spike/llvm-target` → `llvm-target`

- [ ] **Step 1:** `git branch -m spike/llvm-target llvm-target`
- [ ] **Step 2:** `for p in fib.clj loop-recur.clj ref.lg tak.clj; do WASM_RUN=checks/native-run.sh checks/oracle.sh corpus/scalar/$p; done` prints four `MATCH`.
- [ ] **Step 3:** Commit `src/lower_llvm.lg host/native/lg_rt.c checks/native-run.sh src/driver.lg src/lower_wasm.lg DECISIONS.md docs/LLVM-TARGET-SPEC.md`: `llvm target: CPS spike and spec (D206-D208)`. The plan stays local: `docs/superpowers/` is in the global git ignore.

### Task 1: Gate 12 and the first row

**Files:**
- Create: `corpus/llvm-scalar/` (copies of `corpus/scalar/{fib.clj,loop-recur.clj,ref.lg,tak.clj}` with their `.expected` files)
- Modify: `checks/items.tsv`, `checks/affected.sh`

**Interfaces:**
- Produces: row `P12.1` = `env WASM_RUN=checks/native-run.sh checks/run-corpus.sh corpus/llvm-scalar`; `checks/gate.sh 12` runs every phase-12 row.

- [ ] **Step 1:** Add `P12.1	12	env WASM_RUN=checks/native-run.sh checks/run-corpus.sh corpus/llvm-scalar	<date>: scalar programs MATCH native lg on the host profile (D206)` and `P12.1	oracle src/lower_llvm.lg host/native/ checks/native-run.sh corpus/llvm-scalar/` in `affected.sh`.
- [ ] **Step 2:** `LW_ATTEST=0 checks/gate.sh 12` exits 0.
- [ ] **Step 3:** Commit `gate 12: llvm scalar row`.

### Task 2: Hardware profiles (W1)

**Files:**
- Create: `src/lower_llvm_profile.lg` (in `lower-wasm`; required by `lower_llvm.lg`), `targets/host-aarch64-darwin.edn`, `targets/host-x86_64-linux.edn`, `checks/profile-field.lg`, `checks/llvm-profile-check.sh`, `corpus/llvm-profile/{bad-word,bad-fixnum,bad-tailcalls,missing-triple,uniform}.edn`
- Modify: `src/driver.lg` (`target-args` also takes `--profile v`, `--profile=v`, `LW_PROFILE`; flag wins; returned in opts as `:profile`), `src/lower_wasm.lg` (`new-session` keeps `:profile`; `with-session*` binds `*llvm-profile-arg*`), `checks/native-run.sh`

**Interfaces:**
- Produces: `(llvm-profile) -> map`, memoised per session. Reads `targets/<name>.edn` or a path with `clojure.edn/read-string`; with no profile picks `host-<arch>-<os>` from `uname -m`/`uname -s`. Validates: `:triple` string; `:word-bits` ∈ #{32 64}; `:fixnum-bits` integer in `[2, (dec word-bits)]`, default `(dec word-bits)`; `:tail-calls` ∈ #{:tailcc :uniform}; `:float` ∈ #{:hard :soft}; `:host` ∈ #{:posix :bare}; `:heap :bytes` required with `:host :bare`. A violation throws `lower-wasm: profile <name>: <field> <reason>`. `:tail-calls :uniform` and `:host :bare` pass validation but the emitter refuses them with `lower-wasm: profile <name>: <field> <value> is not implemented before M3/M6` (`:host :bare` is M3, `:tail-calls :uniform` M6).
- Produces: `lg checks/profile-field.lg <profile> <key>` prints the field (vectors space-separated, keywords without `:`); exit 1 on an unknown profile.
- Produces: `checks/native-run.sh` takes the profile from `LW_PROFILE` (default host), passes `--profile` to the driver and uses the profile's `:link` command.

- [ ] **Step 1: Write the failing check.** `checks/llvm-profile-check.sh` asserts: (a) `corpus/scalar/fib.clj` compiles with no profile and with `--profile host-aarch64-darwin`; (b) each `bad-*.edn` and `missing-triple.edn` fails with a first error line starting `lower-wasm: profile` that names the field; (c) `uniform.edn` fails with the not-implemented refusal; (d) `--profile` beats `LW_PROFILE`; (e) `lg checks/profile-field.lg host-aarch64-darwin word-bits` prints `64`.
- [ ] **Step 2:** Run it: FAIL (unknown flag `--profile`).
- [ ] **Step 3:** Implement the interfaces. The spike's `i64` word stays until Task 3.
- [ ] **Step 4:** The check exits 0; `LW_ATTEST=0 checks/gate.sh 12` exits 0; P8.0 and P9.1 green (driver and session seams changed).
- [ ] **Step 5:** Row `P12.2	12	checks/llvm-profile-check.sh`; commit `llvm target: hardware profiles (S2)`.

### Task 3: Word-size-generic values and records (W2)

**Files:**
- Modify: `src/lower_llvm.lg`; split `host/native/lg_rt.c` into `host/native/rt.c` (word-generic helpers) and `host/native/posix.c` (`main`, output, imports); `checks/native-run.sh`
- Create: `targets/host-aarch64-darwin-fix31.edn`, `targets/host-x86_64-linux-fix31.edn`, `corpus/llvm/fixnum-edges.lg`

**Interfaces:**
- Produces in `lower_llvm.lg`: `(ll-word) -> "i32"|"i64"`; `(ll-type kind) -> string`: `:int` `"i64"`, `:bool` `"i1"` in registers, `:box` `(ll-word)`, `:float` `"double"`. The module gets `target triple` and `target datalayout`, the latter read from the `target datalayout` line of `clang --target=<triple> -S -emit-llvm -x c /dev/null -o -` (once per session, cached by triple).
- Produces: continuation records as named struct types `%"k.<fn>.<b>_<n>" = type { ptr, ptr, <ll-type of each saved value> }`, sized with `ptrtoint (ptr getelementptr (%T, ptr null, i32 1) to i64)`. Join and continuation params carry each value's `ll-type`.
- Produces in `rt.c`: `intptr_t lg_box_int(int64_t)`, `int64_t lg_unbox_int(intptr_t)`, `intptr_t lg_truthy(intptr_t)`, `void lg_print_box(intptr_t)`, `void *lg_alloc(size_t)`; fixnum bounds from `-DLG_FIXNUM_BITS=<n>`, which the runner passes from the profile.

- [ ] **Step 1: Write the failing test.** `corpus/llvm/fixnum-edges.lg` defines `(defn id [x] x)` and `(defn add [a b] (+ a b))` and, for each of `1073741823 1073741824 -1073741824 -1073741825 2147483647 2147483648 4611686018427387903 4611686018427387904 -4611686018427387904 -4611686018427387905 9223372036854775807 -9223372036854775808`, prints `v`, `(id v)`, `(= v (id v))` and `(add v 0)`. The `-fix31` profiles are the host profiles with `:fixnum-bits 31`.
- [ ] **Step 2:** It MATCHes on the host profile; with `LW_PROFILE=host-aarch64-darwin-fix31` it FAILS (the width is ignored).
- [ ] **Step 3:** Implement; remove every `i64`-as-word assumption from `lower_llvm.lg`.
- [ ] **Step 4:** MATCH on both profiles and with `LW_NATIVE_JIT=1`; `P12.1` green.
- [ ] **Step 5:** Row `P12.3` running `corpus/llvm` and `corpus/llvm-scalar` under both host profiles; commit `llvm target: word-size-generic values (S6)`.

### Task 4: The jank suite harness (W3)

**Files:**
- Create: `checks/jank-suite.sh`, `checks/jank-native.lg`, `corpus/jank/files.tsv`, `corpus/jank/baseline.tsv`, `corpus/jank-harness/conditionals.cljc`
- Modify: `src/driver.lg` (a `--read-clj` flag that calls `(set-read-clj! true)` before reading the program, so `#?(:clj …)` branches are taken as native's suite harness takes them), `checks/run-tests.sh` (pass `--read-clj` to the driver and `LG_READ_CLJ=1` to the native side when the list's header asks for it)

**Interfaces:**
- Produces: `corpus/jank/files.tsv`, lines `core_test/<f>.cljc<TAB><deftest count>` for all 243 `core_test` and `string_test` files, generated by `checks/jank-suite.sh --list` (counts `(deftest` forms) and checked in.
- Produces: `checks/jank-native.lg <file>`: sets `set-read-clj!`, loads `$LETGO/test/compat/clojure/core-test/portability.lg`, loads the file with source paths `$LETGO/test/compat:$LETGO/test/clojure-test-suite/test`, runs its namespace's tests, and prints the same summary lines `run-tests` prints. This is the native side for every suite comparison.
- Produces: `checks/jank-suite.sh [--filter w,…]` runs `checks/run-tests.sh --corpus corpus/jank/files.tsv` under the current `WASM_RUN`, then prints `files MATCH M/F`, `deftests N/T`, and a cause table with columns `d15` (the backend's failure line names Ratio, BigInt or BigDecimal), `compile` (the driver refused the file; the first refusal line), `mismatch` and `crash`. With `--ratchet` it exits 1 when a deftest listed in `corpus/jank/baseline.tsv` no longer passes; `--update-baseline` rewrites the baseline from the current run.

- [ ] **Step 1: Write the failing test.** `corpus/jank-harness/conditionals.cljc` is a namespace with one deftest whose assertions use `#?(:clj 1 :cljs 2 :default 3)`, `#?(:cljs 2 :default 3)` and `[#?@(:clj [1 2] :cljs [3])]`. `checks/jank-suite.sh --self-test` runs it on both sides and expects agreement, and expects a deliberately wrong fixture (`conditionals-wrong.cljc`, asserting the `:cljs` value) to be reported as FAIL on both sides.
- [ ] **Step 2:** FAIL (no harness).
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `--self-test` exits 0. Run the whole suite once under the WasmGC lane (`WASM_RUN=checks/wasm-run.sh checks/jank-suite.sh`) and once under this target; record both summaries and cause tables in `STATUS.md` under a dated heading, and write `corpus/jank/baseline.tsv` from the llvm run.
- [ ] **Step 5:** Row `P12.4	12	env WASM_RUN=checks/native-run.sh checks/jank-suite.sh --ratchet`; P8.0 and P9.1 green (driver changed); commit `llvm target: jank suite harness and first measurement (W3)`.

### Task 5: Program code: vars, closures, calls through values, recur (W5)

**Files:**
- Modify: `src/lower_llvm.lg`
- Create: `corpus/llvm/{closures,vars,recur,deep,arity-error}.lg`

**Interfaces:**
- Produces: `lg_invoke<n>` (n = 0–4) and `lg_invoke_v` in the module prelude, `(k, fn word, args…)`: check the arity against the fn object and tail-call its code with `%self`; a wrong arity raises the text `arity-error-msg` produces in `src/lower_wasm.lg`.
- Produces: fn objects as `%Fn = type { word header, ptr info, ptr code0, ptr code1, ptr code2, ptr code3, ptr code4, ptr env }`, mirroring `rt/wasm/seq.lg`'s `Fn`; closure envs as per-closure struct types.
- Produces: var-table vars as globals `@"var.<munged>"` of the word type, read and written by `:load-var`, `:def` and `:set-var`.
- Produces: fn-level `recur` (a branch back to the entry block) moves the entry's body into join function `<fn>.b<entry>`, which the entry tail-calls (S4).

- [ ] **Step 1: Write the failing tests.** `closures.lg`: a `make-adder` closure over an int, a closure over two closures, hand-written recursion applying a passed fn, a 5-arity call. `arity-error.lg`: an uncaught wrong-arity call through a fn value. `vars.lg`: `(def x 1)`, `(def y (inc x))`, a top-level redefinition with `def`, a `declare`d var defined later. `recur.lg`: fn-level `recur` with 3 params, 1,000,000 iterations. `deep.lg`: `(defn down [n] (if (zero? n) 0 (inc (down (dec n)))))` at 10,000,000, and mutual `ev?`/`od?` stored in vars and called through them, at 10,000,000.
- [ ] **Step 2:** `P12.3` FAILS on the new files (closures and vars refused).
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `P12.3` green on both host profiles.
- [ ] **Step 5:** Commit `llvm target: closures, vars, recur (S4, S10)`.

### Task 6: Parameterized fixnums in the runtime (W4)

**Files:**
- Modify: `rt/wasm/intrinsics.lg` (rename `i31`, `i31?`, `i31-get` to `fix`, `fix?`, `fix-get`; add constants `fix-min`, `fix-max` with reference values -1073741824 and 1073741823), every use (`grep -n 'wasm/i31' rt/wasm/*.lg src/lw_ext.lg`), `rt/wasm/seq.lg:98` (`box-int` reads `wasm/fix-min`/`wasm/fix-max`), `rt/wasm/emit.lg:854`, `src/lower_wasm.lg` (`emit-intrinsic` for the new names; `coerce` and the box helpers at today's lines 200, 3094 and 3144 take their bounds from one def), `rt/wasm/INTRINSICS.md`

**Interfaces:**
- Produces: `wasm/fix`, `wasm/fix?`, `wasm/fix-get`, `wasm/fix-min`, `wasm/fix-max`, recognised by var identity. Under gc and linear they emit exactly the instructions the i31 forms emit today; under llvm the bounds come from the profile's `:fixnum-bits`.

- [ ] **Step 1:** Baseline: `checks/run-intrinsics-native.sh` and P8.0 green.
- [ ] **Step 2:** Rename and re-route.
- [ ] **Step 3:** `checks/run-intrinsics-native.sh` green with the same test count; P8.0 exit 0; P9.1 1130; `LW_ATTEST=0 checks/gate.sh 8` green (linear unchanged).
- [ ] **Step 4:** Commit `runtime: fixnum intrinsics parameterized by target (S8, D207)`.

### Task 7: Intrinsics, constants, leaves and the runtime library (W6, W7)

**Files:**
- Create: `src/lower_llvm_rt.lg` (intrinsic forms, struct layouts from `wasm/defstruct`/`defarray` decls, leaf classification), `host/native/helpers.c` (native forms of `print-runtime`, `exn-runtime`'s report, `fn-runtime`'s descriptions, `bframe-runtime`), `corpus/llvm-intrinsics/{structs,arrays,bytes,fixnums,floats,host}.lg`, `corpus/llvm/constants.lg`
- Modify: `src/lower_llvm.lg`, `src/driver.lg` (stop forcing `:rt false` under `:llvm`), `src/lower_wasm.lg` (`rtlib-key` includes the profile's bytes under `:llvm`), `checks/native-run.sh` (`opt -passes=internalize,globaldce -internalize-public-api-list=lg_run` before `llc`), `corpus/llvm/fixnum-edges.lg` (add `(println [v (id v)] (hash v) #{v})` per value)

**Interfaces:**
- Produces: `(ll-struct-type decl) -> "%\"T.<Name>\""`: header word, then fields `:i32`→`i32`, `:i64`→`i64`, `:f64`→`double`, `:ref`→word, `:funcref`→`ptr`, `[:mut t]`→`t`; arrays `{ word header, word len, [0 x elem] }`.
- Produces: one LLVM form per intrinsic in `rt/wasm/intrinsics.lg` (its `:wasm` metadata is the semantic reference). `wasm/is?` compares the header kind; `wasm/as`, `wasm/get` and `wasm/set!` on the wrong kind call `lg_cast_fail(kind, expected)`, which raises through Task 8's path (until then: prints `error: lower-wasm: cast failed` and exits 1).
- Produces: boxed constants as globals initialised by `lg_run` before `_main`: strings as `Str` objects over `Bytes` arrays from private constant data; keywords and symbols interned through the runtime's own interning fns. `=` on anything but two ints calls the runtime's `wasm.seq/equiv?`.
- Produces: `(ll-leaf? var) -> bool`, a fixpoint over the call graph (every call to an intrinsic, a primitive op, a C helper or another leaf). Leaves are `define fastcc <ll-type ret> @"<name>"(<params>)`, called with `call fastcc`.

- [ ] **Step 1: Write the failing rows.** `P12.5`: `corpus/scalar` (all five, `os-args.lg` included), `corpus/seqs`, `corpus/llvm-intrinsics` and `corpus/llvm/constants.lg` (string, keyword, symbol, char, float, nil/true/false constants printed with `println` and `prn`, compared with `=`, used as map keys) on both host profiles. The `corpus/llvm-intrinsics` programs use `wasm.intrinsics` the way `corpus/intrinsics/intrinsics_test.lg` does; native lg runs them on the reference implementation.
- [ ] **Step 2:** FAIL (runtime not compiled).
- [ ] **Step 3:** Implement intrinsics family by family, each `corpus/llvm-intrinsics` file MATCHing before the next.
- [ ] **Step 4:** Leaf classification, then the runtime; `P12.5` green; `fixnum-edges.lg` with its new line MATCHes on both host profiles; P8.0 and P9.1 green.
- [ ] **Step 5:** Commit `llvm target: intrinsics, constants, leaves, runtime (S5)`.

### Task 8: Exceptions (W8)

**Files:**
- Modify: `src/lower_llvm.lg`, `src/lower_llvm_rt.lg`, `host/native/rt.c`
- Create: `corpus/llvm/leaf-throw.lg`, `corpus/llvm/thrown-classes.lg`

**Interfaces:**
- Produces: globals `@lg_handler` (ptr to the innermost frame; null when none) and `@lg_pending` (word; 0 when none). Frame `{ ptr handler_code, ptr saved_k, ptr prior, word binding_depth }`, heap-allocated, never mutated (S15).
- Produces: `:try` over the lifted regions: push a frame, run the body with a continuation that restores `@lg_handler` to `prior` and continues; a `finally` frame runs its region and rethrows the original value.
- Produces: `lg_throw(word)` for CPS code: pop the frame, unwind bindings to its depth, tail-call `handler_code`. A leaf throws by storing `@lg_pending` and returning; every leaf call in CPS code is followed by `load @lg_pending`, `icmp ne 0`, and a branch to `lg_throw_pending`. An uncaught throw reaches `lg_halt`, which reports through the native form of `lw report` and exits 1.

- [ ] **Step 1: Write the failing tests.** `leaf-throw.lg`: `(try (doall (map #(nth [] %) [1])) (catch Exception e (println "caught" (ex-message e))))`; a `finally` that prints; a `binding` of a dynamic var inside the `try`, printed in the handler (must be the outer value). `thrown-classes.lg`: one `try`/`catch` per class in Review Focus 5, each catching the error native throws for it (`(/ 1 0)`, `(+ 1 :a)`, `(nth [] 0)`, `(ex-info "x" {})`).
- [ ] **Step 2:** Row `P12.6` (`corpus/control` and `corpus/llvm` on both host profiles) FAILS.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** `P12.6` green; `checks/jank-suite.sh --update-baseline` (the passing count may only grow).
- [ ] **Step 5:** Commit `llvm target: exceptions without longjmp (S9)`.

### Task 9: Host ABI on posix (W9)

**Files:**
- Modify: `host/native/posix.c`, `src/lower_llvm_rt.lg` (host-call intrinsics map to these symbols)
- Create: `corpus/llvm/host.lg` (getenv of a set and an unset var, `os/args`, a non-negative `nanotime` difference, `(<!! (timeout 10))`)

**Interfaces:**
- Produces: every import of `host/ABI.md` as a C function `lg_env_<name>` / `lg_term_<name>` with the ABI's signature, pointer-sized params as `intptr_t`.

- [ ] **Step 1:** `corpus/llvm/host.lg` FAILS on the host profile (imports missing).
- [ ] **Step 2:** Implement.
- [ ] **Step 3:** `P12.3` green on both host profiles.
- [ ] **Step 4:** Commit `llvm target: host ABI (S11)`.

### Task 10: `defmulti`, `deftype`, `defprotocol`, `defrecord` (W10)

**Files:**
- Modify: `src/driver.lg` (remove the refusal at line 834 and the matching entry in the head set at line 557; route these forms to the IR as let-go's own compiler does), the runtime files that need multimethod dispatch, type construction and protocol dispatch twins (`rt/wasm/core.lg` and a new `rt/wasm/poly.lg`, added to the load-order table in `rt/wasm/README.md`)
- Create: `corpus/poly/{multimethod,deftype,defrecord,protocol}.lg`

**Interfaces:**
- Produces: the four forms compile under every target; the runtime twins reproduce native's dispatch, `type`/`instance?` answers and error texts. `corpus/refused` loses the entries that pinned these refusals.

- [ ] **Step 1: Write the failing tests.** `multimethod.lg`: `defmulti` on a keyword and on a fn, `defmethod` with `:default`, a missing-method error. `deftype.lg`: fields, a method, `instance?`. `defrecord.lg`: map behaviour (`assoc`, `get`, `=`), printing. `protocol.lg`: `defprotocol` with two methods, implemented inline in a `deftype` and a `defrecord`.
- [ ] **Step 2:** All four FAIL on both lanes with the driver's refusal.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** All four MATCH under `checks/wasm-run.sh` and under `checks/native-run.sh` (both host profiles); P8.0 and P9.1 green; the seven suite files that use these forms move from the harness's `compile` column.
- [ ] **Step 5:** Rows `P12.7` (`corpus/poly` under this target) and `P7.x` (the same under the WasmGC lane); `checks/jank-suite.sh --update-baseline`; commit `front end: defmulti, deftype, defprotocol, defrecord on every target`.

### Task 11: The suite to its bar (W11)

**Files:**
- Modify: whichever of the files above each failure's cause belongs to; `checks/items.tsv`, `checks/affected.sh`, `STATUS.md`, `DECISIONS.md`
- Create: `checks/llvm-convention-check.sh`, `checks/llvm-bench.sh`

**Interfaces:**
- Produces: rows `P12.8` (`corpus/opmatrix` with its SKIP, `corpus/typed`, `corpus/closure` on both host profiles); `P12.9` (every host row again with `LW_NATIVE_JIT=1`); `P12.10` `checks/llvm-convention-check.sh` (the host profile with `:triple "mipsel-unknown-linux-gnu"` makes `native-run.sh` exit 1 naming the profile and `:tail-calls`); `P12.11` `checks/llvm-bench.sh` (fib(32) and a 1e6-element `reduce` over native lg, `checks/wasm-run.sh` and the host profile; exit 0 when the outputs agree; timings recorded, not gated); `P12.12` `env LW_PROFILE=host-aarch64-darwin-fix31 WASM_RUN=checks/native-run.sh checks/jank-suite.sh --ratchet`.

- [ ] **Step 1:** Run `checks/jank-suite.sh`; take the largest cause bucket first and fix it in the task's file that owns it; after each fix, `--update-baseline` (the count only grows) and commit with the bucket named.
- [ ] **Step 2:** When every remaining failure is in the `d15` column, write the D15 decision (implement the number tower, or count those deftests as named exceptions) as a DECISIONS.md entry with the measured counts from both lanes, and stop for the human partner's choice before acting on it.
- [ ] **Step 3:** Add rows `P12.8`–`P12.12`; `LW_ATTEST=0 checks/gate.sh 12` exits 0; P8.0 and P9.1 green.
- [ ] **Step 4:** Record the final suite numbers, peak memory and bench timings in `STATUS.md` and a DECISIONS entry for M1; commit `llvm target: M1, jank suite on the 64-bit host`.
